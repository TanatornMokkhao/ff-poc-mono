# Moving a backend from EC2 to ECS

How this repo rehearses Freedom Fight's move of its backend from one EC2 box to ECS, on this POC's own
AWS account, and what each step taught. Read it before planning the real move.

The rehearsal runs staging the way FF would run the move: one load balancer in front of the old EC2
box and the new ECS services, both on the same Postgres and Redis. Traffic moves between them by
weight, and moves back the same way.

## Result, 2026-10-24

The move works end to end with no request lost, given two api tasks. Measured from outside through the
load balancer, every request recorded:

| Change | Requests across it | Server errors | Settled after |
|---|---|---|---|
| 0 → 10% ECS | 934 | 0 | ~12 s |
| 10 → 50% | 822 | 0 | ~15 s |
| One of **one** api task lost at 50% | 114 in the gap | **57 (503)** for 19 s | new task registered 19 s later |
| One of **two** api tasks lost at 50% | 1,252 | 0 | |
| 50 → 100% | 682 | 0 | ~11 s |
| Rollback 100 → 0% | 552 | 0 | ~11 s |
| Back to 100%, then the EC2 box retired | 316, then live checks | 0 | |
| A migration that fails on real data | the deploy stopped before new code served | 0 | |

What the real move needs, from these results:

1. Two or more api tasks across two zones. One task leaves ECS's share with no target when it fails.
2. The ECS stack reads FF's existing load balancer, subnets, security group, database and Redis by name
   (`infra/sim/ecs`, `var.existing`). Nothing of FF's is imported or edited.
3. The cutover is one weighted listener rule. Rollback is a weight change while the box still runs, and
   the box is retired only after a rollback drill.
4. The platform's database and Redis values win over the settings store.
5. Migrations run as a one-off task before new code serves, and are rehearsed on a copy of real data:
   CI's empty database passed the migration that failed on staging.
6. The deploy watches each ECS rollout until `COMPLETED` and tells a rollback from a rollout still running.

Not rehearsed: crons running once across two runtimes (Redis lock) and socket events between them
(steps 4 and 6). They are where FF's NestJS code differs most and need their own rehearsal.

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
- [x] Split into `current` and `ecs` with `moved` blocks. #34: `1 added, 2 changed, 0 destroyed`, 32
  moved. The listener rule is added, the listener goes back to all-EC2, and the EC2 policy loses its log
  statement.

### 4. Teach the be and the deploy both runtimes

- [x] Settings set by the platform (`DB_HOST`, `DB_PASSWORD`, `REDIS_QUEUE_HOST`) win over Parameter
  Store where `RUNTIME` is set. #35; `/info` reads the RDS endpoint, not the placeholder.
- [x] The be builds its database connection from `DB_*`, with TLS checked against the RDS bundle, when
  `DATABASE_URL` is empty. #35; migrations and `/notes` ran against RDS.
- [x] `/version` reports `runtime` (`ec2`, `ecs` or `local`). #35.
- [ ] Not done: a `worker.js` entry point with a queue and a cron behind a Redis lock, and socket events
  on a Redis channel every api process reads. Left out of this rehearsal (see Result).
- [x] `scripts/deploy.sh` takes targets from `deploy/<stage>/be.yaml`. `ec2` deploys through SSM Run
  Command; `ecs` registers task definitions, migrates as a one-off task, rolls both services and waits
  for `rolloutState` `COMPLETED`, then smoke-tests through the ALB. #36, #37, #38.

### 5. Move traffic

One pull request per weight: 10, 50, 100. During each, a script calls the ALB without pause and
records every error and which runtime answered.

