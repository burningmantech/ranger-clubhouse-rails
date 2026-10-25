# frozen_string_literal: true

require "test_helper"

class PersonFkaTest < ActiveSupport::TestCase
  # IRRELEVANT_REGEXP drops the callsign shapes the Clubhouse itself issues to
  # applicants -- a name+year handle, a "B" alpha handle, and the (NR) suffix --
  # so a search never matches on a handle no one chose for themselves. Only the
  # suffix is tested, so a chosen callsign that merely contains a digit stays.
  test "filter_out_irrelevant keeps real callsigns and drops generated applicant ones" do
    names = ["Hubcap", "Fourie2025", "2025B", "Chrigi (NR)", "Agent 99 Reborn", "Dynomite"]

    assert_equal ["Hubcap", "Agent 99 Reborn", "Dynomite"], PersonFka.filter_out_irrelevant(names)
  end

  test "filter_out_irrelevant returns an empty array for nothing to filter" do
    assert_equal [], PersonFka.filter_out_irrelevant(nil)
    assert_equal [], PersonFka.filter_out_irrelevant([])
  end

  test "the is_irrelevant column agrees with the filter" do
    person = person(:prospective_ranger)

    generated = PersonFka.create!(person: person, fka: "Fourie2025")
    chosen = PersonFka.create!(person: person, fka: "Hubcap")

    assert generated.is_irrelevant
    assert_not chosen.is_irrelevant
    assert_equal [chosen.fka], PersonFka.filter_out_irrelevant([generated.fka, chosen.fka])
  end
end
