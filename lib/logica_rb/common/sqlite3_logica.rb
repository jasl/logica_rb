# frozen_string_literal: true

require "csv"
require "stringio"
require "digest"
require "json"
require "sqlite3"

require_relative "../util"
require_relative "python_repr"

module LogicaRb
  module Common
    module Sqlite3Logica
      module_function

      def de_facto_type(value)
        value.is_a?(Integer) || value.is_a?(Float) ? "number" : "string"
      end

      def normalize_sqlite_value(value)
        return 1 if value == true
        return 0 if value == false
        value
      end

      def load_json(str)
        JSON.parse(str)
      rescue JSON::ParserError => e
        warn("Failed to parse JSON object: #{str}")
        raise e
      end

      def dump_json(value)
        case value
        when Hash
          inner = value.map { |k, v| "#{dump_json(k)}: #{dump_json(v)}" }.join(", ")
          "{#{inner}}"
        when Array
          inner = value.map { |v| dump_json(v) }.join(", ")
          "[#{inner}]"
        when String
          JSON.generate(value)
        when TrueClass, FalseClass, NilClass, Numeric
          JSON.generate(value)
        else
          JSON.generate(value.to_s)
        end
      end

      def argmin_step(ctx, arg, value, limit)
        if !limit.nil? && limit.to_i <= 0
          raise "ArgMin's limit must be positive."
        end
        result = (ctx[:result] ||= [])
        if !result.empty? && de_facto_type(value) != de_facto_type(result[0][0])
          raise "ArgMin got incompatible values: #{value.inspect} vs #{result[0][0].inspect}"
        end
        result << [value, arg]
        if limit && result.length > limit.to_i
          max_index = result.each_index.max_by { |i| result[i] }
          result.delete_at(max_index)
        end
      end

      def argmin_finalize(ctx)
        result = ctx[:result] || []
        dump_json(result.sort.map { |v, a| a })
      end

      def argmax_step(ctx, arg, value, limit)
        if !limit.nil? && limit.to_i <= 0
          raise "ArgMax's limit must be positive."
        end
        result = (ctx[:result] ||= [])
        if !result.empty? && de_facto_type(value) != de_facto_type(result[0][0])
          raise "ArgMax got incompatible values: #{value.inspect} vs #{result[0][0].inspect}"
        end
        result << [value, arg]
        if limit && result.length > limit.to_i
          min_index = result.each_index.min_by { |i| result[i] }
          result.delete_at(min_index)
        end
      end

      def argmax_finalize(ctx)
        result = ctx[:result] || []
        dump_json(result.sort.reverse.map { |v, a| a })
      end

      def distinct_list_step(ctx, element)
        set = (ctx[:result] ||= {})
        set[element] = true
      end

      def distinct_list_finalize(ctx)
        set = ctx[:result] || {}
        dump_json(set.keys)
      end

      def array_concat_agg_step(ctx, value)
        return if value.nil?
        result = (ctx[:result] ||= [])
        result.concat(load_json(value))
      end

      def array_concat_agg_finalize(ctx)
        dump_json(ctx[:result] || [])
      end

      def take_first_step(ctx, value)
        ctx[:result] ||= value
      end

      def take_first_finalize(ctx)
        normalize_sqlite_value(ctx[:result])
      end

      def array_concat(a, b)
        return nil if a.nil? || b.nil?
        dump_json(load_json(a) + load_json(b))
      end

      def print_to_console(message)
        puts message
        1
      end

      def join(array, separator)
        load_json(array).map(&:to_s).join(separator)
      end

      def read_file(filename)
        File.read(filename)
      rescue StandardError
        nil
      end

      def write_file(filename, content)
        File.write(filename, content)
        "OK"
      rescue StandardError => e
        e.to_s
      end

      def dataframe_as_artistic_table(df)
        artistic_table(df.columns, df.to_a)
      end

      def artistic_table(header, rows)
        stringify = lambda { |v| LogicaRb::Common::PythonRepr.format(v, top_level: true) }
        header = header.map { |h| stringify.call(h) }
        rows = rows.map { |row| row.map { |v| stringify.call(v) } }
        pad = lambda { |s, w| s.to_s + " " * (w - s.to_s.length) }

        row_lines = lambda do |row, width|
          row_columns = row.map { |x| x.to_s.split("\n") }
          height = row_columns.map(&:length).max
          result = []
          height.times do |i|
            next_row = []
            row.length.times do |j|
              next_row << (row_columns[j][i] || "")
            end
            result << next_row
          end
          result.map { |rr| "| " + rr.zip(width).map { |r, w| pad.call(r, w) }.join(" | ") + " |" }
        end

        width = Array.new(header.length, 0)
        ([header] + rows).each do |r|
          r.each_with_index do |val, idx|
            width[idx] ||= 0
            cell_width = val.to_s.split("\n").map(&:length).max || 0
            width[idx] = [width[idx], cell_width].max
          end
        end

        top_line = "+-" + width.map { |w| "-" * w }.join("-+-") + "-+"
        header_line = "| " + header.zip(width).map { |h, w| pad.call(h, w) }.join(" | ") + " |"
        result = [top_line, header_line, top_line]

        rows.each do |row|
          line = "| " + row.zip(width).map { |r, w| pad.call(r, w) }.join(" | ") + " |"
          if line.include?("\n")
            sep_up = "/˙" + row.zip(width).map { |_, w| "˙" * w }.join("˙|˙") + "˙\\"
            sep_down = "\\." + row.zip(width).map { |_, w| "." * w }.join(".|.") + "./"
            result << sep_up
            result.concat(row_lines.call(row, width))
            result << sep_down
          else
            result << line
          end
        end
        result << top_line
        result.join("\n") + "\n"
      end

      def artistic_table_minimal(header, rows)
        width = Array.new(header.length, 0)
        ([header] + rows).each do |r|
          r.each_with_index do |val, idx|
            width[idx] = [width[idx], val.to_s.length].max
          end
        end
        pad = lambda { |s, w| s.to_s + " " * (w - s.to_s.length) }
        top_line = "+-" + width.map { |w| "-" * w }.join("-+-") + "-+"
        header_line = "| " + header.zip(width).map { |h, w| pad.call(h, w) }.join(" | ") + " |"
        result = [top_line, header_line, top_line]
        rows.each do |row|
          result << "| " + row.zip(width).map { |r, w| pad.call(r, w) }.join(" | ") + " |"
        end
        result << top_line
        result.join("\n") + "\n"
      end

      def csv_output(header, rows)
        io = StringIO.new
        writer = CSV.new(io)
        writer << header
        rows.each { |row| writer << row }
        io.string
      end

      def sort_list(input_list_json)
        dump_json(load_json(input_list_json).sort)
      end

      def in_list(item, a_list)
        load_json(a_list).include?(item) ? 1 : 0
      end

      def assemble_record(field_value_list)
        field_value_list = load_json(field_value_list)
        result = {}
        field_value_list.each do |kv|
          if kv.is_a?(Hash) && kv.key?("arg") && kv.key?("value")
            result[kv["arg"]] = kv["value"]
          else
            return "ERROR: AssembleRecord called on bad input: #{field_value_list}"
          end
        end
        dump_json(result)
      end

      def disassemble_record(record)
        record = load_json(record)
        dump_json(record.map { |k, v| { "arg" => k, "value" => v } })
      end

      def user_error(error_text)
        warn("[USER DEFINED ERROR]: #{error_text}")
        raise "User error"
      end

      def fingerprint(s)
        digest = Digest::MD5.hexdigest(s.to_s)[0, 16].to_i(16)
        digest - (1 << 63)
      end

      def sqlite_connect(database = ":memory:")
        con = SQLite3::Database.new(database)
        extend_connection_with_logica_functions(con)
        con
      end

      def extend_connection_with_logica_functions(con)
        mod = LogicaRb::Common::Sqlite3Logica
        con.create_aggregate("ArgMin", 3) do
          step { |ctx, arg, value, limit| mod.argmin_step(ctx, arg, value, limit) }
          finalize { |ctx| ctx.result = mod.argmin_finalize(ctx) }
        end
        con.create_aggregate("ArgMax", 3) do
          step { |ctx, arg, value, limit| mod.argmax_step(ctx, arg, value, limit) }
          finalize { |ctx| ctx.result = mod.argmax_finalize(ctx) }
        end
        con.create_aggregate("DistinctListAgg", 1) do
          step { |ctx, element| mod.distinct_list_step(ctx, element) }
          finalize { |ctx| ctx.result = mod.distinct_list_finalize(ctx) }
        end
        con.create_aggregate("ARRAY_CONCAT_AGG", 1) do
          step { |ctx, value| mod.array_concat_agg_step(ctx, value) }
          finalize { |ctx| ctx.result = mod.array_concat_agg_finalize(ctx) }
        end
        con.create_aggregate("ANY_VALUE", 1) do
          step { |ctx, value| mod.take_first_step(ctx, value) }
          finalize { |ctx| ctx.result = mod.take_first_finalize(ctx) }
        end

        con.create_function("PrintToConsole", 1) { |func, message| func.result = mod.print_to_console(message) }
        con.create_function("ARRAY_CONCAT", 2) { |func, a, b| func.result = mod.array_concat(a, b) }
        con.create_function("JOIN_STRINGS", 2) { |func, a, b| func.result = mod.join(a, b) }
        con.create_function("ReadFile", 1) { |func, filename| func.result = mod.read_file(filename) }
        con.create_function("WriteFile", 2) { |func, filename, content| func.result = mod.write_file(filename, content) }
        con.create_function("SQRT", 1) { |func, x| func.result = Math.sqrt(x.to_f) }
        con.create_function("POW", 2) { |func, x, p| func.result = x.to_f**p.to_f }
        con.create_function("Exp", 1) { |func, x| func.result = Math.exp(x.to_f) }
        con.create_function("Log", 1) { |func, x| func.result = Math.log(x.to_f) }
        con.create_function("Sin", 1) { |func, x| func.result = Math.sin(x.to_f) }
        con.create_function("Cos", 1) { |func, x| func.result = Math.cos(x.to_f) }
        con.create_function("Asin", 1) { |func, x| func.result = Math.asin(x.to_f) }
        con.create_function("Acos", 1) { |func, x| func.result = Math.acos(x.to_f) }
        con.create_function("Split", 2) { |func, x, y| func.result = mod.dump_json(x.to_s.split(y.to_s)) }
        con.create_function("ARRAY_TO_STRING", 2) do |func, x, y|
          if x.is_a?(Array)
            func.result = x.join(y.to_s)
          else
            func.result = x.to_s.chars.join(y.to_s)
          end
        end
        con.create_function("SortList", 1) { |func, x| func.result = mod.sort_list(x) }
        con.create_function("MagicalEntangle", 2) { |func, x, _y| func.result = x }
        con.create_function("IN_LIST", 2) { |func, item, list| func.result = mod.in_list(item, list) }
        con.create_function("ERROR", 1) { |func, msg| func.result = mod.user_error(msg) }
        con.create_function("Fingerprint", 1) { |func, s| func.result = mod.fingerprint(s) }
        con.create_function("Floor", 1) { |func, x| func.result = x.to_f.floor }
        con.create_function("RE_SUB", 5) do |func, string, pattern, repl, count, flags|
          re = Regexp.new(pattern.to_s, flags.to_i)
          text_val = string.to_s
          count = count.to_i
          if count <= 0
            func.result = text_val.gsub(re, repl.to_s)
          else
            count.times do
              break unless text_val.match?(re)
              text_val = text_val.sub(re, repl.to_s)
            end
            func.result = text_val
          end
        end

        # Optional intelligence/clingo hooks not implemented in Ruby.
        con.create_function("Intelligence", 1) { |func, _command| func.result = nil }
        con.create_function("RunClingo", 1) { |func, _script| func.result = nil }
        con.create_function("RunClingoFile", 1) { |func, _file| func.result = nil }
        con.create_function("AssembleRecord", 1) { |func, v| func.result = mod.assemble_record(v) }
        con.create_function("DisassembleRecord", 1) { |func, v| func.result = mod.disassemble_record(v) }
      end

      def run_sql_script(statements, output_format)
        raise "RunSqlScript requires non-empty statements list." if statements.empty?

        connect = sqlite_connect
        cursor = connect
        statements[0..-2].each { |s| cursor.execute_batch(s) }
        rows = cursor.execute2(statements[-1])
        header = rows.shift || []
        connect.close

        case output_format
        when "artistictable"
          artistic_table(header, rows)
        when "csv"
          csv_output(header, rows)
        else
          raise "Bad output format: #{output_format}"
        end
      end

      def run_sql(sql, output_format = "artistictable")
        connect = sqlite_connect
        rows = connect.execute2(sql)
        header = rows.shift || []
        connect.close
        case output_format
        when "artistictable"
          artistic_table(header, rows)
        when "csv"
          csv_output(header, rows)
        else
          raise "Bad output format: #{output_format}"
        end
      end
    end
  end
end
