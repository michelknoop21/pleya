# Run: ruby fastlane/test/tvos_assistant_default_test.rb
require "minitest/autorun"
require "open3"

SCRIPT = File.expand_path("../../tvos/scripts/xcode_appletv.sh", __dir__)
SOURCE = File.read(SCRIPT)
ASSIGNMENT = SOURCE[/^PLEYA_ASSISTANT_ENABLED=.*$/]

class TvosAssistantDefaultTest < Minitest::Test
  def resolved(env = {})
    out, status = Open3.capture2(env, "bash", "-c", "#{ASSIGNMENT}\nprintf %s \"$PLEYA_ASSISTANT_ENABLED\"", unsetenv_others: true)
    assert status.success?
    out
  end

  def test_the_default_is_defined_once_at_the_top
    refute_nil ASSIGNMENT, "the script must set PLEYA_ASSISTANT_ENABLED itself"
    assert_operator SOURCE.index(ASSIGNMENT), :<, SOURCE.index("ReadPubspecVersion()")
  end

  # tvos_beta exports nothing, so this is what an App Store Connect build gets.
  def test_a_build_without_an_environment_override_has_big_p
    assert_equal "true", resolved
  end

  def test_an_explicit_true_is_retained
    assert_equal "true", resolved("PLEYA_ASSISTANT_ENABLED" => "true")
  end

  def test_the_explicit_rollout_stop_is_retained
    assert_equal "false", resolved("PLEYA_ASSISTANT_ENABLED" => "false")
  end

  def test_both_compile_paths_pass_the_resolved_value
    defines = SOURCE.scan(/-DPLEYA_ASSISTANT_ENABLED=\S+/)
    assert_equal 2, defines.size, "kernel and AOT compile both need the define"
    defines.each { |d| assert_equal "-DPLEYA_ASSISTANT_ENABLED=${PLEYA_ASSISTANT_ENABLED}", d }
  end
end
