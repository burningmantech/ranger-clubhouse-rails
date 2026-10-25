# frozen_string_literal: true

module TeamsPositions::MembershipReportHelper
  # The filter tokens live here, with the labels, rather than on the controller:
  # a helper constant that names a controller constant is resolved at load time,
  # and a helper/controller pair naming each other that way deadlocks both
  # autoloads. The controller reads these inside methods, at request time.
  MANAGERS_MISSING = "missing"
  MANAGERS_PRESENT = "present"

  MANAGER_LABELS = {
    MANAGERS_MISSING => "No managers assigned",
    MANAGERS_PRESENT => "Has managers"
  }.freeze

  SORT_TITLE = "title"
  SORT_MEMBERS = "members"
  SORT_MANAGERS = "managers"

  SORT_LABELS = {
    SORT_TITLE => "Team name",
    SORT_MEMBERS => "Most members",
    SORT_MANAGERS => "Fewest managers"
  }.freeze

  FILTER_CHIP_LABELS = {
    type: "Type",
    managers: "Managers",
    sort: "Sorted by",
    title: "Name contains"
  }.freeze

  # Type labels come from TeamManagement, beside the validator's list of allowed
  # types, rather than a second copy here -- a copy could only drift from the
  # page that edits them. Every key is labelled by construction, so this reads
  # the hash directly where a view labelling a stored type goes through
  # team_record_type_label for its unknown-type fallback.
  def membership_report_type_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      TeamManagement::TYPE_LABELS.map { |type, label| [label.pluralize, type] }
  end

  def membership_report_manager_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + MANAGER_LABELS.invert.to_a
  end

  # No "All" entry: every list is sorted somehow, and the default is by name.
  def membership_report_sort_options
    SORT_LABELS.invert.to_a
  end

  def membership_report_filter_chips(filter_params)
    active = UiComponents::FilterBarHelper.active_filters(filter_params)

    filter_chips(active, FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { membership_report_filter_value_label(key, value) }) do |remaining, _key|
      teams_positions_membership_report_path(remaining)
    end
  end

  # The one summary line above the rows, in the filter bar's count slot. Every
  # number describes the teams listed below it; "of N" appears only while a
  # filter is narrowing them, so an unfiltered page does not say "61 of 61".
  # Same job as Scheduling::ShiftDropReportHelper#shift_drop_summary_count.
  def membership_report_summary_count(shown:, total:, memberships:, people:, unmanaged:)
    return "No teams match the current filters" if shown.zero?

    teams = shown == total ? pluralize(shown, "team") : "#{shown} of #{pluralize(total, "team")}"

    [teams,
     pluralize(memberships, "membership"),
     pluralize(people, "person"),
     "#{unmanaged} without managers"].join(" · ")
  end

  # Counts for one row. The managers half is dropped at zero because the row
  # already carries a badge saying so, and "0 managers · No managers" says it
  # twice.
  def membership_report_row_meta(members, managers)
    parts = [pluralize(members, "member")]
    parts << pluralize(managers, "manager") if managers.positive?
    parts.join(" · ")
  end

  # Badges only mark the exception -- one on every row is noise, and the type is
  # already a filter. size: "base" so it sits correctly in the row's text-lg
  # headline. Never colour alone: the badge names the problem and carries an
  # icon.
  def membership_report_row_badges(managers)
    return [] if managers.positive?

    [ui_badge("No managers", :error, icon: "triangle-exclamation", icon_type: :solid,
                                     size: "base", class: "whitespace-nowrap")]
  end

  # Upstream fetches each person's status and never shows it, which leaves an
  # inactive member reading exactly like an active one. The rendering itself is
  # Person::StatusesHelper#person_status_label, shared with Position Grants.

  # Managers and members are separate lists that usually overlap, so the stat
  # boxes are not a head count -- a reader who adds them over-counts the team.
  # Mirrors the qualifying line the Shift Drop Report closes its drill-down
  # with, and says nothing at all when there is nothing to qualify.
  def membership_report_overlap_summary(members, managers)
    return if managers.empty?

    member_ids = members.map(&:id)
    both = managers.count { |person| member_ids.include?(person.id) }

    "#{pluralize(managers.size, "manager")} · #{both} of them also on the member list"
  end

  private

  def membership_report_filter_value_label(key, value)
    case key
    when :type then team_record_type_label(value)
    when :managers then MANAGER_LABELS[value] || value
    when :sort then SORT_LABELS[value] || value
    else value
    end
  end
end
