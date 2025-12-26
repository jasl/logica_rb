# frozen_string_literal: true

module LogicaRb
  module Rails
    class Executor
      DEFAULT_QUERY_NAME = "LogicaRb".freeze

      def initialize(connection:)
        @connection = connection
      end

      def select_all(sql)
        @connection.select_all(sql)
      end

      def exec_query(sql, name: DEFAULT_QUERY_NAME, binds: [], prepare: false)
        @connection.exec_query(sql, name, binds, prepare: prepare)
      end

      def exec_script(sql_script)
        sql_script = sql_script.to_s

        raw = @connection.respond_to?(:raw_connection) ? @connection.raw_connection : nil

        if defined?(::SQLite3::Database) && raw.is_a?(::SQLite3::Database)
          raw.execute_batch(sql_script)
        elsif defined?(::PG::Connection) && raw.is_a?(::PG::Connection)
          raw.exec(sql_script)
        else
          @connection.execute(sql_script)
        end
      end
    end
  end
end
