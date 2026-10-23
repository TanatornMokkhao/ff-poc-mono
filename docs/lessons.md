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
