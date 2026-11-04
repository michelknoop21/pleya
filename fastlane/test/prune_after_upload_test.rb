# Regressie op fastlane/Fastfile#prune_after_upload en op de plek waar de lanes
# hem aanroepen: attach_after_upload, waar elke upload-lane in eindigt.
# Draaien: ruby fastlane/test/prune_after_upload_test.rb
require "minitest/autorun"

FASTFILE = File.expand_path("../Fastfile", __dir__)
SOURCE = File.read(FASTFILE)
PRUNE = SOURCE[/^def prune_after_upload\b.*?^end\n/m]
ATTACH = SOURCE[/^def attach_after_upload\b.*?^end\n/m]
raise "prune_after_upload niet gevonden in #{FASTFILE}" unless PRUNE
raise "attach_after_upload niet gevonden in #{FASTFILE}" unless ATTACH

class Harness
  PROJECT_ROOT = "/repo/root".freeze

  module UI
    def self.messages
      @messages ||= []
    end

    def self.important(message)
      messages << message
    end

    def self.message(message)
      messages << message
    end
  end

  attr_reader :calls, :attached

  def initialize(sh_fails: false)
    @calls = []
    @attached = []
    @sh_fails = sh_fails
  end

  def sh(*command)
    @calls << command
    raise "exit 1" if @sh_fails
  end

  def attach_build_to_version(platform, build_number)
    @attached << [platform, build_number]
  end

  class_eval(PRUNE)
  class_eval(ATTACH)
end

class LanePlacementTest < Minitest::Test
  # Elke aanroep van attach_after_upload staat in een lane na zijn upload_beta,
  # en upload_beta raised bij een mislukte upload: dan komt de opruiming niet.
  def test_every_attach_after_upload_call_follows_an_upload
    calls = SOURCE.lines.each_index.select { |i| SOURCE.lines[i] =~ /^\s+attach_after_upload\(/ }
    assert_operator calls.size, :>=, 4
    calls.each do |i|
      preceding = SOURCE.lines[0...i].reverse
      lane_start = preceding.index { |l| l =~ /^lane :/ }
      lane = preceding[0...lane_start]
      assert(lane.any? { |l| l =~ /^\s+upload_beta\b/ }, "attach_after_upload op regel #{i + 1} staat niet na een upload_beta")
    end
  end
end

class PruneAfterUploadTest < Minitest::Test
  def setup
    $skip_attach = nil
    $defer_attach = nil
    $pending_attach = nil
    Harness::UI.messages.clear
  end

  def prune_calls(harness)
    harness.calls.select { |c| c.first.end_with?("scripts/prune_after_upload.sh") }
  end

  def test_runs_the_script_with_platform_and_build_number
    harness = Harness.new
    harness.prune_after_upload("ios", 412)
    assert_equal [["/repo/root/scripts/prune_after_upload.sh", "ios", "412"]], harness.calls
  end

  def test_a_failing_cleanup_never_breaks_the_lane
    harness = Harness.new(sh_fails: true)
    harness.prune_after_upload("appletvos", 412)
    assert(Harness::UI.messages.any? { |m| m.include?("opruimen na de upload van build 412 faalde") })
  end

  def test_a_normal_upload_cleans_up_and_attaches
    harness = Harness.new
    harness.attach_after_upload("ios", 412)
    assert_equal 1, prune_calls(harness).size
    assert_equal [["ios", 412]], harness.attached
  end

  def test_a_preview_build_cleans_up_although_it_does_not_attach
    $skip_attach = true
    harness = Harness.new
    harness.attach_after_upload("ios", 412)
    assert_equal 1, prune_calls(harness).size
    assert_empty harness.attached
  end

  def test_a_deferred_attach_cleans_up_right_away
    $defer_attach = true
    harness = Harness.new
    harness.attach_after_upload("osx", 412)
    assert_equal 1, prune_calls(harness).size
    assert_empty harness.attached
    assert_equal({ "osx" => 412 }, $pending_attach)
  end
end
