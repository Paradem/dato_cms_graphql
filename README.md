# DatoCmsGraphql

[![Ruby Version](https://img.shields.io/badge/ruby-3.2%2B-brightgreen)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Ruby gem that simplifies integrating DatoCMS GraphQL API into Rails applications, enabling dynamic route generation, content caching, and seamless query building for headless CMS functionality.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Dynamic Route Generation**: Automatically creates Rails routes from DatoCMS content for SEO-friendly URLs.
- **Content Caching**: Persists DatoCMS data in a local database for improved performance.
- **GraphQL Query Building**: Declarative query classes with support for nested fields, blocks, and localization.
- **Rails Integration**: Seamless integration via Railtie, with queries in `app/queries`.
- **Localization Support**: Multi-locale content fetching with fallbacks.
- **Pagination and Meta Data**: Built-in support for paginated queries and count metadata.
- **SEO Meta Tags**: Automatic inclusion of SEO metadata from DatoCMS.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'dato_cms_graphql', git: 'https://github.com/Paradem/dato_cms_graphql.git'
```

And then execute:

```bash
bundle install
```

Note: This gem is not yet published to RubyGems.org. Install from GitHub until release.

## Requirements

- Ruby 3.2.0 or higher (tested with Ruby 3.4.5)
- Bundler for dependency management
- A DatoCMS account with GraphQL API access

## Configuration

### Environment Variables

Set the following environment variables:

- `DATO_API_TOKEN`: Your DatoCMS API token (required).
- `DATO_API_INCLUDE_DRAFTS`: Set to `true` to include draft content (optional).

### Rails Setup

1. Ensure your Rails app has a database configured.

2. Create a migration for the cache table:

   ```ruby
   # db/migrate/20240309043109_create_records.rb
   class CreateRecords < ActiveRecord::Migration[7.0]
     def change
       create_table :records do |t|
         t.string :type, null: false
         t.integer :locale, null: false
         t.integer :cms_id, null: false
         t.string :permalink
         t.json :cms_record
         t.boolean :render, default: true
         t.timestamps
       end
       add_index :records, [:type, :locale, :cms_id], unique: true
       add_index :records, [:type, :render, :permalink]
     end
   end
   ```

3. Create the Record model:

   ```ruby
   # app/models/record.rb
   class Record < ApplicationRecord
     include DatoCmsGraphql::Rails::CacheTable
   end
   ```

4. Run migrations:

   ```bash
   rails db:migrate
   ```

 5. Cache DatoCMS data:

    ```bash
    rake dato_cms:cache
    ```

### Manual Setup (Non-Rails)

For non-Rails environments or manual configuration:

```ruby
DatoCmsGraphql.path_to_queries = "/path/to/your/queries"
```

This sets the path where query classes are loaded from, as demonstrated in the tests.

### Routes Configuration

In `config/routes.rb`, add dynamic routing:

```ruby
Rails.application.routes.draw do
  # Dynamically create routes for all Queries
  DatoCmsGraphql::Rails::Routing.draw_routes(Record)

  # Other routes...
end
```

## Usage

### Defining Query Classes

Create query classes in `app/queries/` that inherit from `DatoCmsGraphql::BaseQuery`:

```ruby
# app/queries/news_query.rb
class NewsQuery < DatoCmsGraphql::BaseQuery
  graphql_fields(:id, :permalink, :title, :publication_date)
end
```

For complex fields with nested data:

```ruby
class NewsQuery < DatoCmsGraphql::BaseQuery
  graphql_fields(
    :id,
    :permalink,
    :title,
    photos: [:url, :alt, focal_point: [:x, :y]],
    content: [
      :value,
      blocks: [
        "... on ImageRecord": [image: [:url, :alt]]
      ]
    ]
   )
end
```

After defining fields, query instances provide access to attributes:

```ruby
# Assuming attributes from a query result
attributes = {"id" => "aOgVuOkbTpKl56nHftl3FA", ...}
news_item = NewsQuery.new(attributes.deep_transform_keys(&:underscore))
puts news_item.id  # => "aOgVuOkbTpKl56nHftl3FA"
```

### Query Options

- **Page Size**: Set `page_size(50)` for pagination.
- **Single Instance**: Use `single_instance(true)` for singleton models.
- **Custom Route**: Override `def self.route; "news/:permalink"; end` for custom paths.
- **Rendering**: Control with `render(false)` to exclude from routing.

### Fetching Data

```ruby
# Get all items
NewsQuery.all.each do |news_item|
  puts news_item.title
end

# Get a single item
home = HomeQuery.get
puts home.title

# Access nested attributes
news_item.photos.each do |photo|
  puts photo.url
end
```

### Controllers

Use cached records in controllers:

```ruby
# app/controllers/news_controller.rb
class NewsController < ApplicationController
  def show
    @news = News.find_by(locale: I18n.locale, permalink: params[:permalink])
  end
end
```

## API Reference

### DatoCmsGraphql::BaseQuery

- `graphql_fields(*fields)`: Defines GraphQL fields for the query.
- `page_size(size)`: Sets pagination size (default: 100).
- `single_instance(bool)`: Marks as singleton (default: false).
- `render(bool)`: Includes in dynamic routing (default: true).
- `all`: Returns a ModelIterator for paginated access.
- `get`: Fetches single instance.
- `route`: Returns route pattern (default: ":permalink").

### DatoCmsGraphql::Client

- `query(graphql_string, variables: {})`: Executes a raw GraphQL query.
- `count(query, variables: {})`: Gets total count for a query.

### DatoCmsGraphql::Fields

- `new(fields_array)`: Initializes with an array of fields (symbols/strings/hashes).
- `to_query`: Generates a GraphQL query string from the fields structure.

### Rails Modules

- `DatoCmsGraphql::Rails::Routing.draw_routes(base_class)`: Generates routes.
- `DatoCmsGraphql::Rails::Persistence.cache_data`: Caches data to database.

## Examples

See the [sample Rails application](https://github.com/Paradem/datocms_rails_prototype) for a complete integration example.

### Basic News Query

```ruby
class NewsQuery < DatoCmsGraphql::BaseQuery
  graphql_fields(:id, :permalink, :title, :publication_date)
end
```

### Advanced Page Query with Structured Text

```ruby
class PageQuery < DatoCmsGraphql::BaseQuery
  graphql_fields(
    :id, :title, :permalink,
    content: [
      "... on ProseRecord": [:content],
      "... on ImageRecord": [image: [:url, :alt]]
    ]
  )

  def self.route
    "pages/:permalink"
  end
end
```

### Manual GraphQL Query Generation

Use the `Fields` class for direct query string generation:

```ruby
fields = [
  :id, :title,
  :permalink, :_status,
  :_first_published_at,
  interview_location: [:latitude, :longitude],
  featured_image: [colors: [:alpha]]
]

query_string = DatoCmsGraphql::Fields.new(fields).to_query
# Generates: id\ntitle\npermalink\n_status\n_firstPublishedAt\ninterviewLocation {\n  latitude\n  longitude\n}\nfeaturedImage {\n  colors {\n    alpha\n  }\n}\n
```

### Caching Task

Add to your Rakefile or run manually:

```ruby
# lib/tasks/dato_cache.rake
namespace :dato_cms do
  task cache: :environment do
    DatoCmsGraphql::Rails::Persistence.cache_data
  end
end
```

## Troubleshooting

### Common Issues

- **API Token Invalid**: Ensure `DATO_API_TOKEN` is set correctly in your environment.
- **Routes Not Generating**: Check that queries have `render: true` and run `rake dato_cms:cache`.
- **Localization Errors**: Verify `I18n.available_locales` matches DatoCMS locales.
- **Caching Issues**: Run `rake dato_cms:cache` after content changes.

### Debug Logging

Enable Rails debug logging to see GraphQL queries:

```ruby
Rails.logger.level = :debug
```

### Support

- Check the [DatoCMS GraphQL API documentation](https://www.datocms.com/docs/content-management-api).
- Open issues on [GitHub](https://github.com/Paradem/dato_cms_graphql).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Paradem/dato_cms_graphql.

1. Fork the repository.
2. Create your feature branch (`git checkout -b my-new-feature`).
3. Commit your changes (`git commit -am 'Add some feature'`).
4. Push to the branch (`git push origin my-new-feature`).
5. Create a new Pull Request.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
