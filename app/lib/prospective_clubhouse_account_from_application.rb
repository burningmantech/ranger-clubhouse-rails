# frozen_string_literal: true

# Previews or commits the creation of Clubhouse accounts (and updates to
# eligible existing accounts) from approved prospective applications. Ported
# from the Laravel App\Lib\ProspectiveClubhouseAccountFromApplication class.
#
# One instance per application: it carries the verdict (#status), the human
# explanations (#errors), and the accounts involved. The class method runs a
# whole batch and hands back a Batch of those instances.
#
# Salesforce is only ever contacted on a commit, and only when writebacks are
# enabled -- see .execute.
class ProspectiveClubhouseAccountFromApplication
  # Raised inside the persistence transaction to abandon one account without
  # taking down the rest of the batch.
  class AccountSaveError < StandardError; end

  # Application is missing fields, or the account it would make refuses a
  # value: one of the application's, or a converted account's own.
  STATUS_INVALID = "invalid"

  # An account can be created from the application.
  STATUS_READY = "ready"
  # An account can be created, and the callsign taken from its current holder.
  STATUS_READY_REASSIGN_CALLSIGN = "ready-reassign-callsign"

  # Account was created successfully.
  STATUS_CREATED = "created"
  # Could not create the account.
  STATUS_CREATE_FAILED = "create-failed"

  # Conflict with an existing account holding the desired callsign.
  STATUS_EXISTING_CALLSIGN = "existing-callsign"
  # Conflict with a reserved callsign or operational word/phrase.
  STATUS_RESERVED_CALLSIGN = "reserved-callsign"
  # An account already exists with the same BPGUID or email, but its status
  # cannot be converted back to prospective.
  STATUS_EXISTING_BAD_STATUS = "existing-bad-status"

  # Verdicts a commit acts on.
  READY_STATUSES = [STATUS_READY, STATUS_READY_REASSIGN_CALLSIGN].freeze

  # Application column => label used in the "blank fields" message. State is
  # handled separately: only some countries have one.
  REQUIRED_FIELDS = {
    "first_name" => "First Name",
    "last_name" => "Last Name",
    "email" => "Email",
    "approved_handle" => "Approved Handle",
    "street" => "Street",
    "city" => "City",
    "postal_code" => "Postal Code",
    "country" => "Country",
    "phone" => "Phone",
    "bpguid" => "BPGUID",
    "sfuid" => "SFUID"
  }.freeze

  # Person attribute => the label of the application field it is copied from,
  # in REQUIRED_FIELDS' words, so a value the account refuses is reported
  # against the field the VC can correct. Only the attributes populate_person
  # copies that Person validates.
  ACCOUNT_FIELD_LABELS = {
    callsign: "Approved Handle",
    first_name: "First Name",
    last_name: "Last Name",
    email: "Email",
    home_phone: "Phone",
    street1: "Street",
    city: "City",
    state: "State/Province",
    zip: "Postal Code",
    country: "Country"
  }.freeze

  # Statuses of an existing account that may be safely updated to prospective.
  UPDATABLE_EXISTING_STATUSES = [Person::AUDITOR, Person::PAST_PROSPECTIVE, Person::ECHELON].freeze

  APPLICATION_APPROVED_MESSAGE = "application approved"
  REASSIGN_CALLSIGN_REASON = "Reassigned callsign due to incoming prospective application"

  # Intake note channel for notes copied off the application.
  INTAKE_NOTE_SOURCE = "vc"

  # ErrorLog tag for account-creation failures.
  ERROR_LOG_TAG = "application-account-fail"

  # Salesforce object backing a Ranger record.
  SALESFORCE_OBJECT = "Ranger__c"

  # A brief for an account referenced in the results.
  PersonSummary = Data.define(:id, :callsign, :status)

  # The outcome of a batch run. A nil results list means Salesforce
  # authentication failed and nothing was attempted.
  Batch = Data.define(:results, :auth_error) do
    def auth_failure?
      results.nil?
    end
  end

  attr_reader :application, :status, :errors, :person_id,
              :created_person, :conflicting_person, :reassign_callsign, :existing_person

  class << self
    # Preview or commit account creation for every approved application.
    #
    # Salesforce is only reached for a commit with writebacks enabled: with
    # writebacks off the source's connector went unused anyway, and skipping it
    # keeps previews (and writeback-free commits) entirely offline.
    #
    # @param commit [Boolean] false previews, true performs the writes
    # @param connector [#auth, #obj_update, nil] injected in tests
    # @return [Batch]
    def execute(commit: false, connector: nil)
      sf = nil
      if commit && Setting.get_value(Setting::SF_ENABLE_WRITEBACKS)
        sf = connector || Salesforce.connector
        return Batch.new(results: nil, auth_error: sf.error_message) unless sf.auth
      end

      reserved_handles = HandleReservation.active.index_by(&:normalized_handle)

      results = ProspectiveApplication.retrieve_approved.map do |application|
        prospective = new(application, reserved_handles:, commit:, sf:)
        prospective.process
        prospective
      end

      record_action_log(results) if commit && results.any?

      Batch.new(results:, auth_error: nil)
    end

    private

    # Record a privacy-conscious summary of the run. The result objects carry
    # applicant PII and are never serialized into the audit log.
    def record_action_log(results)
      summary = results.map do |result|
        {
          application_id: result.application.id,
          person_id: result.person_id,
          status: result.status,
          errors: result.errors
        }
      end

      ActionLog.record(Current.person, "prospective-account-create", "",
                       {
                         results: summary,
                         commit: true,
                         sent_welcome_emails: Setting.get_value(Setting::SEND_WELCOME_EMAIL),
                         updated_salesforce: Setting.get_value(Setting::SF_ENABLE_WRITEBACKS)
                       })
    end
  end

  def initialize(application, reserved_handles:, commit:, sf: nil)
    @application = application
    @reserved_handles = reserved_handles
    @commit = commit
    @sf = sf
    @status = STATUS_READY
    @errors = []
  end

  # Vet the application, check the account it would make, then create that
  # account when committing. A preview runs every check a commit runs.
  def process
    return unless verify_required_fields

    check_for_existing
    return unless READY_STATUSES.include?(status)

    person = build_account
    verify_account(person)

    create_account(person) if @commit && READY_STATUSES.include?(status)
  end

  # Verify the application has everything an account needs.
  #
  # @return [Boolean]
  def verify_required_fields
    valid = true

    if application.year != Current.year
      @status = STATUS_INVALID
      errors << "Application year #{application.year} is not the current year"
      valid = false
    end

    missing = REQUIRED_FIELDS.filter_map { |field, label| label if application[field].blank? }
    if ProspectiveApplication::COUNTRIES_WITH_STATES.include?(application.country) && application.state.blank?
      missing << "State/Province"
    end

    if missing.any?
      @status = STATUS_INVALID
      errors << "Required fields are blank: #{missing.join(', ')}"
      valid = false
    end

    valid
  end

  # See if the application conflicts with an existing account.
  def check_for_existing
    callsign_holder = Person.retrieve_by_callsign(application.approved_handle)

    return if detect_callsign_conflict(callsign_holder)
    return if detect_reserved_handle_conflict(callsign_holder)

    detect_duplicate_identity_conflict
  end

  private

  # Detect a conflict between the approved handle and an account belonging to
  # someone else. Marks the account for callsign reassignment when the handle
  # can be freed.
  #
  # @param person [Person, nil] the current holder of the approved handle
  # @return [Boolean] true if a hard conflict was recorded
  def detect_callsign_conflict(person)
    return false if person.nil? || person.bpguid == application.bpguid

    if person.vintage?
      mark_conflict(STATUS_EXISTING_CALLSIGN, "Callsign conflict with existing account with vintage status.", person)
      return true
    end

    return !release_deceased_callsign?(person) if person.status == Person::DECEASED

    unless [Person::RETIRED, Person::RESIGNED].include?(person.status)
      mark_conflict(STATUS_EXISTING_CALLSIGN,
                    "Callsign conflict with an existing account. This application's and the account's " \
                    "BPGUIDs do not match, and status is neither retired nor resigned",
                    person)
      return true
    end

    # Retired or resigned: the callsign may be reassigned.
    mark_reassign(person)
    false
  end

  # Whether a deceased person's callsign may be released for reuse. Records a
  # conflict when the grieving period cannot be determined or has not elapsed.
  #
  # @return [Boolean] true if the callsign may be reassigned
  def release_deceased_callsign?(person)
    deceased = PersonStatus.find_for_time(person.id, Current.time)

    if deceased.nil? || deceased.new_status != Person::DECEASED
      # Either no history exists, or the last status change was not to deceased.
      mark_conflict(STATUS_EXISTING_CALLSIGN,
                    "Person deceased but cannot determine if still within the grieving period", person)
      return false
    end

    release_date = deceased.created_at.advance(years: Person::GRIEVING_PERIOD_YEARS)
    if release_date > Current.time
      mark_conflict(STATUS_EXISTING_CALLSIGN,
                    "Callsign conflict with deceased person, and still in the grieving period of " \
                    "#{Person::GRIEVING_PERIOD_YEARS} years. Callsign can be released on " \
                    "#{release_date.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)}",
                    person)
      return false
    end

    mark_reassign(person)
    true
  end

  # Detect a conflict with the reserved handle list. An applicant who already
  # holds the reserved handle (matching BPGUID) is exempt.
  #
  # @return [Boolean] true if a reserved-handle conflict was recorded
  def detect_reserved_handle_conflict(person)
    message = reserved_handle_message
    return false if message.nil?
    return false if person && person.bpguid == application.bpguid

    @status = STATUS_RESERVED_CALLSIGN
    errors << message
    true
  end

  # @return [String, nil] why the callsign is reserved, or nil if it is free
  def reserved_handle_message
    reserved = @reserved_handles[WordUtils.normalize_word(application.approved_handle)]
    return nil unless reserved

    message = "Is a reserved handle/word (#{reserved.type_label})"
    message += ", expires on #{reserved.expires_on.strftime(DateTimeHelper::DATE)}" if reserved.expires_on
    message
  end

  # Detect existing accounts matching the application's email or BPGUID. An
  # eligible match is captured for update; an ineligible match, or two distinct
  # accounts, is a conflict.
  def detect_duplicate_identity_conflict
    %w[email bpguid].each do |unique|
      person = Person.find_by(unique => application[unique])
      next unless person

      unless UPDATABLE_EXISTING_STATUSES.include?(person.status)
        mark_conflict(STATUS_EXISTING_BAD_STATUS,
                      "Account with the same #{unique} already exists, and is not an auditor, " \
                      "past prospective, or echelon",
                      person)
        return
      end

      if @existing_person_model && @existing_person_model.id != person.id
        mark_conflict(STATUS_EXISTING_BAD_STATUS,
                      "The application's email and BPGUID match two different existing accounts " \
                      "(##{@existing_person_model.id} and ##{person.id})",
                      person)
        return
      end

      @existing_person = person_summary(person)
      @existing_person_model = person
    end
  end

  # Record a hard conflict against a person and halt further checks.
  def mark_conflict(status, error, person)
    @status = status
    errors << error
    @conflicting_person = person_summary(person)
  end

  # Mark an account for callsign reassignment.
  def mark_reassign(person)
    @status = STATUS_READY_REASSIGN_CALLSIGN
    @reassign_callsign = person_summary(person)
    @reassign_callsign_model = person
  end

  def person_summary(person)
    PersonSummary.new(id: person.id, callsign: person.callsign, status: person.status)
  end

  # The account a commit would save: a new one, or the eligible existing one,
  # with the application copied onto it.
  def build_account
    person = @existing_person_model || Person.new
    populate_person(person)
    person
  end

  # Run Person's own validations on the account, so a preview reports what a
  # commit's save would refuse. A refused value makes the application invalid,
  # each message led by the field to correct.
  def verify_account(person)
    return if person.valid?
    return if detect_exact_callsign_holder(person)
    return if person.errors.empty?

    @status = STATUS_INVALID
    errors.concat(account_error_messages(person))
  end

  # Person reports the callsign taken when the account being reassigned holds
  # it, because it keeps the callsign until the commit frees it. That is set
  # aside only when no other account holds the exact callsign:
  # callsign_normalized is not unique, so the account being reassigned may not
  # be the one holding it, and an account sharing the applicant's BPGUID passes
  # detect_callsign_conflict.
  #
  # @return [Boolean] true if a conflict was recorded
  def detect_exact_callsign_holder(person)
    return false unless person.errors.of_kind?(:callsign, :taken)

    # Compared as the uniqueness check compares, by the column's collation.
    holder = Person.where.not(id: [person.id, @reassign_callsign_model&.id].compact)
                   .find_by(callsign: person.callsign)
    if holder
      mark_conflict(STATUS_EXISTING_CALLSIGN,
                    "Callsign conflict with the account shown, which already holds this exact callsign.", holder)
      return true
    end

    person.errors.delete(:callsign, :taken)
    false
  end

  # Person's complaints about the account, each led by what to correct: the
  # application field the value came from, or, for a converted account's own
  # stored value, that account. No message carries the value: the action log
  # keeps every commit's messages.
  def account_error_messages(person)
    person.errors.map do |error|
      label = ACCOUNT_FIELD_LABELS[error.attribute]
      next ValidationMessage.naming(error, label) if label

      person.new_record? ? error.message : "Existing account ##{person.id}: #{error.message}"
    end
  end

  # Save the account process built and checked: a new one, or an eligible
  # existing one converted. Irreversible side effects (the welcome email) only
  # fire after the database work commits.
  def create_account(person)
    is_new = @existing_person_model.nil?

    # A password is required, and this one is never told to anyone: the
    # applicant sets a real one through the welcome email's login token.
    person.password = SecureRandom.urlsafe_base64(24) if is_new

    return unless persist_account(person, is_new)

    @person_id = person.id
    @status = STATUS_CREATED
    @created_person = person_summary(person)

    send_welcome_email(person)
  end

  # Copy the application onto the person. The password is create_account's:
  # setting one runs Argon2, which a preview has no use for.
  def populate_person(person)
    person.callsign = application.approved_handle
    person.callsign_approved = true
    person.first_name = application.first_name
    person.last_name = application.last_name
    person.street1 = application.street
    person.city = application.city
    person.state = application.state
    person.zip = application.postal_code
    person.country = application.country
    person.home_phone = application.phone
    person.email = application.email
    person.bpguid = application.bpguid
    person.sfuid = application.sfuid
    person.emergency_contact = application.emergency_contact
    person.known_rangers = application.known_rangers
    person.known_pnvs = application.known_applicants

    person.status = Person::PROSPECTIVE
    person.audit_reason = APPLICATION_APPROVED_MESSAGE
  end

  # Free any conflicting callsign, save the person, mark the application
  # created, and bootstrap status/roles/positions/intake notes -- atomically,
  # so a failure anywhere leaves no half-built account and no stolen callsign.
  #
  # @return [Boolean] true on success
  def persist_account(person, is_new)
    ActiveRecord::Base.transaction do
      reassign_callsign_from_holder

      raise AccountSaveError, validation_error_message(person, is_new) unless person.save

      application.status = ProspectiveApplication::STATUS_CREATED
      application.person_id = person.id
      application.save!(validate: false)

      bootstrap_new_account(person) if is_new
      copy_intake_notes(person)

      raise AccountSaveError, "Salesforce record update failure. #{@sf.error_message}" unless sync_salesforce(person, is_new)
    end

    true
  rescue AccountSaveError => e
    record_failure(e.message)
    ErrorLog.record(ERROR_LOG_TAG,
                    data: { person_id: person.id, application_id: application.id,
                            errors: person.errors.to_hash })
    false
  rescue ActiveRecord::StatementInvalid => e
    record_failure("SQL Error: #{e.message}")
    ErrorLog.record_exception(e, ERROR_LOG_TAG,
                              extra: { person_id: person.id, application_id: application.id })
    false
  rescue StandardError => e
    record_failure("#{is_new ? 'Creation' : 'Update'} error: #{e.message}")
    ErrorLog.record_exception(e, ERROR_LOG_TAG,
                              extra: { person_id: person.id, application_id: application.id })
    false
  end

  def record_failure(message)
    errors << message
    @status = STATUS_CREATE_FAILED
    # The application row rolled back with everything else; drop the stale
    # in-memory status so callers see what is actually stored.
    application.reload
  end

  # Take the callsign off its current holder so the applicant can have it.
  def reassign_callsign_from_holder
    return unless @reassign_callsign_model

    holder = @reassign_callsign_model
    holder.reset_callsign
    holder.audit_reason = REASSIGN_CALLSIGN_REASON
    holder.save!(validate: false)
  end

  # A brand new account has no status history, roles, or positions yet.
  # Converted accounts get all of this from Person's own status-change hook.
  def bootstrap_new_account(person)
    PersonStatus.record(person.id, "", Person::PROSPECTIVE, APPLICATION_APPROVED_MESSAGE, Current.person_id)
    PersonRole.reset_roles(person.id, APPLICATION_APPROVED_MESSAGE, Person::ADD_NEW_USER)
    PersonPosition.reset_positions(person.id, APPLICATION_APPROVED_MESSAGE, Person::ADD_NEW_USER)
  end

  def copy_intake_notes(person)
    application.notes.each do |note|
      PersonIntakeNote.record(person_id: person.id, year: Current.year, type: INTAKE_NOTE_SOURCE,
                              note: note.note, is_log: false,
                              person_source_id: note.person_id || Current.person_id)
    end
  end

  # Render a person's validation errors into a single message, worded as
  # verify_account words them. The messages hold commas of their own, so a
  # semicolon parts them.
  def validation_error_message(person, is_new)
    "#{is_new ? 'Creation' : 'Update'} error: #{account_error_messages(person).join('; ')}"
  end

  # Send the welcome email with a temporary login token, if enabled. The token
  # is how the applicant sets a real password before their first sign-in.
  def send_welcome_email(person)
    return unless Setting.get_value(Setting::SEND_WELCOME_EMAIL)

    invite_token = person.create_temporary_login_token(Person::PNV_INVITATION_EXPIRE)
    WelcomeMailer.with(sender_id: Current.person_id).notify(person:, invite_token:).deliver_later
  end

  # Write the result back to the linked Salesforce Ranger record. Nil sf means
  # writebacks are off (or this is a preview), which is a silent success.
  #
  # @return [Boolean]
  def sync_salesforce(person, is_new)
    return true if @sf.nil?

    action = is_new ? "created" : "updated"

    @sf.obj_update(SALESFORCE_OBJECT, application.salesforce_id,
                   {
                     "CH_ImportStatusMessage__c" =>
                       "#{Current.time.strftime('%Y-%m-%d %H:%M:%S')}: Clubhouse account successfully #{action}",
                     "CH_UID__c" => person.id.to_s,
                     "VC_Approved_Radio_Call_Sign__c" => application.approved_handle,
                     "VC_Event_Year__c" => application.year.to_s,
                     "VC_Status__c" => is_new ? "Clubhouse Record Created" : "Clubhouse Record Updated"
                   })
  end
end
