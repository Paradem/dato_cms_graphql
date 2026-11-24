# frozen_string_literal: true

require "action_dispatch/system_test_case"
require "axe/configuration"
require "json"
require "fileutils"
require "securerandom"
require "net/http"

raise ArgumentError, "CMS system-test support is test-only" unless Rails.env.test?

module ParademCmsSite
  module Testing
    # Opt-in test support only; never loaded by the client or production Railtie.
    module LoopbackHttp
      private

      def connect
        unless %w[localhost 127.0.0.1 ::1].include?(address)
          raise IOError, "External HTTP is forbidden in CMS fixture system tests"
        end
        super
      end
    end
    Net::HTTP.prepend(LoopbackHttp)

    class SystemTestCase < ActionDispatch::SystemTestCase
      driven_by :selenium, using: :headless_chrome do |options|
        options.add_argument("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1")
      end

      def each_cms_viewport
        ParademCmsSite.configuration.installation.manifest.locales.each do |locale|
          [[390, 844], [1280, 900]].each do |width, height|
            page.current_window.resize_to(width, height)
            page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
            assert_equal [width, height], page.evaluate_script("[innerWidth, innerHeight]")
            yield locale
          end
        end
      end

      def assert_cms_accessibility
        assert_equal 1, page.all("h1").length
        assert_includes I18n.available_locales.map { |locale| locale.to_s.tr("_", "-") }, page.evaluate_script("document.documentElement.lang")
        page.execute_script(Axe::Configuration.instance.jslib)
        report = page.driver.browser.execute_async_script(<<~JS)
          const done = arguments[arguments.length - 1];
          axe.run(document).then(done).catch(error => done({error: error.message}));
        JS
        directory = Rails.root.join("tmp/accessibility")
        FileUtils.mkdir_p(directory)
        File.write(directory.join("#{self.class.name}-#{SecureRandom.hex(6)}.json"), JSON.pretty_generate(report))
        assert_empty report.fetch("violations"), "Review complete axe JSON in tmp/accessibility, including manual-review incompletes"
      end
    end
  end
end
