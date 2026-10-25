class Bmid < ApplicationRecord
  self.table_name = "bmid"

  # Badges are edited by hand, one person page or one bulk grid at a time, and
  # "who changed my title?" is a real question. Upstream audits this model too
  # (App\Models\Bmid::$auditModel).
  self.audit_model = true

  # BMID is being prepped
  IN_PREP = "in_prep"
  # Ready to be sent off to be printed
  READY_TO_PRINT = "ready_to_print"
  # BMID was changed (name, photos, titles, etc.) and needs to be reprinted
  READY_TO_REPRINT_CHANGE = "ready_to_reprint_changed"
  # BMID was lost and a new one issued
  READY_TO_REPRINT_LOST = "ready_to_reprint_lost"

  # BMID has issues, do not print.
  ISSUES = "issues"

  # Person is not rangering this year (common) or another reason.
  DO_NOT_PRINT = "do_not_print"

  # BMID was submitted
  SUBMITTED = "submitted"

  READY_TO_PRINT_STATUSES = [
    IN_PREP,
    READY_TO_PRINT,
    READY_TO_REPRINT_CHANGE,
    READY_TO_REPRINT_LOST
  ].freeze

  ALLOWED_PERSON_STATUSES = [
    Person::ACTIVE,
    Person::ALPHA,
    Person::INACTIVE,
    Person::INACTIVE_EXTENSION,
    Person::ECHELON,
    Person::PROSPECTIVE,
    Person::RETIRED
  ].freeze

  # The badge titles a position earns now live in the bmid_title table, which
  # the CreateBmidTitle migration seeded from this list. See BmidTitle.

  # People who left the Rangers. Their badges are never made for a current year.
  DEPARTED_STATUSES = [
    Person::DECEASED,
    Person::DISMISSED,
    Person::RESIGNED
  ].freeze

  ALLOWED_STATUSES = [
    IN_PREP,
    READY_TO_PRINT,
    READY_TO_REPRINT_CHANGE,
    READY_TO_REPRINT_LOST,
    ISSUES,
    DO_NOT_PRINT,
    SUBMITTED
  ].freeze

  belongs_to :person

  # Callbacks
  before_validation :set_default_status, on: :create
  after_save :update_sap

  # Validations
  validates :status, inclusion: { in: ALLOWED_STATUSES }
  validate :admission_date_is_a_choice

  # Virtual attributes (populated by BmidRelationshipLoader).
  #
  # org_vehicle_insurance deliberately shadows the bmid column of the same name:
  # the column is dead (never read, never written) and the live value comes from
  # the person's person_event row. Upstream behaves identically -- do not "fix".
  attr_accessor :access_date, :access_any_time, :org_vehicle_insurance,
                :has_signups, :has_ticket, :training_signed_up,
                :meals_granted, :showers_granted, :have_allocated_provisions,
                :sap

  def self.find_for_query(query)
    scope = all
    year = query[:year]

    if year.present?
      scope = scope.where(year: year)
    end

    bmids = scope.includes(:person)
    bulk_load_relationships(bmids, bmids.map(&:person_id), year.present? ? year.to_i : Current.year)
    bmids
  end

  def self.find_for_person_year(person_id, year)
    where(person_id: person_id, year: year).first
  end

  def self.find_for_person_manage(person_id, year)
    find_for_person_ids(year, [person_id]).first
  end

  def self.find_for_person_ids(year, person_ids, exclude_departed = false)
    return [] if person_ids.empty?

    if exclude_departed
      # Narrow the person ids, not just the badges already on file: filtering
      # the rows alone let a departed person come straight back below as a
      # freshly synthesized blank badge (the upstream bug).
      person_ids = Person.where(id: person_ids).where.not(status: DEPARTED_STATUSES).pluck(:id)
      return [] if person_ids.empty?
    end

    bmids = where(year: year).where(person_id: person_ids).to_a
    bmids_by_person = bmids.index_by(&:person_id)

    # Create new Bmids for those missing
    person_ids.each do |person_id|
      next if bmids_by_person.key?(person_id)

      bmid = Bmid.new(person_id: person_id, year: year, status: IN_PREP)
      bmids << bmid
      bmids_by_person[person_id] = bmid
    end

    bulk_load_relationships(bmids, person_ids, year)

    bmids.sort_by { |b| b.person.callsign.downcase }
  end

  def self.bulk_load_relationships(bmids, person_ids, year = Current.year)
    BmidRelationshipLoader.new(bmids, person_ids, year).call
  end

  def load_relationships
    self.class.bulk_load_relationships([self], [person_id], year)
  end

  def set_sap(sap)
    self.access_date = sap.access_date
    self.access_any_time = sap.access_any_time
    self.sap = sap
    # What the documents already say, remembered so a save that never touched
    # the access date can tell.
    @loaded_admission = admission_pair
  end

  # Push the badge's access date out to every SAP and Staff Credential the
  # person holds that is still changeable -- but only when this save actually
  # moved it.
  #
  # The callback fires on every save, and the badge is carrying the date of one
  # document (whichever the loader picked) on behalf of all of them. Writing it
  # back unconditionally means a title-only edit stamps that one date onto
  # every other pass the person owns, including banked ones the page never
  # showed. access_date and access_any_time are virtual, so ActiveRecord's own
  # change tracking cannot answer this -- hence the remembered pair.
  def update_sap
    return if admission_pair == loaded_admission

    AccessDocument.update_saps_for_person(person_id, access_date, access_any_time, "set via BMID update")
    if sap
      sap.reload
      set_sap(sap)
    end
  end

  def is_printable?
    person_status_printable? && qualified_to_print?
  end

  def append_notes(new_notes)
    date = Current.time.strftime("%-m/%-d/%y %H:%M:%S")
    callsign = Current.person&.callsign || "(unknown)"
    self.notes = "#{date} #{callsign}: #{new_notes}\n#{self.notes}"
  end

  # Attribute Accessors for virtual/json attributes

  def sap_id
    sap&.id
  end

  def sap_status
    sap&.status
  end

  def sap_type
    sap&.type
  end

  def has_approved_photo
    person&.has_photo?
  end

  # --- Print-qualification predicates ---------------------------------------
  # (Reconstructed from the Ember bmid model / bmid-edit template. The virtual
  # sign-up/ticket/training flags are populated by BmidRelationshipLoader.)

  # The person hasn't earned a printed badge yet: Echelon volunteers need a
  # shift sign-up; everyone else needs a claimed ticket or in-person training.
  def not_qualified_to_print?
    if person&.status == Person::ECHELON
      !has_signups
    else
      !training_signed_up && !has_ticket
    end
  end

  # The current status will cause the badge to be printed.
  def qualified_to_print?
    READY_TO_PRINT_STATUSES.include?(status)
  end

  # The person's status allows a badge to print at all. The other half of
  # is_printable?, named so the export page can bucket and explain the two
  # failure modes separately.
  def person_status_printable?
    ALLOWED_PERSON_STATUSES.include?(person&.status)
  end

  # Fit to go into a print batch as-is: photo approved and qualifications met.
  # Pre-checks the export page's rows (upstream vc/bmid-print parity).
  def print_ready?
    has_approved_photo && !not_qualified_to_print?
  end

  # The current status explicitly prevents printing.
  def will_not_print?
    [DO_NOT_PRINT, ISSUES].include?(status)
  end

  def submitted?
    status == SUBMITTED
  end

  # --- SAP (Setup Access Pass) display --------------------------------------

  def sap_type_label
    AccessDocument::TYPE_LABELS[sap_type] if sap_type
  end

  def sap_submitted?
    sap&.status == AccessDocument::SUBMITTED
  end

  def sap_banked?
    sap&.status == AccessDocument::BANKED
  end

  # This badge prints for its own event year; the pass attached to it is
  # whichever one the person holds right now.
  def current_event_year?
    year == Current.year
  end

  # The SAP date can't be changed with no SAP on file, once submitted, or from a
  # badge belonging to a past year.
  #
  # That last one is not cosmetic. AccessDocument.find_sap_for_person_ids is not
  # year-scoped and TicketingInfo offers this year's dates, so a badge from 2025
  # is shown -- and would write -- the pass the person is holding for the event
  # they are about to attend. Saving a 2025 badge must never move a 2026
  # arrival date.
  def sap_disabled?
    sap.nil? || sap_submitted? || !current_event_year?
  end

  # The single admin-form access-date choice, mirroring AccessDocument. Writing
  # it sets the virtual access_date/access_any_time that update_sap propagates
  # to the person's SAP & Staff Credential documents on save.
  def admission_date
    return AccessDocument::ADMISSION_ANY if access_any_time

    access_date&.to_date&.iso8601
  end

  # The form offers exactly three kinds of value: nothing (unspecified), "any",
  # or one of the selectable dates. Anything else is refused rather than
  # stored: update_sap hands whatever it finds to a save that skips validation,
  # so a value the database cannot cast would land on the person's real access
  # documents as NULL and erase an arrival date no one touched.
  def admission_date=(value)
    value = value.to_s.strip
    @admission_date_rejected = nil

    if value == AccessDocument::ADMISSION_ANY
      self.access_any_time = true
      self.access_date = nil
    elsif value.empty?
      self.access_any_time = false
      self.access_date = nil
    else
      assign_admission_date(value)
    end
  end

  # --- Provisions (meals / showers) -----------------------------------------
  # meals_granted / showers_granted are populated from live provisions by
  # BmidRelationshipLoader; the persisted meals/showers columns are the snapshot
  # that gets printed, written by load_provision_package on save.

  def meals_label
    meals_granted&.title || "No meals"
  end

  def no_meals?
    m = meals_granted
    m.nil? || !(m.pre || m.event || m.post)
  end

  # Snapshot the current provision package onto the printable meals/showers
  # columns, matching the Ember loadProvisions(pkg) behaviour at save time.
  def load_provision_package(package)
    self.meals = self.class.meals_enum_value(package.meals)
    self.showers = package.showers
    self.have_allocated_provisions = package.have_allocated
  end

  # Map a Provision::Package::Meals to the bmid.meals enum value (nil == none).
  def self.meals_enum_value(meals)
    periods = []
    periods << "pre" if meals.pre
    periods << "event" if meals.event
    periods << "post" if meals.post

    return nil if periods.empty?
    return "all" if periods.size == 3

    periods.join("+")
  end

  private

  # The access date as the two values that decide it, normalized so a Time from
  # the database and a Date from the form compare as the same day.
  def admission_pair
    [access_date&.to_date, access_any_time.present?]
  end

  # A badge no one called set_sap on holds no access date, which is exactly
  # what an untouched save must leave the person's documents holding: there is
  # no changeable pass for the loader to have found (find_sap_for_person_ids
  # already looks wider than the write-back reaches).
  def loaded_admission
    @loaded_admission ||= [nil, false]
  end

  # A refused date leaves access_date holding whatever was loaded, so the row
  # comes back showing the value that is really on file rather than the one
  # that could not be understood.
  def assign_admission_date(value)
    parsed = Date.iso8601(value)
    self.access_any_time = false
    self.access_date = parsed
  rescue Date::Error
    @admission_date_rejected = value
  end

  def admission_date_is_a_choice
    return if @admission_date_rejected.nil?

    errors.add(:admission_date, "The SAP date must be a date, \"any\", or left unspecified.")
  end

  def set_default_status
    self.status = IN_PREP if status.blank?
  end
end
