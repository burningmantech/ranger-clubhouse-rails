# frozen_string_literal: true

module Vc::HandleCheckerHelper
  RULE_NAMES = HandleChecker.rule_options.to_h.freeze

  # Icon and accent card variant per priority. Conflicts sort most serious
  # first, so the first one sets the tone for the whole card. Pairing an icon
  # with every variant keeps severity off color alone.
  STYLES = {
    nil => ["circle-check", :success],
    HandleChecker::PRIORITY_HIGH => ["triangle-exclamation", :error],
    HandleChecker::PRIORITY_MEDIUM => ["circle-exclamation", :warning],
    HandleChecker::PRIORITY_LOW => ["circle-info", :warning]
  }.freeze

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

  def handle_checker_result_icon(conflicts) = handle_checker_styles(conflicts).first

  def handle_checker_result_variant(conflicts) = handle_checker_styles(conflicts).last

  def handle_checker_result_summary(conflicts)
    return "No conflicts found." if conflicts.empty?

    high = conflicts.count { |conflict| conflict.priority == HandleChecker::PRIORITY_HIGH }
    counted = "#{pluralize(number_with_delimiter(conflicts.size), "conflict")} found"
    high.zero? ? "#{counted}." : "#{counted}, #{number_with_delimiter(high)} of them serious."
  end

  # Conflicts are capped per card because the eye rhyme rules can match
  # thousands of handles at once. Sorted most serious first, so the cap only
  # ever hides the least interesting ones.
  def handle_checker_shown_conflicts(conflicts) = conflicts.first(Vc::HandleCheckerForm::MAX_CONFLICTS)

  def handle_checker_overflow_note(conflicts)
    shown = handle_checker_shown_conflicts(conflicts).size
    return if conflicts.size <= shown

    "Showing the #{shown} most serious of #{number_with_delimiter(conflicts.size)} conflicts. " \
      "Switch off a rule above to narrow this down."
  end

  # A whole conflict on one line, e.g.
  #   may sound like Hubcap [active ranger] high priority - double metaphone
  # The conflicting name is a link when it belongs to a person.
  def handle_checker_conflict_line(conflict)
    handle = conflict.conflicting_handle

    safe_join([
                handle_checker_description(conflict),
                (handle_checker_type_badge(handle) if handle),
                (ui_badge("Vintage", :error, size: "sm") if handle&.vintage),
                handle_checker_priority_text(conflict.priority),
                handle_checker_rule_note(conflict.rule_id)
              ].compact, " ")
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

  def handle_checker_type_badge(handle)
    ui_badge handle_checker_type_label(handle.entity_type), :secondary, size: "sm"
  end

  # Spelled out rather than shown by color alone.
  def handle_checker_priority_text(priority)
    tag.span("#{priority} priority", class: PRIORITY_CLASSES.fetch(priority, "text-stone-muted"))
  end

  def handle_checker_rule_note(rule_id)
    tag.span("• #{handle_checker_rule_name(rule_id)}", class: "text-stone-muted")
  end

  private

  def handle_checker_styles(conflicts) = STYLES.fetch(conflicts.first&.priority, STYLES[HandleChecker::PRIORITY_MEDIUM])
end
