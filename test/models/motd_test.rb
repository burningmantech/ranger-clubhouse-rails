# frozen_string_literal: true

require "test_helper"

class MotdTest < ActiveSupport::TestCase
  setup do
    @ranger = motd(:ranger_announcement)
    @applicant = motd(:applicant_announcement)
    @auditor = motd(:auditor_announcement)
    @expired = motd(:expired_ranger_announcement)
  end

  # ==========================================================================
  # Validations
  # ==========================================================================

  test "an announcement needs at least one audience" do
    announcement = Motd.new(person: person(:active_ranger), subject: "Subject",
                            message: "Body", expires_at: 1.week.from_now)

    assert_not announcement.valid?
    assert_includes announcement.errors[:base], "Choose at least one audience for this announcement."
  end

  # Each bad expiration gets exactly the one message that fits it. An unreadable
  # date lands in the column as nil just like an empty box does, so "can't be
  # blank" alone would be wrong for four of these five.
  test "each kind of bad expiration reports the reason that fits it" do
    {
      "" => "End date can't be blank.",
      "nonsense" => "The end date is not a date we could read. Pick one from the calendar.",
      "2026-13-45" => "The end date is not a date we could read. Pick one from the calendar.",
      "12345" => "The end date must be in the future.",
      "next tuesday" => "The end date must be in the future."
    }.each do |input, message|
      announcement = Motd.new(person: person(:active_ranger), subject: "Subject",
                              message: "Body", for_rangers: true, expires_at: input)

      assert_not announcement.valid?, "#{input.inspect} should be rejected"
      assert_equal [message], announcement.errors[:expires_at], "for #{input.inspect}"
    end
  end

  # "12345" parses to the year 12 rather than raising, so without the
  # future check it would save and then vanish on the next nightly sweep.
  test "an expiration already in the past is rejected" do
    announcement = Motd.new(person: person(:active_ranger), subject: "Subject",
                            message: "Body", for_rangers: true, expires_at: 1.day.ago)

    assert_not announcement.valid?
    assert_includes announcement.errors[:expires_at], "The end date must be in the future."
  end

  # Fixing a typo on an announcement that has already run out must not require
  # moving its date.
  test "an expired announcement can still be edited without touching its date" do
    @expired.subject = "Corrected subject"

    assert @expired.valid?
  end

  # An emptied editor still submits its block markup, and a typed space arrives
  # as an entity — both are present? in Ruby, so neither is caught by a plain
  # presence check.
  test "a message holding no words is rejected however it is empty" do
    ["<div><br></div>", "<div> </div>", "<div>&nbsp;</div>", "<div>&nbsp;&nbsp; </div>", "",
     "<p><br></p>", "<p></p>"].each do |body|
      announcement = Motd.new(person: person(:active_ranger), subject: "Subject",
                              message: body, for_rangers: true,
                              expires_at: 1.week.from_now)

      assert_not announcement.valid?, "#{body.inspect} should be rejected"
      assert_includes announcement.errors[:message], "The message can't be blank.", "for #{body.inspect}"
    end
  end

  test "a message with real content is accepted" do
    announcement = Motd.new(person: person(:active_ranger), subject: "Subject",
                            message: "<ul><li>Bring your Ranger ID</li></ul>",
                            for_rangers: true, expires_at: 1.week.from_now)

    assert announcement.valid?
  end

  # ==========================================================================
  # find_for_query
  # ==========================================================================

  test "find_for_query returns everything when no filters are given" do
    ids = Motd.find_for_query.map(&:id)

    assert_includes ids, @ranger.id
    assert_includes ids, @applicant.id
    assert_includes ids, @auditor.id
  end

  test "find_for_query narrows to one audience" do
    ids = Motd.find_for_query(audience: "pnvs").map(&:id)

    assert_equal [@applicant.id], ids
  end

  test "find_for_query narrows to active or expired" do
    assert_equal [@expired.id], Motd.find_for_query(status: "expired").map(&:id)

    active_ids = Motd.find_for_query(status: "active").map(&:id)
    assert_includes active_ids, @ranger.id
    assert_not_includes active_ids, @expired.id
  end

  test "find_for_query combines audience and status" do
    ids = Motd.find_for_query(audience: "rangers", status: "expired").map(&:id)

    assert_equal [@expired.id], ids
  end

  # Three fixtures share an expiration date, so the id tiebreaker is what makes
  # the order total. Without it MariaDB may return ties in any order and the
  # list reshuffles between loads.
  test "find_for_query sorts by expiration and settles ties by id" do
    descending = Motd.find_for_query.map(&:id)
    ascending = Motd.find_for_query(sort: "asc").map(&:id)

    assert_equal descending.reverse, ascending
    assert_equal @expired.id, ascending.first
  end

  # ==========================================================================
  # expire!
  # ==========================================================================

  test "expire! deletes expired announcements and reports the count" do
    PersonMotd.create!(person_id: person(:active_ranger).id, motd_id: @expired.id, read_at: Current.time)

    assert_equal 1, Motd.expire!

    assert_not Motd.exists?(@expired.id)
    assert Motd.exists?(@ranger.id)
    assert_empty PersonMotd.where(motd_id: @expired.id)
  end

  test "expire! reports zero when nothing has expired" do
    @expired.destroy!

    assert_equal 0, Motd.expire!
  end

  # ==========================================================================
  # audience_labels
  # ==========================================================================

  test "audience_labels names every checked audience" do
    assert_equal ["Rangers"], @ranger.audience_labels

    everyone = Motd.new(for_rangers: true, for_pnvs: true, for_auditors: true)
    assert_equal ["Rangers", "Prospectives & Alphas", "Auditors"], everyone.audience_labels
  end
end
