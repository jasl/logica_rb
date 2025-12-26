# frozen_string_literal: true

module LogicaRb
  module Rails
    QueryDefinition = Data.define(
      :name,
      :file,
      :predicate,
      :format,
      :engine,
      :flags,
      :as,
      :import_root
    ) do
      def initialize(name:, file:, predicate:, format: :query, engine: :auto, flags: {}, as: nil, import_root: nil)
        super(
          name: name&.to_sym,
          file: file,
          predicate: predicate.to_s,
          format: (format || :query).to_sym,
          engine: engine,
          flags: flags || {},
          as: as,
          import_root: import_root
        )
      end
    end
  end
end
