# frozen_string_literal: true

# Helper names are one shared pool across the whole app, so everything here is
# prefixed with the page it belongs to.
module People::PeopleByLocationHelper
  # The country as a reader would say it. A record with no country on file says
  # so rather than borrowing the country picker's "Choose Country" prompt,
  # which is what a blank code is labelled there.
  def people_by_location_country_label(code)
    return "Not on file" if code.blank? || code == PeopleByLocationReport::NO_COUNTRY

    CountryStateHelper::COUNTRY_LABELS[code].presence || code
  end

  # What a country calls the region under it: a state, a province, or both.
  def people_by_location_region_noun(country)
    CountryStateHelper::STATE_LABELS[country.to_sym] || "State"
  end

  def people_by_location_state_label(country, state)
    if state == PeopleByLocationReport::NO_STATE
      return "#{people_by_location_region_noun(country)} not on file"
    end

    regions = CountryStateHelper::STATES_BY_COUNTRY[country.to_sym]
    regions&.find { |_name, code| code == state }&.first || state
  end

  # Counts on this page reach the thousands, and "5419 people" is a number the
  # reader has to stop and parse.
  def people_by_location_count(count, noun = "person")
    pluralize(number_with_delimiter(count), noun)
  end

  def people_by_location_participation_label(participation, year)
    case participation
    when PeopleByLocationReport::SIGNED_UP then "Signed up in #{year}"
    when PeopleByLocationReport::RANGERED then "Rangered in #{year}"
    when PeopleByLocationReport::BOTH then "Signed up and rangered in #{year}"
    when PeopleByLocationReport::EITHER then "Signed up or rangered in #{year}"
    end
  end

  def people_by_location_participation_options(year)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      PeopleByLocationReport::PARTICIPATION_VALUES.map do |value|
        [people_by_location_participation_label(value, year), value]
      end
  end

  # The year and the filters every link on the page has to carry. Without them
  # drilling into a country, or exporting one, would quietly hand back the
  # unfiltered list.
  #
  # active_filters drops the ones not actually narrowing anything, so what
  # counts as "off" is decided in the one place the whole app reads it from.
  def people_by_location_query(year:, participation: nil, statuses: [], **overrides)
    UiComponents::FilterBarHelper.active_filters(participation:, statuses:)
                                 .merge(year:, **overrides)
  end

  # The statuses being left out of every count on the page, in the report's own
  # order so the notice reads the same way each time.
  def people_by_location_hidden_statuses(statuses)
    PeopleByLocationReport::OPTIONAL_STATUSES - statuses
  end

  # "bonked, deceased, and retired" -- spelled the way a status is stored, so
  # the notice names the same thing the record does.
  def people_by_location_status_list(statuses)
    statuses.to_sentence
  end

  # The filter bar's result line. regions is the number of states the people are
  # spread over, or false on a page that is not grouping by state.
  def people_by_location_showing(people, regions, country)
    line = "Showing #{people_by_location_count(people)}"
    return line unless regions

    "#{line} in #{pluralize(regions, people_by_location_region_noun(country).downcase)}"
  end

  # What a country page is offering: a list of its states, or its people.
  def people_by_location_country_intro(country, show_states, year)
    if show_states
      "Select a #{people_by_location_region_noun(country).downcase} to see its people."
    else
      "Everyone on file here, with who signed up for a shift and who rangered in #{year}."
    end
  end

  # One chip per filter in force. Each chip's link drops just that filter and
  # keeps the rest; the block turns the remaining filters into this page's URL,
  # so a chip removed on a country page stays on that country.
  def people_by_location_chips(year:, participation:, statuses:)
    chips = []

    if (label = people_by_location_participation_label(participation, year))
      chips << { label: "Showing: #{label}",
                 url: yield(people_by_location_query(year:, statuses:)) }
    end

    statuses.each do |status|
      chips << { label: "Including: #{status}",
                 url: yield(people_by_location_query(year:, participation:,
                                                     statuses: statuses - [status])) }
    end

    chips
  end
end
