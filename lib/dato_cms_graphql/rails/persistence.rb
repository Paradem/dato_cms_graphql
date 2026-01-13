module DatoCmsGraphql::Rails
  module Persistence
    def self.persist_record(query, record)
      return if record.id.nil?

      cms_id = record.id
      existing = Record.find_by(
        type: query.query_name,
        locale: I18n.locale,
        cms_id: cms_id
      )
      if existing
        existing.update(
          render: query.render?,
          permalink: (record.permalink if record.respond_to?(:permalink)),
          cms_record: record.localized_raw_attributes
        )
      else
        Record.create(
          type: query.query_name,
          locale: I18n.locale,
          cms_id: cms_id,
          render: query.render?,
          permalink: (record.permalink if record.respond_to?(:permalink)),
          cms_record: record.localized_raw_attributes
        )
      end
    end

    def self.cache_data
      DatoCmsGraphql.queries.each do |query|
        I18n.available_locales.each do |locale|
          I18n.with_locale(locale) do
            if query.single_instance?
              record = query.get
              persist_record(query, record)
            else
              query.all.uniq { |r| r.id }.each do |record|
                persist_record(query, record)
              end
            end
          end
        end
      end
    end
  end
end
