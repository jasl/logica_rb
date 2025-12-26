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

## Rails Integration (optional)

Rails integration is **opt-in** and only loaded after:

```ruby
require "logica_rb"
require "logica_rb/rails"
```

### Configuration

```ruby
# config/initializers/logica_rb.rb
require "logica_rb/rails"

LogicaRb::Rails.configure do |c|
  c.import_root = Rails.root.join("app/logica")
  c.cache = true
  c.cache_mode = :mtime
  c.default_engine = nil # auto-detect from the connection when nil
end
```

Configuration API:
- `LogicaRb::Rails.configure { |c| ... }`
- `LogicaRb::Rails.configuration`
- `LogicaRb::Rails.cache` / `LogicaRb::Rails.clear_cache!`

Caching is enabled by default. In Rails development, the Railtie clears the compilation cache on each reload via `ActiveSupport::Reloader.to_prepare`.

### Model DSL

```ruby
class User < ApplicationRecord
  logica_query :active_users, file: "users.l", predicate: "ActiveUsers"
end
```

DSL API:
- `logica_query(name, file:, predicate:, engine: :auto, format: :query, flags: {}, as: nil, import_root: nil)`
- `logica(name, connection: nil, **overrides)` (returns `LogicaRb::Rails::Query`)
- `logica_sql`, `logica_result`, `logica_relation`, `logica_records`

### Consumption modes

Relation (recommended, for parameterization via ActiveRecord):

```ruby
rel = User.logica_relation(:active_users)
rel = rel.where("logica_activeusers.age >= ?", 18).order("logica_activeusers.age DESC")
rel.to_a
```

Result (returns `ActiveRecord::Result`, useful when you don't need a model):

```ruby
User.logica_result(:active_users) # => ActiveRecord::Result
```

Records (returns model instances via `find_by_sql`):

```ruby
User.logica_records(:active_users) # => [#<User ...>, ...]
```

Advanced: `User.logica(:active_users)` returns a `LogicaRb::Rails::Query` with `sql`, `plan_json`, `result`, `relation`, `records`, and `cte`.

### Safety notes

- `LogicaRb::Rails::Query#relation` uses `Arel.sql` to wrap the compiled subquery. Treat compilation output as trusted code, and do **not** pass untrusted user input into Logica flags without validation.

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
