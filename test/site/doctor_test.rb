# frozen_string_literal: true

require "test_helper"
require "paradem_cms_site/cli"

class DoctorTest < Minitest::Test
  def test_checks_files_without_executing_host_code_or_using_credentials
    with_site do |root, _data|
      original = ENV["DATO_API_TOKEN"]
      ENV["DATO_API_TOKEN"] = "sentinel-must-not-be-logged"
      output = StringIO.new
      errors = StringIO.new
      status = ParademCmsSite::CLI.new(out: output, err: errors).run(["doctor", "--root", root])
      assert_equal 0, status
      assert_includes output.string, "2 owned queries"
      assert_includes output.string, "runtime delivery, routes, credentials and cache freshness are not verified"
      refute_includes output.string + errors.string, ENV["DATO_API_TOKEN"]
    ensure
      ENV["DATO_API_TOKEN"] = original
    end
  end

  def test_reports_missing_and_unregistered_files
    with_site do |root, data|
      File.delete(File.join(root, "app/models/page.rb"))
      File.write(File.join(root, "app/queries/sibling_query.rb"), "raise \"must not load\"")
      problems = ParademCmsSite::Doctor.new(ParademCmsSite::Manifest.new(data, root: root)).problems
      assert_includes problems, "Missing owned model: Page"
      assert_includes problems, "Unregistered query file: sibling_query.rb"
    end
  end

  def test_reports_invalid_schema_and_unknown_override_options
    with_site do |root, data|
      File.write(File.join(root, data["schema_export"]), "{}")
      problems = ParademCmsSite::Doctor.new(ParademCmsSite::Manifest.new(data, root: root)).problems
      assert_includes problems, "Owned model absent from schema export: Page"
      File.write(File.join(root, data["overrides_path"]), "Page:\n  fallbak_locale: :none\n")
      problems = ParademCmsSite::Doctor.new(ParademCmsSite::Manifest.new(data, root: root)).problems
      assert_match(/Unknown override keys/, problems.join)
    end
  end

  def test_hand_authored_hosts_need_no_schema_or_api_client
    with_site(generated: false) do |root, _data|
      assert_empty ParademCmsSite::Doctor.new(ParademCmsSite::Manifest.load(root: root)).problems
    end
    assert_equal 1, ParademCmsSite::CLI.new(err: StringIO.new).run(["sync"])
  end
end
