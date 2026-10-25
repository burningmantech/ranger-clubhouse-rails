# frozen_string_literal: true

class VehicleDashboard
  attr_reader :person, :year, :person_event

  def initialize(person, year)
    @person = person
    @year = year
    @person_event = PersonEvent.first_or_new_for_person_year(person.id, year)
  end

  def mvr_eligible?
    @mvr_eligible ||= VehicleEligibility.is_mvr_eligible?(person.id, person_event, year)
  end

  def mvr_potential?
    @mvr_potential ||= Position.vehicle_potential?("mvr", person.id)
  end

  def mvr_eligible_positions
    return [] unless !mvr_eligible? && mvr_potential?

    @mvr_eligible_positions ||= Position.vehicle_eligible_for_person("mvr", person.id)
  end

  def pvr_eligible?
    @pvr_eligible ||= VehicleEligibility.is_pvr_eligible?(person.id, person_event, year)
  end

  def pvr_potential?
    @pvr_potential ||= Position.vehicle_potential?("pvr", person.id)
  end

  def pvr_eligible_positions
    return [] unless !pvr_eligible? && pvr_potential?

    @pvr_eligible_positions ||= Position.vehicle_eligible_for_person("pvr", person.id)
  end

  def motorpool_agreement_signed?
    @motorpool_signed ||= Agreements.did_sign_document?(person, Document::MOTORPOOL_POLICY_TAG, person_event)
  end

  def personal_vehicle_agreement_signed?
    @pv_agreement_signed ||= Agreements.did_sign_document?(person, Document::PERSONAL_VEHICLE_AGREEMENT_TAG, person_event)
  end

  def mvr_approved?
    person_event.org_vehicle_insurance
  end

  def mvr_deadline_info
    @mvr_deadline_info ||= VehicleEligibility.retrieve_mvr_deadline
  end

  def mvr_deadline
    mvr_deadline_info[0]
  end

  def mvr_deadline_passed?
    mvr_deadline_info[1]
  end

  def vehicles
    @vehicles ||= Vehicle.find_for_query(person_id: person.id, event_year: year)
  end

  def any_eligible?
    mvr_eligible? || mvr_potential? || pvr_eligible? || pvr_potential?
  end

  # ADHD-friendly progress tracking
  def mvr_complete?
    mvr_approved? || !mvr_eligible?
  end

  def pvr_complete?
    return true unless pvr_eligible? || pvr_potential?

    personal_vehicle_agreement_signed? && vehicles.any?
  end

  def total_tasks
    count = 0
    count += 1 if mvr_eligible?
    count += 1 if pvr_eligible? || pvr_potential?
    count
  end

  def completed_tasks
    count = 0
    count += 1 if mvr_eligible? && mvr_approved?
    count += 1 if (pvr_eligible? || pvr_potential?) && personal_vehicle_agreement_signed?
    count
  end

  def pending_tasks
    total_tasks - completed_tasks
  end

  def days_until_mvr_deadline
    return nil if mvr_deadline.nil?

    (mvr_deadline.to_date - Time.current.to_date).to_i
  end

  def deadline_urgency
    days = days_until_mvr_deadline
    return :passed if days.nil? || days.negative?
    return :critical if days <= 7
    return :warning if days <= 30

    :normal
  end
end
