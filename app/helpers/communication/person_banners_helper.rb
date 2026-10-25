# frozen_string_literal: true

module Communication::PersonBannersHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  FILTER_CHIP_LABELS = {
    type: "Type",
    year: "Year",
    callsign: "Callsign"
  }.freeze

  # The one source for both the values the page accepts and the words it shows
  # for them, so a new type cannot be accepted without also being labelled.
  TYPE_LABELS = {
    "permanent" => "Permanent",
    "event" => "Event only"
  }.freeze

  def person_banner_type_filter_options
    [ALL_FILTER_OPTION, *TYPE_LABELS.map { |value, label| [label, value] }]
  end

  def person_banner_year_filter_options(years)
    [ALL_FILTER_OPTION, *years.map { |year| [year.to_s, year.to_s] }]
  end

  # One filter_bar chip per active filter; each URL drops that filter and keeps
  # the rest.
  #
  # Callsign is handled apart from the others because it is free text: someone
  # searching for the letters "all" would otherwise match the sentinel that
  # means "no filter", and their search would apply with no chip to remove it.
  def person_banner_filter_chips(filter_params)
    active = active_filters(filter_params.except(:callsign))
    callsign = filter_params[:callsign]
    active = active.merge(callsign:) if callsign.present?

    display = ->(key, value) { key == :type ? TYPE_LABELS.fetch(value, value) : value }

    filter_chips(active, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      communication_person_banners_path(remaining)
    end
  end

  # Permanent or event-only, as an icon-and-text badge so the meaning does not
  # rest on colour alone.
  def person_banner_type_badge(banner)
    if banner.is_permanent?
      ui_badge "Permanent", :warning, icon: "thumbtack", icon_type: :solid
    else
      ui_badge "Event only", :secondary, icon: "calendar", icon_type: :solid
    end
  end

  # Who posted the banner and who last changed it. Neither person is guaranteed
  # to still exist -- the table carries no foreign key for either -- and the
  # banners carried over from the old account note field have no creator at all.
  def person_banner_history(banner)
    entries = [["Posted", banner.created_at, banner.creator_person, banner.creator_person_id]]

    # A banner gets an updated_at the moment it is saved, so that stamp alone
    # would report an edit on every banner ever posted. Only an actual edit
    # records who made it, so that is what the second line waits for.
    if banner.updater_person_id.present?
      entries << ["Changed", banner.updated_at, banner.updater_person, banner.updater_person_id]
    end

    entries.map do |label, at, person, person_id|
      # datetime_format returns a <span>, so the pieces are joined, never interpolated.
      safe_join([label, datetime_format(at, year: true), "by",
                 person_display_name(person, person_id, blank: "unknown")], " ")
    end
  end
end
