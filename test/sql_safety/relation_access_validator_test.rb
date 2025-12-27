# frozen_string_literal: true

require "test_helper"

class RelationAccessValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::RelationAccessValidator.validate!(sql, **opts)
  end

  def test_allows_explicit_allowlisted_relation
    validate!(
      "SELECT * FROM bi.orders",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_allows_cte_reference
    validate!(
      "WITH t AS (SELECT * FROM bi.orders) SELECT * FROM t",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_rejects_denied_postgres_schemas
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM pg_catalog.pg_class",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_match(/pg_catalog/i, err.message)

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM information_schema.tables",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_match(/information_schema/i, err.message)
  end

  def test_rejects_non_allowlisted_relation
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM secret.orders",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end

    assert_match(/secret\.orders/i, err.message)
  end

  def test_handles_quotes_aliases_and_joins
    validate!(
      <<~SQL,
        SELECT o.id
        FROM "bi"."orders" AS o
        JOIN bi.orders o2 ON o2.id = o.id
      SQL
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_sqlite_denies_sqlite_master
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM sqlite_master",
          engine: "sqlite",
          allowed_relations: ["allowed_table"]
        )
      end

    assert_match(/sqlite_master/i, err.message)
  end
end
