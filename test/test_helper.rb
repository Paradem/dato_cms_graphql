# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV["TEST"] = "true"
require "dato_cms_graphql"

require "minitest/autorun"
