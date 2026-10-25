# frozen_string_literal: true

module People::LanguagesKnownHelper
  # How well someone speaks a language, coloured so a reader scanning for a
  # fluent speaker can find one without reading every row. A level no one set
  # gets no colour, since there is nothing to rank.
  PROFICIENCY_VARIANTS = {
    PersonLanguage::PROFICIENCY_FLUENT => :success,
    PersonLanguage::PROFICIENCY_INTERMEDIATE => :primary,
    PersonLanguage::PROFICIENCY_BASIC => :secondary
  }.freeze

  def languages_known_proficiency(speaker)
    variant = PROFICIENCY_VARIANTS[speaker.proficiency]
    return tag.span(speaker.proficiency_label, class: "me-muted") unless variant

    ui_badge speaker.proficiency_label, variant
  end

  # The levels this language has speakers at, surest first, ready for a stat box
  # each. Every level with someone at it is here, so the counts add up to the
  # number of speakers. A level no one claims is left out rather than shown as a
  # zero.
  #
  # Only fluent takes a colour: the count boxes have no primary shade, so
  # ranking the middle levels by colour is not something they can do.
  def languages_known_levels(language)
    PersonLanguage::PROFICIENCY_TYPES.reverse.filter_map do |proficiency|
      count = language.count_of(proficiency)
      next unless count.positive?

      variant = proficiency == PersonLanguage::PROFICIENCY_FLUENT ? :success : :secondary
      [PersonLanguage::PROFICIENCY_LABELS[proficiency], count, variant]
    end
  end

  # What one person is doing right now: the shift they are on, and whether they
  # can be reached by radio. Blank for someone who is neither, so the column
  # only draws the eye to people the reader can actually go get.
  #
  # A badge that would land on every row says nothing, so each is left off the
  # list that was narrowed to exactly those people. The shift itself is still
  # named -- that part differs per row.
  def languages_known_status(speaker, site)
    parts = []

    if speaker.on_duty?
      parts << ui_badge("On duty", :success, icon: "clock", icon_type: :solid) unless narrowed_to_on_duty?(site)
      parts << tag.span(speaker.position, class: "me-muted text-sm")
    end

    parts << ui_badge("Radio", :primary, icon: "walkie-talkie", icon_type: :solid) if speaker.radio?

    if !speaker.on_site? && !languages_known_arrival_pinned?(site)
      parts << ui_badge("Off site", :warning, icon: "plane-departure", icon_type: :solid)
    end

    safe_join(parts, " ")
  end

  # How many speakers a language has -- the number of people the language's own
  # page will list under the same filter.
  def languages_known_row_meta(language)
    pluralize(language.speaker_count, "speaker")
  end

  # The badges beside a language on the index: how many of its speakers are on a
  # shift right now, and whether it has anyone here at all. Each is dropped from
  # the list that was narrowed to exactly those people, where it would only
  # repeat the count already beside it, or sit on every row.
  #
  # No one here is not worth saying about a language somebody is standing a
  # shift for -- the two badges would argue with each other.
  def languages_known_row_badges(language, site)
    on_duty = language.on_duty_count.positive? && !narrowed_to_on_duty?(site)
    away = language.off_site_only? && language.on_duty_count.zero? && !languages_known_arrival_pinned?(site)

    [
      (ui_badge("#{language.on_duty_count} on duty", :success, size: "base") if on_duty),
      (ui_badge("Off site only", :warning, size: "base") if away)
    ].compact
  end

  # Whether the page is showing only people who are on a shift right now.
  def narrowed_to_on_duty?(site) = site == LanguagesKnownReport::SITE_ON_DUTY

  # Whether the filter already settles whether everyone listed has arrived. When
  # it does, saying so again on each row tells the reader nothing -- but the
  # people on a shift are not all here, so that list still has it worth saying.
  def languages_known_arrival_pinned?(site)
    [LanguagesKnownReport::SITE_ON, LanguagesKnownReport::SITE_OFF].include?(site)
  end

  SITE_LABELS = {
    LanguagesKnownReport::SITE_EVERYONE => "Everyone",
    LanguagesKnownReport::SITE_ON_DUTY => "On duty",
    LanguagesKnownReport::SITE_ON => "On site",
    LanguagesKnownReport::SITE_OFF => "Off site"
  }.freeze

  # Who the reader can choose to count, the widest choice first.
  def languages_known_site_options = SITE_LABELS.map { |site, label| [label, site] }

  # The chip that says the page has been narrowed. There is only one filter
  # here, so dropping it lands where "Clear all filters" lands. Counting
  # everybody draws no chip: it is where the page starts, so there is nothing to
  # remove.
  FILTER_CHIP_LABELS = { site: "Speakers" }.freeze

  def languages_known_filter_chips(site, clear_url)
    active = UiComponents::FilterBarHelper.active_filters(site:)

    filter_chips(active, FILTER_CHIP_LABELS,
                 value_label: ->(_key, chosen) { SITE_LABELS[chosen] }) { clear_url }
  end

  # How the page names the people it is counting. Nothing to add when it is
  # counting all of them, so that choice is left out.
  SITE_PHRASES = SITE_LABELS.except(LanguagesKnownReport::SITE_EVERYONE)
                            .transform_values(&:downcase)
                            .freeze

  def languages_known_site_phrase(site) = SITE_PHRASES[site]

  # The filter as a link needs it. Every page here opens counting everybody, so
  # saying so again would only lengthen the address -- but a narrower choice has
  # to travel, or following a link would quietly widen the page again.
  def languages_known_carried_site(site)
    site unless site == LanguagesKnownReport::SITE_EVERYONE
  end

  # Everything the reader chose, for a link that has to keep it. A link that
  # drops the search sends them back to a list they have to narrow again.
  def languages_known_carried(query, site, **extra)
    { q: query.presence, site: languages_known_carried_site(site) }.compact.merge(extra)
  end

  # What the page is showing, counted and named.
  def languages_known_summary(report, site)
    "Showing #{pluralize report.language_count, "language"} " \
      "spoken by #{pluralize report.people_count, "person"} #{languages_known_site_phrase(site)}".squish
  end

  # Said when no one the filter covers has listed any language at all.
  def languages_known_nothing_listed(site)
    "No one #{languages_known_site_phrase(site)} has listed a language yet.".squish
  end

  # Said when a language has no speakers the filter covers.
  def languages_known_missing(site)
    "No one #{languages_known_site_phrase(site)} has listed this language.".squish
  end
end
