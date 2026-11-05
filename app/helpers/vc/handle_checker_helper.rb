# frozen_string_literal: true

module Vc::HandleCheckerHelper
  RULE_NAMES = HandleChecker.rule_options.to_h.freeze

  PRIORITY_CLASSES = {
    HandleChecker::PRIORITY_HIGH => "text-error font-semibold",
    HandleChecker::PRIORITY_MEDIUM => "text-warning",
    HandleChecker::PRIORITY_LOW => "text-stone-muted"
  }.freeze

  def handle_checker_rule_name(rule_id) = RULE_NAMES[rule_id] || rule_id

  # Label shown for a handle type. Reserved handle types have their own
  # labels; callsign types show as-is, e.g. "active ranger".
  def handle_checker_type_label(entity_type)
    HandleReservation::TYPE_LABELS[entity_type] || entity_type
  end

  def handle_checker_type_options(entity_types)
    entity_types.map { |type| [type, handle_checker_type_label(type)] }
  end

  def handle_checker_result_summary(conflicts)
    return "No conflicts found." if conflicts.empty?

    high = conflicts.count { |conflict| conflict.priority == HandleChecker::PRIORITY_HIGH }
    counted = "#{pluralize(number_with_delimiter(conflicts.size), "conflict")} found"
    high.zero? ? "#{counted}." : "#{counted}, #{number_with_delimiter(high)} of them serious."
  end

  # Conflicts are capped per result because the eye rhyme rules can match
  # thousands of handles at once. Sorted most serious first, so the cap only
  # ever hides the least interesting ones.
  def handle_checker_shown_conflicts(conflicts) = conflicts.first(Vc::HandleCheckerForm::MAX_CONFLICTS)

  # Shown right after the summary's count, so it does not repeat it.
  def handle_checker_overflow_note(conflicts)
    shown = handle_checker_shown_conflicts(conflicts).size
    return if conflicts.size <= shown

    "Showing the #{shown} most serious. Switch off a rule above to narrow this down."
  end

  # The shown conflicts, each paired with the rowspan of the rule cell that
  # starts on its row: the length of its run of consecutive rows sharing a
  # rule, or nil when the row continues the run above it. Conflicts sort by
  # priority and then by rule, so a rule's rows already sit together.
  def handle_checker_rule_runs(conflicts)
    handle_checker_shown_conflicts(conflicts)
      .chunk_while { |earlier, later| earlier.rule_id == later.rule_id }
      .flat_map { |run| run.each_with_index.map { |conflict, index| [conflict, (run.size if index.zero?)] } }
  end

  # The description with its segments rendered: the conflicting handle's name
  # is linked, everything else is plain text.
  def handle_checker_description(conflict)
    handle = conflict.conflicting_handle

    safe_join(conflict.parts.map do |part|
      (part == HandleChecker::HANDLE_NAME) ? handle_checker_handle_name(handle) : part
    end)
  end

  def handle_checker_handle_name(handle)
    return handle.name unless handle.person?

    link_to handle.name, person_path(handle.person_id),
            class: "link font-semibold", target: "_blank", rel: "noopener"
  end

  # The conflicting handle's type, and Vintage when it is one. A rule about
  # the proposed handle itself has no handle to type.
  def handle_checker_type_badges(handle)
    return value_or_dash(nil) unless handle

    safe_join([
                ui_badge(handle_checker_type_label(handle.entity_type), :secondary, size: "sm"),
                (ui_badge("Vintage", :error, size: "sm") if handle.vintage)
              ].compact, " ")
  end

  # Spelled out rather than shown by color alone.
  def handle_checker_priority_text(priority)
    tag.span(priority, class: PRIORITY_CLASSES.fetch(priority, "text-stone-muted"))
  end
end
