# frozen_string_literal: true

require "json"

require_relative "parser"
require_relative "compiler/universe"
require_relative "type_inference/research/infer"
require_relative "util"

module LogicaRb
  class Pipeline
    def self.parse_file(source, import_root: nil)
      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      pretty_json(parsed_rules)
    end

    def self.infer_types(source, dialect: "psql", import_root: nil)
      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      typing_engine = TypeInference::Research::Infer::TypesInferenceEngine.new(parsed_rules, dialect)
      typing_engine.infer_types
      pretty_json(parsed_rules)
    end

    def self.show_signatures(source, dialect: "psql", import_root: nil)
      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      typing_engine = TypeInference::Research::Infer::TypesInferenceEngine.new(parsed_rules, dialect)
      typing_engine.infer_types
      typing_engine.show_predicate_types + "\n"
    end

    def self.compile_predicate(source, predicate:, user_flags: {}, import_root: nil)
      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      program = Compiler::LogicaProgram.new(parsed_rules, user_flags: user_flags)
      formatted_sql = program.formatted_predicate_sql(predicate)
      { program: program, formatted_sql: formatted_sql }
    end

    def self.pretty_json(obj)
      sorted = LogicaRb::Util.sort_keys_recursive(obj)
      JSON.pretty_generate(sorted, indent: " ", space: " ", space_before: "", object_nl: "\n", array_nl: "\n") + "\n"
    end
  end
end
