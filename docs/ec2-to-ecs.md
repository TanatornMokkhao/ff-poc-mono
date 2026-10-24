# Moving a backend from EC2 to ECS

How this repo rehearses Freedom Fight's move of its backend from one EC2 box to ECS, on this POC's own
AWS account, and what each step taught. Read it before planning the real move.

The rehearsal runs staging the way FF would run the move: one load balancer in front of the old EC2
box and the new ECS services, both on the same Postgres and Redis. Traffic moves between them by
weight, and moves back the same way.

## What FF runs, and what stands in for it here

| FF today | This rehearsal | Same or different |
|---|---|---|
| One EC2 `t3a.medium`, pm2, api + worker + crons in one process | One EC2 `t3a.micro`, Docker, the be in one container | Same shape, smaller box |
| Deploy by SSH from Gitea Actions, `git pull` + `npm ci` | Deploy by SSM Run Command from GitHub Actions, `docker pull` | Different transport; SSM needs no SSH key or open port |
| MySQL on RDS, read replica | Postgres on RDS `db.t4g.micro`, no replica | Different engine; the deploy steps are the same |
| Valkey `cache.t3.small`, one node | Valkey `cache.t4g.micro`, one node | Same |
| An Application Load Balancer (inferred from the bill, not read) | One ALB with two weighted target groups | Same idea |
| Secrets in a `.env` file on the box | Parameter Store, plus the RDS-managed password in Secrets Manager | Different; the move has to carry every key across |
| ECS: none | api and worker as separate Fargate services | The target |

## How it is wired

```
                    default action (FF today) ──────────► target group "ec2" ─► EC2 box (api + worker + crons)
Internet ─► ALB :80 ┤                                    ▲                              │
                    └─ rule "/*" (the move) ┬─ 100 - w ─┘                              │
                                            └─ w ─► target group "ecs" ─► ECS "api"   │
                                                    ECS "worker" (no load balancer) ───┤
                                                                                      ▼
                                                        Postgres (private) and Valkey (private)
```

- `infra/sim/current` stands in for FF today: network, ALB with a listener that sends everything to
  EC2, the EC2 box, Postgres, Valkey. It exists while `staging_enabled` is true.
- `infra/sim/ecs` is the move. It owns only what the move adds (cluster, services, task definitions,
  the `ecs` target group, one listener rule, the exec role, the log group) and finds everything else
  **by name** with data sources (`var.existing`), as it would on FF's account. It exists while
  `staging_enabled` and `ecs_enabled` are true.
- The ECS tasks carry the EC2 box's own security group, which the database and Redis already accept,
  so no rule on the existing side changes.
- The cutover is a listener rule (`/*`, priority 100) that splits by `ecs_weight`. The listener's default
  action is never edited, so `ecs_enabled = false` deletes the rule and leaves the existing side exactly
  as it was.
- `infra/sim.auto.tfvars` holds the switches. Each change is a pull request with a plan to read.
- Starting from nothing takes two applies, `current` first and then `ecs`, because `ecs` reads `current`
  at plan time. On FF the existing side is already there.
- The ALB uses group stickiness, so a client stays on the side it first reached. socket.io needs this
  while both sides serve.
- Terraform creates the ECS services once and then ignores `task_definition`. Deploys own the running
  version, so a later `terraform apply` never rolls a release back.
- The worker service may stop before its replacement starts (minimum healthy 0%), so two workers never
  run the same crons at once.

## Safety rails

- Terraform refuses any account but `375355731232` (`allowed_account_ids` in `infra/versions.tf` and
  `infra/bootstrap/main.tf`). Credentials for FF's account, or any other, fail before the first call.
- Every apply waits for an approval on the `infra` environment.
- The plan role can read every simulated resource but no secret: `secretsmanager:GetSecretValue`,
  `ssm:*` and `kms:*` are denied outright.
- The database password never enters Terraform state. RDS manages it in Secrets Manager. ECS hands it
  to the container, and the EC2 box reads it with its own role.
- The deploy role still cannot read a setting or the password.
- A budget in `infra/bootstrap` mails at 80% of USD 50 spent, or when the month is forecast past it.

## Cost

On-demand list prices for ap-southeast-1 from the AWS Price List API, read 2026-10-24. A month is 730
hours.

| Part | USD / month |
|---|---|
| EC2 `t3a.micro`, 8 GB disk, public IPv4 | 13.03 |
| ECS api, 0.25 vCPU / 0.5 GB, public IPv4 | 14.90 |
| ECS worker, 0.25 vCPU / 0.5 GB, public IPv4 | 14.90 |
| ALB, 1 LCU, 2 public IPv4 | 31.54 |
| RDS Postgres `db.t4g.micro`, 20 GB | 21.01 |
| Valkey `cache.t4g.micro` | 14.02 |
| CloudWatch Logs, 1 GB | 0.73 |
| **Total** | **110.12**, about 3.62 a day |

