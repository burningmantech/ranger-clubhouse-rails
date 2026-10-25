# frozen_string_literal: true

# Bulk-loads virtual attributes for a collection of BMID records.
# Enriches each BMID with: org_vehicle_insurance, SAP data, signups,
# tickets, provisions (meals/showers), and training sign-up status.
class BmidRelationshipLoader
  # @param bmids [Array<Bmid>]
  # @param person_ids [Array<Integer>]
  # @param year [Integer] the event year every flag is computed against -- pass
  #   the badges' own year, or a past-year listing silently reports this year's
  #   sign-ups, tickets, training, and vehicle insurance.
  def initialize(bmids, person_ids, year = Current.year)
    @bmids = bmids
    @person_ids = person_ids
    @year = year
  end

  def call
    attach_people
    load_org_vehicle_insurance
    load_saps
    load_signups
    load_tickets
    load_provisions
    load_training
  end

  private

  attr_reader :bmids, :person_ids, :year

  def attach_people
    people = Person.where(id: person_ids).index_by(&:id)

    bmids.each do |bmid|
      if bmid.association(:person).target.nil?
        bmid.person = people[bmid.person_id]
      end
    end

    # Filter out any deleted accounts (if person turned out nil)
    bmids.reject! { |b| b.person.nil? }
  end

  def load_org_vehicle_insurance
    person_events = PersonEvent.find_all_for_ids_year(person_ids, year).index_by(&:person_id)
    bmids.each do |bmid|
      event = person_events[bmid.person_id]
      bmid.org_vehicle_insurance = event&.org_vehicle_insurance || false
    end
  end

  def load_saps
    saps = AccessDocument.find_sap_for_person_ids(person_ids)
    bmids.each do |bmid|
      bmid.set_sap(saps[bmid.person_id]) if saps[bmid.person_id]
    end
  end

  def load_signups
    signup_person_ids = Person.joins(person_slot: :slot)
                              .where(id: person_ids)
                              .where(slot: { begins_year: year })
                              .distinct
                              .pluck(:id)
                              .to_set

    bmids.each do |bmid|
      bmid.has_signups = signup_person_ids.include?(bmid.person_id)
    end
  end

  def load_tickets
    ticket_person_ids = AccessDocument.where(person_id: person_ids)
                                      .where(type: [AccessDocument::SPT, AccessDocument::STAFF_CREDENTIAL, AccessDocument::SAP])
                                      .where(status: [AccessDocument::CLAIMED, AccessDocument::SUBMITTED])
                                      .distinct
                                      .pluck(:person_id)
                                      .to_set

    bmids.each do |bmid|
      bmid.has_ticket = ticket_person_ids.include?(bmid.person_id)
    end
  end

  def load_provisions
    provisions_by_person = Provision.retrieve_usable_for_person_ids(person_ids).group_by(&:person_id)

    bmids.each do |bmid|
      cookies = provisions_by_person[bmid.person_id] || []
      package = Provision.build_package(cookies)
      bmid.meals_granted = package.meals
      bmid.showers_granted = package.showers
      bmid.have_allocated_provisions = package.have_allocated
    end
  end

  def load_training
    training_slot_ids = Slot.where(begins_year: year)
                            .where(position_id: [Position::TRAINING, Position::TRAINER, Position::TRAINER_ASSOCIATE, Position::TRAINER_UBER])
                            .where(active: true)
                            .pluck(:id)

    training_person_ids = if training_slot_ids.any?
                            PersonSlot.where(person_id: person_ids, slot_id: training_slot_ids)
                                      .distinct
                                      .pluck(:person_id)
                                      .to_set
                          else
                            Set.new
                          end

    bmids.each do |bmid|
      bmid.training_signed_up = training_person_ids.include?(bmid.person_id)
    end
  end
end
