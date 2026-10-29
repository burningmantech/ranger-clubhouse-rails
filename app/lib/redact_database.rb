# frozen_string_literal: true

# Takes the personal detail out of a copy of the Clubhouse database, so a copy
# can be handed to a developer or used for training without carrying anyone's
# address, phone number, or password with it.
#
# Run this against a copy. Run against the real database it would destroy it.
class RedactDatabase
  # What everybody's details become. Addresses and phone numbers are replaced
  # rather than emptied, so pages that show them still have something to show.
  PERSON_DETAILS = {
    alt_phone: "+17755550100",
    apt: "",
    behavioral_agreement: false,
    bpguid: "DEAD-BEEF",
    camp_location: "D-Lot",
    city: "Springfield",
    country: "US",
    emergency_contact: "On-playa: John Smith (father), camped at 3:45 and G. " \
                       "Off-playa: Jane Smith (mother), phone 123-456-7890, email jane@noemail.none",
    employee_id: nil,
    home_phone: "+17755550100",
    known_pnvs: "",
    known_rangers: "",
    lms_id: "",
    lms_username: "",
    mi: "",
    on_site: false,
    preferred_name: "",
    sfuid: "",
    sms_code: "",
    sms_number: "",
    sms_off_playa: "",
    sms_on_playa: "",
    state: "NT",
    street1: "123 Any St.",
    street2: "",
    vehicle_blacklisted: false,
    zip: "99999"
  }.freeze

  # Everyone gets this password when the copy is redacted down to the bone.
  SUPER_REDACT_PASSWORD = "abcdef"

  # Emptied outright: either no one needs them in a copy, or what they hold is
  # too personal to keep. Names that do not exist here are skipped.
  EMPTIED_TABLES = %w[
    access_document_changes
    bmid_export
    broadcast
    broadcast_message
    contact_log
    email_history
    error_logs
    legacy_log
    log
    mail_log
    manual_review
    mentee_status
    motd
    oauth_client
    oauth_code
    online_course
    person_banner
    person_event
    person_intake
    person_intake_note
    person_mentoring_note
    person_motd
    person_passkey
    person_pog
    prospective_application
    prospective_application_log
    prospective_application_note
    request_log
    sessions
    survey
    survey_answer
    survey_question
    telescope_entries
    telescope_entries_tags
    telescope_monitoring
    timesheet_missing
    timesheet_missing_note
    trainee_note
    vehicle
  ].freeze

  # Also emptied when nothing at all is to be kept. The photos go, so the file
  # records that point at them go with them.
  SUPER_REDACT_TABLES = %w[
    person_photo
    active_storage_attachments
    active_storage_blobs
    active_storage_variant_records
  ].freeze

  SUPER_REDACT_ONLY_TABLES = %w[access_document bmid provision].freeze

  # The mailing address every ticket and pass ends up with.
  DOCUMENT_ADDRESS = {
    street1: "1 Main St",
    street2: "",
    city: "Springfield",
    state: "NT",
    postal_code: "99999"
  }.freeze

  # How a copy is set up once it is redacted: nothing reaches the outside world,
  # and the parts of the Clubhouse a developer needs are switched on.
  DEFAULT_SETTINGS = {
    Setting::ALLOW_SIGNUPS_WITHOUT_PHOTO => "true",
    Setting::AUDITOR_REGISTRATION_DISABLED => "true",
    Setting::BROADCAST_CLUBHOUSE_NOTIFY => "false",
    Setting::BROADCAST_CLUBHOUSE_SANDBOX => "true",
    Setting::BROADCAST_MAIL_SANDBOX => "true",
    Setting::BROADCAST_MAIL_TEST_ADDRESS => "",
    Setting::BROADCAST_SMS_SANDBOX => "true",
    Setting::HQ_WINDOW_INTERFACE_ENABLED => "true",
    Setting::MEAL_INFO_AVAILABLE => "true",
    Setting::ONLINE_COURSE_DISABLED_ALLOW_SIGNUPS => "true",
    Setting::ONLINE_COURSE_ENABLED => "false",
    Setting::RADIO_INFO_AVAILABLE => "true",
    Setting::TICKETING_PERIOD => "offseason",
    Setting::TIMESHEET_CORRECTION_ENABLE => "true"
  }.freeze

  # Two accounts the training material walks people through, given back the
  # detail those pages are meant to show.
  TRAINING_PEOPLE = {
    "Safety Phil" => { camp_location: "DPW Ghetto" },
    "keeper" => { emergency_contact: "Morticia Addams (Mother), Gomez Addams (Father)\nPhone: +1-415-865-3800" }
  }.freeze

  class << self
    # @param super_redact [Boolean] also clear tickets, provisions, badges and
    #   photos, and give everybody the same password
    def execute(super_redact: false)
      redact_people(super_redact)
      redact_training_notes
      empty_tables(super_redact)
      redact_documents(super_redact)
      empty_message_archives
      clear_credentials
      apply_default_settings
      close_on_site_histories
    end

    # Used by the training-database build as well, which sets its own handful of
    # settings straight after the redaction.
    def write_settings(values)
      known = Setting.where(name: values.keys).pluck(:name)
      values.slice(*known).each { |name, value| Setting.where(name:).update_all(value:) }

      missing = values.except(*known)
      Setting.insert_all(missing.map { |name, value| { name:, value: } }) if missing.any?
    end

    private

    def redact_people(super_redact)
      Person.update_all(PERSON_DETAILS)
      Person.update_all(password: Person.new.tap { |p| p.password = SUPER_REDACT_PASSWORD }.password) if super_redact

      # An address no one can reach, and one that stays the same each time the
      # copy is rebuilt so a tester can guess it from the callsign. The name is
      # cut short first: the column holds fifty characters, and what follows it
      # has to fit as well.
      Person.where(status: [Person::ACTIVE, Person::INACTIVE])
            .update_all("email = concat(substring(callsign_normalized, 1, 38), '@nomail.none')")
      Person.where.not(status: [Person::ACTIVE, Person::INACTIVE])
            .update_all("email = concat(substring(callsign_normalized, 1, 37 - length(id)), '-', id, '@nomail.none')")

      TRAINING_PEOPLE.each do |callsign, details|
        Person.where(callsign_normalized: WordUtils.normalize_word(callsign)).update_all(details)
      end
    end

    def redact_training_notes
      TraineeStatus.update_all(notes: "", rank: nil)
      # What a mentor wrote about the person they were mentoring, which is the
      # same kind of writing as the training notes above.
      PersonMentor.update_all(notes: "")
      # Only the sign-up history is kept, which on a real database means removing
      # nearly three million rows. In batches, so it does not ask the server to
      # hold locks on all of them at once.
      ActionLog.where.not(event: %w[person-slot-add person-slot-remove]).in_batches.delete_all
    end

    def empty_tables(super_redact)
      tables = EMPTIED_TABLES
      tables += SUPER_REDACT_TABLES + SUPER_REDACT_ONLY_TABLES if super_redact

      connection.disable_referential_integrity do
        tables.each do |table|
          connection.truncate(table) if connection.table_exists?(table)
        end
      end
    end

    def redact_documents(super_redact)
      return if super_redact

      Provision.update_all(status: Provision::AVAILABLE)
      AccessDocument.update_all(comments: "")

      DOCUMENT_ADDRESS.each do |column, value|
        AccessDocument.where.not(column => "").update_all(column => value)
      end

      # A pass for somebody's other half is the one kind that carries a name.
      AccessDocument.where(type: AccessDocument::SAPSO).update_all("name = concat('SAP Name #', id)")
      AccessDocument.where.not(type: AccessDocument::SAPSO).update_all(name: "")
    end

    # Every Clubhouse message is somebody's private conversation. A copy taken
    # before MergePersonMessageArchives ran still keeps them in a table per
    # year as well, so the prefix is matched rather than the one table named.
    def empty_message_archives
      connection.disable_referential_integrity do
        connection.tables.grep(/\Aperson_message/).each { |table| connection.truncate(table) }
      end
    end

    def clear_credentials
      names = Setting::DESCRIPTIONS.select { |_name, description| description[:is_credential] }.keys
      Setting.where(name: names).update_all(value: "")
    end

    def apply_default_settings
      write_settings(DEFAULT_SETTINGS.merge(Setting::DATABASE_CREATED_ON => Time.current.to_fs(:db)))
    end

    # PERSON_DETAILS marks everyone off site with update_all, which skips
    # Person's hook. Run last, so a copy too old to have the log has had its
    # personal detail taken out before this finds the table missing. On the real
    # clock, not Current.time: a pinned Groundhog Day time can fall before rows
    # already in the log, and the closing row has to come last.
    def close_on_site_histories
      PersonOnSite.reconcile(at: Time.zone.now)
    end


    def connection
      ActiveRecord::Base.connection
    end
  end
end
