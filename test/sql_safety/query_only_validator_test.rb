# frozen_string_literal: true

require "test_helper"

class QueryOnlyValidatorTest < Minitest::Test
  def test_allows_select_and_with
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1\n", engine: "sqlite")
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("WITH t AS (SELECT 1 AS x) SELECT x FROM t\n", engine: "sqlite")
  end

  def test_rejects_semicolons
    err =
      assert_raises(LogicaRb::QueryOnlyViolationError) do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1; SELECT 2", engine: "sqlite")
      end

    assert_match(/Multiple SQL statements/i, err.message)
  end

  def test_rejects_dml_and_ddl_keywords
    %w[INSERT UPDATE DELETE MERGE CREATE DROP ALTER TRUNCATE GRANT REVOKE].each do |kw|
      assert_raises(LogicaRb::QueryOnlyViolationError, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "sqlite")
      end
    end
  end

  def test_rejects_transactions_and_session_keywords
    %w[BEGIN COMMIT ROLLBACK SET].each do |kw|
      assert_raises(LogicaRb::QueryOnlyViolationError, "expected #{kw} to be rejected") do
        LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 #{kw} 2", engine: "sqlite")
      end
    end
  end

  def test_engine_specific_keywords
    assert_raises(LogicaRb::QueryOnlyViolationError) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 PRAGMA 2", engine: "sqlite")
    end

    assert_raises(LogicaRb::QueryOnlyViolationError) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 COPY 2", engine: "psql")
    end
  end

  def test_rejects_select_into_for_psql
    assert_raises(LogicaRb::QueryOnlyViolationError) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("SELECT 1 INTO new_table", engine: "psql")
    end
  end

  def test_explain_is_opt_in
    assert_raises(LogicaRb::QueryOnlyViolationError) do
      LogicaRb::SqlSafety::QueryOnlyValidator.validate!("EXPLAIN SELECT 1", engine: "sqlite")
    end

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!("EXPLAIN SELECT 1", engine: "sqlite", allow_explain: true)
  end

  def test_ignores_strings_and_comments
    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 'DROP TABLE users; INSERT INTO x VALUES (1)' AS message\n",
      engine: "sqlite"
    )

    LogicaRb::SqlSafety::QueryOnlyValidator.validate!(
      "SELECT 1 -- DROP TABLE users; INSERT INTO x VALUES (1)\n",
      engine: "sqlite"
    )
  end
end
