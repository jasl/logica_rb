# frozen_string_literal: true

module LogicaRb
  module Rails
    class Railtie < ::Rails::Railtie
      config.logica_rb = ActiveSupport::OrderedOptions.new

      initializer "logica_rb.configure" do |app|
        app.config.logica_rb.import_root ||= ::Rails.root.join("app/logica")
        app.config.logica_rb.cache = true if app.config.logica_rb.cache.nil?
        app.config.logica_rb.cache_mode ||= :mtime
        app.config.logica_rb.default_engine ||= nil
      end

      initializer "logica_rb.active_record" do
        LogicaRb::Rails.install!
      end

      initializer "logica_rb.reloader" do
        ActiveSupport::Reloader.to_prepare do
          LogicaRb::Rails.clear_cache!
        end
      end
    end
  end
end
