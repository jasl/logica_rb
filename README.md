# LogicaRb

Core gem: pure Logica -> SQL transpiler for SQLite and PostgreSQL. It does **not** connect to databases or execute SQL by default.

Optional Rails/ActiveRecord integration is available via `require "logica_rb/rails"`.

## Engine support

- Supported: SQLite (`@Engine("sqlite")`), PostgreSQL (`@Engine("psql")`).
- Default engine in LogicaRb: `sqlite` (upstream Logica defaults to `duckdb` when `@Engine` is absent).
- DuckDB is **not** supported here, so any program that resolves to duckdb raises `UnsupportedEngineError("duckdb")`.
- To target PostgreSQL, add `@Engine("psql")`, pass `--engine=psql`, or set user flag `-- --logica_default_engine=psql`.

## CLI usage

```
logica <l file | -> <command> [predicate(s)] [options] [-- user_flags...]
```

Commands:
- `parse`        -> prints AST JSON
- `infer_types`  -> prints typing JSON (psql dialect)
- `show_signatures` -> prints predicate signatures (psql dialect)
- `print <pred>` -> prints SQL (default `--format=script`)
- `plan <pred>`  -> prints plan JSON (alias for `--format=plan`)
- `validate-plan <plan.json or ->` -> validates plan JSON (schema + semantics)

Options:
- `--engine=sqlite|psql`
- `--format=query|script|plan`
- `--import-root=PATH`
- `--output=FILE`
- `--no-color`

Examples:

```bash
exe/logica program.l print Test --engine=sqlite --format=script
exe/logica program.l plan Test
exe/logica validate-plan /tmp/plan.json
exe/logica - print Test -- --my_flag=123
```

Query vs script example:

```bash
cat > /tmp/example.l <<'LOGICA'
@Engine("sqlite");
Test(x) :- x = 1;
LOGICA

exe/logica /tmp/example.l print Test --format=query
```

```sql
SELECT
  1 AS col0
```

```bash
exe/logica /tmp/example.l print Test --format=script
```

```sql
SELECT
  1 AS col0;
```

## Ruby API

```ruby
compilation = LogicaRb::Transpiler.compile_string(
  File.read("program.l"),
  predicate: "Test",
  engine: "sqlite",
  user_flags: {"my_flag" => "123"}
)

sql = compilation.sql("Test", :script)
plan_json = compilation.plan_json("Test", pretty: true)
```

Plan docs:
- `docs/PLAN_SCHEMA.md`
- `docs/plan.schema.json`
- `docs/EXECUTOR_GUIDE.md`

## Development

```bash
bundle exec rake test
bundle exec rake goldens:generate
```

### DB smoke tests

These tests validate that generated SQL/Plan is executable in real databases (no result assertions; just “no error”).

SQLite:

```bash
bundle exec rake test:db_smoke_sqlite
```

Postgres (requires a reachable database):

```bash
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/postgres
bundle exec rake test:db_smoke_psql
```

## License

Apache-2.0. See `LICENSE.txt`.
