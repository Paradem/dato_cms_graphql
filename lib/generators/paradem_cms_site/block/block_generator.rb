# frozen_string_literal: true

require "generators/paradem_cms_site/base"

module ParademCmsSite
  module Generators
    class BlockGenerator < Base
      argument :name, type: :string, required: true
      class_option :layout, type: :string, default: "reading", desc: "reading, wide or section (host-owned wrapper)"

      def generate_block
        @component = name.camelize
        model_name!(@component)
        unless name.underscore.match?(/\A[a-z][a-z0-9_]*\z/) && %w[reading wide section].include?(options[:layout])
          raise Error, "Use a conventional block name and reading, wide or section layout"
        end
        require_view_component!
        installed_manifest
        @key = @component.underscore
        files = test_helper_files.merge(
          "app/components/site/blocks/#{@key}.rb" => component_source,
          component_template("app/components/site/blocks/#{@key}") => component_view,
          "test/fixtures/files/cms_block_#{@key}.json" => JSON.pretty_generate({"id" => "synthetic-#{@key}", "_model_api_key" => @key, "title" => "Synthetic #{@component}", "body" => "Synthetic plain-text block."}) + "\n",
          "test/components/site/blocks/#{@key}_test.rb" => component_test,
          "docs/cms/blocks/#{@key}.md" => <<~MARKDOWN
            # Custom #{@component} block

            Host-owned component: `Site::Blocks::#{@component}`, constructor `resource:`.
            Its `#{options[:layout]}` wrapper owns its gutters; do not add a second container.
            The starter escapes title/body text and accepts plain Hash/OpenStruct payloads.
            Adapt fields and markup locally; no shared block catalogue or registry is required.

            With the reviewed DAST module-dispatch API, supply `component_module: Site::Blocks`
            to `DastDocument::Document` in your existing host renderer. Other walkers retain
            their own adapters/constructors. Nothing was registered in CMS fields, added to
            queries or published. Prepare actual block schema/validators/queries only after
            separate site-scoped review; this fixture is not a CMS export.
          MARKDOWN
        )
        write_scaffold("block:#{@component}", {"layout" => options[:layout]}, files)
      end

      private

      def component_source
        <<~RUBY
          # frozen_string_literal: true

          module Site
            module Blocks
              class #{@component} < ViewComponent::Base
                def initialize(resource:)
                  @resource = ParademCmsSite::PlainData.call(resource)
                  raise ArgumentError, "Block resource must be a mapping" unless @resource.is_a?(Hash)
                end
              end
            end
          end
        RUBY
      end

      def component_view
        classes = {"reading" => "mx-auto max-w-3xl px-6 py-8", "wide" => "mx-auto max-w-7xl px-6 py-8", "section" => "w-full px-6 py-12"}.fetch(options[:layout])
        <<~ERB
          <section class="#{classes}">
            <% if @resource["title"].present? %>
              <h2 class="font-site-heading text-2xl"><%= @resource["title"] %></h2>
            <% end %>
            <% if @resource["body"].present? %>
              <p class="mt-4"><%= @resource["body"] %></p>
            <% end %>
          </section>
        ERB
      end

      def component_test
        <<~RUBY
          require "test_helper"
          require "view_component/test_case"
          require "ostruct"

          class Site#{@component}BlockTest < ViewComponent::TestCase
            test "custom block accepts fixture envelopes and escapes text" do
              payload = JSON.parse(file_fixture("cms_block_#{@key}.json").read)
              [payload, OpenStruct.new(payload)].each do |resource|
                render_inline(Site::Blocks::#{@component}.new(resource: resource))
                assert_selector "h2", text: payload.fetch("title")
              end
              render_inline(Site::Blocks::#{@component}.new(resource: {"body" => "<script>unsafe()</script>"}))
              assert_no_selector "script"
              assert_text "<script>unsafe()</script>"
              render_inline(Site::Blocks::#{@component}.new(resource: {}))
              assert_no_selector "h2"
              assert_raises(ArgumentError) { Site::Blocks::#{@component}.new(resource: nil) }
            end
          end
        RUBY
      end
    end
  end
end
