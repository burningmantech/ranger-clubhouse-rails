# frozen_string_literal: true

module VehicleEligibility
  include BasicCacheHelper

  CACHE_PREFIX = "person-vehicle-"

  def self.is_person_eligible?(person_id, year, person_event = nil)
    key = cache_key(person_id, year)
    return cache_read(key) if cache_exist?(key)

    person_event ||= PersonEvent.first_or_new_for_person_year(person_id, year)
    eligible = is_mvr_eligible?(person_id, person_event, year) || is_pvr_eligible?(person_id, person_event, year)
    cache_write(key, eligible)
    eligible
  end

  # Eligibility depends on the year (signups, person_event are per-year), so the cache
  # must be keyed per-year too — otherwise one year's result poisons another's.
  def self.cache_key(person_id, year)
    "#{CACHE_PREFIX}#{person_id}-#{year}"
  end

  def self.purge_cache(person_id, year)
    cache_delete(cache_key(person_id, year))
  end

  # Is the person MVR eligible?
  #
  # @param [Integer] person_id
  # @param [PersonEvent, nil] person_event
  # @param [Integer] year
  # @return [Boolean]

  def self.is_mvr_eligible?(person_id, person_event, year)
    return true if person_event&.mvr_eligible

    PersonTeam.have_mvr_eligible_for_person(person_id) || PersonSlot.mvr_eligible_signups?(person_id, year)
  end

  # Is the person Personal Vehicle eligible?
  #
  # @param person_id [Integer]
  # @param event [PersonEvent, nil]
  # @param year [Integer]
  # @return [Boolean]
  def self.is_pvr_eligible?(person_id, event, year)
    return true if event&.may_request_stickers

    PersonTeam.have_pvr_eligible_team(person_id) || PersonSlot.pvr_eligible_signups?(person_id, year)
  end

  # Return the MVR submission deadline, and has it past?
  #
  # MVRDeadline is an admin-entered MM-DD string with no default, so it can be
  # blank or malformed. That used to raise ArgumentError out of Time.zone.parse
  # and take down every MVR-position signup and the vehicle dashboard with it.
  # An unset deadline now reads as "none configured" — nil, and NOT past, since
  # a deadline no one has set cannot have been missed. Callers already expect a
  # nil deadline (VehicleDashboard#days_until_mvr_deadline, full_datetime_format).
  #
  # @return [Array<ActiveSupport::TimeWithZone, Boolean>]

  def self.retrieve_mvr_deadline
    setting = Setting.get_value(Setting::MVR_DEADLINE)
    deadline = Time.zone.parse("#{Current.year}-#{setting} 23:59:59") if setting.present?
    return [nil, false] if deadline.nil?

    [deadline, Current.time > deadline]
  rescue ArgumentError
    [nil, false]
  end
end
