# frozen_string_literal: true

module Training::SessionLinkHelper
  # Times sit in table columns and in wrapping rows of chips; neither may break
  # a timestamp across lines, and stacked times only line up when the digits do.
  STAMP_CLASSES = "whitespace-nowrap tabular-nums"

  # When a session starts, in its own local time.
  #
  # slot.begins is ALREADY the session's local wall-clock time, so it is stamped
  # with its zone rather than converted. Slot#begins_adjusted converts, and would
  # shift every session held outside the app zone -- Green Dot's sessions span
  # seven zones, so this is load bearing. Every training report reads its times
  # through here so there is one place to get that wrong.
  def training_session_time(slot)
    datetime_format slot.begins, tz: slot.timezone, tz_abbr: slot.timezone_abbr
  end

  # The when-and-where of one session: the start time linked to its session
  # page, then where it is held. Descriptions are NULL on real slots, so the
  # fallback is load bearing.
  #
  # The caller owns the wrapper, which is what lets one helper serve both
  # layouts in use -- a flex-col cell stacks the two, a flex-wrap row runs them
  # together -- and lets a report add its own leading content on the same line.
  # Trailing content (a badge, a position title) goes in the block.
  #
  # session_id names the session page to link to: a trainer slot teaches a
  # different session than the one it belongs to. linkable: false covers the
  # volunteer shifts that mentor and mentee sections list, which have no
  # session page at all.
  def training_session_link(slot, session_id: slot.id, year: nil, linkable: true, &block)
    stamp =
      if linkable
        link_to training_session_time(slot), training_session_path(training_slug, session_id, year: year),
                class: class_names(LinkHelper::TABLE_LINK_CLASSES, STAMP_CLASSES)
      else
        tag.span training_session_time(slot), class: STAMP_CLASSES
      end

    safe_join [
      stamp,
      tag.span(slot.description.presence || "(no description)", class: "text-stone-muted"),
      (capture(&block) if block)
    ].compact
  end
end