Turn it off between test sessions (step 7).

## Steps

Each step is one pull request unless it says otherwise. Check a box only when its evidence exists.

### 1. Add the simulation, switched off

- [x] Pull request adds `infra/sim/`, `infra/sim.tf`, `infra/sim.auto.tfvars` with
  `staging_enabled = false`, the account lock, and the bootstrap changes. #30, merged as `50ce130`.
- [x] The Terraform plan on the pull request reads `No changes`. #30's plan job.

### 2. Grant the new permissions (bootstrap, by a person)

`infra/bootstrap` is applied from a laptop with admin keys, never by CI. It widens the Terraform role,
the plan role and the boundary for the simulated services, and adds the budget.

- [x] `aws sts get-caller-identity` prints account `375355731232`.
- [x] `cd infra/bootstrap && terraform plan -var budget_email=<address>` shows only the changed role
  policies, the boundary and the new budget. Nothing is destroyed. `Plan: 1 to add, 3 to change, 0 to
  destroy`, 2026-10-24.
- [x] The person who owns the account applies it. Applied 2026-10-24 from the saved plan on the
  owner's go: `1 added, 3 changed, 0 destroyed`. Read back: the Terraform role holds the `Simulation`
  statement, the plan role `ReadSimulation`, the boundary 15 statements, and the budget is USD 50 a
  month.

### 3. Turn staging on

- [x] Pull request sets `staging_enabled = true`, `ecs_weight = 0`, `worker_count = 0`. #31.
- [x] The plan adds the network, the ALB, the EC2 box, the ECS cluster and services, RDS, Valkey, the
  log group and the roles, and destroys nothing. `Plan: 35 to add, 0 to change, 0 to destroy`.
- [x] After the approved applies (two, see Findings), all 35 exist: RDS `available` and not public,
  Valkey `available`, EC2 `running`, ECS api 1/1 healthy in the `ecs` target group, and its log reads
  `loaded 10 settings from /ff-poc-mono/staging/be/`. The ALB answers 502 until the be runs on EC2
  (step 4).
- [ ] Split into `current` and `ecs` with `moved` blocks. Read-only plan: `1 to add, 2 to change, 0 to
  destroy`, 32 moved. The listener rule is added, the listener goes back to all-EC2, and the EC2 policy
  loses its log statement.

### 4. Teach the be and the deploy both runtimes

- [ ] Settings set by the platform (`DB_HOST`, `DB_PASSWORD`, `REDIS_QUEUE_HOST`) win over Parameter
  Store. Today `loadSettings` overwrites them.
- [ ] The be builds its database URL from `DB_*` when `DATABASE_URL` is empty.
- [ ] `/version` reports `RUNTIME` (`ec2` or `ecs`), so a request shows which side answered.
- [ ] A `worker.js` entry point runs a queue and a cron behind a Redis lock, and the api publishes
  socket events on a Redis channel that every api process reads.
- [ ] `scripts/deploy.sh` takes a target. `ec2` sends the old deploy through SSM Run Command. `ecs`
  registers a task definition, runs the migration as a one-off task, updates the services, waits
  until they are stable, smoke-tests through the ALB and rolls back on failure.

### 5. Move traffic

One pull request per weight: 10, 50, 100. During each, a script calls the ALB without pause and
records every error and which runtime answered.

- [ ] Weight 10: about 10% of answers come from ECS, no errors.
- [ ] Weight 50, then 100: no errors during either change.
- [ ] Back to 0 (the rollback): EC2 answers everything again, no errors.
- [ ] An ECS task killed at weight 50: the ALB stops sending to it and EC2 carries the load.
- [ ] A deploy to ECS while EC2 serves: no errors.

### 6. Prove the hard parts

- [ ] Both runtimes up, crons enabled on both: each cron tick runs once (Redis lock).
- [ ] A socket client on EC2 receives an event raised on ECS, and the other way round.
- [ ] A migration that fails stops the deploy, and the old version keeps serving.
- [ ] A rollback after a migration still reads and writes through the old version.

### 7. Turn it off

- [ ] Pull request sets `staging_enabled = false`. The plan destroys everything it created in step 3,
  and nothing else.
- [ ] After the approved apply, Cost Explorer shows no new simulation charges the next day.

## Findings

Record each result here with its date, the run or pull request, and what it means for FF's move.

