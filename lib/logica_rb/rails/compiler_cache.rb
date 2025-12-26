# frozen_string_literal: true

require "json"
require "pathname"

module LogicaRb
  module Rails
    class CompilerCache
      def initialize
        @mutex = Mutex.new
        @cache = {}
      end

      def clear!
        @mutex.synchronize { @cache.clear }
        nil
      end

      def fetch(definition, connection:)
        key_data = cache_key_data(definition, connection: connection)
        key = JSON.generate(LogicaRb::Util.sort_keys_recursive(key_data))

        cached = @mutex.synchronize { @cache[key] }
        return cached if cached

        compilation = compile(definition, connection: connection, key_data: key_data)

        @mutex.synchronize { @cache[key] ||= compilation }
      end

      private

      def cache_key_data(definition, connection:)
        engine = resolve_engine(definition.engine, connection: connection)
        import_root = resolve_import_root(definition.import_root)
        cache_mode = (LogicaRb::Rails.configuration.cache_mode || :mtime).to_sym

        file_path = resolve_logica_file_path(definition.file, import_root: import_root)
        realpath = File.realpath(file_path)

        flags = definition.flags || {}
        normalized_flags = flags.transform_keys(&:to_s)

        deps = dependencies_for(realpath, import_root: import_root, cache_mode: cache_mode)

        {
          cache_mode: cache_mode.to_s,
          engine: engine,
          file: realpath,
          predicate: definition.predicate.to_s,
          format: (definition.format || :query).to_s,
          flags: normalized_flags.sort.to_h,
          import_root: import_root_key(import_root),
          dependencies_mtime: deps[:mtimes],
        }
      end

      def compile(definition, connection:, key_data:)
        engine = key_data.fetch(:engine)
        import_root = resolve_import_root(definition.import_root)
        predicate = definition.predicate.to_s
        flags = (definition.flags || {}).transform_keys(&:to_s)

        file_path = resolve_logica_file_path(definition.file, import_root: import_root)
        file_path = File.realpath(file_path)

        compilation = LogicaRb::Transpiler.compile_file(
          file_path,
          predicates: predicate,
          engine: engine,
          user_flags: flags,
          import_root: import_root_for_parser(import_root)
        )

        compilation.metadata["dependencies"] = key_data.dig(:dependencies_mtime)&.keys&.sort
        compilation
      end

      def resolve_engine(engine, connection:)
        engine = engine.to_s if engine.is_a?(Symbol)
        return engine.to_s if engine && !engine.empty? && engine != "auto"

        cfg = LogicaRb::Rails.configuration
        cfg.default_engine&.to_s || EngineDetector.detect(connection)
      end

      def resolve_import_root(import_root)
        return nil if import_root.nil?

        if import_root.is_a?(Array)
          import_root.map { |r| r.respond_to?(:to_path) ? r.to_path : r.to_s }
        else
          import_root.respond_to?(:to_path) ? import_root.to_path : import_root.to_s
        end
      end

      def import_root_key(import_root)
        return nil if import_root.nil?
        return import_root.map { |p| File.expand_path(p.to_s) }.sort if import_root.is_a?(Array)

        File.expand_path(import_root.to_s)
      end

      def import_root_for_parser(import_root)
        return "" if import_root.nil?
        return import_root.map(&:to_s) if import_root.is_a?(Array)

        import_root.to_s
      end

      def resolve_logica_file_path(file, import_root:)
        file = file.to_s
        return File.expand_path(file) if Pathname.new(file).absolute?
        return File.expand_path(file) if import_root.nil?

        roots = import_root.is_a?(Array) ? import_root : [import_root]
        roots.each do |root|
          next if root.nil? || root.to_s.empty?
          candidate = File.join(root.to_s, file)
          return File.expand_path(candidate) if File.exist?(candidate)
        end

        File.expand_path(File.join(roots.first.to_s, file))
      end

      def dependencies_for(file_path, import_root:, cache_mode:)
        return { files: [file_path], mtimes: { file_path => File.mtime(file_path).to_i } } unless cache_mode == :mtime

        source = File.read(file_path)
        parsed_imports = {}
        LogicaRb::Parser.parse_file(source, import_root: import_root_for_parser(import_root), parsed_imports: parsed_imports)

        dep_paths = parsed_imports.keys.map do |file_import_str|
          resolve_imported_file_path(file_import_str, import_root: import_root_for_parser(import_root))
        end

        all = ([file_path] + dep_paths).uniq
        mtimes = all.each_with_object({}) { |p, h| h[p] = File.mtime(p).to_i }
        { files: all, mtimes: mtimes.sort.to_h }
      end

      def resolve_imported_file_path(file_import_str, import_root:)
        parts = file_import_str.to_s.split(".")

        if import_root.is_a?(Array)
          considered = import_root.map { |root| File.join(root.to_s, File.join(parts) + ".l") }
          existing = considered.find { |p| File.exist?(p) }
          return existing || considered.first
        end

        File.join(import_root.to_s, File.join(parts) + ".l")
      end
    end
  end
end
