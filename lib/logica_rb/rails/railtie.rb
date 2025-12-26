# frozen_string_literal: true

module LogicaRb
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "logica_rb.configure" do |app|
        app.config.logica_rb ||= ActiveSupport::OrderedOptions.new

        app.config.logica_rb.import_root ||= ::Rails.root.join("app/logica").to_s
        app.config.logica_rb.default_format ||= :query
        app.config.logica_rb.default_engine ||= nil
        app.config.logica_rb.cache = false if app.config.logica_rb.cache.nil?

        LogicaRb::Rails.install!
      end
    end
  end
end
