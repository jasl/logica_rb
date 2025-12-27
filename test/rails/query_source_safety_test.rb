# frozen_string_literal: true

require "test_helper"

class RailsQuerySourceSafetyTest < Minitest::Test
  def test_untrusted_source_query_rejects_non_allowlisted_function
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select my_evil(1) as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.sql }
    assert_equal :function_not_allowed, err.reason
    assert_equal "my_evil", err.details
  end

  def test_untrusted_source_query_ignores_dangerous_function_names_in_strings
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Safe(x:) :-
        `((select 'pg_read_file(' as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Safe", trusted: false)

    result = query.result
    assert_equal %w[x], result.columns
    assert_equal [["pg_read_file("]], result.rows
  end

  def test_untrusted_source_query_raises_violation_for_dangerous_sql
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select 1 as x; select 2 as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SqlSafety::Violation) { query.result }
  end

  def test_untrusted_source_query_rejects_sqlexpr
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = SqlExpr("1", {x: 1});
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end

  def test_untrusted_source_query_rejects_file_io_builtins
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = ReadFile("/tmp/x");
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() :- WriteFile("/tmp/x", content: "[1,2,3]") == "OK";
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end

  def test_untrusted_source_query_rejects_sqlite_master_reference
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(n:) :-
        `((select name as n from "sqlite_master"))`(n:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false, allowed_relations: ["users"])

    err = assert_raises(LogicaRb::SqlSafety::Violation) { query.sql }
    assert_equal :denied_schema, err.reason
    assert_match(/sqlite_master/i, err.message)
  end
end
