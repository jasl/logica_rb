# Changelog

## 0.1.0

### Added

- Logica -> SQL transpiler for SQLite and PostgreSQL (Ruby 3.4+).
- `logica` CLI (`exe/logica`) and optional Rails/ActiveRecord integration.

### Security

- Untrusted `source:` mode guardrails (query-only validation, relation/function allow/deny lists, import whitelist for `allow_imports: true`).
