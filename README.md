# LogicaRb

Ruby wrapper/runtime for Logica with SQLite and PostgreSQL support.

## Engine support

- Supported: SQLite (`@Engine("sqlite")`), PostgreSQL (`@Engine("psql")`).
- Default engine follows upstream Logica (duckdb). DuckDB is **not** supported here, so any program that resolves to duckdb at execution will raise `UnsupportedEngineError("duckdb")`.
- To avoid that, either add `@Engine("sqlite")` / `@Engine("psql")`, or pass `--logica_default_engine=sqlite` on the CLI.

## Usage

Run a predicate:

```bash
exe/logica path/to/program.l run Test
```

Print SQL:

```bash
exe/logica path/to/program.l print Test
```

PostgreSQL connection string is read from `LOGICA_PSQL_CONNECTION`.


## Testing with PostgreSQL

PostgreSQL tests are enabled when `LOGICA_PSQL_CONNECTION` is set.

Example (local Docker):

```bash
docker run --rm --name logica-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres -e POSTGRES_DB=logica_test -p 5432:5432 postgres:16
export LOGICA_PSQL_CONNECTION=postgres://postgres:postgres@localhost:5432/logica_test
bundle exec rake test
```

Alternative example (pgvector image + one-shot test run):

```bash
docker run -it --rm -p 5432:5432 -e POSTGRES_DB=logica -e POSTGRES_USER=logica -e POSTGRES_PASSWORD=logica -e PGDATA=/var/lib/postgresql/18/docker pgvector/pgvector:pg18-trixie
LOGICA_PSQL_CONNECTION=postgresql://logica:logica@localhost:5432/logica bundle exec rake test
```

If the env var is missing, the psql suite is skipped with a clear message.

## Development

```bash
bundle exec rake test
```

## License

Apache-2.0. See `LICENSE.txt`.
