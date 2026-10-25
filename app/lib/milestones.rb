# frozen_string_literal: true

class Milestones
  attr_accessor :alpha_shift,
                :alpha_shift_prep_link,
                :alpha_shift_publish_date,
                :alpha_shifts_available,
                :art_trainings,
                :asset_authorized,
                :behavioral_agreement,
                :bmid_qualified,
                :burn_weekend_available,
                :burn_weekend_signup,
                :cheetah_cub_shift,
                :contacts,
                :did_work,
                :dirt_shifts_available,
                :has_reviewed_pi,
                :ignore_mvr,
                :ignore_pvr,
                :is_binary,
                :is_cheetah_cub,
                :is_trainer,
                :links,
                :missing_bpguid,
                :motorpool_agreement_available,
                :motorpool_agreement_signed,
                :mvr_eligible,
                :mvr_potential,
                :nda_required,
                :needs_full_training,
                :online_course_enabled,
                :online_course_url,
                :online_course_passed,
                :org_vehicle_insurance,
                :period,
                :photo,
                :pvr_eligible,
                :pvr_potential,
                :radio_checkout_agreement_enabled,
                :sandman_affidavit_signed,
                :sandman_affidavit_required,
                :shift_signups,
                :surveys,
                :ticketing_package,
                :ticketing_period,
                :timesheet_confirmed,
                :timesheets_unverified,
                :training,
                :trainings_available,
                :ts_mentor_survey_url,
                :ts_mentor_worked,
                :vehicle_requests

  def initialize(attributes = {})
    attributes.each do |key, value|
      send("#{key}=", value) if respond_to?("#{key}=")
    end
  end

  def self.build_for_person(person)
    status = person.status
    person_id = person.id

    now = Current.time
    year = Current.year

    event = PersonEvent.first_or_new_for_person_year(person_id, year)
    period = EventDate.calculate_period
    full_training, is_binary = Training.requires_training_full_day?(person)

    is_echelon = person.is_echelon?

    milestones = new
    milestones.online_course_enabled = Setting.get_value(Setting::ONLINE_COURSE_ENABLED)
    milestones.online_course_passed = PersonOnlineCourse.did_complete_for_year?(person_id, year, Position::TRAINING)
    milestones.online_course_url = Setting.get_value(Setting::ONLINE_COURSE_SITE_URL)

    milestones.trainings_available = Slot.have_active_for_position(Position::TRAINING, year: year)
    milestones.needs_full_training = full_training

    milestones.behavioral_agreement = person.behavioral_agreement

    milestones.has_reviewed_pi = event.pii_finished_at&.year == year

    milestones.asset_authorized = event.asset_authorized
    milestones.radio_checkout_agreement_enabled = Setting.get_value(Setting::RADIO_CHECKOUT_AGREEMENT_ENABLED)

    milestones.surveys = Survey.retrieve_unanswered_for_person_year(person_id, year, status)
    milestones.period = period
    milestones.photo = PersonPhoto.retrieve_info(person)

    milestones.missing_bpguid = true if person.missing_bpguid?

    trainings = PersonPosition.find_training_positions(person_id, true)
    art_trainings = []
    trainings.each do |training|
      education = Training.retrieve_education(person_id, training, year)
      if training.id == Position::TRAINING
        milestones.training = education
      else
        art_trainings << education
      end
    end

    milestones.training ||= Training::EducationInfo.new(status: Training::NO_SHIFT)

    art_trainings.sort_by! { |a| a.position_title.downcase }

    milestones.art_trainings = art_trainings

    case status
    when Person::ALPHA, Person::PROSPECTIVE
      milestones.alpha_shift_prep_link = Setting.get_value(Setting::ONBOARD_ALPHA_SHIFT_PREP_LINK)
      milestones.alpha_shifts_available = have_alpha_shifts = Slot.have_active_for_position(Position::ALPHA, year: year)
      milestones.alpha_shift_publish_date = Date.parse("second Wednesday of July").strftime("%Y-%m-%d")
      if have_alpha_shifts
        alpha_shift = Scheduling::Query.find_enrolled_slots(person_id, year, Position::ALPHA).last
        if alpha_shift
          milestones.alpha_shift = {
            slot_id: alpha_shift.id,
            begins: alpha_shift.slot.begins,
            status: (alpha_shift.slot.begins.advance(hours: 24) <= now) ? Training::NO_SHOW : Training::PENDING
          }
        end
      end

    when Person::ACTIVE
      if is_binary
        milestones.is_binary = true
      end

    when Person::INACTIVE_EXTENSION, Person::RETIRED, Person::RESIGNED
      milestones.is_cheetah_cub = true
      cheetah = Scheduling::Query.find_enrolled_slots(person_id, year, Position::CHEETAH_CUB).last
      if cheetah
        milestones.cheetah_cub_shift = {
          slot_id: cheetah.id,
          begins: cheetah.begins
        }
      end
    end

    if Person::ACTIVE_STATUSES.include?(status)
      links_tag = Document::DASHBOARD_LINKS_RANGER_TAG
      contact_tag = Document::CONTACTS_RANGER_TAG
    else
      links_tag = Document::DASHBOARD_LINKS_PNV_TAG
      contact_tag = Document::CONTACTS_PNV_TAG
    end

    milestones.links = Document.contents_by_tag(links_tag)
    milestones.contacts = Document.contents_by_tag(contact_tag)

    milestones.motorpool_agreement_available = Setting.get_value(Setting::MOTOR_POOL_PROTOCOL_ENABLED)
    milestones.motorpool_agreement_signed = event.signed_motorpool_agreement

    unless Person::ACTIVE_STATUSES.include?(status) || is_echelon
      return milestones
    end

    if period == "event" && Timesheet.did_work_position_in_year?(person_id, Position::TROUBLESHOOTER_MENTOR, year)
      milestones.ts_mentor_worked = true
      milestones.ts_mentor_survey_url = Setting.get_value(Setting::TROUBLESHOOTER_MENTOR_SURVEY_URL)
    end

    # Starting late 2022 - All (effective) login management roles require annual NDA signature.
    # MOAR PAPERWERKS! MOAR WINZ!
    # Don't require the NDA if the agreement does not exist.
    if person.has_raw_role?(Role::EVENT_MANAGEMENT) && !event.signed_nda && Document.have_tag?(Document::DEPT_NDA_TAG)
      milestones.nda_required = true
    end

    unless is_echelon
      # note, some inactives are active trainers yet do not work on playa.
      milestones.is_trainer = PersonPosition.have_position?(person_id, Position::TRAINERS[Position::TRAINING])
    end

    ticketing_period = Setting.get_value(Setting::TICKETING_PERIOD)
    milestones.ticketing_period = ticketing_period
    if ticketing_period == "open" || ticketing_period == "closed"
      milestones.ticketing_package = TicketAndProvisionsPackage.new(person_id)
    end

    # Timesheets!
    if Setting.get_value(Setting::TIMESHEET_CORRECTION_ENABLE) || person.has_role?(Role::SHIFT_MANAGEMENT_SELF)
      did_work = milestones.did_work = Timesheet.did_person_work?(person_id, year)

      if did_work
        milestones.timesheets_unverified = Timesheet.count_unverified_for_person_year(person_id, year)
        milestones.timesheet_confirmed = event.timesheet_confirmed
      end
    end

    if period == EventDate::AFTER_EVENT
      return milestones
    end

    unless is_echelon
      milestones.dirt_shifts_available = Scheduling::Query.dirt_shifts_available?
    end

    milestones.shift_signups = Scheduling::Summaries.summarize_shift_signups(person)
    # Person is *not* signed up - figure out if weekend shirts are available
    milestones.burn_weekend_available = BurnWeekendShiftRecommendation.available_burn_weekend_shifts_for_person?(person)
    # Burn weekend!
    milestones.burn_weekend_signup = Scheduling::Query.burn_weekend_signup?(person)

    milestones.org_vehicle_insurance = event.org_vehicle_insurance

    milestones.ignore_pvr = event.ignore_pvr
    if VehicleEligibility.is_pvr_eligible?(person_id, event, year)
      milestones.pvr_eligible = true
      milestones.vehicle_requests = Vehicle.retrieve_all_for_person_year(person_id, year)
    end

    # Person might not be eligible until an PVR eligible position is signed up for.
    milestones.pvr_potential = Position.vehicle_potential?("pvr", person_id)
    milestones.ignore_mvr = event.ignore_mvr
    milestones.mvr_eligible = VehicleEligibility.is_mvr_eligible?(person_id, event, year)
    # Person might not be eligible until an MVR eligible position is signed up for.
    milestones.mvr_potential = Position.vehicle_potential?("mvr", person_id)

    if !is_echelon && PersonPosition.have_position?(person_id, Position::SANDMAN)
      if event.sandman_affidavit
        milestones.sandman_affidavit_signed = true
      elsif TraineeStatus.did_person_pass_for_year?(person_id, Position::SANDMAN_TRAINING, year) || TrainerStatus.taught?(person_id, Position::SANDMAN_TRAINING, year)
        # Sandpeople! Put the affidavit in your walk, head-to-toe let your whole body talk.
        milestones.sandman_affidavit_required = true
      end
    end

    # BMID inspection
    have_signup = Slot.joins(:person_slot)
                      .where("slot.begins_year": year)
                      .where("slot.position_id": [Position::TRAINING, Position::TRAINER, Position::TRAINER_ASSOCIATE, Position::TRAINER_UBER])
                      .where("slot.active": true)
                      .where("person_slot.person_id": person_id)
                      .exists?

    have_ticket = AccessDocument.where(person_id: person_id)
                                .where(type: [AccessDocument::SPT, AccessDocument::STAFF_CREDENTIAL, AccessDocument::SAP])
                                .where(status: [AccessDocument::CLAIMED, AccessDocument::SUBMITTED])
                                .exists?

    have_bmid = Bmid.where(year: year)
                    .where(person_id: person_id)
                    .where(status: [Bmid::IN_PREP, Bmid::READY_TO_PRINT, Bmid::SUBMITTED])
                    .exists?

    milestones.bmid_qualified = (have_signup || have_ticket || have_bmid)

    milestones
  end
end
