# frozen_string_literal: true

# Ticket and Provisions Package class
# Builds up ticketing and provisions packages for a person
class TicketAndProvisionsPackage
  attr_reader :access_documents,
              :tickets,
              :gift_items,
              :lsd_items,
              :credits_earned,
              :year_earned,
              :period,
              :started_at,
              :finished_at,
              :visited_at,
              :provision_records,
              :provisions,
              :provisions_bankable,
              :provisions_banked

  # Initialize the package for a person
  #
  # @param person_id [Integer] The ID of the person
  def initialize(person_id)
    @year_earned = Current.year - 1
    person_event = PersonEvent.first_or_new_for_person_year(person_id, Current.year)

    @access_documents = []
    @gift_items = []
    @lsd_items = []
    @tickets = []

    AccessDocument.find_for_query(person_id: person_id).each do |ad|
      case ad.type
      when AccessDocument::GIFT
        @gift_items << ad if ad.available?
      when AccessDocument::LSD, AccessDocument::VEHICLE_PASS_LSD
        @lsd_items << ad if ad.available?
      else
        if ad.type == AccessDocument::STAFF_CREDENTIAL || ad.type == AccessDocument::SPT
          @tickets << ad
        end
        @access_documents << ad
      end
    end

    @credits_earned = Timesheet.earned_credits_for_year(person_id, @year_earned)
    @period = Setting.get_value(Setting::TICKETING_PERIOD)
    @started_at = person_event.ticketing_started_at
    @finished_at = person_event.ticketing_finished_at
    @visited_at = person_event.ticketing_last_visited_at

    build_provisions(person_id)
  end

  private

  # Build up the provisions package.
  # - Combine all provisions types to a single effective type
  # - Indicate if the provisions can be banked, i.e., no allocated provisions present
  # - Provide an expiry date on earned (non-allocated) types. Assume only one earned
  #   type will be present (no earned double meals, showers, etc.)
  #
  # @param person_id [Integer] The ID of the person
  # @return [void]
  def build_provisions(person_id)
    @provision_records = Provision.retrieve_usable_for_person_ids([person_id])

    have_banked = false
    meals_expire = nil
    showers_expire = nil
    radio_expires = nil

    package = Provision.build_package(@provision_records)
    have_allocated = package.have_allocated

    @provision_records.each do |provision|
      have_banked = true if provision.status == Provision::BANKED

      case provision.type
      when Provision::MEALS
        meals_expire = provision.expires_on
      when Provision::EVENT_RADIO
        radio_expires = provision.expires_on unless have_allocated
      when Provision::WET_SPOT
        showers_expire = provision.expires_on unless have_allocated
      end
    end

    return unless package.have_meals || package.showers || package.radios.positive?

    @provisions = package

    unless have_allocated
      @provisions.meals_expire = meals_expire
      @provisions.showers_expire = showers_expire
      @provisions.radio_expire = radio_expires
    end

    @provisions_bankable = !have_allocated
    @provisions_banked = have_banked
  end
end
