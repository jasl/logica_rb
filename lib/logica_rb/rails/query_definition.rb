# frozen_string_literal: true

module LogicaRb
  module Rails
    QueryDefinition = Data.define(
      :name,
      :file,
      :source,
      :predicate,
      :format,
      :engine,
      :flags,
      :as,
      :import_root,
      :trusted,
      :allow_imports,
      :capabilities,
      :library_profile
    ) do
      def initialize(
        name:,
        file: nil,
        source: nil,
        predicate:,
        format: :query,
        engine: :auto,
        flags: {},
        as: nil,
        import_root: nil,
        trusted: nil,
        allow_imports: nil,
        capabilities: nil,
        library_profile: nil
      )
        file = normalize_optional_string(file)
        source = normalize_optional_string(source)
        predicate = predicate.to_s
        raise ArgumentError, "predicate must be provided" if predicate.empty?

        if file.nil? && source.nil?
          raise ArgumentError, "Exactly one of file or source must be provided"
        end
        if !file.nil? && !source.nil?
          raise ArgumentError, "file and source are mutually exclusive (provide only one)"
        end

        trusted =
          if trusted.nil?
            file ? true : false
          else
            !!trusted
          end

        format = (format || :query).to_sym

        if source && !trusted && format != :query
          raise ArgumentError, "source queries require format: :query unless trusted: true"
        end

        allow_imports =
          if allow_imports.nil?
            source ? trusted : true
          else
            !!allow_imports
          end

        effective_capabilities =
          if capabilities.nil?
            if source && !trusted
              []
            else
              LogicaRb::Rails.configuration.capabilities
            end
          else
            LogicaRb::Rails.normalize_capabilities(capabilities)
          end

        effective_library_profile =
          if source && !trusted
            :safe
          else
            base = LogicaRb::Rails.configuration.library_profile
            LogicaRb::Rails.normalize_library_profile(library_profile.nil? ? base : library_profile)
          end

        super(
          name: name&.to_sym,
          file: file,
          source: source,
          predicate: predicate,
          format: format,
          engine: engine,
          flags: flags || {},
          as: as,
          import_root: import_root,
          trusted: trusted,
          allow_imports: allow_imports,
          capabilities: effective_capabilities,
          library_profile: effective_library_profile
        )
      end

      private

      def normalize_optional_string(value)
        return nil if value.nil?

        str =
          if value.respond_to?(:to_path)
            value.to_path
          else
            value.to_s
          end

        return nil if str.empty?
        str
      end
    end
  end
end
