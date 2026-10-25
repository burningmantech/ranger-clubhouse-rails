# frozen_string_literal: true

module LinkHelper
  # In-table links. min-h-5 (20px) is deliberately under the 36px touch floor:
  # these sit inline inside dense table rows, where raising them would set the
  # height of every report table in the app. Known exception, not an oversight.
  TABLE_LINK_CLASSES = "link link-primary inline-flex min-h-5 items-center"

  def nav_link_to(name, path, options = {}, is_root = false)
    if (is_root && current_page?(path)) || (!is_root && request.fullpath.start_with?(path))
      options[:class] = "#{options[:class]} active"
      options["aria-current"] = "true"
    end
    options[:class] = "#{options[:class]} no-decoration"
    link_to name, path, options
  end

  # Person link showing their callsign, styled as a standard table link.
  # Defaults to the person page; pass a path to point somewhere else.
  def callsign_link(person, path = nil, **options)
    options[:class] = class_names(TABLE_LINK_CLASSES, options[:class])
    link_to person.callsign, path || person, options
  end

  # An email address as a table link, or the house dash when none is on file --
  # never a mailto: link to nowhere.
  def email_link_or_dash(email)
    email.present? ? mail_to(email, class: TABLE_LINK_CLASSES) : value_or_dash(nil)
  end

  # A person who may no longer exist. Asset and log rows keep a person_id long
  # after the person row is gone -- the Laravel-shared schema carries no FK, so
  # a non-optional belongs_to still reads nil -- and every caller was spelling
  # the fallback itself, in four wordings that had already drifted apart.
  # blank: is what a missing id renders as; pass nil for CSV cells.
  def person_display_name(person, person_id, blank: "—")
    return person.callsign if person
    return blank if person_id.blank?

    "Deleted ##{person_id}"
  end

  # The same value as a link, but only for readers who can open person pages --
  # otherwise every callsign is a link that bounces to /me.
  # if in_turbo_frame is true, the link will be rendered with turbo_frame="_top" so a breakout of
  # the turbo frame happens.
  #
  # path: points the link somewhere other than /person/:id -- a report whose
  # rows are fixed on one of the person tabs should land the reader there
  # rather than on the profile they would have to navigate out of.
  def person_display_link(person, person_id, blank: "—", path: nil, in_turbo_frame: false)
    return person_display_name(person, person_id, blank:) unless person && can_view_person_page?

    options = {}
    options["data-turbo-frame"] = "_top" if in_turbo_frame
    callsign_link(person, path, **options)
  end

  # True when the current person may open /person/:id. Reports are routinely
  # readable by roles the person pages are not -- Quartermaster and Timesheet
  # Management among them -- so a roster linking every callsign hands those
  # readers a page of links that all bounce to /me. Guard the link with this
  # and render the plain callsign instead.
  def can_view_person_page?
    Current.has_role?(PersonConcern::VIEW_ROLES)
  end
end
