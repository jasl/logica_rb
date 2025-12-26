# frozen_string_literal: true

require "logica_rb"

begin
  require "active_support/lazy_load_hooks"
  require "active_support/ordered_options"
rescue LoadError
  raise LogicaRb::MissingOptionalDependencyError.new(
    "activesupport",
    'ActiveSupport is required for logica_rb Rails integration. Add `gem "activesupport"` (or install Rails).'
  )
end

require_relative "rails/configuration"
require_relative "rails/engine_detector"
require_relative "rails/active_record_executor"
require_relative "rails/model_dsl"

module LogicaRb
  module Rails
    @installed = false

    def self.install!
      return if @installed

      ActiveSupport.on_load(:active_record) do
        extend LogicaRb::Rails::ModelDSL
      end

      @installed = true
    end

    def self.configuration
      if defined?(::Rails) && ::Rails.respond_to?(:application)
        app = ::Rails.application
        if app && app.config.respond_to?(:logica_rb) && (opts = app.config.logica_rb)
          import_root = opts.import_root
          import_root = import_root.to_path if import_root.respond_to?(:to_path)

          default_format = (opts.default_format || :query).to_sym
          default_engine = opts.default_engine&.to_s
          cache = opts.cache.nil? ? false : !!opts.cache

          return Configuration.new(
            import_root: import_root,
            default_format: default_format,
            default_engine: default_engine,
            cache: cache
          )
        end
      end

      Configuration.new(import_root: nil, default_format: :query, default_engine: nil, cache: false)
    end
  end
end

LogicaRb::Rails.install!

require_relative "rails/railtie" if defined?(::Rails::Railtie)