| Date | Step | Result | What it means for FF |
|---|---|---|---|
| 2026-10-24 | 2 | Bootstrap cannot run from CI on purpose: it defines CI's own rights, and the Terraform role is denied changing itself, the plan role or the boundary | FF's account needs the same split. One person-applied base (roles, boundary, state, budget), everything else through an approved pipeline |
| 2026-10-24 | 3 | First plan with changes failed in CI: the runner's `bash -e` stopped on `terraform plan`'s exit 2 ("changes") before the script read it. Fixed in #32 with a check that keeps it fixed | Any pipeline that reads `-detailed-exitcode` has this trap; test the "changes" path, not only "no changes" |
| 2026-10-24 | 3 | First apply created 28 of 35, then RDS failed with `KMSKeyNotAccessibleFault`: the Terraform role had no KMS rights, and an encrypted RDS with a managed password uses `aws/rds` and `aws/secretsmanager` as the caller. Fixed in #33 (only through RDS and Secrets Manager); the second apply added the 7 missing in 7m34s for RDS | A plan cannot catch a missing permission; only an apply can. Give the deploying role KMS through RDS and Secrets Manager before the first database |
| 2026-10-24 | 3 | Approving #33's run before bootstrap was applied failed the same way: merging bootstrap code changes nothing in AWS until a person applies it | Order on FF: base change applied, then the pipeline run approved |
| 2026-10-24 | 3 | With every target unhealthy the ALB still forwards and answers 502, not 503 | A 502 at the ALB during a cutover can mean "nothing listening", not "load balancer broken" |
| 2026-10-24 | 3 | The first split plan replaced the `ecs` target group and both task definitions: `depends_on = [module.current]` deferred every data source to apply time. Without it: 0 destroyed | In the real move, never make the ECS stack depend on the existing stack; read it with data sources at plan time |
| 2026-10-24 | 4b | First deploy through both targets (run 40096969014): the migration ran as a one-off ECS task, the EC2 box took the release through SSM and its target group turned healthy. Then the deploy failed on ECS: `aws ecs wait services-stable` returned while the rollout was still `IN_PROGRESS` (the old task drains for the target group's 30 s), and the script read that as a rollback. ECS finished on its own two minutes later | "Stable" is not "done". A deploy pipeline watches `rolloutState` until `COMPLETED`, and tells a rollback (old definition primary again) apart from a rollout still running |
| 2026-10-24 | 4 | `1.3.0-rc.1` through both targets: migrations `0001` and `0002` ran on RDS as a one-off ECS task over TLS; `POST /notes` and `GET /notes` through the ALB wrote and read RDS from EC2; `/info` shows the RDS endpoint, not the Parameter Store placeholder | The platform's values must win over the settings store, or a move carries the old box's placeholders onto the new runtime |
| 2026-10-24 | 5 | Weight 0 -> 10 (#39): 316 requests before, 618 after, all 200; 8.7% from ECS; first ECS answer 12.5 s after the rule changed. Weight 10 -> 50 (#40): 236 before, 586 after, all 200; 49.6% from ECS once settled | Moving weight on a listener rule drops no request. Allow ~15 s before the new share shows |
| 2026-10-24 | 5 | One ECS api task stopped at 50% (`aws ecs stop-task`, 14:09:26 UTC). The old task served for 37 s while it drained; then for 19 s the `ecs` target group had no healthy target and the ALB answered **503 to its whole share** (57 of 114 requests), instead of sending them to EC2. ECS started a new task within 1 s; it was registered 19 s later; then 0 errors over 5 min (1 stray 5xx, not yet explained) | Weighted target groups do not fail over to each other. Run at least two api tasks across two zones during the move and after, so losing one never empties the group |
| 2026-10-24 | 5 | The same test with `api_count = 2` (#41): one of the two api tasks stopped at 14:53:11 UTC, traffic at 50%. 1,252 requests over 3.5 min, all 200, **0 errors**, including the +37 to +60 s window that gave 57 errors with one task | Two tasks is the measured minimum for the move, not a guess |

## What carries over to FF, and what does not

- `infra/sim/ecs` is the code for FF's move: point `var.existing` at FF's load balancer, target group,
  subnets, security group, database and Redis names. Nothing of FF's existing side is imported or edited.
- The cutover is one listener rule on FF's existing ALB, so there is no new load balancer and no DNS
  change. Deleting the rule is the rollback.
- FF's ALB, database and Redis were likely made by hand. Read them with data sources; importing them
  would let a wrong plan replace production.
- Crons, queues and socket events are where the move is hard, not the load balancer. Step 6 rehearses
  them on this repo's small be. FF's NestJS code has its own versions of each.
- FF deploys from Gitea Actions over SSH. Until FF moves to GitHub, its ECS deploy needs the same steps
  driven from Gitea.
