# frozen_string_literal: true

require "digest"
require "date"

module Bi
  class ReportRunner
    MAX_PER_PAGE = 200
    DEFAULT_PER_PAGE = 50
    DEFAULT_MAX_ROWS_UNTRUSTED = 1000
    DEFAULT_STATEMENT_TIMEOUT_MS = 3000
    DEFAULT_LOCK_TIMEOUT_MS = 500

    ReportSpec = Data.define(
      :mode,
      :file,
      :source,
      :predicate,
      :engine,
      :trusted,
      :allow_imports,
      :flags_schema,
      :default_flags
    )

    RunResult = Data.define(:sql, :executed_sql, :result, :duration_ms, :row_count, :sql_digest)

    def initialize(report:, flags:, page:, per_page:)
      @report = report
      @flags = flags || {}
      @page = normalize_page(page)
      @per_page = normalize_per_page(per_page)
    end

    def run!
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      flags = validate_and_normalize_flags!
      query = build_query(flags)
      sql = query.sql
      executed_sql = paginate_sql(sql, page: @page, per_page: @per_page, max_rows: max_rows_limit)

      result = execute_select(executed_sql)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      row_count = extract_row_count(result)
      sql_digest = Digest::SHA256.hexdigest(executed_sql.to_s)

      RunResult.new(
        sql: sql,
        executed_sql: executed_sql,
        result: result,
        duration_ms: duration_ms,
        row_count: row_count,
        sql_digest: sql_digest
      )
    end

    private

    def normalize_page(value)
      value = value.to_i
      value = 1 if value < 1
      value
    end

    def normalize_per_page(value)
      value = value.to_i
      value = DEFAULT_PER_PAGE if value < 1
      [value, MAX_PER_PAGE].min
    end

    def untrusted_source?
      report_mode = @report.mode.to_s
      report_mode == "source" && !@report.trusted
    end

    def max_rows_limit
      return nil unless untrusted_source?

      DEFAULT_MAX_ROWS_UNTRUSTED
    end

    def build_query(flags)
      base = {
        predicate: @report.predicate.to_s,
        engine: (@report.engine.presence || "auto"),
        flags: flags,
        trusted: !!@report.trusted,
        allow_imports: !!@report.allow_imports,
      }

      case @report.mode.to_s
      when "file"
        LogicaRb::Rails.query(**base.merge(file: @report.file.to_s))
      when "source"
        LogicaRb::Rails.query(**base.merge(source: @report.source.to_s))
      else
        raise ArgumentError, "Unknown report mode: #{@report.mode.inspect}"
      end
    end

    def paginate_sql(sql, page:, per_page:, max_rows:)
      sql = sql.to_s.strip
      sql = sql.sub(/;\s*\z/, "")

      offset = (page - 1) * per_page
      limit = per_page

      if max_rows
        remaining = max_rows - offset
        limit = [limit, remaining].min
        return wrap_with_limit_offset(sql, limit: 0, offset: 0) if limit <= 0
      end

      wrap_with_limit_offset(sql, limit: limit, offset: offset)
    end

    def wrap_with_limit_offset(sql, limit:, offset:)
      <<~SQL.squish
        SELECT * FROM (#{sql}) AS logica_rows
        LIMIT #{Integer(limit)} OFFSET #{Integer(offset)}
      SQL
    end

    def execute_select(sql)
      return ActiveRecord::Base.connection.select_all(sql) unless untrusted_source?

      with_prevent_writes do
        conn = ActiveRecord::Base.connection

        if conn.adapter_name.to_s.match?(/postg/i)
          conn.transaction(requires_new: true) do
            # NOTE: SET LOCAL only lasts for the duration of the current transaction.
            conn.execute("SET LOCAL statement_timeout = '#{DEFAULT_STATEMENT_TIMEOUT_MS}ms'")
            conn.execute("SET LOCAL lock_timeout = '#{DEFAULT_LOCK_TIMEOUT_MS}ms'")
            conn.execute("SET LOCAL transaction_read_only = on")
            conn.execute("SET LOCAL app.tenant_id = '#{tenant_id_for_rls}'")
            conn.select_all(sql)
          end
        else
          conn.select_all(sql)
        end
      end
    end

    def tenant_id_for_rls
      Integer(ENV.fetch("BI_TENANT_ID", "1"))
    rescue ArgumentError, TypeError
      1
    end

    def with_prevent_writes
      if ActiveRecord::Base.respond_to?(:connected_to) && reading_role_configured?
        ActiveRecord::Base.connected_to(role: :reading, prevent_writes: true) { yield }
      elsif ActiveRecord::Base.respond_to?(:while_preventing_writes)
        ActiveRecord::Base.while_preventing_writes { yield }
      else
        yield
      end
    end

    def reading_role_configured?
      handler = ActiveRecord::Base.connection_handler
      return false unless handler.respond_to?(:retrieve_connection_pool)

      !!handler.retrieve_connection_pool(ActiveRecord::Base.connection_specification_name, role: :reading)
    rescue StandardError
      false
    end

    def extract_row_count(result)
      return result.rows.length if result.respond_to?(:rows)
      return Array(result["rows"]).length if result.is_a?(Hash) && result.key?("rows")

      nil
    end

    def validate_and_normalize_flags!
      defaults = normalize_hash(@report.default_flags)
      provided = normalize_hash(@flags)
      flags = defaults.merge(provided)

      schema = normalize_optional_hash(@report.flags_schema)
      return normalize_untyped_flags!(flags) unless schema

      unknown = flags.keys - schema.keys
      raise ArgumentError, "Unknown flags: #{unknown.sort.join(", ")}" if unknown.any?

      schema.each do |key, spec|
        next unless flags.key?(key)

        flags[key] = validate_and_normalize_flag_value!(key, spec, flags.fetch(key))
      end

      flags
    end

    def normalize_hash(value)
      value = {} if value.nil?
      unless value.is_a?(Hash)
        raise ArgumentError, "Expected a JSON object (Hash), got: #{value.class}"
      end

      value.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    def normalize_optional_hash(value)
      return nil if value.nil?

      normalize_hash(value)
    end

    def normalize_untyped_flags!(flags)
      flags.transform_values do |value|
        case value
        when String
          value
        when Integer, Float
          value.to_s
        when TrueClass, FalseClass
          value ? "true" : "false"
        when Date
          value.iso8601
        when nil
          raise ArgumentError, "flags values may not be null (use an empty string instead)"
        else
          raise ArgumentError, "flags values must be scalar strings/numbers/bools (got: #{value.class})"
        end
      end
    end

    def validate_and_normalize_flag_value!(key, spec, value)
      spec = normalize_hash(spec)
      type = spec.fetch("type", nil).to_s
      raise ArgumentError, "flags_schema[#{key}] missing type" if type.empty?

      case type
      when "integer"
        v = Integer(value)
        min = spec["min"]
        max = spec["max"]
        raise ArgumentError, "flags[#{key}] must be >= #{min}" if !min.nil? && v < Integer(min)
        raise ArgumentError, "flags[#{key}] must be <= #{max}" if !max.nil? && v > Integer(max)
        v.to_s
      when "float"
        v = Float(value)
        min = spec["min"]
        max = spec["max"]
        raise ArgumentError, "flags[#{key}] must be >= #{min}" if !min.nil? && v < Float(min)
        raise ArgumentError, "flags[#{key}] must be <= #{max}" if !max.nil? && v > Float(max)
        v.to_s
      when "string"
        v = value.to_s
        min_len = spec["min_length"]
        max_len = spec["max_length"]
        raise ArgumentError, "flags[#{key}] is too short" if !min_len.nil? && v.length < Integer(min_len)
        raise ArgumentError, "flags[#{key}] is too long" if !max_len.nil? && v.length > Integer(max_len)
        v
      when "enum"
        values = Array(spec["values"]).map(&:to_s)
        raise ArgumentError, "flags_schema[#{key}].values must be provided" if values.empty?

        v = value.to_s
        raise ArgumentError, "flags[#{key}] must be one of #{values.inspect}" unless values.include?(v)

        v
      when "date"
        if value.is_a?(Date)
          value.iso8601
        else
          Date.iso8601(value.to_s).iso8601
        end
      else
        raise ArgumentError, "Unknown flags_schema[#{key}] type: #{type}"
      end
    rescue ArgumentError => e
      raise ArgumentError, "Invalid flag #{key}: #{e.message}"
    end
  end
end
