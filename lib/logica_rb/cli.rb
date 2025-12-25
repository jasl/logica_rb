# frozen_string_literal: true

require "tempfile"
require "set"

require_relative "runner"
require_relative "common/color"
require_relative "pipeline"
require_relative "parser"
require_relative "compiler/universe"

module LogicaRb
  class CLI
    def self.main(argv)
      if argv.length <= 1 || argv[1] == "help"
        puts "Usage:"
        puts "  logica <l file> <command> <predicate name> [flags]"
        puts "  Commands are:"
        puts "    print: prints the StandardSQL query for the predicate."
        puts "    run: runs the StandardSQL query on BigQuery with pretty output."
        puts "    run_to_csv: runs the query on BigQuery with csv output."
        puts ""
        puts ""
        puts "Example:"
        puts "  logica - run GoodIdea <<<\" GoodIdea(snack: \\\"carrots\\\")\""
        return 1
      end

      filename = argv[0]
      command = argv[1]

      commands = %w[parse print run run_to_csv run_in_terminal infer_types show_signatures]
      unless commands.include?(command)
        puts Common::Color.format("Unknown command {warning}{command}{end}. Available commands: {commands}.",
                                  { command: command, commands: commands.join(", ") })
        return 1
      end

      if %w[parse infer_types show_signatures].include?(command)
        predicate = nil
      else
        if argv.length < 3
          warn "Not enough arguments. Run 'logica help' for help."
          return 1
        end
        predicate = argv[2]
      end

      temp_file = nil
      if filename == "-"
        temp_file = Tempfile.new(["logica", ".l"])
        temp_file.write($stdin.read)
        temp_file.flush
        filename = temp_file.path
      end

      import_root = import_root_from_env

      begin
        case command
        when "parse"
          puts Pipeline.parse_file(File.read(filename), import_root: import_root)
        when "infer_types"
          puts Runner.infer_types(src: filename, dialect: "psql", import_root: import_root)
        when "show_signatures"
          user_flags = read_user_flags(filename, import_root: import_root, argv: argv[3..])
          program = compile_program(filename, import_root: import_root, user_flags: user_flags)
          if program.typing_engine.nil?
            program.run_typechecker
          end
          puts program.typing_engine.show_predicate_types
        when "print"
          user_flags = read_user_flags(filename, import_root: import_root, argv: argv[3..])
          puts Runner.formatted_sql(src: filename, predicate: predicate, user_flags: user_flags, import_root: import_root)
        when "run", "run_to_csv", "run_in_terminal"
          user_flags = read_user_flags(filename, import_root: import_root, argv: argv[3..])
          output_format = command == "run_to_csv" ? "csv" : "artistictable"
          runner = command == "run_in_terminal" ? "concertina" : "default"
          output = Runner.run_predicate(
            src: filename,
            predicate: predicate,
            import_root: import_root,
            runner: runner,
            user_flags: user_flags,
            output_format: output_format
          )
          puts output
        end
      rescue Parser::ParsingException => e
        e.show_message
        return 1
      rescue Compiler::RuleTranslate::RuleCompileException => e
        e.show_message
        return 1
      rescue Compiler::Functors::FunctorError => e
        e.show_message
        return 1
      rescue TypeInference::Research::Infer::TypeErrorCaughtException => e
        if command == "show_signatures"
          begin
            puts program.typing_engine.show_predicate_types if program&.typing_engine
          rescue StandardError
            nil
          end
        end
        e.show_message
        return 1
      ensure
        temp_file&.close
        temp_file&.unlink
      end

      0
    end

    def self.import_root_from_env
      roots = ENV["LOGICAPATH"]
      return nil if roots.nil? || roots.empty?
      split = roots.split(":")
      split.length > 1 ? split : split.first
    end

    def self.read_user_flags(filename, import_root:, argv:)
      program_text = File.read(filename)
      parsed_rules = Parser.parse_file(program_text, import_root: import_root)["rule"]
      defined = Compiler::Annotations.extract_annotations(parsed_rules, restrict_to: ["@DefineFlag"])["@DefineFlag"].keys
      allowed = (defined + ["logica_default_engine"]).to_set

      user_flags = {}
      idx = 0
      while idx < argv.length
        arg = argv[idx]
        if arg.start_with?("--")
          key, value = arg[2..].split("=", 2)
          if value.nil?
            idx += 1
            value = argv[idx]
          end
          if key.nil? || key.empty? || value.nil?
            raise ArgumentError, "Invalid flag: #{arg}"
          end
          unless allowed.include?(key)
            raise ArgumentError, "Undefined command argument: #{key}"
          end
          user_flags[key] = value
        else
          raise ArgumentError, "Unexpected argument: #{arg}"
        end
        idx += 1
      end
      user_flags
    end

    def self.compile_program(filename, import_root:, user_flags:)
      parsed_rules = Parser.parse_file(File.read(filename), import_root: import_root)["rule"]
      Compiler::LogicaProgram.new(parsed_rules, user_flags: user_flags)
    end
  end
end
