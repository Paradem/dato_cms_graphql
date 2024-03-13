desc "A rake task to persist the DatoCMS data locally"
task cache_dato: :environment do
  DatoCmsGraphql::Rails::Persistence.cache_data
end
