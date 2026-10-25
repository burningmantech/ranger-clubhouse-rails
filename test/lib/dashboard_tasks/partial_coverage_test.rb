# frozen_string_literal: true

require "test_helper"

class DashboardTasks::PartialCoverageTest < ActiveSupport::TestCase
  SOURCE_FILES = Dir[Rails.root.join("app/lib/dashboard_tasks/*.rb")] + [Rails.root.join("app/lib/dashboard.rb")]

  test "every referenced dashboard_tasks partial exists" do
    # Without these two floors the whole guard evaporates silently: if the glob
    # stops matching, or the scan regex stops finding partial: references, the
    # loop body never runs, nothing is asserted, and the test still reports
    # success -- retiring the check that keeps a missing partial from 500-ing /me.
    assert_operator SOURCE_FILES.size, :>=, 2,
      "no dashboard task sources found -- the glob in SOURCE_FILES has gone stale"

    checked = 0

    SOURCE_FILES.each do |source_file|
      File.read(source_file).scan(/partial:\s*"([^"]+)"/).flatten.each do |name|
        checked += 1
        partial_path = Rails.root.join("app/views/dashboard_tasks/_#{name}.html.erb")

        assert File.exist?(partial_path),
          "#{source_file} references partial \"#{name}\" but #{partial_path} does not exist"
      end
    end

    assert_operator checked, :>=, 1,
      "no partial: references found -- the scan regex no longer matches the source"
  end
end
