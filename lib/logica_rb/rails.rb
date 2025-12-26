# frozen_string_literal: true

require "logica_rb"

begin
  require "active_support/lazy_load_hooks"
  require "active_support/core_ext/class/attribute"
  require "active_support/ordered_options"
rescue LoadError
  raise LogicaRb::MissingOptionalDependencyError.new(
    "activesupport",
    'ActiveSupport is required for logica_rb Rails integration. Add `gem "activesupport"` (or install Rails).'
  )
end

require_relative "rails/configuration"
require_relative "rails/engine_detector"
require_relative "rails/compiler_cache"
require_relative "rails/catalog"
require_relative "rails/executor"
require_relative "rails/query_definition"
require_relative "rails/query"
require_relative "rails/model_dsl"

module LogicaRb
  module Rails
    DEFAULT_CONFIGURATION = Configuration.new(
      import_root: nil,
      cache: true,
      cache_mode: :mtime,
      default_engine: nil
    )

    @configuration = DEFAULT_CONFIGURATION
    @installed = false

    def self.configure
      options = ActiveSupport::OrderedOptions.new
      cfg = @configuration || DEFAULT_CONFIGURATION

      options.import_root = cfg.import_root
      options.cache = cfg.cache
      options.cache_mode = cfg.cache_mode
      options.default_engine = cfg.default_engine

      yield options if block_given?

      @configuration = Configuration.new(
        import_root: options.import_root,
        cache: options.cache.nil? ? cfg.cache : !!options.cache,
        cache_mode: (options.cache_mode || cfg.cache_mode || :mtime).to_sym,
        default_engine: options.default_engine&.to_s
      )

      clear_cache!
      nil
    end

    def self.configuration
      base = @configuration || DEFAULT_CONFIGURATION

      app_cfg =
        if defined?(::Rails) && ::Rails.respond_to?(:application)
          app = ::Rails.application
          app&.config&.respond_to?(:logica_rb) ? app.config.logica_rb : nil
        end

      return base unless app_cfg

      import_root = app_cfg.respond_to?(:import_root) ? app_cfg.import_root : nil
      import_root = import_root.to_path if import_root.respond_to?(:to_path)

      cache = app_cfg.respond_to?(:cache) ? app_cfg.cache : nil
      cache_mode = app_cfg.respond_to?(:cache_mode) ? app_cfg.cache_mode : nil
      default_engine = app_cfg.respond_to?(:default_engine) ? app_cfg.default_engine : nil

      Configuration.new(
        import_root: import_root.nil? ? base.import_root : import_root,
        cache: cache.nil? ? base.cache : !!cache,
        cache_mode: cache_mode.nil? ? base.cache_mode : cache_mode.to_sym,
        default_engine: default_engine.nil? ? base.default_engine : default_engine&.to_s
      )
    end

    def self.cache
      @cache ||= CompilerCache.new
    end

    def self.clear_cache!
      return nil unless instance_variable_defined?(:@cache) && @cache

      @cache.clear!
      nil
    end

    def self.install!
      return if @installed

      ActiveSupport.on_load(:active_record) do
        extend LogicaRb::Rails::ModelDSL
      end

      @installed = true
    end

    def self.query(
      file: nil,
      source: nil,
      predicate:,
      connection: nil,
      engine: :auto,
      flags: {},
      format: :query,
      import_root: nil,
      trusted: nil,
      allow_imports: nil,
      as: nil
    )
      connection ||= defined?(::ActiveRecord::Base) ? ::ActiveRecord::Base.connection : nil
      unless connection
        raise LogicaRb::MissingOptionalDependencyError.new(
          "activerecord",
          'ActiveRecord is required for LogicaRb::Rails.query. Add `gem "activerecord"` (or install Rails).'
        )
      end

      definition = QueryDefinition.new(
        name: nil,
        file: file,
        source: source,
        predicate: predicate,
        engine: engine,
        format: format,
        flags: flags,
        as: as,
        import_root: import_root,
        trusted: trusted,
        allow_imports: allow_imports
      )

      cfg = configuration
      cache = cfg.cache ? LogicaRb::Rails.cache : nil
      Query.new(definition, connection: connection, cache: cache)
    end

    def self.cte(name, file: nil, source: nil, predicate:, model: nil, **opts)
      query(file: file, source: source, predicate: predicate, **opts).cte(name, model: model)
    end
  end
end

LogicaRb::Rails.install!

require_relative "rails/railtie" if defined?(::Rails::Railtie)
