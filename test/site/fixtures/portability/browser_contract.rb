require "test_helper"
require "paradem_cms_site/testing/system_test_case"

class CmsThemePortabilitySystemTest < ParademCmsSite::Testing::SystemTestCase
  self.use_transactional_tests = false

  setup do
    ParademCmsSite::RefreshJob.perform_now({"source" => "portability_browser"})
  end

  test "independent shells retain cache identity CSS keyboard and Turbo behavior" do
    identities = {}
    %w[journal folio].each do |theme|
      each_cms_viewport do |locale|
        visit public_send("cms_#{theme}_theme_path", locale: locale)
        assert_selector "html[lang='#{locale}'][data-cms-theme='#{theme}']"
        assert_selector "h1", text: "Synthetic Article"
        assert_selector "h2", text: "Synthetic Promo"
        identity = find("[data-cms-proof-id]")["data-cms-proof-id"]
        identities[locale] ||= identity
        assert_equal identities.fetch(locale), identity
        assert_equal locale, find("[data-cms-proof-locale]")["data-cms-proof-locale"]

        styles = page.evaluate_script(<<~JS)
          (() => {
            const body = getComputedStyle(document.body);
            const heading = getComputedStyle(document.querySelector('h1'));
            return [body.backgroundColor, body.color, heading.fontFamily];
          })()
        JS
        expected = (theme == "journal") ? ["rgb(255, 247, 237)", "rgb(63, 29, 11)", "Georgia, serif"] : ["rgb(15, 23, 42)", "rgb(248, 250, 252)", "Arial, sans-serif"]
        assert_equal expected, styles
        width = page.evaluate_script("innerWidth")
        main_left = page.evaluate_script("document.querySelector('main').getBoundingClientRect().left")
        assert_equal((theme == "folio" && width >= 768) ? 224 : 0, main_left)
        assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "Shell must not overflow horizontally"

        page.driver.browser.switch_to.active_element.send_keys(:tab)
        assert_selector "a[href='#main-content']:focus"
        assert_operator find("a[href='#main-content']").native.rect.x, :>=, 0
        page.driver.browser.switch_to.active_element.send_keys(:enter)
        assert_selector "main:focus"
        assert_equal "3px", page.evaluate_script("getComputedStyle(document.querySelector('main')).outlineWidth")
        find("summary").send_keys(:enter)
        assert_selector "details[open]"
        assert_cms_accessibility

        page.execute_script("window.cmsPortabilityTurbo = true")
        other = (locale == "en") ? "fr" : "en"
        click_link other, exact: true
        assert_current_path public_send("cms_#{theme}_theme_path", locale: other)
        assert page.evaluate_script("window.cmsPortabilityTurbo"), "Locale link must use the installed Turbo module"
        page.go_back
        assert_current_path public_send("cms_#{theme}_theme_path", locale: locale)
        assert_selector "details[open]"
        assert page.evaluate_script("window.cmsPortabilityTurbo"), "Turbo must restore the same document"
        assert_selector "html[data-cms-theme='#{theme}']"
        assert_cms_accessibility
        find("summary").send_keys(:enter)
        assert_no_selector "details[open]"
        page.execute_script("window.scrollTo(0, 0)")
        path = Rails.root.join("tmp/screenshots/portability-#{theme}-#{locale}-#{width}.png")
        FileUtils.mkdir_p(path.dirname)
        page.driver.browser.save_screenshot(path.to_s)
      end
    end
  end
end
