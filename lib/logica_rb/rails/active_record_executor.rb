# frozen_string_literal: true

module LogicaRb
  module Rails
    class ActiveRecordExecutor
      def initialize(connection: ActiveRecord::Base.connection)
        @connection = connection
      end

      def select_all(sql)
        @connection.select_all(sql)
      end

      def exec_query(sql, binds: [])
        @connection.exec_query(sql, "LogicaRb", binds)
      end

      def exec_script(script_sql)
        script_sql = script_sql.to_s
        raw = @connection.respond_to?(:raw_connection) ? @connection.raw_connection : nil

        if defined?(::SQLite3::Database) && raw.is_a?(::SQLite3::Database)
          raw.execute_batch(script_sql)
        elsif defined?(::PG::Connection) && raw.is_a?(::PG::Connection)
          raw.exec(script_sql)
        else
          @connection.execute(script_sql)
        end
      end
    end
  end
end
