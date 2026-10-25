# frozen_string_literal: true

module PersonStatusManagement
  module_function

  def change(person:, old_status:, reason:, person_source_id: Current.person_id)
    new_status = person.status
    return if new_status == old_status

    person_id = person.id

    PersonStatus.record(person_id, old_status, new_status, reason, person_source_id)

    change_reason = "#{reason} new status #{new_status}"

    case new_status
    when Person::ACTIVE
      grant_active_defaults(person_id, change_reason)

      if [Person::ALPHA, Person::BONKED].include?(old_status)
        PersonPosition.add_ids_to_person(person_id, [Position::DIRT_SHINY_PENNY], change_reason)
      end
    when Person::ALPHA
      PersonPosition.add_ids_to_person(person_id, [Position::ALPHA], change_reason)
    when Person::UBERBONKED, Person::DECEASED, Person::DISMISSED, Person::RESIGNED
      PersonPosition.reset_positions(person_id, change_reason, Person::REMOVE_ALL)
      PersonRole.reset_roles(person_id, change_reason, Person::REMOVE_ALL)
      PersonTeam.remove_all_from_person(person_id, change_reason)
      Scheduling::Signup::Bulk.remove_future_sign_ups(person_id, "conversion to #{new_status}")
    when Person::BONKED
      PersonPosition.reset_positions(person_id, change_reason, Person::REMOVE_ALL)
      Scheduling::Signup::Bulk.remove_future_sign_ups(person_id, "conversion to bonked")
    when Person::RETIRED
      PersonTeam.remove_all_from_person(person_id, change_reason)
      PersonRole.reset_roles(person_id, change_reason, Person::ADD_NEW_USER)
      PersonPosition.reset_positions(person_id, change_reason, Person::ADD_NEW_USER)
    when Person::AUDITOR, Person::PROSPECTIVE
      unless old_status == Person::ECHELON && new_status == Person::PROSPECTIVE
        # Don't lose any positions or permission if the Echelon is trying to
        # become a Ranger
        PersonRole.reset_roles(person_id, change_reason, Person::ADD_NEW_USER)
        PersonPosition.reset_positions(person_id, change_reason, Person::ADD_NEW_USER)
      end
    when Person::PAST_PROSPECTIVE
      PersonRole.reset_roles(person_id, change_reason, Person::REMOVE_ALL)
      PersonPosition.reset_positions(person_id, change_reason, Person::REMOVE_ALL)
      PersonTeam.remove_all_from_person(person_id, change_reason)
      Scheduling::Signup::Bulk.remove_future_sign_ups(person_id, "conversion to past prospective")
    end

    if new_status == Person::DECEASED && person.callsign_approved? && !person.vintage?
      HandleReservation.record_deceased(person.callsign)
    end

    if old_status == Person::ALPHA
      PersonPosition.remove_ids_from_person(person_id, [Position::ALPHA], "#{reason} no longer alpha")
    end

    return unless Person::LOCKED_STATUSES.include?(new_status)

    event = PersonEvent.find_for_person_year(person_id, Current.year)
    return unless event

    event.asset_authorized = false
    event.save(validate: false)
  end

  def grant_active_defaults(person_id, reason)
    position_ids = Position.where(all_rangers: true).pluck(:id)
    PersonPosition.add_ids_to_person(person_id, position_ids, reason)

    role_ids = Role.where(new_user_eligible: true).pluck(:id)
    PersonRole.add_ids_to_person(person_id, role_ids, reason)
  end

  private_class_method :grant_active_defaults
end
