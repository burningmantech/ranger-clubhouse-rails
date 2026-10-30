# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261010000002_copy_bouncing_flags_to_email_suppression.rb")

# The copy still has to run on a database that is behind, after person.is_bouncing
# left the schema, so the test puts the column back for its own run. Adding a
# column commits the test transaction, so this class runs without one and cleans
# up by hand.
class CopyBouncingFlagsToEmailSuppressionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MIGRATION = CopyBouncingFlagsToEmailSuppression

  setup do
    remove_flag_column
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Base.connection.add_column :person, :is_bouncing, :boolean, default: false, null: false
    end
    MIGRATION::MigrationPerson.reset_column_information
    @ranger = person(:active_ranger)
  end

  teardown do
    EmailSuppression.delete_all
    ActionLog.where(event: "email-bouncing").delete_all
    remove_flag_column
  end

  test "a flag is copied from its Permanent logs, dated first to last; the rest are skipped" do
    flag(@ranger)
    travel_to(Time.zone.local(2024, 3, 1, 9)) { bounce_log(@ranger, to_email: @ranger.email.upcase) }
    travel_to(Time.zone.local(2025, 6, 2, 10)) { bounce_log(@ranger, sub_type: "General", message_id: "ses-2") }
    travel_to(Time.zone.local(2023, 1, 1, 9)) { bounce_log(@ranger, bounce_type: "Transient") }

    transient = person(:auditor_ranger)
    moved = person(:echelon_ranger)
    unflagged = person(:retired_ranger)
    taken = person(:inactive_ranger)
    [transient, moved, taken].each { flag(it) }
    bounce_log(transient, bounce_type: "Transient")
    bounce_log(moved, to_email: "old-address@example.com")
    bounce_log(unflagged)
    bounce_log(taken)
    EmailSuppression.record(taken.email, reason: EmailSuppression::BOUNCE, sub_type: "kept", message_id: "kept")

    assert_equal [1, 3], MIGRATION.new.send(:copy_bouncing_flags)

    row = EmailSuppression.find_by!(email: @ranger.email)
    assert_equal EmailSuppression::BOUNCE, row.reason
    assert_equal Time.zone.local(2024, 3, 1, 9), row.first_reported_at
    assert_equal Time.zone.local(2025, 6, 2, 10), row.last_reported_at
    assert_equal 2, row.report_count
    assert_equal "General", row.sub_type
    assert_equal "ses-2", row.message_id
    assert_equal "kept", EmailSuppression.find_by!(email: taken.email).sub_type, "an existing row is left as it is"
    assert_equal 2, EmailSuppression.count
    assert_equal [0, 4], MIGRATION.new.send(:copy_bouncing_flags), "a second run adds nothing"
  end

  private

  def remove_flag_column
    connection = ActiveRecord::Base.connection
    return unless connection.column_exists?(:person, :is_bouncing)

    ActiveRecord::Migration.suppress_messages { connection.remove_column :person, :is_bouncing }
    MIGRATION::MigrationPerson.reset_column_information
  end

  def flag(person)
    MIGRATION::MigrationPerson.where(id: person.id).update_all(is_bouncing: true)
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
