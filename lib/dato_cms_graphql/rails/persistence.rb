module DatoCmsGraphql::Rails::Persistence
  def self.persist_record(query, record)
    Object.const_get(query.query_name)
      .find_or_create_by(
        locale: I18n.locale,
        cms_id: record.id
      )
      .update(
        render: query.render?,
        permalink: record.permalink,
        cms_record: record.localized_raw_attributes
      )
  end

  def self.cache_data
    DatoCmsGraphql.queries.each do |query|
      I18n.available_locales.each do |locale|
        I18n.with_locale(locale) do
          if query.single_instance?
            record = query.get
            persist_record(query, record)
          else
            query.all.each do |record|
              persist_record(query, record)
            end
          end
        end
      end
    end
  end
end
