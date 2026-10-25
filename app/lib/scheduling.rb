# frozen_string_literal: true

module Scheduling
  LOCATE_SHIFT_START_WITHIN = 60.minutes # Find a shift starting within +/- X minutes

  # Add signup / remove signup results
  STATUS_SUCCESS = "success"
  # Shift is full
  STATUS_FULL = "full"
  # The same position, usually the In-Person Training, is already signed up for
  STATUS_MULTIPLE_ENROLLMENT = "multiple-enrollment"
  # The slot has not been activated
  STATUS_NOT_ACTIVE = "not-active"
  # The person does not hold the position
  STATUS_NO_POSITION = "no-position"
  # The shift has ended
  STATUS_HAS_ENDED = "has-ended"
  # The shift has started
  STATUS_HAS_STARTED = "has-started"
  # The signup already exists
  STATUS_EXISTS = "exists"
  # The shift is not signed up for (attempted removal)
  STATUS_MISSING_SIGNUP = "missing-signup"
  # The person has not met the requirements to signup for a shift (see the requirements sections below)
  STATUS_MISSING_REQUIREMENTS = "missing-requirements"
  # The shift is a paid position, and the person does not have an employee id on file
  STATUS_NO_EMPLOYEE_ID = "no-employee-id"
  # Attempted to sign up for non-existing shift
  STATUS_SLOT_NOT_FOUND = "slot-not-found"

  # Something bad happened with the database
  STATUS_DB_FAILURE = "db-failure"

  # The statuses that may be overridden
  MAY_FORCE_STATUSES = [
    STATUS_FULL,
    STATUS_HAS_STARTED,
    STATUS_HAS_ENDED,
    STATUS_MULTIPLE_ENROLLMENT
  ].freeze

  # Missing requirements to signup for shifts or shift

  # The person is a past prospective
  IS_PAST_PROSPECTIVE = "past-prospective"
  # The person does not have a BPGUID on file -- usually most signups are blocked.
  MISSING_BPGUID = "bpguid-missing"
  # The person does not have an approved callsign
  MISSING_CALLSIGN_APPROVAL = "callsign-unapproved"
  # The person's submitted photo has not been approved yet (usually applicants)
  MISSING_PHOTO_APPROVAL = "photo-unapproved"
  # The person has not reviewed their personal info yet (usually applicants)
  MISSING_PI_REVIEW = "pi-unreviewed"
  # The person is attempting to signup for a Sandman shift, and the affidavit has not been signed yet.
  MISSING_SIGNED_SANDMAN_AFFIDAVIT = "unsigned-sandman-affidavit"
  # The Online Course has not been activated yet (person trying to signup for an In-Person Training)
  OC_IS_DISABLED = "oc-disabled"
  # The Online Course has not been completed yet -- requirement for In-Person Training signup
  OC_IS_NOT_COMPLETED = "oc-missing"

  REQUIREMENT_LABELS = {
    MISSING_PI_REVIEW => "The Personal Information needs to be reviewed first",
    MISSING_BPGUID => "The Burner Profile and Clubhouse accounts are not linked",
    OC_IS_DISABLED => "The Online Course has to be completed. However, the course is not quite ready yet and usually available by mid-to-late March. Watch the Ranger Announce mailing list for a message on when the course will be available.",
    OC_IS_NOT_COMPLETED => "The Online Course has not been completed.",
    MISSING_CALLSIGN_APPROVAL => "Callsign has not been approved",
    MISSING_PHOTO_APPROVAL => "The BMID photo is missing or has been rejected",
    IS_PAST_PROSPECTIVE => "The person is a Past Prospective is not eligible to sign up for any trainings or on playa shifts.",
    MISSING_SIGNED_SANDMAN_AFFIDAVIT => "The Sandman Affidavit has to be agreed to first before the shift can be signed up for.<br> Visit Me > Agreements to sign the affidavit."
  }
end
