# frozen_string_literal: true

class ActionLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  EVENT_FILTER_OPTIONS = [
    ["Agreement Signatures", "agreement-signature"],
    ["Alert Changes", "alert-create,alert-update,alert-delete"],
    ["BMID Changes", "bmid-%"],
    ["Client Routing", "client-route"],
    ["Login Failures", "auth-failed"],
    ["Email Bounces/Complaints", "email-%"],
    ["Event Date Changes", "event-dates-%"],
    ["Logins", "auth-login"],
    ["Password Resets", "auth-password-%"],
    ["Person Creation", "person-create"],
    ["Person Update", "person-update"],
    ["Position Changes", "position-create,position-update,position-delete"],
    ["Position Lineup Updates", "position-lineup-%"],
    ["Position Role Updates", "position-role-%"],
    ["Position Manual Grant/Revokes", "person-position-%"],
    ["Role Manual Grant/Revokes", "person-role-%"],
    ["Schedule Updates", "person-slot-%"],
    ["Setting Changes", "setting-%"],
    ["Slot Changes", "slot-%"],
    ["Team Updates", "team-create,team-update,team-destroy"],
    ["Team Role Updates", "team-role-%"],
    ["Team Grant/Revokes", "person-team-%"],
    ["Ticketing/Provision Changes", "access-document-%"]
  ].freeze

  attribute :person_callsign, :string
  attribute :target_person_callsign, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :event_name, :string
  attribute :message, :string
  attribute :page, :integer, default: 1

  attr_reader :event_filters

  def initialize(attributes = {})
    super(attributes)
    self.event_filters = attributes&.[](:event_filters) || attributes&.[]("event_filters")
    self.page = 1 if page.blank? || page.to_i <= 0
  end

  def event_filters=(values)
    @event_filters = Array(values).flatten.filter_map do |value|
      cleaned = value.to_s.strip
      cleaned.presence
    end.uniq
  end

  def persisted?
    false
  end

  def events
    (event_filters.flat_map { |value| value.split(",") } + [event_name.to_s])
      .filter_map do |value|
      cleaned = value.to_s.strip
      cleaned.presence
    end
      .uniq
  end

  def parsed_start_time
    parse_time(start_time)
  end

  def parsed_end_time
    parse_time(end_time)
  end

  def query_params(page: nil)
    values = {
      person_callsign: person_callsign.presence,
      target_person_callsign: target_person_callsign.presence,
      start_time: start_time.presence,
      end_time: end_time.presence,
      event_name: event_name.presence,
      message: message.presence
    }.compact
    values[:event_filters] = event_filters if event_filters.any?
    values[:page] = page if page.present? && page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end

  private

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end
end
