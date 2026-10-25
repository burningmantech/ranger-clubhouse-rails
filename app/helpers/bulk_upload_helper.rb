# frozen_string_literal: true

# The shared vocabulary of the eight bulk pages: how the action select is drawn,
# what each verdict looks and reads like, and the sentences the preview and the
# results banner print.
#
# One module rather than one per page, because the pages differ only in their
# action lists and their copy -- the verdicts, the buckets and the banner rules
# are the same everywhere. Every method keeps the `bulk_upload_` prefix: helper
# modules share one namespace on the view context, so a bare `badge` here would
# silently replace another page's.
module BulkUploadHelper
  # Per verdict: the pill's label and colour, and the icon carrying the same
  # meaning without it -- status must never be colour alone.
  #
  # `replace` is amber rather than green: it writes, but it writes over
  # something that is already there, and that is the one row a reader should
  # stop on before confirming.
  VERDICT_BADGES = {
    change: ["Will be applied", :success, "circle-plus"],
    replace: ["Will replace", :warning, "arrow-right-arrow-left"],
    no_change: ["No change", :secondary, "circle-check"],
    duplicate: ["No change", :secondary, "clone"],
    not_found: ["Problem", :error, "triangle-exclamation"],
    ambiguous: ["Problem", :error, "triangle-exclamation"],
    blocked_status: ["Problem", :error, "triangle-exclamation"],
    invalid: ["Problem", :error, "triangle-exclamation"]
  }.freeze

  OUTCOME_ICONS = {
    error: "triangle-exclamation",
    warning: "circle-exclamation",
    success: "circle-check"
  }.freeze

  def bulk_upload_badge(entry)
    label, color, icon = VERDICT_BADGES.fetch(entry.verdict)
    ui_badge label, color, icon:, icon_type: :solid
  end

  # The action select. Grouped only when the page's list says so: a flat select
  # of four vehicle flags needs no headings, and a select of thirteen provisions
  # is unreadable without them.
  def bulk_upload_action_options(actions, selected)
    selected = selected.to_s
    return options_for_select(actions.map { |a| [a.label, a.id] }, selected) if actions.none?(&:group)

    grouped = actions.group_by(&:group)
                     .map { |group, listed| [group, listed.map { |a| [a.label, a.id] }] }
    grouped_options_for_select(grouped, selected)
  end

  # The preview headline, which doubles as the confirm button's label: the
  # action in the page's own words, and how many people it lands on. This
  # sentence is the page's real guard against confirming the wrong list.
  def bulk_upload_preview_title(batch)
    "#{batch.action.label} — #{pluralize(batch.changing.size, "person")}"
  end

  # The confirm button, and the confirm dialog's own button. Separate from the
  # headline above because a heading may be a noun phrase and a button may not:
  # several pages label their actions with the state being recorded ("Signed
  # Motorpool Agreement"), which names the thing but never says what pressing
  # the button does.
  # "Confirm" rather than a per-page verb: it is the one word that fits an
  # action list as mixed as "Set as Active", "Create Access Documents" and
  # "Earned All Eat Pass", and it says what the button does without arguing with
  # what the action is called.
  def bulk_upload_confirm_label(batch)
    "Confirm #{batch.action.label} — #{pluralize(batch.changing.size, "person")}"
  end

  # The last thing read before anything is written.
  def bulk_upload_consequence(batch)
    "#{batch.action.label} will be applied to #{pluralize(batch.changing.size, "person")}. " \
      "Everyone else on your list is left alone."
  end

  # Success is reserved for a run that changed something and left nothing
  # needing attention. A run where every line was unusable wrote nothing, and
  # painting that green invites a reader scanning by colour to move on from a
  # job that did not happen.
  def bulk_upload_outcome_banner(batch, outcome)
    variant = if outcome.failed?
                :error
              elsif outcome.changed.empty? || batch.problems.any?
                :warning
              else
                :success
              end

    [variant, OUTCOME_ICONS.fetch(variant)]
  end

  def bulk_upload_outcome_headline(batch, outcome)
    return "Nothing was changed." if outcome.changed.empty?

    "#{batch.action.label} — applied to #{pluralize(outcome.changed.size, "person")}."
  end

  # Failures name the people so the reader can retry them, but never the
  # exception text: that is already in the log, and a raw Ruby or SQL message is
  # not something to hand an administrator.
  #
  # Problems are named too, not just counted: the apply re-renders the form, so
  # the per-line table that identified each bad callsign is no longer on the
  # page and a bare count would send the reader back through the preview.
  def bulk_upload_outcome_detail(batch, outcome)
    parts = []
    parts << "Changed: #{outcome.changed.map(&:callsign).to_sentence}." if outcome.changed.any?
    if outcome.failed?
      parts << "Could not be changed: #{outcome.failed.map(&:callsign).to_sentence} — " \
               "the reason is in the log. Try those again."
    end
    parts << "Could not be used: #{batch.problems.map(&:callsign).to_sentence}." if batch.problems.any?
    # "Needed no action" rather than "already correct": the skipping bucket also
    # holds the repeats of a line, and a callsign pasted twice has no second
    # state to be right about.
    parts << "#{pluralize(batch.skipping.size, "callsign")} needed no action." if batch.skipping.any?

    parts.join(" ")
  end

  # True when the page ships the named optional partial. Three hooks exist --
  # `advisory` above the form, `formats` under the textarea, `consequence` in
  # the preview -- and a page that needs none simply has no file.
  def bulk_upload_partial?(name)
    lookup_context.exists?(name, [controller_path], true)
  end
end
