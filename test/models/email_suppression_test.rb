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
end
