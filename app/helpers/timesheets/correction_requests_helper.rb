# frozen_string_literal: true

module Timesheets::CorrectionRequestsHelper
  FILTER_CHIP_LABELS = { letter: "Callsign Starts With" }.freeze

  # "All" carries no value, so it clears the filter by being the option without
  # one. Only the letters the report holds are offered -- the rest could only
  # ever return an empty table.
  def correction_request_letter_options(letters)
    [["All callsigns", ""]] + letters.map { |letter| [letter, letter] }
  end

  def correction_request_filter_chips(letter, year)
    return [] unless letter

    filter_chips({ letter: }, FILTER_CHIP_LABELS) do |remaining|
      timesheets_correction_requests_path(year:, **remaining)
    end
  end

  # Which of the two requests this is. The icon carries it as well as the
  # colour: the two kinds are decided differently -- a correction changes an
  # entry, a missing entry creates one -- and that has to survive a printed page
  # and a reader who cannot tell the two badge colours apart.
  def correction_request_type_badge(entry)
    return ui_badge("Missing Entry", :secondary, icon: "circle-plus", icon_type: :solid) if entry.missing?

    ui_badge("Correction", :warning, icon: "pen-to-square", icon_type: :solid)
  end

  def correction_request_detail_id(entry) = "correction-request-detail-#{entry.dom_key}"

  # The collapsed stand-in for the reason the request was made. Upstream's page
  # never showed this at all, so every row cost a trip to a person page to find
  # out what was being asked; opened here, the table can be triaged in place.
  #
  # Kept closed rather than printed inline because most rows need no argument --
  # the reader is scanning for the ones that do. A row with nothing to open says
  # so rather than offering a control that reveals an empty box.
  #
  # The ARIA pairing with the detail row belongs to the table builder, so the
  # two cannot drift apart; describing: is appended to the visible label rather
  # than replacing it, which keeps the button operable by voice.
  def correction_request_reason_toggle(table, entry)
    return tag.span("None given", class: "text-stone-muted italic") if entry.notes.empty?

    label = entry.notes.size > 1 ? pluralize(entry.notes.size, "note") : "Reason"

    table.detail_row_toggle(label,
                            id: correction_request_detail_id(entry),
                            describing: "why #{entry.callsign} asked for this")
  end

  # Who wrote the note, in the third person. NoteTypes#from_label is the same
  # answer written for the ranger's own timesheet page: it says "you" whenever
  # the note's author matches the person asked about, which on a reviewer's page
  # would put the reader's own voice into somebody else's request.
  #
  # A note written on somebody's behalf names the desk it came from, because
  # "the ranger says their hours are wrong" and "the HQ window says so" are
  # different claims to weigh.
  def correction_request_note_author(note)
    # person_display_name, not a callsign fallback spelled here: a note can
    # outlive its author, and a note recorded with no author at all renders
    # "person #" if the id is interpolated blind.
    callsign = person_display_name(note.create_person, note.create_person_id, blank: "Unknown")

    case note.type
    when NoteTypes::TYPE_HQ_WORKER then "#{callsign} (HQ Window)"
    when NoteTypes::TYPE_WRANGLER then "#{callsign} (Timesheet Review)"
    else callsign
    end
  end
end
