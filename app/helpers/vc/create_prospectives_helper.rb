# frozen_string_literal: true

module Vc::CreateProspectivesHelper
  Creator = ProspectiveClubhouseAccountFromApplication

  # How each verdict is presented, in the order the sections appear. Outcomes
  # come first so the answer to "what just happened" is at the top after a
  # commit; on a preview only the later buckets can occur.
  #
  # account names the column showing an account involved and the result reader
  # behind it; problem adds the column carrying the engine's explanations. A
  # group may have both -- a callsign conflict names the holder AND says why.
  GROUPS = [
    { status: Creator::STATUS_CREATED, title: "Accounts Created",
      icon: "circle-check", variant: :success, account: ["Account", :created_person],
      intro: "These prospective accounts now exist, and each application is marked Account Created." },

    { status: Creator::STATUS_CREATE_FAILED, title: "Creation Failures",
      icon: "triangle-exclamation", variant: :error, problem: true,
      intro: "The Clubhouse could not create these accounts, and nothing was saved for them. " \
             "Send the messages below to the Ranger Tech Cadre." },

    { status: Creator::STATUS_READY, title: "Ready to Create",
      icon: "user-plus", variant: :success,
      intro: "These approved applications pass every check. Create Accounts makes one prospective " \
             "account for each." },

    { status: Creator::STATUS_READY_REASSIGN_CALLSIGN, title: "Ready, Callsign Needs Reassigning",
      icon: "arrow-right-arrow-left", variant: :warning,
      account: ["Callsign Taken From", :reassign_callsign],
      intro: "These applications are ready, but each callsign still belongs to someone else. " \
             "Create Accounts takes the callsign from the account shown and gives that person a new one." },

    { status: Creator::STATUS_INVALID, title: "Missing or Invalid Fields",
      icon: "circle-exclamation", variant: :warning, problem: true,
      intro: "These applications cannot become accounts until each problem listed is fixed. " \
             "Open each application to fill in or correct the fields named. A problem that names " \
             "an existing account is fixed on that account instead." },

    { status: Creator::STATUS_EXISTING_CALLSIGN, title: "Callsign Conflicts",
      icon: "id-badge", variant: :warning, account: ["Conflicting Account", :conflicting_person],
      problem: true,
      intro: "Each approved callsign already belongs to the account shown. Read why before deciding " \
             "whether to approve a different callsign on the application." },

    { status: Creator::STATUS_RESERVED_CALLSIGN, title: "Reserved Callsigns",
      icon: "ban", variant: :warning, problem: true,
      intro: "Each approved callsign matches a reserved handle or a disallowed word or phrase. " \
             "Approve a different callsign on the application." },

    { status: Creator::STATUS_EXISTING_BAD_STATUS, title: "Existing Account Conflicts",
      icon: "user-lock", variant: :warning, account: ["Existing Account", :conflicting_person],
      problem: true,
      intro: "An account with the same email or BPGUID already exists, and its status is not auditor, " \
             "past prospective, or echelon, so it cannot be converted. Review the account shown." }
  ].freeze

  # Bucket results into the display groups. Anything with a status this page
  # does not know about still gets a section rather than vanishing.
  #
  # @param results [Array<ProspectiveClubhouseAccountFromApplication>]
  # @return [Array<Hash>] groups with a :results key, empty ones dropped
  def create_prospectives_groups(results)
    buckets = results.group_by(&:status)

    groups = GROUPS.filter_map do |group|
      found = buckets.delete(group[:status])
      group.merge(results: found) if found
    end

    groups + buckets.map do |status, found|
      { status:, title: "Unrecognized Status: #{status}", icon: "bug", variant: :error,
        problem: true, results: found,
        intro: "The account creator returned a status this page does not recognize. " \
               "Report this to the Ranger Tech Cadre." }
    end
  end

  # Statuses the VC team has to resolve before an account can be created.
  BLOCKED_STATUSES = [
    Creator::STATUS_INVALID, Creator::STATUS_EXISTING_CALLSIGN,
    Creator::STATUS_RESERVED_CALLSIGN, Creator::STATUS_EXISTING_BAD_STATUS
  ].freeze

  # Headline counts for one run. :ready counts what a commit would act on
  # (reassignments included), :blocked what needs a person to intervene.
  def create_prospectives_summary(results)
    counts = results.group_by(&:status).transform_values(&:size)
    counts.default = 0

    {
      created: counts[Creator::STATUS_CREATED],
      failed: counts[Creator::STATUS_CREATE_FAILED],
      reassign: counts[Creator::STATUS_READY_REASSIGN_CALLSIGN],
      ready: Creator::READY_STATUSES.sum { |status| counts[status] },
      blocked: BLOCKED_STATUSES.sum { |status| counts[status] },
      total: results.size
    }
  end

  # "1 application needs attention" / "3 applications need attention", since
  # pluralize alone leaves the verb disagreeing with the count.
  def needs_attention_phrase(count)
    "#{pluralize(count, 'application')} #{count == 1 ? 'needs' : 'need'} attention"
  end

  # An account named in the results, with its status so the reader can tell a
  # retired Ranger from an active one.
  def prospective_person_link(person)
    return value_or_dash(nil) if person.nil?

    link_to "#{person.callsign} (#{person.status})", person_path(person.id), class: "underline font-semibold"
  end

  def application_salesforce_link(application)
    return value_or_dash(nil) if application.salesforce_id.blank?

    ext_link application.salesforce_name.presence || application.salesforce_id,
             salesforce_record_url(application.salesforce_id)
  end

  # What a commit will actually do, given the settings in force.
  def create_prospectives_confirm_message(send_welcome_email:, sf_writebacks:)
    message = +"This creates a Clubhouse account for every application listed as ready, and marks each " \
               "application Account Created. Callsigns listed for reassignment are taken from their " \
               "current holders. "
    message << "Each new prospective is sent a welcome email. " if send_welcome_email
    message << "Each application's Salesforce record is updated. " if sf_writebacks
    message << "Preview first if you have not already."
    message
  end
end
