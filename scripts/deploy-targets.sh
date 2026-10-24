#!/usr/bin/env bash
# The be's two runtimes, for scripts/deploy.sh (sourced; it sets V, SHA, IMAGE, NAME, URL,
# AWS_REGION). Every step runs as the deploy role, which can roll ECS and send commands to the box
# but can never read a setting or the database password: the tasks and the box read those
# themselves.

# Registers the family's current task definition again with this release's image and version, and
# prints the new revision's ARN. The definition itself (env, secrets, roles) stays Terraform's.
register_task_definition() {
  local family=$1 current
  current=$(aws ecs describe-task-definition --task-definition "$family" --query taskDefinition)
  jq --arg img "$IMAGE" --arg v "$V" '
    del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
        .registeredAt, .registeredBy, .deregisteredAt)
    | .containerDefinitions |= map(.image = $img
        | .environment = ([(.environment // [])[] | select(.name != "APP_VERSION")] + [{name: "APP_VERSION", value: $v}]))
  ' <<<"$current" > "$WORK_TD"
  aws ecs register-task-definition --cli-input-json "file://$WORK_TD" \
    --query taskDefinition.taskDefinitionArn --output text
}
WORK_TD=$(mktemp)

# Prints the last lines a stopped task wrote, from its log stream.
task_log() {
  local task_id=${1##*/}
  MSYS_NO_PATHCONV=1 aws logs get-log-events --log-group-name "/$NAME/be" \
    --log-stream-name "be/be/$task_id" --limit 20 --query 'events[].message' --output text 2>/dev/null \
    | tr '\t' '\n' || true
}

# The migration as a one-off task from the new definition, on the api service's network. Its exit
# code decides: anything but 0 stops the deploy before any new code serves.
migrate_on_ecs() {
  local td=$1 net task code
  net=$(aws ecs describe-services --cluster "$NAME" --services api --query 'services[0].networkConfiguration')
  task=$(aws ecs run-task --cluster "$NAME" --launch-type FARGATE --task-definition "$td" \
    --network-configuration "$net" \
    --overrides '{"containerOverrides":[{"name":"be","command":["node","migrate.js"]}]}' \
    --query 'tasks[0].taskArn' --output text)
  echo "be $V: migrating as task ${task##*/}"
  aws ecs wait tasks-stopped --cluster "$NAME" --tasks "$task"
  code=$(aws ecs describe-tasks --cluster "$NAME" --tasks "$task" --query 'tasks[0].containers[0].exitCode' --output text)
  task_log "$task"
  if [ "$code" != 0 ]; then
    echo "::error::be $V: migrate exited $code; deploy stopped, nothing new serves."; exit 1
  fi
}

# Rolls both services to the new definitions and waits until ECS calls them stable. The circuit
# breaker rolls a service back by itself when new tasks fail to start; that shows here as the old
# definition still primary, and fails the deploy.
deploy_ecs() {
  local svc td primary state
  aws ecs update-service --cluster "$NAME" --service api --task-definition "$API_TD" --query service.serviceName --output text >/dev/null
  aws ecs update-service --cluster "$NAME" --service worker --task-definition "$WORKER_TD" --query service.serviceName --output text >/dev/null
  echo "be $V: ECS services updating"
  aws ecs wait services-stable --cluster "$NAME" --services api worker
  for svc in api worker; do
    td=$([ "$svc" = api ] && echo "$API_TD" || echo "$WORKER_TD")
    read -r primary state < <(aws ecs describe-services --cluster "$NAME" --services "$svc" \
      --query 'services[0].deployments[?status==`PRIMARY`]|[0].[taskDefinition,rolloutState]' --output text)
    if [ "$primary" != "$td" ] || [ "$state" != COMPLETED ]; then
      echo "::error::ECS $svc did not take be $V (primary ${primary##*/}, $state); the circuit breaker kept the old one."
      exit 1
    fi
    echo "Check: ECS $svc runs ${td##*/}"
  done
  target_group_healthy "$NAME-ecs"
}

# Waits until every target in the group reports healthy, at most two minutes.
target_group_healthy() {
  local tg=$1 arn states
  arn=$(aws elbv2 describe-target-groups --names "$tg" --query 'TargetGroups[0].TargetGroupArn' --output text)
  for _ in $(seq 1 24); do
    states=$(aws elbv2 describe-target-health --target-group-arn "$arn" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text)
    if [ -n "$states" ] && [ -z "$(tr '\t' '\n' <<<"$states" | grep -v '^healthy$' || true)" ]; then
      echo "Check: target group $tg is healthy ($states)"; return 0
    fi
    sleep 5
  done
  echo "::error::target group $tg is not healthy: $states"; exit 1
}

# The box (FF's EC2 today): one container runs api, worker and crons, as pm2 does. The script goes
# through SSM Run Command; the box pulls the image and reads the database password with its own role.
# The same environment as the ECS api task, with RUNTIME=ec2, so both sides read the same settings.
deploy_ec2() {
  local instance env_lines secret script cmd status out
  instance=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME-be" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
  [ "$instance" != None ] || { echo "::error::no running instance tagged $NAME-be"; exit 1; }
  local td_json
  td_json=$(aws ecs describe-task-definition --task-definition "$NAME-api" --query 'taskDefinition.containerDefinitions[0]')
  env_lines=$(jq -r --arg v "$V" --arg r "$AWS_REGION" '
    [(.environment // [])[] | select(.name != "RUNTIME" and .name != "APP_VERSION")]
    + [{name: "RUNTIME", value: "ec2"}, {name: "APP_VERSION", value: $v}, {name: "AWS_REGION", value: $r}]
    | .[] | "\(.name)=\(.value)"' <<<"$td_json")
  secret=$(jq -r '.secrets[] | select(.name == "DB_PASSWORD") | .valueFrom | sub(":password::$"; "")' <<<"$td_json")
  script=$(cat <<EOF
set -euo pipefail
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${IMAGE%%/*} >/dev/null
docker pull -q $IMAGE
umask 077
F=\$(mktemp)
cat > "\$F" <<'ENV'
$env_lines
ENV
aws secretsmanager get-secret-value --region $AWS_REGION --secret-id '$secret' --query SecretString --output text \
  | python3 -c 'import json,sys; print("DB_PASSWORD=" + json.load(sys.stdin)["password"])' >> "\$F"
if [ "${MIGRATE_ON_BOX:-}" = 1 ]; then docker run --rm --env-file "\$F" $IMAGE node migrate.js; fi
docker rm -f be >/dev/null 2>&1 || true
docker run -d --name be --restart unless-stopped -p 3000:3000 --log-opt max-size=10m --env-file "\$F" $IMAGE >/dev/null
rm -f "\$F"
for _ in \$(seq 1 30); do curl -fs localhost:3000/health >/dev/null && break; sleep 1; done
curl -fs localhost:3000/version
EOF
)
  cmd=$(aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
    --comment "be $V" --parameters "$(jq -n --arg s "$script" '{commands: [$s]}')" \
    --query Command.CommandId --output text)
  echo "be $V: sent to $instance (command $cmd)"
  aws ssm wait command-executed --command-id "$cmd" --instance-id "$instance" || true
  read -r status < <(aws ssm get-command-invocation --command-id "$cmd" --instance-id "$instance" --query Status --output text)
  out=$(aws ssm get-command-invocation --command-id "$cmd" --instance-id "$instance" --query '[StandardOutputContent,StandardErrorContent]' --output text)
  echo "$out" | tail -5
  [ "$status" = Success ] || { echo "::error::be $V on EC2: $status"; exit 1; }
  target_group_healthy "$NAME-ec2"
}

# What a member reaches: the load balancer answers /health, and /version names this release.
smoke_through_load_balancer() {
  local ver
  for _ in $(seq 1 12); do curl -fs "$URL/health" >/dev/null && break; sleep 5; done
  ver=$(curl -fs "$URL/version") || { echo "::error::$URL/version does not answer"; exit 1; }
  echo "Through the load balancer: $ver"
  [ "$(jq -r .version <<<"$ver")" = "$V" ] || { echo "::error::$URL answered $(jq -r .version <<<"$ver"), expected $V"; exit 1; }
  same_commit "the be behind $URL" "$(jq -r '.commit // empty' <<<"$ver")" "$SHA"
}
