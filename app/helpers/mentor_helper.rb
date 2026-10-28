# frozen_string_literal: true

module MentorHelper
  MENTOR_STATUS = {
    PersonMentor::STATUS_PASS => :success,
    PersonMentor::STATUS_BONK => :error,
    PersonMentor::STATUS_SELF_BONK => :error,
    PersonMentor::STATUS_PENDING => :warning,
    # Neither for the mentee nor against: the word and the icon tell them apart.
    PersonMentor::STATUS_ABSTAIN => :secondary,
    PersonMentor::STATUS_NOT_COMPLETED => :secondary
  }.freeze

  # The words for how a walk ended, on every mentoring page (ruled
  # 2026-10-21; the two ART-only verdicts 2026-10-27). Upstream printed the raw
  # database values ("pending", "self-bonk"); one page printing both would
  # make one result look like two.
  RESULT_LABELS = {
    PersonMentor::STATUS_PENDING => "Pending",
    PersonMentor::STATUS_PASS => "Passed",
    PersonMentor::STATUS_BONK => "Bonked",
    PersonMentor::STATUS_SELF_BONK => "Self-bonked",
    PersonMentor::STATUS_ABSTAIN => "Abstained",
    PersonMentor::STATUS_NOT_COMPLETED => "Not completed"
  }.freeze

  # A badge names its result in words and an icon as well as a colour.
  RESULT_ICONS = {
    PersonMentor::STATUS_PENDING => "hourglass-half",
    PersonMentor::STATUS_PASS => "circle-check",
    PersonMentor::STATUS_BONK => "circle-xmark",
    PersonMentor::STATUS_SELF_BONK => "circle-minus",
    PersonMentor::STATUS_ABSTAIN => "circle-pause",
    PersonMentor::STATUS_NOT_COMPLETED => "circle-half-stroke"
  }.freeze

  def mentor_result_label(status) = RESULT_LABELS[status] || status.to_s

  # A result select's options, in RESULT_LABELS' order, for the verdicts its
  # page records: PersonMentor::ALPHA_STATUSES on an Alpha page, STATUSES on an
  # ART roster. No default, so a new page has to say which.
  def mentor_result_options(statuses)
    RESULT_LABELS.filter_map { |value, label| [label, value] if statuses.include?(value) }
  end

  # A mentor select's blank choice: no mentor recorded.
  NO_MENTOR = "No mentor"

  # A mentor select's options, for the Alpha and the ART rosters alike: the
  # blank choice, then the [label, options] groups -- empty ones left out --
  # with the row's pick selected.
  def mentor_choices(groups, selected)
    safe_join([options_for_select([[NO_MENTOR, ""]], selected.to_s),
               grouped_options_for_select(groups.reject { |_label, options| options.empty? }, selected)])
  end

  # An unrecognised value still shows, as itself.
  def mentor_result_badge(status)
    ui_badge mentor_result_label(status), MENTOR_STATUS.fetch(status, :secondary),
             icon: RESULT_ICONS.fetch(status, "circle-question"), icon_type: :solid
  end

  # Both descriptions are one sentence whichever halves apply -- a hero
  # description says one thing (design-rules > Hero Panel Description Rule) --
  # and both return a plain String. They used to safe_join: that escaped the
  # apostrophe in "you've" and in a callsign, common/mentoring/index then
  # interpolated the result back into a String, and hero_panel escaped it a
  # second time, so the page printed "you&#39;ve" as text.
  def me_mentoring_description(mentoring, mentee_events, art_shifts: 0)
    parts = []
    if mentoring.year && mentoring.current_status == PersonMentor::STATUS_PASS
      parts << "your Alpha Shift mentors for #{mentoring.year}"
    end
    parts << "the #{mentored_tally(mentee_events, "you've")}" if mentee_events.any?
    parts << "your #{art_tally(art_shifts)}" if art_shifts.positive?
    parts.any? ? "View #{parts.to_sentence}." : ""
  end

  # Only the tally is ever capitalized. A sentence that opens with the callsign
  # is left exactly as it is: callsigns are printed as stored, lower case included.
  def person_mentoring_description(person, mentoring, mentee_events, art_shifts: 0)
    tally = "the #{mentored_tally(mentee_events, "#{person.callsign} has")}" if mentee_events.any?
    art = "#{person.callsign}'s #{art_tally(art_shifts)}" if art_shifts.positive?

    if mentoring.year
      mentors = "#{person.callsign}'s Alpha Shift mentors for #{mentoring.year}"
      "#{[mentors, tally, art].compact.to_sentence}."
    elsif tally || art
      "#{[tally, art].compact.to_sentence.upcase_first}."
    else
      ""
    end
  end

  # In place of Send Message for someone the compose page would refuse
  # (Person#messaging_permitted?), on every mentoring card.
  def no_contact_allowed = tag.span("no contact allowed", class: "text-sm text-stone-muted italic")

  # The rows the mentoring pages lay their cards and tallies out in: the Alpha
  # sections and the ART sections share them.
  def mentor_card_row(&) = tag.div(class: "flex flex-wrap gap-2", &)

  def mentor_tally_row(&) = tag.div(class: "flex flex-wrap gap-2 mb-3", &)

  # Where an ART walk is recorded: a button to the ART's Verdicts page for
  # that year, for a reader who may open that ART's mentoring pages (its
  # trainer role, or Admin). Nil for anyone else, and for walks under a
  # position whose team has no ART mentoring training.
  def art_history_verdicts_link(training, year)
    return unless training && has_role?(Training.view_roles(training))

    button_link "View Verdicts", :secondary, training_mentoring_verdicts_path(Training.slug(training), year:),
                icon: "clipboard-check", icon_type: :solid
  end

  private

  # "4 ART mentoring shifts": walked or mentored, both sides.
  def art_tally(count) = pluralize(count, "ART mentoring shift")

  # "12 Alphas you've mentored across 3 years"
  def mentored_tally(mentee_events, who_has)
    "#{pluralize mentee_events.sum { |e| e.alphas.size }, "Alpha"} #{who_has} mentored " \
      "across #{pluralize mentee_events.size, "year"}"
  end
end
