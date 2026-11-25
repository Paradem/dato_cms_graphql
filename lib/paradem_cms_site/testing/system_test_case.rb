# frozen_string_literal: true

require "action_dispatch/system_test_case"
require "axe/configuration"
require "capybara/selenium/driver_specializations/chrome_driver"
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

    # Chrome 158 rejects origin "*" for Storage.clearDataForOrigin; Capybara 3.40
    # still sends it. Vendored from Capybara PR #2868 until a release fixes it.
    module ChromeStorageResetFallback
      def reset!
        @capybara_reset_origin = begin
          uri = URI.parse(current_url)
          uri.origin if %w[http https].include?(uri.scheme)
        rescue URI::InvalidURIError
          nil
        end
        super
      ensure
        @capybara_reset_origin = nil
      end

      private

      def execute_cdp(cmd, params = {})
        super
      rescue Selenium::WebDriver::Error::InvalidArgumentError
        raise unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

        super("Network.clearBrowserCookies")
        return unless @capybara_reset_origin && params[:storageTypes].to_s.include?("local_storage")

        super("Storage.clearDataForOrigin", origin: @capybara_reset_origin, storageTypes: "local_storage")
      end
    end
    Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageResetFallback)

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
