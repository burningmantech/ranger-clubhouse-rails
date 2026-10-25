# frozen_string_literal: true

# Filters the year's prospective applications on the VC applications index.
# Filter state lives in the URL so filtered views are shareable.
class Vc::ApplicationFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  # Pseudo status groups combining several statuses.
  GROUP_CALLSIGN = "_callsign"
  GROUP_HELD = "_held"
  GROUP_REJECTED = "_rejected"

  AGE_OPTIONS = [
    ALL_FILTER_OPTION,
    ["Is >= 18", "over-18"],
    ["Is < 18", "young"]
  ].freeze

  EXPERIENCE_OPTIONS = [
    ALL_FILTER_OPTION,
    ["Qualified", "qualified"],
    ["Unqualified", "unqualified"]
  ].freeze

  PRESETS = {
    "my-queue" => { label: "My Queue", icon: "user" },
    "needs-triage" => { label: "Needs Triage", icon: "inbox" },
    "awaiting-response" => { label: "Awaiting Response", icon: "hourglass-half" },
    "ready-for-callsign" => { label: "Ready for Callsign", icon: "id-badge" }
  }.freeze

  attribute :status, :string, default: ProspectiveApplication::STATUS_PENDING
  attribute :assigned_to, :string, default: "all"
  attribute :age, :string, default: "all"
  attribute :experience, :string, default: "all"
  attribute :name, :string, default: "all"

  def self.from_params(params, user_id:)
    # Anything but a hash under the scope -- ?filter=x, ?filter[]=x -- is ignored.
    values = params[PARAM_SCOPE].respond_to?(:to_unsafe_h) ? params[PARAM_SCOPE].to_unsafe_h : {}
    preset = params[:preset].presence
    form = new(values.slice("status", "assigned_to", "age", "experience", "name"))
    form.apply_preset(preset, user_id:) if preset
    form
  end

  def apply_preset(preset, user_id:)
    case preset
    when "my-queue"
      self.status = ProspectiveApplication::STATUS_PENDING
      self.assigned_to = user_id.to_s
    when "needs-triage"
      self.status = ProspectiveApplication::STATUS_PENDING
      self.assigned_to = "unassigned"
    when "awaiting-response"
      self.status = GROUP_HELD
      self.assigned_to = user_id.to_s
    when "ready-for-callsign"
      self.status = ProspectiveApplication::STATUS_PENDING
      self.assigned_to = "all"
      self.experience = "qualified"
    end
  end

  # Filter + staleness-sort the year's applications.
  def apply(applications)
    apps = filter_by_status(applications)

    case assigned_to
    when "all" then nil
    when "unassigned" then apps = apps.select { |a| a.assigned_person_id.blank? }
    else
      person_id = assigned_to.to_i
      apps = apps.select { |a| a.assigned_person_id == person_id }
    end

    case age
    when "over-18" then apps = apps.select(&:is_over_18)
    when "young" then apps = apps.reject(&:is_over_18)
    end

    case experience
    when "qualified" then apps = apps.select(&:brc_experience_okay?)
    when "unqualified" then apps = apps.reject(&:brc_experience_okay?)
    end

    apps = apps.select { |a| last_name_letter(a) == name } if name != "all"

    # Staleness sort: oldest-updated first, never-updated first of all.
    apps.sort_by { |a| [a.updated_by_person_at ? 1 : 0, a.updated_by_person_at || Time.zone.at(0)] }
  end

  def status_options
    [
      ALL_FILTER_OPTION,
      ["Dashboard Groups", [
        ["Callsign Processing", GROUP_CALLSIGN],
        ["On Hold", GROUP_HELD],
        ["Rejected", GROUP_REJECTED]
      ]],
      *ProspectiveApplication::STATUS_OPTIONS
    ]
  end

  def assigned_to_options(vcs)
    [
      ALL_FILTER_OPTION,
      ["Unassigned", "unassigned"],
      ["Volunteer Coords.", vcs.map { |vc| [vc[:callsign], vc[:id].to_s] }]
    ]
  end

  def name_options(applications)
    letters = applications.map { |a| last_name_letter(a) }.compact.uniq.sort
    [ALL_FILTER_OPTION, *letters]
  end

  # Human description of the active filters, e.g.
  # "awaiting review AND assigned to Firecracker AND < 18 yrs"
  def description(vcs)
    [
      status_description,
      assigned_to_description(vcs),
      name == "all" ? nil : "w/last name starting with #{name}",
      { "qualified" => "event qualified", "unqualified" => "event NOT qualified" }[experience],
      { "over-18" => ">= 18 yrs", "young" => "< 18 yrs" }[age]
    ].compact_blank.join(" AND ")
  end

  def active_preset(user_id:)
    PRESETS.keys.find do |preset|
      self.class.new.tap { |f| f.apply_preset(preset, user_id:) }.filter_values == filter_values
    end
  end

  def filter_values
    { "status" => status, "assigned_to" => assigned_to, "age" => age, "experience" => experience, "name" => name }
  end

  def query_params
    defaults = self.class.new.filter_values
    values = filter_values.reject { |key, value| defaults[key] == value }
    values.empty? ? {} : { PARAM_SCOPE => values }
  end

  def default?
    query_params.empty?
  end

  def persisted?
    false
  end

  private

  def filter_by_status(applications)
    case status
    when "all"
      applications
    when GROUP_CALLSIGN
      applications.select(&:processing_callsign?)
    when GROUP_HELD
      applications.select { |a| a.held_status? && !a.status_more_handles? }
    when GROUP_REJECTED
      applications.select(&:stop_status?)
    else
      applications.select { |a| a.status == status }
    end
  end

  def status_description
    case status
    when "all" then "all statuses"
    when GROUP_HELD then "on hold"
    when GROUP_REJECTED then "rejected"
    when GROUP_CALLSIGN then "callsign processing"
    else
      ProspectiveApplication::STATUS_LABELS[status]&.downcase || "unknown status #{status}"
    end
  end

  def assigned_to_description(vcs)
    case assigned_to
    when "all" then ""
    when "unassigned" then "unassigned"
    else
      callsign = vcs.find { |vc| vc[:id] == assigned_to.to_i }&.dig(:callsign) || "Unknown"
      "assigned to #{callsign}"
    end
  end

  def last_name_letter(application)
    application.last_name.to_s.chars.first&.unicode_normalize(:nfc)&.upcase
  end
end