- [x] Weight 10: about 10% of answers come from ECS, no errors. #39.
- [x] Weight 50, then 100: no errors during either change. #40, #42.
- [x] Back to 0 (the rollback): EC2 answers everything again, no errors. #43, then back to 100 in #44.
- [x] An ECS task killed at weight 50. With one task the ALB did **not** move its share to EC2: 57
  errors over 19 s. With two tasks (#41): 0 errors.
- [ ] Not measured: a deploy to ECS while EC2 served. Deploys ran during the rehearsal, but none with
  the measuring script running.
- [x] Retire the EC2 box once ECS serves everything. #45: only the box's five pieces destroyed.

### 6. Prove the hard parts

- [ ] Not done: crons running once across both runtimes (Redis lock).
- [ ] Not done: socket events between EC2 and ECS.
- [x] A migration that fails stops the deploy, and the old version keeps serving. #46, release
  `1.4.0-rc.1`.
- [ ] Not done: a traffic rollback after a migration has already applied. The rollback drill (#43) ran
  on an unchanged schema.

### 7. Turn it off

- [ ] Pull request sets `staging_enabled = false`. The plan destroys everything it created in step 3,
  and nothing else. Local plan before the pull request: `0 to add, 0 to change, 31 to destroy` (21 in
  the current stack, 9 in the ECS stack, and the deploy role's simulation policy). ECR, CloudFront, the
  web bucket and bootstrap stay. The same pull request removes `deploy/staging/be.yaml`, so staging
  deploys go back to the runner path.
- [ ] After the approved apply, Cost Explorer shows no new simulation charges the next day.

Task definition revisions registered by `scripts/deploy.sh` are outside Terraform and stay after the
destroy. They cost nothing.

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
| 2026-10-24 | 5 | Weight 50 -> 100 (#42): 414 requests across the change, 0 errors; the last EC2 answer 10.8 s after the rule changed, then 100% ECS | The full move is one weight change, with nothing dropped |
| 2026-10-24 | 5 | Rollback drill, 100 -> 0 (#43): 552 requests across the change, 0 errors; the last ECS answer 10.9 s after, then 100% EC2. Back to 100 in #44 | Keeping the box running behind the rule makes the way back as quiet as the way in. Keep it until the move is final |
| 2026-10-24 | 5 | Back to 100 (#44): 316 requests across the change, 0 errors, 100% ECS 20 s after. Retiring the box (#45): `ec2_enabled = false` and staging deploys to `ecs` only; plan `0 to add, 1 to change, 5 to destroy`, the five being the instance, its role, policy and instance profile, and its target group attachment. The listener is left as it is: the `/*` rule at 100% ECS catches every path, so its default (the empty EC2 group) is never used | The cutover needs no edit to FF's hand-made listener. Retire the box only after a rollback drill, and expect the plan to destroy the box's pieces and nothing else |
| 2026-10-24 | 5 | After the box was retired: EC2 `terminated`, ECS api 2/2, `/version` answers `runtime: ecs`, and `/notes` reads the note written while EC2 served alongside a new one | Both runtimes share one database, so nothing moves with the cutover |
| 2026-10-24 | 6 | A migration that passes on a fresh database and fails on real data (#46): `CHECK (char_length(body) <= 200)` with one 252-character note on staging. CI passed it, `migrations` job included. Release `1.4.0-rc.1`: the one-off task failed with `check constraint "notes_body_at_most_200" ... is violated by some row`, the deploy stopped before ECS changed, and ECS kept serving `1.3.0-rc.1` with all notes readable. #47 removes the migration (it rolled back and never reached a prod tag) | CI's empty database cannot prove a migration against real data. Migrating as a separate step before new code serves is what keeps members unaffected; on FF, also rehearse each migration on a copy of real data before release |
| 2026-10-24 | 6 | Recovery: release `1.4.0-rc.2` (run 40109477042) printed `schema already current`, so the failed `0003` was recorded nowhere. ECS moved to api:8 and worker:8, `/version` answered `1.4.0-rc.2` with `runtime: ecs`, and notes 3, 2 and 1 were intact | The failed migration left nothing to clean up. The fix is the next release, not a database repair |

## What carries over to FF, and what does not

- `infra/sim/ecs` is the code for FF's move: point `var.existing` at FF's load balancer, target group,
  subnets, security group, database and Redis names. Nothing of FF's existing side is imported or edited.
- The cutover is one listener rule on FF's existing ALB, so there is no new load balancer and no DNS
  change. Deleting the rule is the rollback.
- FF's ALB, database and Redis were likely made by hand. Read them with data sources; importing them
  would let a wrong plan replace production.
- Crons, queues and socket events are where the move is hard, not the load balancer. This rehearsal did
  not cover them; FF's NestJS code has its own versions of each and needs its own rehearsal.
- FF deploys from Gitea Actions over SSH. Until FF moves to GitHub, its ECS deploy needs the same steps
  driven from Gitea.
