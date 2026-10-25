# frozen_string_literal: true

require "test_helper"

class EmailSuppressionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include EmailSuppressionTestHelper

  setup do
    Current.reset
    @ranger = person(:active_ranger)
  end

  teardown do
    travel_back
    Current.reset
  end

  # =========================================================================
  # The record
  # =========================================================================

  test "an address is stored as person.email is normalized" do
    row = EmailSuppression.create!(email: "  Ranger@Example.COM ", reason: EmailSuppression::BOUNCE,
                                   first_reported_at: Time.current, last_reported_at: Time.current)

    assert_equal "ranger@example.com", row.email
    assert_equal Person.normalize_value_for(:email, "  Ranger@Example.COM "), row.email
  end

  test "the reason is a bounce or a complaint" do
    row = EmailSuppression.new(email: "ranger@example.com", reason: "spam",
                               first_reported_at: Time.current, last_reported_at: Time.current)

    assert_not row.valid?
    assert row.errors.added?(:reason, :inclusion, value: "spam")
  end

  test "a first report writes a row dated now, counted once" do
    travel_to Time.zone.local(2026, 10, 9, 14, 30, 0)

    row = suppress_email("Ranger@Example.com ", sub_type: "General", message_id: "ses-1")

    assert_equal "ranger@example.com", row.email
    assert_equal EmailSuppression::BOUNCE, row.reason
    assert_equal "General", row.sub_type
    assert_equal "ses-1", row.message_id
    assert_equal 1, row.report_count
    assert_equal Time.zone.local(2026, 10, 9, 14, 30, 0), row.first_reported_at
    assert_equal row.first_reported_at, row.last_reported_at
  end

  # The SNS handler passes "" for a report with no mail.messageId; stored as
  # given, the second such report would read as the first one redelivered.
  test "a report with no id stores none and is counted every time" do
    suppress_email("ranger@example.com", message_id: "")
    row = suppress_email("ranger@example.com", message_id: "")

    assert_nil row.message_id
    assert_equal 2, row.report_count
    assert_equal 3, suppress_email("ranger@example.com").report_count
  end

  # The delete and its action log go together: a clear nobody can trace never happens.
  test "a clear whose action log fails leaves the row" do
    original = ActionLog.method(:record)
    row = suppress_email("ranger@example.com")
    ActionLog.define_singleton_method(:record) { |*| raise ActiveRecord::ActiveRecordError, "log failed" }

    assert_raises(ActiveRecord::ActiveRecordError) { row.clear(by: @ranger, person: @ranger) }
    assert EmailSuppression.suppressed?("ranger@example.com")
  ensure
    ActionLog.define_singleton_method(:record, original)
  end

  test "on_ses_list? holds for a complaint and an OnAccountSuppressionList bounce only" do
    assert suppress_email("a@example.com", reason: EmailSuppression::COMPLAINT).on_ses_list?
    assert suppress_email("b@example.com", sub_type: EmailSuppression::ON_ACCOUNT_SUPPRESSION_LIST).on_ses_list?
    assert_not suppress_email("c@example.com", sub_type: "General").on_ses_list?
    assert_not suppress_email("d@example.com").on_ses_list?
  end

  # =========================================================================
  # The lookup
  # =========================================================================

  test "suppressed answers many addresses in one query, in the caller's own strings" do
    suppress_email("bounced@example.com")
    suppress_email("complained@example.com", reason: EmailSuppression::COMPLAINT)

    found = assert_queries_count(1) do
      EmailSuppression.suppressed(["Bounced@Example.com", " complained@example.com", "fine@example.com"])
    end

    assert_equal Set["Bounced@Example.com", " complained@example.com"], found
  end

  # Clubhouse 2 stored addresses as typed. update_columns would run the
  # normalizer and store this one lowercase; the string form of update_all
  # writes it as given.
  test "a mixed-case person.email, plucked, matches its row and comes back as stored" do
    Person.where(id: @ranger.id).update_all("email = 'Mixed.Case@Example.com'")
    suppress_email("mixed.case@example.com")

    plucked = Person.where(id: @ranger.id).pluck(:email)

    assert_equal ["Mixed.Case@Example.com"], plucked
    assert_equal Set["Mixed.Case@Example.com"], EmailSuppression.suppressed(plucked)
  end

  test "blank entries are ignored, and an empty list runs no query" do
    suppress_email("bounced@example.com")

    assert_no_queries do
      assert_equal Set.new, EmailSuppression.suppressed([])
      assert_equal Set.new, EmailSuppression.suppressed([nil, "", "  "])
      assert_equal Set.new, EmailSuppression.suppressed(nil)
    end
    assert_equal Set["bounced@example.com"], EmailSuppression.suppressed([nil, "", "bounced@example.com"])
  end

  test "suppressed? answers one address, for either reason" do
    suppress_email("bounced@example.com")
    suppress_email("complained@example.com", reason: EmailSuppression::COMPLAINT)

    assert EmailSuppression.suppressed?("Bounced@Example.com")
    assert EmailSuppression.suppressed?("complained@example.com")
    assert_not EmailSuppression.suppressed?("fine@example.com")
    assert_not EmailSuppression.suppressed?(nil)
  end

  test "a person's new address has no row, and the old address's row stays" do
    old_address = @ranger.email
    suppress_email(old_address)

    @ranger.update!(email: "new-address@example.com")

    assert_not EmailSuppression.suppressed?(@ranger.reload.email)
    assert EmailSuppression.suppressed?(old_address)
  end

  # =========================================================================
  # The copy of person.is_bouncing
  # =========================================================================

  test "a flagged person's Permanent logs for their address are copied, dated first to last" do
    flag(@ranger)
    travel_to(Time.zone.local(2024, 3, 1, 9, 0, 0)) { bounce_log(@ranger, to_email: "TestRanger@Example.com") }
    travel_to(Time.zone.local(2025, 6, 2, 10, 0, 0)) do
      bounce_log(@ranger, sub_type: "General", message_id: "ses-2")
    end
    travel_to(Time.zone.local(2023, 1, 1, 9, 0, 0)) { bounce_log(@ranger, bounce_type: "Transient") }

    assert_equal [1, 0], EmailSuppression.copy_bouncing_flags

    row = EmailSuppression.find_by!(email: @ranger.email)
    assert_equal EmailSuppression::BOUNCE, row.reason
    assert_equal Time.zone.local(2024, 3, 1, 9, 0, 0), row.first_reported_at
    assert_equal Time.zone.local(2025, 6, 2, 10, 0, 0), row.last_reported_at
    assert_equal 2, row.report_count
    assert_equal "General", row.sub_type
    assert_equal "ses-2", row.message_id
  end

  test "the latest log without a sub-type or an id leaves them empty" do
    flag(@ranger)
    travel_to(Time.zone.local(2024, 3, 1, 9, 0, 0)) { bounce_log(@ranger, sub_type: "General", message_id: "ses-1") }
    travel_to(Time.zone.local(2025, 6, 2, 10, 0, 0)) { bounce_log(@ranger, message_id: "") }

    EmailSuppression.copy_bouncing_flags

    row = EmailSuppression.find_by!(email: @ranger.email)
    assert_nil row.sub_type
    assert_nil row.message_id
  end

  test "a flagged person with only a Transient log, an older address's log, or no log is skipped" do
    transient = person(:auditor_ranger)
    moved = person(:echelon_ranger)
    unlogged = person(:retired_ranger)
    [transient, moved, unlogged].each { flag(it) }
    bounce_log(transient, bounce_type: "Transient")
    bounce_log(moved, to_email: "old-address@example.com")

    assert_no_difference -> { EmailSuppression.count } do
      assert_equal [0, 3], EmailSuppression.copy_bouncing_flags
    end
  end

  test "an unflagged person with a Permanent log is skipped" do
    bounce_log(@ranger)

    assert_no_difference -> { EmailSuppression.count } do
      assert_equal [0, 0], EmailSuppression.copy_bouncing_flags
    end
  end

  test "a flagged person with no address is skipped" do
    flag(@ranger)
    bounce_log(@ranger)
    Person.where(id: @ranger.id).update_all("email = NULL")

    assert_equal [0, 1], EmailSuppression.copy_bouncing_flags
  end

  test "an existing row is left as it is, and a second run adds nothing" do
    other = person(:auditor_ranger)
    [@ranger, other].each do |flagged|
      flag(flagged)
      bounce_log(flagged)
    end
    travel_to(Time.zone.local(2026, 1, 2, 3, 4, 5)) do
      suppress_email(other.email, reason: EmailSuppression::COMPLAINT, message_id: "ses-complaint")
    end

    assert_equal [1, 1], EmailSuppression.copy_bouncing_flags
    assert_no_changes -> { EmailSuppression.order(:id).map(&:attributes) } do
      assert_equal [0, 2], EmailSuppression.copy_bouncing_flags
    end

    kept = EmailSuppression.find_by!(email: other.email)
    assert_equal EmailSuppression::COMPLAINT, kept.reason
    assert_equal "ses-complaint", kept.message_id
    assert_equal Time.zone.local(2026, 1, 2, 3, 4, 5), kept.first_reported_at
  end

  test "a log whose data does not parse is skipped" do
    flag(@ranger)
    travel_to(Time.zone.local(2024, 3, 1, 9, 0, 0)) { bounce_log(@ranger) }
    broken = travel_to(Time.zone.local(2025, 6, 2, 10, 0, 0)) { bounce_log(@ranger) }
    ActionLog.where(id: broken.id).update_all("data = '{\"to_email\": '")
    odd = bounce_log(@ranger)
    ActionLog.where(id: odd.id).update_all(%(data = '{"bounce_type": "Permanent", "to_email": "#{@ranger.email}", ) +
                                           %("message": "not an event"}'))

    assert_equal [1, 0], EmailSuppression.copy_bouncing_flags

    row = EmailSuppression.find_by!(email: @ranger.email)
    assert_equal 1, row.report_count
    assert_equal Time.zone.local(2024, 3, 1, 9, 0, 0), row.last_reported_at
  end

  private

  def flag(person)
    person.update_columns(is_bouncing: true)
  end

  # An email-bouncing log as the SNS handler writes one, and Clubhouse 2's did.
  def bounce_log(person, to_email: person.email, bounce_type: "Permanent", sub_type: nil, message_id: "ses-1")
    bounce = { "bounceType" => bounce_type, "bouncedRecipients" => [{ "emailAddress" => to_email }] }
    bounce["bounceSubType"] = sub_type if sub_type
    ActionLog.record(nil, "email-bouncing", "", {
      to_email:, message_id:, bounce_type:, mail_log_id: nil,
      message: { "notificationType" => "Bounce", "mail" => { "messageId" => message_id }, "bounce" => bounce }
    }, person.id)
  end
end
