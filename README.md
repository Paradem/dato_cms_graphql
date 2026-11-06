# DatoCmsGraphql

DatoCMS GraphQL queries, transport policy and optional offline-first Rails integration.

## Rails CMS integration

Version 0.5.0 includes the former `paradem_cms_site` implementation in this public,
MIT-licensed gem: query generation, atomic published-cache refresh, coordination,
webhooks/jobs, an install generator and offline diagnostics. There is **one gem**;
`ParademCmsSite` remains the integration namespace so existing routes, initializers
and serialized jobs keep working. No private repository or build credential is
needed.

Opt in without loading the legacy global live-schema client:

```ruby
gem "dato_cms_graphql", git: "https://github.com/Paradem/dato_cms_graphql.git",
  ref: "REVIEWED_PUBLIC_COMMIT", require: "paradem_cms_site"
```

See [new Rails installation](docs/installation.md),
[existing application migration](docs/legacy-adoption.md),
[refresh semantics](docs/runtime-sync.md) and
[webhooks/configuration](docs/rails-integration.md).
Rails dependencies remain optional; client-only and Bridgetown usage is unchanged.
Requiring `paradem_cms_site` or its tooling never contacts DatoCMS.
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

The global `DatoCmsGraphql::HTTP`/`Client` is published-only, regardless of an
ambient preview flag or request context. Independently composed public clients
should also fix their policy, and pass the explicit per-request context:

```ruby
DatoCmsGraphql::Client.query(query, variables: {}, context: {include_drafts: false})
```

For independently constructed transports with no fixed policy, only boolean
`true` in context, or exact `DATO_API_INCLUDE_DRAFTS=true` without a context policy,
enables drafts. `HTTPTransport.new(include_drafts: false)` fixes published-only
behavior; `true` fixes preview behavior. Other constructor values are rejected.
Independent preview clients and their authorization/cache boundaries remain the
application's policy; do not reuse the global public client for preview.

The transport is also independently available without initializing a client or
loading a schema:

```ruby
require "dato_cms_graphql/http_transport"
transport = DatoCmsGraphql::HTTPTransport.new(include_drafts: false, environment: "staging")
headers = transport.headers(include_drafts: false)
```

Requiring/constructing this class does not contact DatoCMS. Reading headers needs
the configured token; requiring the main library with a real token retains its
existing boot-time schema loading. Omitting `environment:` reads the current
`DATO_ENVIRONMENT`; passing `environment: nil` explicitly selects the primary
endpoint without an environment header, ignoring ambient environment settings.

## Scoped query helpers

Version 0.4.4 lets `BaseQuery` subclasses override `.executor` with a
`DatoCmsGraphql::ClientExecutor.new(client: ..., context: {include_drafts: false})`.
The existing `.all` iterator, indexing and singleton `.get` keep their results
without reaching a global client. Require `dato_cms_graphql/client_executor`
directly for lazy integrations. The default executor remains `DatoCmsGraphql`.
The scoped executor rejects nested GraphQL errors and invalid counts without
logging response payloads; callers still own transport/source policy.

## Rails locale storage compatibility

New `CacheTable` models default to string-backed locale codes. Existing integer
caches must declare their **actual historical values**, before including the
concern; never infer integer positions from the current locale ordering:

```ruby
class Record < ApplicationRecord
  def self.dato_cms_locale_mapping
    {en: 0, fr: 1}
  end

  include DatoCmsGraphql::Rails::CacheTable
end
```

The mapping must cover exactly `I18n.available_locales`, with unique nonnegative
integers or each locale's own string code. Incomplete, mixed or ambiguous mappings
fail before enum definition. Configure locales before loading the model. This
changes neither the column nor persisted rows: verify the host's schema, enum
values, JSON/STI projections, permalink derivation and locale scopes before
repinning. `ModelIterator` retains `each`, count and Array-style `[]` results;
indexing re-enumerates the collection while `each` remains streaming.

The legacy `Rails::Persistence.cache_data` helper retains incremental writes and
returns a fresh set of synced CMS IDs; it is not an atomic refresh or an external
indexing pipeline. A failed call clears its ID tracking, not already-written rows.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`bundle exec rake test` to run both isolated suites (`test:core` and `test:site`),
including disposable Rails applications with synthetic content and HTTP blocked.
Run `bundle exec standardrb` and `gem build dato_cms_graphql.gemspec` before committing. You can also run `bin/console` for an interactive
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
