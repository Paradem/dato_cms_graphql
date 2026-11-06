# frozen_string_literal: true

module ParademCmsSite
  class RailsDoctor
    def initialize(installation)
      @installation = installation
      @manifest = installation.manifest
    end

    def problems
      issues = Doctor.new(@manifest).problems
      settings = @manifest.data.fetch("rails")
      config = ParademCmsSite.configuration
      issues << "Configure the shared CMS sync callable" unless config.sync.respond_to?(:call)
      %i[within_transaction after_sync webhook_context on_error].each do |name|
        value = config.public_send(name)
        issues << "Configured #{name} hook must respond to call" unless value.nil? || value.respond_to?(:call)
      end
      fixture = @manifest.path_for(:fixture_data)
      unless @manifest.path_for(:delivery_schema).file?
        issues << "Supply the local GraphQL delivery schema for offline query validation (cms:schema:snapshot writes the snapshot without refreshing content)"
      end
      unless issues.any?
        begin
          client = ClientFactory.new(@manifest).call
          @installation.query_classes.each do |query|
            unless query < ParademCmsSite::Query
              issues << "Installed queries must inherit ParademCmsSite::Query"
              next
            end
            definition = query.const_get(query.single_instance? ? :SINGLE : :INDEX)
            client.parse(definition.document.to_query_string)
            client.parse(query.const_get(:META_DATA).document.to_query_string) unless query.single_instance?
          end
        rescue ConfigurationError, GraphQL::Error, GraphQL::Client::ValidationError, KeyError, NameError, SystemCallError => error
          issues << "Invalid local query/schema configuration (#{error.class})"
        end
      end
      check_cache(issues)
      if settings.fetch("webhook") != "disabled"
        issues << "Configure webhook authentication" unless config.webhook_authentication.respond_to?(:call)
        route = ::Rails.application.routes.recognize_path("/webhooks/dato", method: :post)
        unless route[:controller] == "paradem_cms_site/webhooks" && route[:action] == "create"
          issues << "Webhook route does not target the shared controller"
        end
        issues << "Configure DATO_WEBHOOK_SECRET" if ENV["DATO_WEBHOOK_SECRET"].blank?
        adapter = RefreshJob.queue_adapter.class.name
        if adapter.end_with?("InlineAdapter") || (::Rails.env.production? && adapter.end_with?("AsyncAdapter", "TestAdapter"))
          issues << "Configure an asynchronous, production-appropriate ActiveJob queue adapter"
        end
      end
      issues << "Configure DATO_API_TOKEN" if !fixture && ENV["DATO_API_TOKEN"].blank?
      issues
    rescue ActionController::RoutingError
      issues << "Missing POST /webhooks/dato route"
    end

    private

    def check_cache(issues)
      record = @installation.record_class
      unless record < ActiveRecord::Base && record.base_class == record && !record.abstract_class? && record.include?(CacheRecord)
        issues << "Configure a dedicated CMS cache base model with ParademCmsSite::CacheRecord"
        return
      end
      config = record.connection_db_config
      if config.adapter == "sqlite3" && config.database != ":memory:" && !File.file?(config.database)
        issues << "Run bin/rails db:migrate to create the CMS cache"
        return
      end
      record.connection_pool.with_connection do |connection|
        unless connection.table_exists?(record.table_name)
          issues << "Run bin/rails db:migrate to create the CMS cache"
          next
        end
        columns = record.columns_hash
        %w[type locale cms_id render permalink cms_record].each do |name|
          issues << "Missing CMS cache column: #{name}" unless columns.key?(name)
        end
        expected_type = (@manifest.locale_storage == "string") ? :string : :integer
        issues << "CMS cache locale storage does not match the manifest" unless columns["locale"]&.type == expected_type
        unless record.defined_enums["locale"] == @manifest.locale_mapping
          issues << "CMS cache locale enum does not match the manifest"
        end
        unless connection.indexes(record.table_name).any? { |index| index.unique && index.columns == %w[type locale cms_id] }
          issues << "Missing unique CMS identity index (type, locale, cms_id)"
        end
      end
    rescue NameError, ActiveRecord::ActiveRecordError => error
      issues << "Unable to inspect the installed CMS cache (#{error.class})"
    end
  end
end
