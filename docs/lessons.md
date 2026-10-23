# Lessons turned into rules

Every incident that could happen again becomes the strongest mechanism that stops it, strongest
first: a state that cannot exist (a ruleset), a check that fails CI, one canonical helper, a check
at run time, and only last a written instruction. Each check here has a case in
`scripts/checks/checks.test.sh` that shows it failing on the mistake, or is a tool run on new code.

The rules check new code only: what a change adds or modifies (the tools look at each changed file whole). Old code is not rechecked, so a rule
can be switched on without fixing the whole repo first.

| Date | What broke | Rule | Kind | Where | Proof |
| --- | --- | --- | --- | --- | --- |
| 2026-10-23 | `apps/fe/android/gradlew` lost its exec mode in the copy into this repo; Android builds stopped with exit 126 | Scripts and `gradlew` must be `100755` | CI check | `scripts/checks/executable-files.sh` | `checks.test.sh` (3 cases) |
| 2026-10-23 | Promote got HTTP 403 creating `prod/v1.0.0` with GITHUB_TOKEN; bot pushes to main were refused by the ruleset | Workflows create refs and push main only with the deploy key | CI check | `scripts/checks/no-token-refs.sh` | `checks.test.sh` (6 cases; a DELETE of a ref is allowed: the first run flagged tag-names.yml deleting a wrong tag, a false positive) |
| 2026-10-23 | In the hub, a `grep` with no match inside `$(...)` under `pipefail` stopped `deploy.sh` with no message | shellcheck on changed scripts | Tool on new code | `scripts/checks/shell-scripts.sh` | shellcheck |
| 2026-10-23 | Workflow logic errors found only by running a release | actionlint (and shellcheck inside `run:`) on changed workflows | Tool on new code | `scripts/checks/workflows.sh` | actionlint |
| 2026-10-23 | `staging/1.1.0-rc.1` (no `v`) was typed in Releases; it would have started nothing | Release tags must match `staging/vX.Y.Z-rc.N` or `prod/vX.Y.Z` | Run-time check (a tag-name ruleset is not available on this plan) | `.github/workflows/tag-names.yml` removes a wrong tag and fails | Pushing a wrong tag (shown in PR) |
| 2026-10-23 | A hotfix branch could be force-pushed or deleted, losing what prod was built from | `release/*` cannot be deleted or force-pushed | Ruleset (cannot exist) | repo ruleset "release branches" | Deleting one is refused |
| 2026-10-23 | The must-fail pull request (four broken rules) showed only the first: the other steps were skipped | Every rules step runs even after one fails | CI structure | `rules` job, `if: !cancelled()` on each step | The must-fail pull request shows every finding |
| 2026-10-23 | fe had an eslint config that CI never ran; be had none | eslint, warnings included, on changed app files | Tool on new code | `scripts/checks/lint-app.sh`, `apps/be/eslint.config.js` | eslint |
| 2026-10-23 | Terraform format and validity were checked only in the Terraform workflow, which is not a required check | `terraform fmt -check` and `validate` on every change to `infra/` | Tool on new code | `infra` job in `ci.yml` | terraform |
| 2026-10-23 | Prevention: this repo holds signing keys and AWS settings as secrets; one pasted into a file would stay in git history | gitleaks on the commits a change adds | Tool on new code | `scripts/checks/secrets.sh` | gitleaks |
| 2026-10-23 | `staging/v1.0.1-rc.1` tried to reuse the builds of `staging/v1.0.0-rc.4`, a refused rc on the same commit that built nothing | Only an rc whose release has `web-build-prod.zip` is reused | Tested logic | `scripts/release-meta.sh` | `release-meta.test.sh` "an rc that built nothing (refused) is not reused"; planting the bug back fails 2 cases |
| 2026-10-23 | A hotfix took 1.0.2 while main had already released `staging/v1.0.2-rc.1` | A version another line of code used is refused, with the next free one named | Tested logic | `scripts/release-meta.sh` | `release-meta.test.sh` "a version another line of code already used is refused" |
| 2026-10-23 | The release logic lived inline in a workflow and was tested only by releasing | Release decisions are one script with cases; the workflow only calls it, from main | Canonical helper | `scripts/release-meta.sh`, `release-run.yml` | `release-meta.test.sh` (10 cases, refusals checked by reason) |
| 2026-10-23 | be is JavaScript: a missed `await` or a wrong field name reached runtime with nothing in between | Type check of be (`checkJs`, strict null checks) | Tool on all of be | `apps/be/jsconfig.json`, `be` job | A missing `await` on `pool.query()` fails with TS2339 |
| 2026-10-23 | Nothing made a fix carry a test, so the same bug could come back unnoticed | A pull request titled `fix` that changes app code must change a test | CI check | `scripts/checks/fix-has-test.sh` | `checks.test.sh` (3 cases) |
| 2026-10-23 | New code could merge with no test running it | At least 80% of the executable lines a change adds must run under the app's tests | Tool on new code | `scripts/checks/new-code-coverage.mjs` | An untested function: 42% and the lines named; with its test: 100% |
| 2026-10-23 | A test that runs code without checking its result passes coverage | Mutation score of the be lines a change adds must be at least 70% (Stryker on file:start-end ranges) | Tool on new code | `scripts/checks/mutation.sh`, `apps/be/stryker.config.json` | `settings.js`: 86% (43 killed, 7 survived) |
| 2026-10-23 | Path filters decided which app's jobs ran; a shared file would not have run both | Nx decides the affected apps from the project graph | CI structure | `nx.json`, `apps/*/project.json`, `changes` job | be-only change: be; fe-only: fe; README-only: none |
| 2026-10-23 | Every check looked only at a change, so a dependency or runner update could break a part nobody touched | Nightly run of every job on every file | Scheduled | `ci.yml` `schedule` | First nightly run |

## Known weak spots (found by the gates, not fixed yet)

| Found | What | By | Next step |
| --- | --- | --- | --- |
| 2026-10-23 | `apps/be/scripts/check-migrations.mjs`: mutation score 32.64% (63 killed, 130 survived). Its unit tests miss most of `checkAll` (the comparison with the release tag) and many of the rule regexes; only the CI `migrations` job exercises them | Mutation testing over the whole file (first run of the gate) | Unit tests for `checkAll` in a throwaway repo; the gate checks only added lines, so this does not block other changes |
