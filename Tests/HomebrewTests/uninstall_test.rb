require "minitest/autorun"
require "pathname"

# Deliberately accept only package metadata: adding executable cleanup behavior
# must fail this fixture instead of silently disappearing into method_missing.
class CaskFixture
  attr_reader :application, :cli, :guidance, :zap_options
  def cask(_name, &block); instance_eval(&block); end
  def version(*_args); "0.0.0"; end
  def sha256(*); end
  def url(*); end
  def name(*); end
  def desc(*); end
  def homepage(*); end
  def depends_on(**); end
  def appdir; Pathname("/Applications"); end
  def app(value); @application = value; end
  def binary(value); @cli = value; end
  def caveats(value); @guidance = value; end
  def zap(**options); @zap_options = options; end
end

class HomebrewUninstallTest < Minitest::Test
  def setup
    @cask = CaskFixture.new
    @cask.instance_eval(File.read(File.expand_path("../../Resources/Homebrew/leftopen.rb", __dir__)))
  end

  def test_package_manages_app_and_cli_without_cleanup_hooks
    assert_equal "LeftOpen.app", @cask.application
    assert_equal "/Applications/LeftOpen.app/Contents/MacOS/leftopen", @cask.cli
  end

  def test_complete_removal_guidance_includes_recovery_after_package_removal
    assert_includes @cask.guidance, "Settings > About > Uninstall LeftOpen"
    assert_includes @cask.guidance, "settings may remain"
    assert_includes @cask.guidance, "reinstall LeftOpen"
  end

  def test_zap_only_removes_saved_window_state
    assert_equal({ trash: ["~/Library/Saved Application State/app.leftopen.mac.savedState"] }, @cask.zap_options)
  end
end
