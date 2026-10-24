#!/usr/bin/env bash
# deploy_ecs against a fake aws that replays ECS rollouts: what each one must decide.
#   bash scripts/deploy-targets.test.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ANSWERS=$(mktemp -d)
pass=0
fail=0

# expect <0|1> <case> <api answers> <worker answers> <text the output must hold>
# Answers are "<primary task definition> <rolloutState>" lines, one per poll; the last repeats.
expect() {
  local want=$1 name=$2 got=0 out
  printf '%b' "$3" > "$ANSWERS/api"
  printf '%b' "$4" > "$ANSWERS/worker"
  out=$(ANSWERS=$ANSWERS bash -c '
    set -euo pipefail
    source "$1"
    NAME=sim V=9.9.9 API_TD=arn/api:3 WORKER_TD=arn/worker:3
    target_group_healthy() { echo "target group checked"; }
    sleep() { :; }
    aws() {
      [ "$2" = describe-services ] || return 0
      local svc f
      svc=$(sed -n "s/.*--services \([a-z]*\).*/\1/p" <<<"$*")
      f="$ANSWERS/$svc"
      head -1 "$f"
      # The answer is out before this call ends, as with a real CLI that is still exiting: code that
      # reads it without waiting for the call to finish reads the next poll from a stale file.
      command sleep 0.3
      [ "$(wc -l < "$f")" -le 1 ] || sed -i 1d "$f"
    }
    deploy_ecs' _ "$HERE/deploy-targets.sh" 2>&1) || got=1
  if [ "$got" = "$want" ] && grep -qF "$5" <<<"$out"; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name (exit $got, wanted $want)"; echo "$out" | sed 's/^/     /'; fi
}

expect 0 "a rollout still in progress is waited for, then passes" \
  'arn/api:3 IN_PROGRESS\narn/api:3 IN_PROGRESS\narn/api:3 COMPLETED\n' 'arn/worker:3 COMPLETED\n' \
  'Check: ECS api runs api:3'
expect 0 "both services and the target group are checked" \
  'arn/api:3 COMPLETED\n' 'arn/worker:3 COMPLETED\n' 'target group checked'
expect 1 "the circuit breaker's rollback (old definition primary) fails" \
  'arn/api:3 IN_PROGRESS\narn/api:2 COMPLETED\n' 'arn/worker:3 COMPLETED\n' 'rolled back to api:2'
expect 1 "a FAILED rollout fails" \
  'arn/api:3 FAILED\n' 'arn/worker:3 COMPLETED\n' 'rollout of api:3 failed'
expect 1 "a rollout that never ends fails after the limit" \
  'arn/api:3 IN_PROGRESS\n' 'arn/worker:3 COMPLETED\n' 'did not end within 15 minutes'
expect 1 "the worker is checked too" \
  'arn/api:3 COMPLETED\n' 'arn/worker:2 COMPLETED\n' 'ECS worker rolled back'

rm -rf "$ANSWERS"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
