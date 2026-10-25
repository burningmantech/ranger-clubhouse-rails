# frozen_string_literal: true

require "test_helper"

# The redaction itself empties tables, which cannot be undone and cannot be
# rolled back, so it is never run here. What is checked is that it names things
# that exist -- a renamed column would otherwise only be found the next time
# somebody built a copy.
class RedactDatabaseTest < ActiveSupport::TestCase
  test "every detail it replaces is a column a person has" do
    assert_empty RedactDatabase::PERSON_DETAILS.keys.map(&:to_s) - Person.column_names
  end

  # The Clubhouse now reaches a Ranger on one number, kept in a column of its
  # own. A copy that left it behind would carry every real phone number in it.
  test "the number a Ranger is texted on is replaced" do
    assert_includes RedactDatabase::PERSON_DETAILS.keys, :sms_number
  end

  # A mentor's notes are about a named person and read like the training notes
  # beside them. Emptying tables cannot be undone and cannot be rolled back, but
  # this part of the redaction only rewrites rows, so it can be run here.
  test "what a mentor wrote about somebody is taken out" do
    mentor_note = person_mentor(:mentee_passed)

    assert_predicate mentor_note.notes, :present?

    RedactDatabase.send(:redact_training_notes)

    assert_predicate mentor_note.reload.notes, :blank?
  end

  # PERSON_DETAILS marks everyone off site with update_all, which skips
  # Person's hook. These parts only rewrite rows, so they can be run here.
  test "marking everyone off site closes each on-site person's log, and only theirs" do
    on_site = person(:active_ranger)
    on_site.update_columns(on_site: true)
    PersonOnSite.create!(person: on_site, action: PersonOnSite::ON_SITE, created_at: 2.days.ago)
    off_site = person(:echelon_ranger)

    RedactDatabase.send(:redact_people, false)
    RedactDatabase.send(:close_on_site_histories)

    assert_not on_site.reload.on_site
    assert_equal [PersonOnSite::ON_SITE, PersonOnSite::OFF_SITE], PersonOnSite.history_for(on_site, :asc).pluck(:action)
    assert_not PersonOnSite.exists?(person: off_site)
  end

  # Like status history it holds only ids and times, so every copy keeps it.
  test "no copy empties the on-site log" do
    named = RedactDatabase::EMPTIED_TABLES + RedactDatabase::SUPER_REDACT_TABLES +
            RedactDatabase::SUPER_REDACT_ONLY_TABLES

    assert_not_includes named, "person_on_site"
  end

  test "every address it writes onto a ticket is a column a ticket has" do
    assert_empty RedactDatabase::DOCUMENT_ADDRESS.keys.map(&:to_s) - AccessDocument.column_names
  end

  # Emptying a table it cannot find is quietly skipped, so a table that was
  # renamed would go on holding what it holds and no one would hear about it.
  # The three exceptions belong to a debugging tool this Clubhouse does not
  # have, and are kept because a database this is pointed at may still have
  # them.
  test "every table it empties is a table that exists" do
    exceptions = %w[telescope_entries telescope_entries_tags telescope_monitoring]
    named = RedactDatabase::EMPTIED_TABLES + RedactDatabase::SUPER_REDACT_TABLES +
            RedactDatabase::SUPER_REDACT_ONLY_TABLES

    assert_empty named - exceptions - ActiveRecord::Base.connection.tables
  end

  # Who is in a group thread is as private as what it says. The redaction
  # empties every table named person_message* (empty_message_archives), and
  # the dump leaves out their rows (clubhouse.rake's skipped_logs), so the
  # member table keeps the prefix.
  test "a group thread's member table is emptied with the messages" do
    assert_includes ActiveRecord::Base.connection.tables.grep(/\Aperson_message/), PersonMessageMember.table_name
  end

  test "every setting it turns on is one the Clubhouse knows" do
    assert_empty RedactDatabase::DEFAULT_SETTINGS.keys - Setting::DESCRIPTIONS.keys
  end

  # A copy is handed to people outside the Clubhouse, so nothing in it may text
  # or email anybody, and no service password may come with it.
  test "a copy can send nothing to anybody" do
    %w[BroadcastMailSandbox BroadcastSMSSandbox BroadcastClubhouseSandbox].each do |name|
      assert_equal "true", RedactDatabase::DEFAULT_SETTINGS[name], "#{name} should be on"
    end
    assert_equal "", RedactDatabase::DEFAULT_SETTINGS[Setting::BROADCAST_MAIL_TEST_ADDRESS],
                 "a copy is never in test mode, which sends through SES"
  end
end
