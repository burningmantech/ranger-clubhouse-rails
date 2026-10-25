# frozen_string_literal: true

# The filters on a person's site log (Person::SiteLogController).
module Person::SiteLogHelper
  PERSON_SITE_LOG_MARKED_OPTIONS = [
    UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
    ["On Site", PersonOnSite::ON_SITE],
    ["Off Site", PersonOnSite::OFF_SITE]
  ].freeze
  # Each filter's name, for its field and its chip alike, so the two read the same.
  PERSON_SITE_LOG_FILTER_LABELS = {
    starts_on: "From", ends_on: "Through", marked: "Marked", creator: "Marked By", sort: "Order"
  }.freeze
  # Who made a change no one was signed in to make.
  PERSON_SITE_LOG_NO_CREATOR = "System"

  def person_site_log_marked_options = PERSON_SITE_LOG_MARKED_OPTIONS

  def person_site_log_filter_label(key) = PERSON_SITE_LOG_FILTER_LABELS.fetch(key)

  # creator_counts: {creator_person_id or nil => changes} across the whole
  # history, which orders the options -- commonest first, ties by name whatever
  # its case, so they keep their places as other filters change. Never by the
  # raw id, which is nil for System and cannot be compared with an Integer.
  # matching: the same counts under the other filters, for the labels: a select
  # navigates, so each count promises the rows its choice shows (the
  # filter_status_options rule).
  def person_site_log_creator_options(creator_counts, creators, matching:)
    options = creator_counts.map { |id, count| [person_site_log_creator_name(id, creators), count, id] }

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      options.sort_by { |name, count, _id| [-count, name.downcase] }
             .map { |name, _count, id| ["#{name} (#{matching.fetch(id, 0)})", PersonOnSiteFilterForm.creator_value(id)] }
  end

  # A creator as the Marked By select, its chip and the table name them: the
  # callsign, "System" when no one was signed in, or "Deleted #N" for an account
  # since removed. The table's cell links the callsign.
  def person_site_log_creator_name(id, creators)
    person_display_name(creators[id], id, blank: PERSON_SITE_LOG_NO_CREATOR)
  end

  def person_site_log_creator_link(id, creators)
    person_display_link(creators[id], id, blank: PERSON_SITE_LOG_NO_CREATOR)
  end

  # How long a stay lasted, on the off-site mark that ended it; every other
  # mark gets a dash, which also keeps the folded card's "Duration:" label
  # from dangling. durations: PersonOnSite.on_site_durations.
  def person_site_log_duration(row, durations)
    seconds = durations[row.id]
    seconds ? hour_minute_words_or_day_format(seconds) : "—"
  end

  # One chip per active filter, its value in the words its field uses (the
  # Marked By chip without the option's count). Each chip's URL drops that
  # filter and keeps the rest.
  def person_site_log_filter_chips(person, form, creators)
    value_label = lambda do |key, value|
      case key
      when :starts_on, :ends_on then value.iso8601
      when :creator then person_site_log_creator_name(form.creator_id, creators)
      when :marked then PERSON_SITE_LOG_MARKED_OPTIONS.rassoc(value).first
      else PersonOnSiteFilterForm::SORT_OPTIONS.rassoc(value).first
      end
    end

    filter_chips(form.active, PERSON_SITE_LOG_FILTER_LABELS, value_label:) do |remaining, _key|
      person_site_log_path(person, PersonOnSiteFilterForm::PARAM_SCOPE => remaining)
    end
  end
end
