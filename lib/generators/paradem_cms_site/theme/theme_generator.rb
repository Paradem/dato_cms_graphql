# frozen_string_literal: true

require "generators/paradem_cms_site/base"

module ParademCmsSite
  module Generators
    class ThemeGenerator < Base
      argument :name, type: :string, required: true

      def generate_theme
        unless name.match?(/\A[a-z][a-z0-9_]*\z/)
          raise Error, "Theme names must be lowercase identifiers (for example client_brand)"
        end
        require_view_component!
        @manifest = installed_manifest
        unless %w[propshaft importmap-rails tailwindcss-rails].all? { |gem| Gem.loaded_specs.key?(gem) } && checked_path("config/importmap.rb").file?
          raise Error, "Install Propshaft, importmap and Tailwind 4 in the host before generating a theme"
        end
        entrypoint = "app/assets/tailwind/application.css"
        css = checked_path(entrypoint).read
        import = /^@import ["']tailwindcss["'][^;]*;[ \t]*\n?/
        raise Error, "Use a Tailwind 4 application.css entrypoint" unless css.match?(import)
        theme_import = %(@import "./themes/#{name}.css";)
        source = '@source "../../components";'
        wiring = [theme_import, source, '@source "../../views";']
        counts = wiring.map { |line| css.lines.count { |existing| existing.strip == line } }
        if counts.any? { |count| count > 1 } || (state.fetch("generators").key?("theme:#{name}") && counts.any?(&:zero?))
          raise Error, "Theme asset wiring was duplicated, customized or removed; review it explicitly"
        end
        additions = wiring.reject { |line| css.lines.any? { |existing| existing.strip == line } }
        files = test_helper_files.merge(
          "app/assets/tailwind/themes/#{name}.css" => theme_css,
          "app/views/layouts/site/#{name}.html.erb" => layout,
          "app/controllers/site/#{name}_theme_controller.rb" => localized_controller("#{name.camelize}Theme", "      # This public fixture never reads CMS records or contacts a provider.", layout: "site/#{name}"),
          "app/views/site/#{name}_theme/show.html.erb" => preview,
          "config/locales/cms_theme_#{name}.yml" => translations,
          "test/integration/cms_#{name}_theme_test.rb" => request_test,
          "test/system/cms_#{name}_theme_test.rb" => system_test,
          ".github/workflows/cms-fixtures.yml" => workflow,
          "docs/cms/themes/#{name}.md" => <<~MARKDOWN
            # #{name.humanize} — host-owned theme

            Preview: `/cms/themes/#{name}/LOCALE`. The shell, tokens, fonts and markup belong
            to this application. Replace the system/Georgia font placeholders and colors locally;
            no remote fonts, logos, provider IDs or copied commercial templates are shipped.
            Resource generators select this shell explicitly with `--theme=#{name}`.

            Tailwind scans host components through an explicit @source. Native links/details need
            no new JavaScript or pins; the shell uses the host's existing importmap/Hotwire setup,
            which is left untouched. No behavior controller was forked.

            Run `bin/rails db:migrate`, `bin/rails tailwindcss:build`, `bin/rails test` and
            `bin/rails test:system`. Browser tests require Capybara, Selenium, axe-core-capybara
            and a compatible Chrome/driver. Tests use exact CSS viewports and all declared locales
            without content skips. Complete axe reports (including incompletes) and screenshots
            are retained by the fixture CI job. Review keyboard, contrast, screen-reader, zoom,
            real fonts and editorial content manually; automated checks are not WCAG certification.
            The fixture labels provide EN/FR defaults; translate other declared locales before release.
            This generator never activates the shell globally or deploys.
          MARKDOWN
        )
        updates = {}
        unless additions.empty?
          updates[entrypoint] = css
          files[entrypoint] = css.sub(import) { |match| "#{match.chomp}\n#{additions.join("\n")}\n" }
        end
        route_name = "cms_#{name}_theme"
        path = "cms/themes/#{name}/:locale"
        add_route(files, updates, %(get #{path.inspect}, to: "site/#{name}_theme#show", as: :#{route_name}), key: "theme:#{name}", marker: "cms/themes/#{name}/", route_name: route_name)
        write_scaffold("theme:#{name}", {}, files, updates: updates)
        say "Review the host shell/tokens and run the required fixture checks; no global layout, importmap pin, CMS data or deployment changed.", :green
      rescue Errno::ENOENT
        raise Error, "Install the host's Tailwind 4/importmap entrypoints before generating a theme"
      end

      private

      def theme_css
        <<~CSS
          [data-cms-theme="#{name}"] {
            --cms-surface: #ffffff;
            --cms-ink: #172554;
            --cms-link: #075985;
            --cms-focus: #7e22ce;
            --cms-font-body: system-ui, sans-serif;
            --cms-font-heading: Georgia, serif;
          }

          @theme inline {
            --color-site-surface: var(--cms-surface);
            --color-site-ink: var(--cms-ink);
            --color-site-link: var(--cms-link);
            --color-site-focus: var(--cms-focus);
            --font-site-body: var(--cms-font-body);
            --font-site-heading: var(--cms-font-heading);
          }
        CSS
      end

      def layout
        <<~ERB
          <!DOCTYPE html>
          <html lang="<%= I18n.locale.to_s.tr("_", "-") %>" data-cms-theme="#{name}">
            <head>
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title><%= t("cms.#{name}.title") %></title>
              <%= csrf_meta_tags %>
              <%= csp_meta_tag %>
              <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
              <%= javascript_importmap_tags %>
            </head>
            <body class="bg-site-surface font-site-body text-site-ink">
              <a href="#main-content" class="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:bg-site-surface focus:p-4 focus:outline-2 focus:outline-site-focus"><%= t("cms.#{name}.skip") %></a>
              <main id="main-content" tabindex="-1" class="focus-visible:outline-2 focus-visible:outline-site-focus">
                <%= yield %>
              </main>
            </body>
          </html>
        ERB
      end

      def preview
        <<~ERB
          <div class="mx-auto max-w-3xl space-y-8 px-6 py-12">
            <h1 class="font-site-heading text-4xl"><%= t("cms.#{name}.title") %></h1>
            <p><%= t("cms.#{name}.body") %></p>
            <nav aria-label="<%= t("cms.#{name}.languages") %>" class="flex flex-wrap gap-6">
              <% ParademCmsSite.configuration.installation.manifest.locales.each do |locale| %>
                <%= link_to locale, cms_#{name}_theme_path(locale: locale), lang: locale.tr("_", "-"), hreflang: locale.tr("_", "-"), class: "text-site-link underline focus-visible:outline-2 focus-visible:outline-site-focus" %>
              <% end %>
            </nav>
            <details id="theme-details" class="rounded-lg border p-6">
              <summary class="cursor-pointer font-semibold focus-visible:outline-2 focus-visible:outline-site-focus"><%= t("cms.#{name}.details") %></summary>
              <p class="mt-4"><%= t("cms.#{name}.body") %></p>
            </details>
          </div>
        ERB
      end

      def translations
        english = {"title" => "Theme preview", "skip" => "Skip to main content", "body" => "Synthetic local content. Customize this host-owned shell before release.", "languages" => "Languages", "details" => "About this fixture"}
        french = {"title" => "Aperçu du thème", "skip" => "Aller au contenu principal", "body" => "Contenu local synthétique. Personnalisez cette présentation avant la publication.", "languages" => "Langues", "details" => "À propos de cet exemple"}
        YAML.dump(@manifest.locales.to_h { |locale| [locale, {"cms" => {name => (locale.start_with?("fr") ? french : english).deep_dup}}] })
      end

      def request_test
        <<~RUBY
          require "test_helper"

          class Cms#{name.camelize}ThemeRequestTest < ActionDispatch::IntegrationTest
            test "theme fixture has public implemented locale routes and rejects unsupported locales" do
              ParademCmsSite.configuration.installation.manifest.locales.each do |locale|
                get cms_#{name}_theme_path(locale: locale)
                assert_response :success
                assert_select "html[lang=?][data-cms-theme=?]", locale.tr("_", "-"), #{name.inspect}
                assert_select "h1", count: 1
              end
              get cms_#{name}_theme_path(locale: "unsupported")
              assert_response :not_found
            end
          end
        RUBY
      end

      def system_test
        <<~RUBY
          require "test_helper"
          require "paradem_cms_site/testing/system_test_case"

          class Cms#{name.camelize}ThemeSystemTest < ParademCmsSite::Testing::SystemTestCase
            test "all locale viewport fixtures have real CSS keyboard behavior and accessibility scans" do
              each_cms_viewport do |locale|
                visit cms_#{name}_theme_path(locale: locale)
                assert_selector "html[lang='\#{locale.tr('_', '-')}'][data-cms-theme='#{name}']"
                find("h1").assert_matches_style("font-size" => "36px")
                page.driver.browser.switch_to.active_element.send_keys(:tab)
                assert_selector "a[href='#main-content']:focus"
                page.driver.browser.switch_to.active_element.send_keys(:enter)
                assert_selector "main:focus"
                find("summary").send_keys(:enter)
                assert_selector "details[open]"
                assert_cms_accessibility
                find("summary").send_keys(:enter)
                assert_no_selector "details[open]"
                page.save_screenshot(Rails.root.join("tmp/screenshots/cms-#{name}-\#{locale}-\#{page.evaluate_script('innerWidth')}.png"))
              end
            end
          end
        RUBY
      end

      def workflow
        <<~YAML
          name: CMS fixture contracts
          on: [push, pull_request]
          permissions:
            contents: read
          jobs:
            fixtures:
              runs-on: ubuntu-24.04
              env:
                RAILS_ENV: test
                SE_SKIP_DRIVER_IN_PATH: "true"
              steps:
                - uses: actions/checkout@v4
                - uses: ruby/setup-ruby@v1
                  with:
                    bundler-cache: true
                - run: bin/rails db:test:prepare tailwindcss:build test
                - run: bin/rails test:system
                - uses: actions/upload-artifact@v4
                  if: always()
                  with:
                    name: cms-fixture-evidence
                    path: |
                      tmp/accessibility
                      tmp/screenshots
                    if-no-files-found: error
        YAML
      end
    end
  end
end
