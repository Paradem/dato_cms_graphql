# frozen_string_literal: true

module ParademCmsSite
  class Sync
    # Extracted from Canada's fetch/validate-before-swap cache refresher and
    # BIC's ordered HTTP pool. All persistence stays on the calling thread.
    class PublishedSource
      def initialize(manifest:, queries:, client:, concurrency:)
        @manifest = manifest
        @queries = queries.to_a
        @client = client
        @concurrency = concurrency
        unless concurrency.is_a?(Integer) && concurrency.positive?
          raise ConfigurationError, "Sync concurrency must be a positive integer"
        end
        names = @queries.map(&:query_name)
        unless names.uniq == names && names.sort == manifest.queries.sort
          raise ConfigurationError, "Sync queries must exactly match the site's owned models"
        end
        if @queries.any? { |query| manifest.optional_singletons.include?(query.query_name) && !query.single_instance? }
          raise ConfigurationError, "Only singleton queries may allow missing published data"
        end
        @queries.reject(&:single_instance?).each do |query|
          size = query.graphql_page_size
          unless size.is_a?(Integer) && size.positive?
            raise ConfigurationError, "Invalid page size for #{query.query_name}"
          end
        end
      end

      def fetch
        singles, collections = @queries.partition(&:single_instance?)
        counts = parallel_map(collections) { |query| published_count(query) }
        jobs = collections.each_with_index.flat_map do |query, index|
          counts.fetch(index).ceildiv(query.graphql_page_size).times.map { |page| [query, page] }
        end
        pages = parallel_map(jobs) do |query, page|
          published_data(query::INDEX, variables: {skip: query.graphql_page_size * page})
        end
        singleton_data = parallel_map(singles) { |query| published_data(query::SINGLE) }

        rows = []
        page_index = 0
        collections.each_with_index do |query, index|
          count = counts.fetch(index)
          query_rows = count.ceildiv(query.graphql_page_size).times.flat_map do
            data = pages.fetch(page_index)
            page_index += 1
            rows_for(query, data, single: false)
          end
          @manifest.locales.each do |locale|
            stored_locale = @manifest.locale_mapping.fetch(locale)
            localized = query_rows.select { |row| row.fetch(:locale) == stored_locale }
            unless localized.length == count && localized.map { |row| row.fetch(:cms_id) }.uniq.length == count
              raise FetchError, "Incomplete or duplicate published records for #{query.query_name} (#{locale})"
            end
          end
          rows.concat(query_rows)
        end
        singles.each_with_index do |query, index|
          rows.concat(rows_for(query, singleton_data.fetch(index), single: true))
        end
        rows
      end

      private

      def published_count(query)
        count = published_data(query::META_DATA).dig("meta_data", "count")
        unless count.is_a?(Integer) && count >= 0
          raise FetchError, "Invalid published count for #{query.query_name}"
        end
        count
      end

      def published_data(query, variables: {})
        response = @client.query(query, variables: variables, context: {include_drafts: false})
        # GraphQL's root-only errors omit errors on nested fields in partial data.
        raise FetchError, "Published CMS response contains errors" if response.errors.all.any?
        data = PlainData.call(response.data.to_h)
        raise FetchError, "Published CMS response must be an object" unless data.is_a?(Hash)
        underscore_keys(data)
      end

      def underscore_keys(value)
        case value
        when Hash
          value.to_h do |key, item|
            normalized = key.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').tr("-", "_").downcase
            [normalized, underscore_keys(item)]
          end
        when Array then value.map { |item| underscore_keys(item) }
        else value
        end
      end

      def rows_for(query, data, single:)
        @manifest.locales.flat_map do |locale|
          key = "#{locale}_#{single ? "item" : "items"}"
          raise FetchError, "Missing published data for #{query.query_name} (#{locale})" unless data.key?(key)
          if single && data.fetch(key).nil? && @manifest.optional_singletons.include?(query.query_name)
            next []
          end
          items = single ? [data.fetch(key)] : data.fetch(key)
          unless items.is_a?(Array) && items.all? { |item| item.is_a?(Hash) && item["id"].is_a?(String) && !item["id"].strip.empty? && item["id"] == item["id"].strip }
            raise FetchError, "Invalid published records for #{query.query_name} (#{locale})"
          end
          items.map do |item|
            {
              type: query.query_name,
              locale: @manifest.locale_mapping.fetch(locale),
              cms_id: item.fetch("id"),
              render: query.render?,
              permalink: @manifest.permalink_for(query.query_name, payload: item),
              cms_record: item
            }
          end
        end
      end

      def parallel_map(items)
        return items.map { |item| yield item } if items.length <= 1
        queue = Queue.new
        items.each_with_index { |item, index| queue << [index, item] }
        results = Array.new(items.length)
        errors = Queue.new
        [@concurrency, items.length].min.times.map do
          Thread.new do
            Thread.current.report_on_exception = false
            loop do
              begin
                index, item = queue.pop(true)
              rescue ThreadError
                break
              end
              begin
                results[index] = yield(item)
              rescue => error
                errors << error
                queue.clear
                break
              end
            end
          end
        end.each(&:join)
        raise errors.pop unless errors.empty?
        results
      end
    end
  end
end
