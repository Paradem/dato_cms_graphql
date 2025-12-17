# Development Commands

## General Development Commands

### Linting
bundle exec standardrb

### Testing
rake test

### Cache Sync
rake dato_cms:cache

## Testing Usage Examples

Run specific tests to validate key usage patterns demonstrated in the test suite:

### GraphQL Field Generation and Query Classes
rake test test/graphql_fields_test.rb

### Path Configuration and Basic Functionality
rake test test/dato_cms_graphql_test.rb

## Using the Gem

This section provides a step-by-step guide to using the gem, based on usage demonstrated in tests and documented in the README.

### Installation and Environment Setup
1. Add to Gemfile and bundle:
   ```
   gem 'dato_cms_graphql', git: 'https://github.com/Paradem/dato_cms_graphql.git'
   bundle install
   ```

2. Set required environment variables (from README):
   - `DATO_API_TOKEN`: Your DatoCMS API token.
   - `DATO_API_INCLUDE_DRAFTS`: Set to `true` to include draft content (optional).

### Configuration
- **Rails Setup** (from README):
  - Create a migration for the cache table (records table with type, locale, cms_id, permalink, cms_record, render, timestamps).
  - Create Record model including DatoCmsGraphql::Rails::CacheTable.
  - Run `rails db:migrate`.
  - Cache data: `rake dato_cms:cache`.
  - Configure routes: Add `DatoCmsGraphql::Rails::Routing.draw_routes(Record)` to config/routes.rb.

- **Manual/Non-Rails Setup** (from tests):
  - Set query path: `DatoCmsGraphql.path_to_queries = "/path/to/queries"` (e.g., "/app/queries").

### Defining Query Classes
1. Create classes inheriting `DatoCmsGraphql::BaseQuery` in your queries directory.
2. Use `graphql_fields` to define fields (from tests and README):
   ```ruby
   class NewsQuery < DatoCmsGraphql::BaseQuery
     graphql_fields(:id, :title, :permalink)
   end
   ```
   - For nested fields: `graphql_fields(id: [:subfield])`.

3. Optional methods (from README):
   - `page_size(50)`: Set pagination size.
   - `single_instance(true)`: For singleton models.
   - `render(false)`: Exclude from routing.

### Generating GraphQL Queries Manually
Use `DatoCmsGraphql::Fields` for direct query string generation (from tests):
```ruby
fields = [:id, :title, nested: [:field]]
query = DatoCmsGraphql::Fields.new(fields).to_query
# Produces GraphQL string like: id\ntitle\nnested {\n  field\n}\n
```

### Fetching and Accessing Data
1. For multiple items: `NewsQuery.all.each { |item| puts item.title }`.
2. For single item: `item = HomeQuery.get; puts item.title`.
3. Instantiate manually (from tests): `news = NewsQuery.new(attributes.deep_transform_keys(&:underscore)); puts news.id`.
4. Access nested attributes: `item.photos.each { |photo| puts photo.url }`.

### Controllers and Routing
- In Rails controllers: `@news = News.find_by(locale: I18n.locale, permalink: params[:permalink])`.
- Routes are auto-generated based on query classes.