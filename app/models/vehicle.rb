class Vehicle < ApplicationRecord
  self.table_name = "vehicle"
  self.inheritance_column = :none

  # Request status
  PENDING = "pending"
  APPROVED = "approved"
  REJECTED = "rejected"

  # Driving stickers
  DRIVING_STICKER_NONE = "none"
  DRIVING_STICKER_PREPOST = "prepost"
  DRIVING_STICKER_STAFF = "staff"

  # Fuel chit
  FUEL_CHIT_EVENT = "event"
  FUEL_CHIT_SINGLE_USE = "single-use"
  FUEL_CHIT_NONE = "none"

  # Ranger logo decals
  LOGO_PERMANENT_NEW = "permanent-new"
  LOGO_PERMANENT_EXISTING = "permanent-existing"
  LOGO_EVENT = "event"
  LOGO_NONE = "none"

  # Amber lights
  AMBER_LIGHT_NONE = "none"
  AMBER_LIGHT_DEPARTMENT = "department"
  AMBER_LIGHT_ALREADY_HAS = "already-has"

  # Vehicle type
  FLEET = "fleet"
  PERSONAL = "personal"

  # Fleet vehicles carry no owner. The conditional presence validation below is
  # the real rule; without optional: true Rails' automatic presence-of-association
  # check rejects every fleet record before that rule can apply.
  belongs_to :person, optional: true

  # Virtual attributes
  attr_accessor :callsign

  # Attributes from joins/calculation
  attribute :org_vehicle_insurance, :boolean, default: false
  attribute :signed_motorpool_agreement, :boolean, default: false

  # The earliest event year the app will browse (ApplicationController.year_floor's
  # default). A record outside this span cannot be reached from any page, so
  # saving one is silent data loss rather than a stored future.
  EVENT_YEAR_FLOOR = 1996

  # Validations
  validates :type, presence: true
  # No person_id presence rule: validate_callsign_if_present already errors on
  # every ownerless personal vehicle, and it names :callsign -- the field the
  # forms actually show. A second rule here only adds "can't be blank" for an
  # attribute no one can act on.
  validates :team_assignment, presence: true, if: -> { type == FLEET }
  validates :event_year, presence: true,
                         numericality: { only_integer: true,
                                         greater_than_or_equal_to: EVENT_YEAR_FLOOR,
                                         less_than_or_equal_to: ->(_record) { Current.year } }
  validates :vehicle_color, presence: true
  validates :vehicle_make, presence: true
  validates :vehicle_model, presence: true

  # Custom validations to match Laravel logic
  validate :check_license_uniqueness, if: -> { license_number.present? && (new_record? || license_number_changed? || license_state_changed? || event_year_changed?) }
  validate :check_rental_uniqueness, if: -> { rental_number.present? && (new_record? || rental_number_changed? || event_year_changed?) }

  # Callbacks
  # normalize_fields runs first so that `type` is defaulted before the callsign
  # resolution reads it.
  before_validation :normalize_fields
  before_validation :validate_callsign_if_present
  before_save :approve_fleet_vehicle

  # Scopes
  scope :for_year, ->(year) { where(event_year: year) }
  scope :pending, -> { where(status: PENDING) }
  scope :personal, -> { where(type: PERSONAL) }
  scope :fleet, -> { where(type: FLEET) }

  CLASS_OPTIONS = {
    "Autos" => [
      "Car",
      "Pickup Truck",
      "SUV",
      "Sedan",
      "Tow Truck",
      "Van",
      "Other"
    ],
    "Golf Carts" => [
      "Golf Cart 2-Seater",
      "Golf Cart 4-Seater",
      "Golf Cart 6-Seater"
    ],
    "UTVs" => [
      "UTV 2-Seater",
      "UTV 4-Seater",
      "UTV 6-Seater"
    ]
  }.freeze

  DRIVING_STICKER_OPTIONS = [
    ["None", Vehicle::DRIVING_STICKER_NONE],
    ["Pre-Event / Post-Event", Vehicle::DRIVING_STICKER_PREPOST],
    ["Staff", Vehicle::DRIVING_STICKER_STAFF]
  ].freeze

  RANGER_LOGO_OPTIONS = [
    ["None", Vehicle::LOGO_NONE],
    ["Event", Vehicle::LOGO_EVENT],
    ["Permanent New", Vehicle::LOGO_PERMANENT_NEW],
    ["Permanent Existing", Vehicle::LOGO_PERMANENT_EXISTING]
  ].freeze

  FUEL_CHIT_OPTIONS = [
    ["None", Vehicle::FUEL_CHIT_NONE],
    ["Single Use", Vehicle::FUEL_CHIT_SINGLE_USE],
    ["Event", Vehicle::FUEL_CHIT_EVENT]
  ].freeze

  AMBER_LIGHT_OPTIONS = [
    ["None", Vehicle::AMBER_LIGHT_NONE],
    ["Department", Vehicle::AMBER_LIGHT_DEPARTMENT],
    ["Already Has", Vehicle::AMBER_LIGHT_ALREADY_HAS]
  ].freeze

  def self.find_for_query(query)
    person_id = query[:person_id]
    event_year = query[:event_year]
    license = query[:license_number]
    sticker = query[:sticker_number]
    status = query[:status]
    number = query[:number]

    scope = self.select("vehicle.*",
                        "COALESCE(person_event.org_vehicle_insurance, FALSE) AS org_vehicle_insurance",
                        "COALESCE(person_event.signed_motorpool_agreement, FALSE) AS signed_motorpool_agreement")
                .joins("LEFT JOIN person_event ON person_event.year = vehicle.event_year AND person_event.person_id = vehicle.person_id")
                .order(:event_year)
                .includes(:person)

    scope = scope.where(person_id:) if person_id.present?
    scope = scope.where(event_year:) if event_year.present?
    scope = scope.where(status:) if status.present?

    if license.present?
      normalized_license = license.gsub(/[\s\-]/, "")
      scope = scope.where_like("vehicle.license_number", "%#{normalized_license}%")
    end

    if sticker.present?
      scope = scope.where_like("vehicle.sticker_number", "%#{sticker}%")
    end

    if number.present?
      normalized_number = number.gsub(/[\s\-]/, "")
      scope = scope.where("vehicle.license_number LIKE ? OR vehicle.sticker_number LIKE ? OR vehicle.rental_number LIKE ?",
                          "%#{normalized_number}%", "%#{number}%", "%#{number}%")
    end

    scope.load
  end

  def self.find_for_person_year(id, person_id, event_year)
    where(id:, person_id:, event_year: event_year).first
  end

  def self.retrieve_all_for_person_year(person_id, year)
    self.select("vehicle.*",
                "COALESCE(person_event.org_vehicle_insurance, FALSE) AS org_vehicle_insurance",
                "COALESCE(person_event.signed_motorpool_agreement, FALSE) AS signed_motorpool_agreement")
        .joins("LEFT JOIN person_event ON person_event.year = vehicle.event_year AND person_event.person_id = vehicle.person_id")
        .where(person_id: person_id, event_year: year)
        .order(:license_number)
        .load
  end

  # Personal vehicle requests waiting for a reviewer this year, by callsign.
  # A request whose owner account is gone is skipped: there is no one to tell a
  # reviewer about, and it has no callsign to sort by.
  def self.find_all_pending
    requests = self.pending.personal.where(event_year: Current.year).includes(:person)
    owned, orphaned = requests.partition(&:person)

    orphaned.each do |vehicle|
      Rails.logger.warn("Vehicle #{vehicle.id} is waiting for review but its owner account is gone")
    end

    owned.sort_by { |vehicle| vehicle.person.callsign }
  end

  def load_relationships
    pv = PersonEvent.find_for_person_year(person_id, event_year)
    if pv
      self.signed_motorpool_agreement = pv.signed_motorpool_agreement
      self.org_vehicle_insurance = pv.org_vehicle_insurance
    else
      self.signed_motorpool_agreement = false
      self.org_vehicle_insurance = false
    end
  end

  def driving_sticker_label
    DRIVING_STICKER_OPTIONS.find { |l, v| v == driving_sticker }&.first || "None"
  end

  def ranger_logo_label
    RANGER_LOGO_OPTIONS.find { |l, v| v == ranger_logo }&.first || "None"
  end

  def fuel_chit_label
    FUEL_CHIT_OPTIONS.find { |l, v| v == fuel_chit }&.first || "None"
  end

  def amber_light_label
    AMBER_LIGHT_OPTIONS.find { |l, v| v == amber_light }&.first || "None"
  end

  private

  def normalize_fields
    self.license_number = license_number.gsub(/[\s\-]/, "") if license_number.present?
    self.notes ||= ""
    self.vehicle_class ||= ""
    self.rental_number ||= ""
    self.vehicle_year ||= ""
    self.team_assignment ||= ""
    self.driving_sticker ||= ""
    self.request_comment ||= ""
    self.response ||= ""

    self.amber_light ||= AMBER_LIGHT_NONE
    self.driving_sticker ||= DRIVING_STICKER_NONE
    self.fuel_chit ||= FUEL_CHIT_NONE
    self.ranger_logo ||= LOGO_NONE
    self.status ||= PENDING
    self.type ||= PERSONAL
  end

  def approve_fleet_vehicle
    if type == FLEET
      self.status = APPROVED
    end
  end

  def check_license_uniqueness
    scope = Vehicle.where(license_state: license_state, license_number: license_number, event_year: event_year)
    scope = scope.where.not(id: id) if persisted?

    if scope.exists?
      errors.add(:license_number, "Another vehicle already exists with the same license plate.")
    end
  end

  def check_rental_uniqueness
    scope = Vehicle.where(rental_number: rental_number, event_year: event_year)
    scope = scope.where.not(id: id) if persisted?

    if scope.exists?
      errors.add(:rental_number, "Another vehicle already exists with the same rental number.")
    end
  end

  def validate_callsign_if_present
    # A fleet vehicle belongs to a team, never to a person. Dropping the owner
    # here keeps `type` and `person_id` from disagreeing -- the roster names the
    # owner from `type` but reads the Setup Access Pass and personal-vehicle
    # eligibility from `person_id`, so a fleet row holding a stale person_id
    # reports that person's pass under the team's name.
    if type == FLEET
      self.person_id = nil
      return
    end

    if callsign.present?
      found_person_id = Person.find_id_by_callsign(callsign)
      if found_person_id
        self.person_id = found_person_id
      else
        errors.add(:callsign, "Callsign not found.")
      end
    elsif person_id.blank?
      errors.add(:callsign, "Missing callsign.")
    end
  end
end
