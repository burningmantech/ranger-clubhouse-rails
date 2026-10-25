# frozen_string_literal: true

# TODO: Move to a flag/certificate/agreement tracking system to layer on top of. This is intended to be a
#       temporary abstraction.

require "ostruct"

class Agreements
  TERM_LIFETIME = "lifetime" # column stored in person
  TERM_ANNUAL = "annual" # column stored in person_event

  # A document list available to most Rangers and Applicants.
  #
  # key: the document tag identifier (see App/Models/Document)
  # term: indicates the agreement is lifetime (person table col.) or annual (person_event table col.)
  # setting: the Clubhouse setting indicating if the document is available to sign by all non-auditor accounts.
  # person_event: the person_event column indicating if the document is available to the user to sign.
  # role: the role (raw, before the NDA wipe) the person must hold to see or sign the document.
  #
  # NOTE: if neither setting nor person_event is present, this indicates the document is available at all times.

  DOCUMENTS = {
    Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG => {
      term: TERM_LIFETIME,
      column: "behavioral_agreement"
    },

    Document::MOTORPOOL_POLICY_TAG => {
      term: TERM_ANNUAL,
      setting: Setting::MOTOR_POOL_PROTOCOL_ENABLED,
      column: "signed_motorpool_agreement"
    },

    Document::PERSONAL_VEHICLE_AGREEMENT_TAG => {
      term: TERM_ANNUAL,
      column: "signed_personal_vehicle_agreement"
    },

    Document::RADIO_CHECKOUT_AGREEMENT_TAG => {
      setting: Setting::RADIO_CHECKOUT_AGREEMENT_ENABLED,
      term: TERM_ANNUAL,
      column: "asset_authorized"
    },

    Document::SANDMAN_AFFIDAVIT_TAG => {
      term: TERM_ANNUAL,
      column: "sandman_affidavit"
    },

    Document::DEPT_NDA_TAG => {
      term: TERM_ANNUAL,
      column: "signed_nda",
      role: Role::EVENT_MANAGEMENT # Only show if the effective role has been granted
    }
  }.freeze

  # Retrieve all available agreements the person may see but not necessarily sign (yet).
  #
  # @param [Person] person
  # @param [Integer] year viewed year for annual flags, defaults to the current year
  # @param [Boolean] include_hidden include documents failing the visibility rules (admin view)
  # @return [Array<Hash>]
  # @raise [ArgumentError]
  def self.retrieve(person, year: Current.year, include_hidden: false)
    agreements = []
    person_event = PersonEvent.first_or_new_for_person_year(person.id, year)

    DOCUMENTS.each do |tag, paper|
      term = paper[:term]

      visible = is_document_visible?(tag, paper, person_event, person, year)
      next unless visible || include_hidden

      document = Document.find_id_or_tag(tag)

      next unless document

      col = paper[:column]
      agreements << OpenStruct.new(
        tag:,
        title: document.description,
        term:,
        signed: ((term == TERM_LIFETIME) ? person.public_send(col) : person_event.public_send(col)),
        available: can_sign_document?(person, tag, person_event),
        visible:
      )
    end

    # Sort priority is available & unsigned, unavailable, signed
    agreements.sort_by { |a| [a.signed ? 1 : 0, a.available ? 0 : 1, a.title] }
  end

  # Digitally sign an agreement
  #
  # @param [Person] person
  # @param [String] tag
  # @raise [ArgumentError]
  def self.sign_agreement(person, tag)
    paper = DOCUMENTS[tag]
    raise ActiveRecord::RecordNotFound, "Agreement not found" unless paper

    person_event = PersonEvent.first_or_new_for_person_year(person.id, Current.year)

    unless can_sign_document?(person, tag, person_event)
      raise ArgumentError, "Document not available to sign"
    end

    col = paper[:column]
    if paper[:term] == TERM_LIFETIME
      person.public_send("#{col}=", true)
      person.save(validate: false)
    else
      person_event.public_send("#{col}=", true)
      person_event.save(validate: false)
    end

    if tag == Document::DEPT_NDA_TAG
      PersonRole.clear_cache(person.id)
    end

    ActionLog.record(person, "agreement-signature", nil, { tag:, signature: true })
  end

  # Administratively set or clear an agreement signature flag for the current year.
  # Bypasses the availability check — this is for corrections; the person signs
  # for themself through sign_agreement.
  #
  # @param [Person] person
  # @param [String] tag
  # @param [Boolean] signed
  # @param [PersonEvent, nil] person_event preloaded event row for annual flags (avoids a re-fetch per tag)
  def self.admin_set_signature(person, tag, signed, person_event: nil)
    paper = DOCUMENTS[tag]
    raise ActiveRecord::RecordNotFound, "Agreement not found" unless paper

    col = paper[:column]
    person_event ||= PersonEvent.first_or_new_for_person_year(person.id, Current.year) if paper[:term] == TERM_ANNUAL
    record = (paper[:term] == TERM_LIFETIME) ? person : person_event

    return if (record.public_send(col) ? true : false) == signed

    record.public_send("#{col}=", signed)
    record.save(validate: false)

    if tag == Document::DEPT_NDA_TAG
      PersonRole.clear_cache(person.id)
    end

    ActionLog.record(Current.person, "agreement-signature", nil, { tag:, signature: signed }, person.id)
  end

  # Check to see if an agreement has been signed.
  #
  # @param [Person] person
  # @param [String] tag
  # @param [PersonEvent, nil] person_event
  # @return [Boolean]
  # @raise [ArgumentError]
  def self.did_sign_document?(person, tag, person_event = nil)
    paper = DOCUMENTS[tag]
    raise ActiveRecord::RecordNotFound, "Document tag not found" unless paper

    col = paper[:column]
    if paper[:term] == TERM_LIFETIME
      person.public_send(col)
    else
      person_event ||= PersonEvent.first_or_new_for_person_year(person.id, Current.year)
      person_event.public_send(col)
    end
  end

  # Check to see if the agreement can be signed.
  #
  # @param [Person] person
  # @param [String] tag
  # @param [PersonEvent] person_event
  # @return [Boolean]
  # @raise [ArgumentError]
  def self.can_sign_document?(person, tag, person_event)
    paper = DOCUMENTS[tag]
    raise ArgumentError, "Document tag not found" unless paper

    setting_name = paper[:setting]
    pe_column = paper[:person_event]
    role = paper[:role]

    return false if role && !person.has_raw_role?(role)

    if setting_name
      Setting.get_value(setting_name)
    elsif pe_column
      person_event.public_send(pe_column)
    else
      true
    end
  end

  # Is the document visible? (however, it may not be ready to be signed)
  #
  # @param [String] tag
  # @param [Hash] doc
  # @param [PersonEvent] person_event
  # @param [Person] person
  # @param [Integer] year
  # @return [Boolean]
  def self.is_document_visible?(tag, doc, person_event, person, year)
    role = doc[:role]
    return false if role && !person.has_raw_role?(role)

    if tag == Document::SANDMAN_AFFIDAVIT_TAG
      # Document becomes visible when the Sandman schedule has been published, and if the person is
      # a Ranger.
      return Person::ACTIVE_STATUSES.include?(person.status) &&
             Slot.have_active_for_position([Position::SANDMAN_TRAINING, Position::SANDMAN], year:)
    elsif tag == Document::PERSONAL_VEHICLE_AGREEMENT_TAG
      return VehicleEligibility.is_pvr_eligible?(person.id, person_event, year) && person_event.org_vehicle_insurance
    end

    pe_column = doc[:person_event]

    if doc[:setting]
      true
    elsif pe_column
      person_event.public_send(pe_column)
    else
      true
    end
  end
end
