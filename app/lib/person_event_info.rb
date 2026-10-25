# frozen_string_literal: true

# PersonEventInfo aggregates event-related information for a person and year.
# Includes training status, radio eligibility, meals/showers, vehicles, and insurance.
class PersonEventInfo
  attr_accessor :event_period,
                :online_course_date,
                :is_binary,
                :may_request_stickers,
                :mvr_eligible,
                :online_course_passed,
                :org_vehicle_insurance,
                :radio_eligible,
                :radio_info_available,
                :showers,
                :signed_motorpool_agreement,
                :radio_max,
                :training,
                :art_trainings,
                :vehicles,
                :meals

  # Gather all information related to a given year for a person
  # - training status & location (if any)
  # - radio eligibility
  # - meals & shower privileges
  #
  # @param person [Person] person to lookup
  # @param year [Integer] event year
  # @return [PersonEventInfo]
  def self.find_for_person_year(person, year)
    person_id = person.id
    info = new

    # Find training positions
    require_training = PersonPosition.find_training_positions(person_id)

    if require_training.empty?
      require_training = [Position.find(Position::TRAINING)]
    end

    # Retrieve education status for each training position
    info.art_trainings = []
    require_training.each do |position|
      info.art_trainings << Training.retrieve_education(person_id, position, year)
    end

    # Sort trainings by position title (case-insensitive)
    info.art_trainings.sort_by! { |t| t.position_title.downcase }

    # Check if in-person training passed
    info.training = info.art_trainings.delete_at(info.art_trainings.find_index { |t| t.position_id == Position::TRAINING })

    # Radio eligibility
    info.radio_info_available = Setting.get_value(Setting::RADIO_INFO_AVAILABLE)
    if info.radio_info_available
      provisions = Provision.retrieve_usable_for_person_ids([person_id])
      package = Provision.build_package(provisions)
      if package.radios.positive?
        info.radio_eligible = true
        info.radio_max = package.radios
      end
    end

    # Meals and showers from BMID
    bmid = Bmid.find_for_person_manage(person_id, year)
    info.meals = bmid&.meals_granted
    info.showers = bmid&.showers_granted || false

    # Event period
    info.event_period = EventDate.retrieve_event_ops_period

    # Binary status (only for active statuses)
    info.is_binary = Person::ACTIVE_STATUSES.include?(person.status) ? Timesheet.person_binary?(person) : false

    # Online course status
    poc = PersonOnlineCourse.find_for_person_year(person_id, year, Position::TRAINING)
    if poc&.completed_at
      info.online_course_passed = true
      info.online_course_date = poc.completed_at
    else
      info.online_course_passed = false
    end

    # Vehicles
    info.vehicles = Vehicle.retrieve_all_for_person_year(person_id, year)

    # Person event info (insurance and motorpool agreement)
    event = PersonEvent.find_for_person_year(person_id, year)
    if event
      info.org_vehicle_insurance = event.org_vehicle_insurance
      info.signed_motorpool_agreement = event.signed_motorpool_agreement
    else
      info.org_vehicle_insurance = false
      info.signed_motorpool_agreement = false
    end

    # MVR and PVR eligibility (only for active statuses or echelon)
    if Person::ACTIVE_STATUSES.include?(person.status) || person.status == Person::ECHELON
      info.mvr_eligible = VehicleEligibility.is_mvr_eligible?(person.id, event, year)
      info.may_request_stickers = VehicleEligibility.is_pvr_eligible?(person_id, event, year)
    end

    info
  end

  private

  def initialize
    @event_period = nil
    @online_course_date = nil
    @is_binary = false
    @may_request_stickers = false
    @mvr_eligible = false
    @online_course_passed = false
    @org_vehicle_insurance = false
    @radio_eligible = false
    @radio_info_available = false
    @showers = false
    @signed_motorpool_agreement = false
    @radio_max = 0
    @training = nil
    @art_trainings = []
    @training_passed = false
    @vehicles = []
    @meals = nil
  end
end
