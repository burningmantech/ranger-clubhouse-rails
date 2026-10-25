# frozen_string_literal: true

# The languages spoken by Rangers, and what each speaker is doing right now.
#
# Each language carries the people who speak it, how well they speak it, whether
# they are on a shift, and whether they are carrying a radio. Languages picked
# from the standard list are called common; a language someone typed in
# themselves is called other.
#
# Only people with an active status are counted. Everyone is counted by default,
# and the reader narrows to the group they want: the desks read this both to find
# someone who can help translate this minute and to find out who is coming.
class LanguagesKnownReport
  # Which speakers to count: all of them, the ones standing a shift right now,
  # the ones here, or the ones away. Being away is simply not being here --
  # there is one column, and it says whether a person has arrived.
  #
  # Counting everyone is the word the filter bar reads as "no narrowing", so a
  # page can hand its filter straight to it.
  SITE_EVERYONE = UiComponents::FilterBarHelper::ALL_FILTER
  SITE_ON_DUTY = "on_duty"
  SITE_ON = "on_site"
  SITE_OFF = "off_site"
  SITES = [SITE_EVERYONE, SITE_ON_DUTY, SITE_ON, SITE_OFF].freeze

  # One person who speaks a language. `position` is the shift they are on right
  # now, and is nil when they are not on one.
  Speaker = Data.define(:person_id, :callsign, :proficiency, :on_site, :position, :radio) do
    def proficiency_label = PersonLanguage::PROFICIENCY_LABELS[proficiency] || proficiency

    def on_site? = on_site

    def on_duty? = position.present?

    def radio? = radio

    # Someone on a shift comes first, then someone reachable by radio, then
    # everyone else. People who are off site sort below all of them.
    def urgency = [on_site? ? 0 : 1, on_duty? ? 0 : (radio? ? 1 : 2), callsign.to_s]
  end

  # One language and everyone who speaks it. `common` marks a language that came
  # from the standard list.
  Language = Data.define(:name, :common, :speakers) do
    def speaker_count = speakers.size

    def count_of(proficiency) = speakers.count { |speaker| speaker.proficiency == proficiency }

    def on_site_count = speakers.count(&:on_site?)

    def off_site_count = speaker_count - on_site_count

    def on_duty_count = speakers.count(&:on_duty?)

    def radio_count = speakers.count(&:radio?)

    # No one who speaks this language is here. The reader still wants to see it
    # when they went looking for it by name.
    def off_site_only? = on_site_count.zero?
  end

  # The whole report, in the two lists the page shows.
  Result = Data.define(:common, :other) do
    def languages = common + other

    def language_count = languages.size

    # How many people are behind the lists. Someone who speaks three languages
    # appears in three of them and still counts once here.
    def people_count = languages.flat_map(&:speakers).map(&:person_id).uniq.size

    def any? = languages.any?
  end

  class << self
    # Every language, or only those whose name contains `query`.
    def execute(query: nil, site: SITE_EVERYONE)
      common, other = languages(query:, site:).partition(&:common)
      Result.new(common:, other:)
    end

    # One language by name, matched without regard to case or spacing. Returns
    # nil when no one the filter covers speaks it.
    def find_language(name, site: SITE_EVERYONE)
      key = normalize(name)
      return nil if key.blank?

      languages(site:, name: key).find { |language| normalize(language.name) == key }
    end

    private

    # Every language asked for, in reading order.
    def languages(query: nil, site: SITE_EVERYONE, name: nil)
      rows = speaker_rows(query:, site:, name:).to_a
      person_ids = rows.map(&:person_id).uniq
      shifts = current_shifts(person_ids)
      radios = radio_holders(person_ids)

      rows.group_by { |row| normalize(row.actual_name) }
          .filter_map { |key, found| build_language(found, shifts, radios) if key.present? }
          .sort_by { |language| normalize(language.name) }
    end

    # The language records of everyone being counted, ordered by callsign. A
    # record whose person is gone drops out: the join needs a person, and a
    # language no one can be sent to is not worth a row.
    def speaker_rows(query:, site:, name: nil)
      scope = PersonLanguage.joins(:person)
                            .where(person: { status: Person::ACTIVE_STATUSES })
                            .order("person.callsign")
                            .select(:id, :person_id, :language_name, :language_custom, :proficiency)
                            .select("person.callsign", "person.on_site")

      scope = scope.where(person_id: open_shifts.select(:person_id)) if site == SITE_ON_DUTY
      scope = scope.where(person: { on_site: true }) if site == SITE_ON
      scope = scope.where(person: { on_site: false }) if site == SITE_OFF
      scope = named(scope, name) if name.present?
      scope = matching(scope, query) if query.present?

      scope
    end

    # Rows for one language only. Asking for a single language reads the records
    # of that language rather than of everybody, which is most of what a page
    # showing one language costs. The comparison matches the one the rows are
    # grouped by afterwards, so nothing that belongs to the language is left out.
    def named(scope, key)
      listed = scope.where.not(language_name: PersonLanguage::LANGUAGE_NAME_CUSTOM)
                    .where("TRIM(LOWER(person_language.language_name)) = :key", key:)

      listed.or(scope.where("TRIM(LOWER(person_language.language_custom)) = :key", key:))
    end

    # Rows whose language reads like what was typed. The name a person picked
    # from the list and the name they typed in live in different columns, so
    # both are searched -- but the picked-from-the-list column holds a marker
    # rather than a name on typed-in rows, and matching that marker would return
    # every typed-in language at once.
    def matching(scope, query)
      like = "%#{PersonLanguage.sanitize_sql_like(query.to_s.strip)}%"

      listed = scope.where.not(language_name: PersonLanguage::LANGUAGE_NAME_CUSTOM)
                    .where_like("person_language.language_name", like)

      listed.or(scope.where_like("person_language.language_custom", like))
    end

    # Records that name the same language become one language, whether they came
    # from the standard list or were typed in. The standard spelling wins the
    # name when there is one, so the list reads the way the form offers it.
    def build_language(rows, shifts, radios)
      listed = rows.find { |row| !row.is_custom? }
      speakers = rows.map do |row|
        Speaker.new(person_id: row.person_id, callsign: row.callsign, proficiency: row.proficiency,
                    on_site: on_site?(row), position: shifts[row.person_id], radio: radios.include?(row.person_id))
      end

      Language.new(name: (listed&.language_name || rows.first.actual_name).strip,
                   common: listed.present?,
                   speakers: one_per_person(speakers).sort_by(&:urgency))
    end

    # A person listing the same language twice is still one speaker. Keep the
    # level they are surest of, so someone fluent is never written down as
    # knowing only a few words.
    def one_per_person(speakers)
      speakers.group_by(&:person_id)
              .map { |_person_id, found| found.max_by { |speaker| proficiency_rank(speaker.proficiency) } }
    end

    # Levels run from least to most sure, so their place in that list ranks
    # them. A level the list does not know ranks lowest.
    def proficiency_rank(proficiency) = PersonLanguage::PROFICIENCY_TYPES.index(proficiency).to_i

    # Whether this person is here. The column is borrowed from another table, so
    # it arrives as the digit the database stores rather than as a yes or no --
    # and a plain reading of that digit calls everyone here, since zero counts
    # as true in Ruby.
    def on_site?(row) = ActiveModel::Type::Boolean.new.cast(row.on_site)

    # Every shift that has been started and not yet ended. Only shifts started
    # this event count: an entry left open in a past year is a mistake, not
    # someone standing out there.
    def open_shifts
      Timesheet.on_duty_now.where_year("timesheet.on_duty", Current.year)
    end

    # The shift each person is on right now, by person id.
    def current_shifts(person_ids)
      return {} if person_ids.blank?

      open_shifts.joins(:position)
                 .where(person_id: person_ids)
                 .order(:on_duty)
                 .pluck(:person_id, "position.title")
                 .to_h
    end

    # Who is holding a radio right now.
    def radio_holders(person_ids)
      return Set.new if person_ids.blank?

      PersonAsset.joins(:asset)
                 .where(person_id: person_ids, checked_in: nil)
                 .where(asset: { type: Asset::TYPE_RADIO })
                 .where_year("person_asset.checked_out", Current.year)
                 .pluck(:person_id)
                 .to_set
    end

    def normalize(name) = name.to_s.strip.downcase
  end
end
