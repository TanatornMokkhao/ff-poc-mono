# ff-poc-mono

The same POC as [ff-poc-hub](https://github.com/TanatornMokkhao/ff-poc-hub) + ff-poc-be + ff-poc-fe, in one repo. be, fe, infra and the release flow live together, so one commit is one version of everything and there are no pins to keep in step.

## Running now

<!-- status:start -->
| Stage | version (be + fe, one commit) | mobile | Last deployed |
| --- | --- | --- | --- |
| staging | `1.2.0-rc.1` (841676c) | `1.2.0-rc.1` | 2026-10-24 11:48 UTC ([run](https://github.com/TanatornMokkhao/ff-poc-mono/actions/runs/40091340170)) |
| prod | `1.0.2` (95b1c4e) | `1.0.2` | 2026-10-23 14:32 UTC ([run](https://github.com/TanatornMokkhao/ff-poc-mono/actions/runs/39969181578)) |

_Each row is written by that stage's last successful deploy. mobile is the app build the testers or stores were last given, not what users have installed._
<!-- status:end -->

## What lives where

| Path | Meaning |
| --- | --- |
| `apps/be/` | Node HTTP server, its Dockerfile, migrations (`MIGRATIONS.md`) |
| `apps/fe/` | Ionic Vue web app and the Capacitor Android / iOS apps |
| `deploy/<stage>/versions.yaml` | What each stage runs: one version and its commit. The Release workflow writes it; Rollback production points prod back. |
| `nx.json`, `apps/*/project.json`, `apps/be/features/*/project.json` | Nx project graph: CI runs the jobs of the apps a change affects (`npx nx show projects --affected`), and inside each app only the tests of the affected features (`scripts/checks/app-tests.sh`). A new feature goes in `apps/be/features/<name>/` or `apps/fe/src/features/<name>/` with its own `project.json` (`<app>-<name>`) and tests, and is added to `implicitDependencies` in the app's `project.json`. Each app keeps its own `package.json` and lock file; the root `package.json` holds only Nx. |
| `scripts/release-notes.sh` | Release notes: commits since the previous prod release, grouped by prefix (feat / fix / other), cherry-picks already shipped left out. Promote writes them on every prod release. |
| `scripts/deploy.sh` | Deploys a stage: be first (keys checked by name in Parameter Store, migrate, start, `/version` holds the commit), then fe (web build to S3 + CloudFront, `build-info.json` holds the commit) |
| `infra/` | Terraform (account 375355731232, ap-southeast-1), every name `ff-poc-mono-*`: `bootstrap/` applied once by hand, the rest by the Terraform workflow after an approval on `infra` |
| FE settings | Variables of the `build-staging` / `build-prod` environments of this repo (no approval needed to read them), baked into each rc's web and app builds |
| BE settings | Parameter Store `/ff-poc-mono/<stage>/be/<KEY>`, read by the server at boot; never in git or GitHub |

Sites: [staging](https://d2opbrm30xq1x7.cloudfront.net/) · [prod](https://dwgvwer6j5v4n.cloudfront.net/)

## Release in one screen

1. Merge pull requests into `main`. CI runs only the jobs of the app a change touches; the `ci` check is the one required.
2. **Releases → Draft a new release**, tag `staging/v1.0.0-rc.1` on `main`, Publish. Release builds the be image and the web once, records `deploy/staging/versions.yaml` and deploys staging. Approve `app-test` to build the apps.
3. A fix during testing: merge it, then release `staging/v1.0.0-rc.2`.
4. Staging passes: Actions → **Promote to prod**, pick the rc in the list (every rc not yet in prod, newest first; Update menus keeps it current after each release). It checks every commit is on `main`, creates `prod/v1.0.0` on the rc's commit and reuses its builds; approve `production` (and `app-store` for the apps).
5. Rollback: Actions → **Rollback production**, pick a prod version or `previous`, then approve `production`. be and fe go back together. It refuses a version older than any contract migration's `removes-use-from`.
6. Hotfix while `main` holds work that cannot ship yet: fix on `main` first (a normal pull request), then cut a branch from what prod runs and cherry-pick the fix onto it:
   ```bash
   git fetch --tags origin
   git switch -c release/1.0.1 prod/v1.0.0
   git cherry-pick -x <the fix commit on main>
   git push -u origin release/1.0.1        # CI runs on release/*
   ```
   Then Actions → **Promote to prod** → pick `release/1.0.1` (it appears in the list after CI passes on the push), approve `production`. Staging keeps running `main`; nothing to merge back, the fix is already on `main`.
   The hotfix build runs on prod first: it is built from the branch for prod only. CI on the branch and the deploy's checks are what stand before it. To test it before prod instead, release `staging/v1.0.1-rc.1` with target `release/1.0.1` and promote that rc (staging then runs the hotfix until the next rc from `main`).
   Promote refuses a commit that is neither on `main` nor a `-x` cherry-pick of a `main` commit, and a branch whose CI did not pass.

Only these are done by hand: an rc release, Promote, Rollback, and the approvals. No tag is ever made anywhere else.

## Compared with the hub layout

| | ff-poc-hub (3 repos) | ff-poc-mono |
| --- | --- | --- |
| A change to the API and the web | two pull requests, merged in step | one pull request |
| After a merge | Notify hub, then Bump submodule pins | nothing |
| Release tags | in the hub, copied to be and fe | here only; the release steps always come from main (`release-run.yml`) |
| Hotfix | Start hotfix button (pins move across repos) | a branch, a cherry-pick and an rc, by hand |
| "Is this on main?" | GitHub compare API across repos | `git merge-base` here |
| CI | each repo runs everything it has | one workflow, jobs filtered by path, one aggregate check |
| Roll back only be or only fe | possible | no: one version |
