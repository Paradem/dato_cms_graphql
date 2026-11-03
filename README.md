# DatoCmsGraphql

A "simple" library to aid in connecting to the DatoCMS graphql api.
## Installation

I don't plan to publish this gem for a while, so for now install it from github.

## Usage

In your application you define classes that will represent a query to the api.

```ruby
class News < DatoCmsGraphql::GrapqlBase
  graphql_fields(:id, :title)
end

# Usage

News.all.each do |item| 
  # do something interesting with your news items.
end
```

## HTTP transport and published content

`DatoCmsGraphql::HTTPTransport` supplies the default `HTTP` transport used by both
schema introspection and delivery. Set `DATO_ENVIRONMENT` explicitly when selecting
a non-default environment; the same header is used throughout initialization.
`DATO_API_TOKEN` and the optional editing-link `PROJECT` remain host configuration.

Published fetches must opt out of drafts explicitly, even if a legacy process-wide
preview flag is enabled:

```ruby
DatoCmsGraphql::Client.query(query, variables: {}, context: {include_drafts: false})
```

Only boolean `true` in the request context, or the exact environment value
`DATO_API_INCLUDE_DRAFTS=true` when the context has no policy, enables the draft
header. False/blank values omit it; an explicit false HTTP header is never sent.
Public-cache clients should always use `include_drafts: false`. Independent preview
clients and their authorization/cache boundaries remain the application's policy.

The transport is also independently available without initializing a client or
loading a schema:

```ruby
require "dato_cms_graphql/http_transport"
transport = DatoCmsGraphql::HTTPTransport.new
headers = transport.headers(include_drafts: false)
```

Requiring/constructing this class does not contact DatoCMS. Reading headers needs
the configured token; requiring the main library with a real token retains its
existing boot-time schema loading. Version 0.4.2 retains 0.4.1's string-backed
CacheTable locale enum: older integer-backed consumers need an explicit reviewed
upgrade, not a blind Git repin just to adopt the transport.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake test` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and the created tag, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Paradem/dato_cms_graphql.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
