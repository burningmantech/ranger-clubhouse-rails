# frozen_string_literal: true

# View helpers for the HQ Window Interface shell and pages.
# Ported from the Ember hq templates (port/templates/hq.hbs,
# port/components/hq-provision-info.hbs, port/constants/event-periods.js).
module HqHelper
  # Rows of the provision-info Meals table (port/constants/event-periods.js).
  EVENT_PERIOD_ROWS = [
    { key: :pre, label: "Pre-Event" },
    { key: :event, label: "Event Week" },
    { key: :post, label: "Post-Event" }
  ].freeze

  # Turbo frame id the Tickets & Provisions modal lazy-loads its tables into.
  TICKETS_PROVISIONS_FRAME = "hq-tickets-provisions-progress"

  # Positions whose workers receive pogs directly from their Cadre and are
  # not issued pogs at the HQ Window. The guidelines copy also names Sandman
  # and Gerlach Patrol; upstream deliberately limits the alert to the Mentor
  # family (DEFERRED note in port/components/hq-pogs.js) — mirrored exactly.
  SELF_SERVE_POG_POSITIONS = [
    Position::MENTOR,
    Position::MENTOR_APPRENTICE,
    Position::MENTOR_MITTEN,
    Position::MENTOR_LEAD,
    Position::MENTOR_KHAKI,
    Position::MENTOR_SHORT
  ].freeze

  # True when the on-duty position's pogs are handled by the worker's own
  # Cadre rather than the HQ Window (drives the Mentor-shift callout on the
  # Meals & Showers panel).
  def hq_self_serve_pog_position?(position_id)
    SELF_SERVE_POG_POSITIONS.include?(position_id)
  end

  # "an Alpha" / "a Prospective" (Ember {{if person.isAlpha ...}}).
  def hq_pnv_noun(person)
    person.status == Person::ALPHA ? "an Alpha" : "a Prospective"
  end

  # Progress-item threshold for display: credit thresholds are floats
  # ("19.00"), hour thresholds are whole hours ("60").
  def hq_threshold_display(item)
    if item.measure == TicketsAndProvisionsProgress::MEASURE_CREDITS
      credit_format_short(item.threshold)
    else
      item.threshold
    end
  end

  # --- Guided-flow section summaries ---------------------------------------
  #
  # One line each, shown on the right of a section's row so folding a section
  # never hides what is still outstanding there. Anything the operator must act
  # on is a badge; settled states are plain muted text.
  #
  # Each summary is the sole live claim its row makes, so each sits in a span
  # with a stable id: everything on this page mutates by turbo stream, and a
  # folded row still insisting "2 entries to review" after both were reviewed
  # is the one failure guided flow cannot afford. See the *_summary streams in
  # Hq::ShiftManageController — every action that changes what a row counts
  # re-streams that row.

  # "On duty — Green Dot" and "Not on duty" are opposite answers to the central
  # question this page exists to settle, and while the shift section is folded
  # the summary row is the only place either one appears. Printed in the same
  # muted grey they were the same row at arm's length — which is the distance
  # the HQ screen is actually read from. The live state takes the success tone
  # the On Duty badge already carries in common/shift_manage/_on_duty, so the
  # folded row and the open panel make one claim; the walking figure repeats it
  # for a colourblind operator and for a sunlit tablet. Ended and never-started
  # both stay muted: they are settled, and nothing on them is owed.
  def hq_shift_summary(on_duty_entry, ended_entry, unreviewed_count)
    if unreviewed_count.to_i.positive?
      return hq_summary_text(
        ui_badge("#{pluralize(unreviewed_count, "entry")} to review", :warning,
                 icon: "triangle-exclamation", icon_type: :solid),
        id: "hq-shift-summary"
      )
    end

    if on_duty_entry
      return hq_summary_text(
        safe_join([fa_icon("person-walking", :solid, end: 2),
                   "On duty — #{on_duty_entry.position.title}"]),
        id: "hq-shift-summary", tone: "text-success"
      )
    end

    hq_summary_text(ended_entry ? "Shift ended" : "Not on duty", id: "hq-shift-summary")
  end

  def hq_assets_summary(radio_accounting, assets_checked_out)
    body = if radio_accounting.collect_count.positive?
             ui_badge "Collect #{pluralize(radio_accounting.collect_count, "radio")}", :warning,
                      icon: "triangle-exclamation", icon_type: :solid
           elsif assets_checked_out.any?
             "#{pluralize(assets_checked_out.size, "asset")} checked out"
           else
             "Nothing checked out"
           end
    hq_summary_text body, id: "hq-assets-summary"
  end

  def hq_pogs_summary(pogs)
    hq_summary_text "#{pluralize(pogs.size, "pog")} recorded", id: "hq-pogs-summary"
  end

  def hq_off_site_summary(person, pending_items)
    body = if !person.on_site
             "Already off site"
           elsif pending_items.any?
             ui_badge "#{pluralize(pending_items.size, "item")} to handle", :warning,
                      icon: "triangle-exclamation", icon_type: :solid
           else
             "Ready to mark off site"
           end
    hq_summary_text body, id: "hq-off-site-summary"
  end

  # Three tones, one meaning each: a badge brings its own colour and must not
  # inherit the muted tone that says "nothing to do here"; an explicit tone
  # marks a live state that is not owed but is worth finding; everything else
  # is settled and recedes.
  def hq_summary_text(body, id: nil, tone: nil)
    tag.span body, id:, class: tone || ("text-stone-muted" unless body.html_safe?)
  end
end
