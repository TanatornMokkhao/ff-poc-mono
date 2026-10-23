# Database migrations: expand / contract

A rollback runs the **older** code on the **newer** schema. Migrations never run down. So every
migration must work with the release before it, and the release after it.

## The two kinds

| Kind | May do | Header |
|---|---|---|
| `expand` | Add a table, a nullable column, a column with a `DEFAULT`, an index | `-- kind: expand` |
| `contract` | Drop, rename, change a type, set `NOT NULL` | `-- kind: contract` and `-- removes-use-from: X.Y.Z` |

`removes-use-from` is the first release whose code no longer reads or writes what the contract
removes. Rollback production refuses to go below that release once the contract is in prod.

## A breaking change takes three releases

Example: rename `notes.body` to `notes.text`.

1. **Expand** (release 1.2.0): add `text`. Code writes both columns and reads `text`, falling back to `body`.
2. **Backfill**: copy `body` into `text` with a command, not a migration.
3. **Contract** (release 1.4.0, after 1.2.0 has been in prod long enough that nobody rolls back to 1.1.x):
   drop `body`, with `-- removes-use-from: 1.2.0`.

## Rules CI checks

`scripts/check-migrations.mjs` (job `migrations` in `.github/workflows/ci.yml`):

- Names are `NNNN_lower_snake.sql`, numbers unique, new files sort after every released file.
- An `expand` file has no `DROP`, `RENAME`, type change, `SET NOT NULL`, `NOT NULL` column without `DEFAULT`, `TRUNCATE` or `DELETE FROM`.
- A `contract` file names `removes-use-from`.
- A file in the last release tag never changes. Fix forward with a new file.

The same job applies the last release's migrations, then this change's, then starts **the last
release's code** on that schema (the rollback case) and this change's code, and checks both answer.

## Running

```bash
DATABASE_URL=postgres://… node migrate.js
```

Each file runs once, in its own transaction, and is recorded in `schema_migrations`.
In a deploy, `scripts/deploy.sh` runs `node migrate.js` from the new image before it starts the
new code: staging at the rc, prod after the production approval. `migrate.js` reads its settings
from Parameter Store like the server. A failure stops the deploy and the running be stays as it is.

Today no stage has a database: `DATABASE_URL` is optional, migrate prints
`no database, migrate skipped`, and `/notes` answers 503. A separate database user for migrations
(and `aws ecs run-task` in place of `docker run`) comes with ECS and RDS.
