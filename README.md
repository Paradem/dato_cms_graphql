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
