module DatoCmsGraphql::Rails
  module Persistence
    def self.persist_record(query, record)
      Object.const_get(query.query_name)
        .find_or_create_by(
          locale: I18n.locale,
          cms_id: record.id
        )
        .update(
          type: query.query_name,
          render: query.render?,
          permalink: (record.permalink if record.respond_to?(:permalink)),
          cms_record: record.localized_raw_attributes
        )

      @synced_ids&.add(record.id)
    end

    def self.cache_data
      @synced_ids = Set.new

      DatoCmsGraphql.queries.each do |query|
        I18n.available_locales.each do |locale|
          I18n.with_locale(locale) do
            if query.single_instance?
              persist_record(query, query.get)
            else
              query.all.each { |record| persist_record(query, record) }
            end
          end
        end
      end

      @synced_ids.dup
    ensure
      @synced_ids = nil
    end
  end
end
