# frozen_string_literal: true

# Intake builds the per-person "unified flagging" history shown on the
# Person Management intake page: Personnel/RRN/VC/Mentor team ranks & notes,
# in-person training history, and the combined year-by-year PNV timeline.
#
# Ported from port/api/Intake.php. `history_for_person` backs the per-person
# page (/person/:id/unified-flagging); `retrieve_all_for_year` backs the
# VC-wide pipeline page (/vc/unified-flagging) and ports the summary math in
# port/utils/intake-summaries.js.
class Intake
  ABOVE_AVERAGE = 1
  AVERAGE = 2
  BELOW_AVERAGE = 3
  FLAG = 4

  INTAKE_STATUSES = [Person::AUDITOR, Person::PROSPECTIVE, Person::ALPHA].freeze

  # The applicant pipeline proper -- auditors are tracked by the intake teams
  # (INTAKE_STATUSES above) but are not themselves potential Alphas.
  PNV_STATUSES = [Person::PROSPECTIVE, Person::ALPHA].freeze

  # Leaving the pipeline: the three statuses upstream's exclude_bonks filter
  # names. Someone set to one of these in the same year they entered is not
  # part of that year's class.
  WASHED_OUT_STATUSES = [Person::PAST_PROSPECTIVE, Person::BONKED, Person::UBERBONKED].freeze

  TEAM_TYPES = %w[personnel rrn vc mentor].freeze

  # The order the five teams read in wherever a row lists them -- the three
  # intake teams in pipeline order, then Training, then Mentors, the person
  # page's section order -- and the tiebreak inside the worst-first rank strip,
  # so a row's lead chip and its gray line name teams in the same order.
  TEAM_ORDER = %w[personnel rrn vc training mentor].freeze

  # Worst-dominates ordering from port/utils/intake-summaries.js RANK_SEVERITY:
  # a Green rank outranks a Normal one because it is the more notable signal.
  RANK_SEVERITY = { FLAG => 4, BELOW_AVERAGE => 3, ABOVE_AVERAGE => 2, AVERAGE => 1 }.freeze

  # Display groups, in render order (port/components/unified-flagging.js).
  GROUP_ORDER = %i[personnel flagged other].freeze

  class << self
    # Collapsed-row summaries for the applicant pipeline for `year`, sorted
    # into render order: Personnel-flagged first, then rank 3/4-or-bonk, then
    # the rest (all alphabetical -- upstream's severityWeight is a constant
    # within the Personnel group, so its "worst-first" sort never reorders).
    #
    # Roster: anyone who was set to Prospective or Alpha during `year`, per
    # upstream. See `roster_ids_for_year`.
    #
    # `only_flagged` ports upstream's $onlyFlagged, which defaults on for this
    # page: it keeps only people carrying some adverse mark in their history.
    # Without it the page is a full roster dump -- 221 people rather than 12
    # for 2026 -- and the two triage sections drown.
    #
    # @param year [Integer]
    # @param only_flagged [Boolean]
    # @return [Array<Hash>] see `summarize_person` for the shape
    def retrieve_all_for_year(year, only_flagged: true)
      summaries_for(Person.where(id: roster_ids_for_year(year)), year, only_flagged: only_flagged)
    end

    # The same summaries for whoever is a Prospective or Alpha *right now*,
    # backing /mentoring/potential-alphas. Deliberately not the year roster
    # above: that one answers "who was in the `year` pipeline", read from the
    # status audit trail, and so keeps people who have since bonked. Mentors
    # sizing up this year's potential Alphas want current standing, which also
    # means the page cannot be re-scoped to a past year -- a bonked person's
    # status no longer says they were ever here.
    #
    # only_flagged is off: a Prospective with a clean record is still a
    # potential Alpha and belongs on the page.
    def retrieve_current_potentials(year)
      summaries_for(Person.where(status: PNV_STATUSES), year, only_flagged: false)
    end

    # The same summaries for /mentoring/alpha-status: everyone who *entered*
    # this year's Prospective/Alpha class, minus whoever washed out during it.
    # Ports Alpha::retrieveMentees with exclude_bonks, which is what the Ember
    # route requests. Its `have_training` narrowing is deliberately not carried
    # -- "waiting on training" is one of that page's four sections, so the
    # people it would drop are the ones a mentor most needs to see.
    #
    # The year roster rather than current standing (which
    # `retrieve_current_potentials` above answers) is the whole reason the two
    # mentoring pages can coexist: someone made an Alpha this year and since
    # made Active is still part of this year's class here, and has already
    # vanished from the current-standing page.
    def retrieve_year_class(year)
      ids = roster_ids_for_year(year)

      summaries_for(Person.where(id: ids - washed_out_ids(ids, year)), year, only_flagged: false)
    end

    # Who reached Alpha during `year`, read from the audit trail rather than
    # from standing status. A Shiny Penny -- made an Alpha, then made Active --
    # has already been an Alpha, and asking `person.status` would drop them
    # back into "ready for Alpha status" and tell a mentor to convert a Ranger.
    def became_alpha_ids(year)
      PersonStatus.where(new_status: Person::ALPHA)
                  .where_year("created_at", year).distinct.pluck(:person_id).to_set
    end

    # The year's Prospective/Alpha class for /mentoring/post-season-summary,
    # with the five viewed-year mentor facts a collapsed summary does not carry.
    #
    # The roster is `retrieve_all_for_year` unfiltered, which is upstream's
    # query verbatim (Alpha::retrieveMentees with neither exclude_bonks nor
    # have_training): everyone set to Prospective or Alpha during the year,
    # INCLUDING whoever washed out. Deliberately not `retrieve_year_class`,
    # which subtracts them -- the people who bonked are the ones the post-season
    # review is about.
    #
    # The extra keys exist only on this page's summaries; every other consumer
    # of `summaries_for` never sees them.
    #
    # `mentorships` is loaded a second time here (`summaries_for` already reads
    # it for the bonk chip). One extra indexed query on a class of ~200 costs
    # less than threading an enrichment hook through a method five pages share.
    def retrieve_post_season_class(year)
      summaries = retrieve_all_for_year(year, only_flagged: false)
      ids = summaries.map { |summary| summary[:person].id }
      return summaries if ids.empty?

      mentorships = PersonMentor.retrieve_all_mentors_for_ids(ids, position_id: Position::ALPHA)
      signed_up = alpha_signup_ids_for_year(ids, year)
      ranks = PersonIntake.where(person_id: ids, year: year).index_by(&:person_id)
      # `is_log` excluded to match `have_notes` upstream: an automatic log entry
      # is not somebody having written something.
      noted = PersonIntakeNote.where(person_id: ids, year: year, type: "mentor", is_log: false)
                              .distinct.pluck(:person_id).to_set

      summaries.each do |summary|
        person_id = summary[:person].id
        mentorship = mentorships.dig(person_id, year) || {}
        # Upstream's default for a year with no person_mentor rows. It means
        # "no verdict recorded", not "walking right now" -- on a past year
        # most of these people simply never signed up, which is what the
        # sign-up chip beside it says.
        status = mentorship[:status] || PersonMentor::STATUS_PENDING

        summary.merge!(
          mentor_status: status,
          mentors: mentorship[:mentors] || [],
          signed_up: signed_up.include?(person_id),
          mentor_rank: ranks[person_id]&.mentor_rank.to_i,
          mentor_notes: noted.include?(person_id)
        )

        # The shared strip's bonk chip is the latest bonk in ANY year; on this
        # page every other signal -- the sections, the Outcome filter, the
        # stat box -- is the viewed year's verdict, so the chip is re-pointed
        # at the same year to keep a row from contradicting itself (a 2024
        # bonk chip on someone the 2026 sections file under "passed"). Prior
        # bonks stay one row-expansion away in the detail frame's history.
        summary[:bonk] =
          if [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].include?(status)
            { year: year, status: status }
          end
      end

      summaries
    end

    # Everyone the intake teams touched during `year`, whatever their status:
    # a human-written note from one of the four teams or from a trainer, a
    # rank from any of the five, a raised Personnel flag, or a mentor verdict
    # of bonk or self-bonk. Backs /people/unified-flagging, which has no
    # upstream page. Not the pipeline roster, and only_flagged is off -- being
    # written about is what lists a person here, so a Personnel note on a
    # twenty-year Ranger lists them beside a Prospective's VC rank. Listed by
    # callsign, as that page reads them.
    #
    # Each summary also carries the viewed year's own facts, which the page's
    # filters and export read (the shared chips and gray line keep reading the
    # latest-to-date ones, as on every pipeline page): year_notes, year_ranks
    # and year_bonk -- see `year_facts_for`. They are read off the very rows the
    # summary is built from, and a person is listed only when they hold a fact,
    # so the roster cannot name what the line and the pane cannot show -- a
    # trainer's word on a session still ahead, or on one the person was since
    # removed from, lists no one.
    #
    # A training status answers a pipeline question, so it is nil for whoever
    # neither had a session that year nor was in its pipeline -- see
    # `clear_training_status_outside_pipeline`.
    #
    # `person_ids` limits every query to those people, for a review pane that
    # asks about one. Only the five person columns the page, the pane, the
    # filters and the export read are loaded; the row carries some eighty.
    def retrieve_recorded_for_year(year, person_ids: nil)
      ids = recorded_candidate_ids(year, person_ids)
      people = Person.where(id: ids).select(:id, :callsign, :first_name, :last_name, :status)

      summaries = summaries_for(people, year, only_flagged: false) do |summary, inputs|
        summary.merge!(year_facts_for(year, **inputs))
      end
      summaries.select! { |summary| summary[:year_notes].any? || summary[:year_ranks].any? || summary[:year_bonk] }
      clear_training_status_outside_pipeline(summaries, year)

      summaries.sort_by { |summary| summary[:person].callsign.to_s.downcase }
    end

    # The same summaries for the Mentors' bulk conversion page: Prospectives
    # who passed a `year` training session. ProspectiveConversion owns who
    # qualifies -- it is also what the conversion itself re-checks against.
    #
    # `keep_ids` holds on the page people who no longer qualify: the
    # just-converted Alphas, which the convert action shows one last time so a
    # mentor can see what their click did.
    def retrieve_trained_prospectives(year, keep_ids: [])
      ids = ProspectiveConversion.eligible_ids(year) | keep_ids

      summaries_for(Person.where(id: ids), year, only_flagged: false)
    end

    # Build the intake history for a single person, for years <= `year`.
    #
    # @param person [Person]
    # @param year [Integer]
    # @param rrn_only [Boolean] restrict to the RRN-only view (RRN team only,
    #   no trainings)
    # @return [Hash] {
    #   personnel_issue: Boolean,
    #   teams: { "personnel"|"rrn"|"vc"|"mentor" => [
    #     { year:, rank:, notes: [PersonIntakeNote, ...], have_notes: Boolean }, ...
    #   ] },
    #   trainings: [training OpenStruct rows from Training.retrieve_training_history_for_ids],
    #   pnv_history: [
    #     { year:, training_status:, mentor_status:, have_alpha_shift:,
    #       was_auditor:, personnel_issue:, passed_previously: }, ...
    #   ]
    # }
    def history_for_person(person, year, rrn_only: false)
      person_id = person.id
      team_types = rrn_only ? %w[rrn] : TEAM_TYPES

      intake_years = PersonIntake.where(person_id: person_id).where(year: ..year).order(:year).to_a
      intake_notes = PersonIntakeNote.where(person_id: person_id).where(year: ..year).order(:created_at).to_a

      mentors = PersonMentor.retrieve_all_mentors_for_ids([person_id], position_id: Position::ALPHA)[person_id]
      trainings = rrn_only ? [] : (Training.retrieve_training_history_for_ids([person_id], Position::TRAINING, year)[person_id] || [])
      alpha_entries = Timesheet.retrieve_all_for_position_ids([person_id], Position::ALPHA)[person_id]
      alpha_signup_years = alpha_signup_years_for(person_id)
      taught_years = rrn_only ? [] : taught_years_for(person_id, year)
      statuses = PersonStatus.where(person_id: person_id, new_status: INTAKE_STATUSES)
                             .where("created_at < ?", Time.local(year + 1))
                             .order(:created_at)
                             .to_a

      pnv_history = {}
      apply_mentor_history(pnv_history, mentors, person_id, year, alpha_signup_years)
      apply_training_history(pnv_history, trainings, statuses, alpha_signup_years)
      personnel_issue = apply_personnel_flags(pnv_history, intake_years, year)
      apply_alpha_shifts(pnv_history, alpha_entries)
      apply_status_history(pnv_history, statuses)
      apply_taught_years(pnv_history, taught_years)

      {
        personnel_issue: personnel_issue,
        teams: team_types.index_with { |type| build_intake_team(type, intake_years, intake_notes) },
        trainings: trainings,
        pnv_history: finalize_pnv_history(pnv_history)
      }
    end

    # One intake team's year-by-year ranks and notes, ascending. Public
    # because it is a pure shaping function two features consume: this class
    # builds all four teams for the intake pages, and AlphaShiftRoster builds
    # the mentor team for the Alpha Schedule -- the same cross-class reuse
    # upstream has (Alpha.php calls Intake::buildIntakeTeam).
    #
    # A year appears if it carries a rank, a note, or both. `have_notes` is
    # false for a year whose only notes are audit-log entries.
    #
    # @param type [String] one of TEAM_TYPES
    # @param intake_years [Array<PersonIntake>]
    # @param intake_notes [Array<PersonIntakeNote>]
    # @return [Array<Hash>] [{ year:, rank:, notes:, have_notes: }, ...]
    def build_intake_team(type, intake_years, intake_notes)
      rank_attr = "#{type}_rank"
      team_years = {}

      intake_years.each do |r|
        rank = r.public_send(rank_attr)
        next unless rank

        team_years[r.year] = { rank: rank }
      end

      intake_notes.each do |note|
        next unless note.type == type

        year_entry = (team_years[note.year] ||= {})
        (year_entry[:notes] ||= []) << note
        year_entry[:have_notes] = true unless note.is_log
      end

      team_years.sort.map do |team_year, info|
        {
          year: team_year,
          rank: info[:rank],
          notes: info[:notes] || [],
          have_notes: info[:have_notes] || false
        }
      end
    end

    private

    # @param scope [ActiveRecord::Relation] the roster, loaded here so the
    #   caller's scope is resolved once rather than plucked and re-queried.
    # A caller that reads more off the same rows passes a block, which is
    # handed each summary with the rows it was built from, before the
    # only_flagged gate and the sort.
    def summaries_for(scope, year, only_flagged:)
      people = scope.includes(:person_fka).to_a
      return [] if people.empty?

      person_ids = people.map(&:id)
      intakes = PersonIntake.where(person_id: person_ids).where(year: ..year).order(:year).group_by(&:person_id)
      notes = PersonIntakeNote.where(person_id: person_ids, is_log: false)
                              .where(year: ..year).order(:created_at).group_by(&:person_id)
      mentorships = PersonMentor.retrieve_all_mentors_for_ids(person_ids, position_id: Position::ALPHA)
      trainings = Training.retrieve_training_history_for_ids(person_ids, Position::TRAINING, year)

      summaries = people.map do |person|
        inputs = { intakes: intakes[person.id] || [], notes: notes[person.id] || [],
                   mentorships: mentorships[person.id] || {}, trainings: trainings[person.id] || [] }
        summarize_person(person, year, **inputs).tap { |summary| yield summary, inputs if block_given? }
      end

      summaries.select! { |summary| summary[:flagged] } if only_flagged

      summaries.sort_by do |summary|
        [
          GROUP_ORDER.index(summary[:group]),
          # Only the Personnel group keeps the worst-first ordering; the other
          # two are alphabetical by deliberate upstream decision.
          summary[:group] == :personnel ? -summary[:severity_weight] : 0,
          summary[:person].callsign.to_s.downcase
        ]
      end
    end

    # Upstream's roster query, verbatim: whoever was *set to* Prospective or
    # Alpha during the year. Not their standing status -- someone made
    # Prospective this year and since bonked still belongs to this year's
    # pipeline, and someone made Prospective years ago does not.
    def roster_ids_for_year(year)
      PersonStatus.where(new_status: PNV_STATUSES).where_year("created_at", year).distinct.pluck(:person_id)
    end

    # Who left the pipeline during the same year they entered it. Upstream
    # writes this as a NOT EXISTS correlated subquery; a second pluck over the
    # roster ids says the same thing in ActiveRecord.
    def washed_out_ids(ids, year)
      PersonStatus.where(person_id: ids, new_status: WASHED_OUT_STATUSES)
                  .where_year("created_at", year).distinct.pluck(:person_id)
    end

    # One collapsed row's worth of data.
    #
    # @return [Hash] {
    #   person:, group: :personnel|:flagged|:other, severity_weight: Integer,
    #   personnel_issue: Boolean, worst_rank: Integer|nil,
    #   ranks: [{ team: "vc"|..|"training", label:, year:, rank: }, ...] worst-first,
    #   training_status: "trained"|"not passed"|"pending"|"none",
    #   bonk: { year:, status: } | nil,
    #   note_teams: [{ team:, rank:, latest_at: }, ...]
    # }
    #
    # NOTE: `retrieve_post_season_class` merges five extra viewed-year keys
    # into these hashes for /mentoring/post-season-summary alone --
    # mentor_status, mentors, signed_up, mentor_rank, mentor_notes -- and
    # `retrieve_recorded_for_year` three for /people/unified-flagging alone --
    # year_notes, year_ranks, year_bonk -- where training_status may also be
    # nil. A new key added here must not reuse one of those names, or that
    # page will silently shadow it.
    def summarize_person(person, year, intakes:, notes:, mentorships:, trainings:)
      team_ranks = latest_team_ranks(intakes)
      all_ranks = build_rank_strip(team_ranks, latest_training_rank(trainings))
      worst_rank = all_ranks.map { |entry| entry[:rank] }.max_by { |rank| RANK_SEVERITY[rank] || 0 }
      personnel_issue = intakes.any? { |row| row.year == year && row.personnel_rank == FLAG }
      bonk = latest_bonk(mentorships)

      {
        person: person,
        flagged: adverse_mark?(intakes: intakes, trainings: trainings, bonk: bonk),
        group: display_group(personnel_issue, worst_rank, bonk, person.status == Person::UBERBONKED),
        severity_weight: personnel_issue ? 100 : (RANK_SEVERITY[worst_rank] || 0),
        personnel_issue: personnel_issue,
        worst_rank: worst_rank,
        ranks: visible_ranks(all_ranks, personnel_issue),
        training_status: training_status_for_year(trainings, year),
        bonk: bonk,
        note_teams: summarize_note_teams(notes, team_ranks)
      }
    end

    # Upstream's _has_flag: does this person carry any adverse mark ANYWHERE in
    # their history? Deliberately unlike `display_group`, which re-partitions
    # the flagged set by each team's LATEST rank -- which is why upstream's
    # third section means "was flagged once, looks calm now" rather than
    # "everyone else in the pipeline".
    def adverse_mark?(intakes:, trainings:, bonk:)
      return true if bonk
      return true if intakes.any? { |row|
        TEAM_TYPES.any? { |type| (row.public_send("#{type}_rank") || 0) >= BELOW_AVERAGE }
      }

      # Deliberately not restricted to ended sessions: a rank recorded against
      # a session still in progress is already a signal worth surfacing.
      trainings.any? { |training| training.training_rank.to_i >= BELOW_AVERAGE }
    end

    def display_group(personnel_issue, worst_rank, bonk, uberbonked)
      return :personnel if personnel_issue
      # Self-bonks and uber-bonks count here, unlike upstream: the row's lead
      # chip shows either in red (IntakeHelper#intake_lead_kind), so leaving
      # them out of this group put a red-chipped person in "Other Potential
      # Alphas", the group of people whose latest ranks are calm.
      return :flagged if [BELOW_AVERAGE, FLAG].include?(worst_rank) || bonk || uberbonked

      :other
    end

    # Latest ranked year per team, for years <= the page year.
    def latest_team_ranks(intakes)
      TEAM_TYPES.index_with do |type|
        row = intakes.reverse.find { |intake| intake.public_send("#{type}_rank") }
        row && { year: row.year, rank: row.public_send("#{type}_rank") }
      end.compact
    end

    # Latest ended-and-ranked training session, mirroring latestTraining in
    # port/utils/intake-summaries.js.
    def latest_training_rank(trainings)
      ranked = trainings.select { |training| training.slot_has_ended && training.training_rank.to_i.positive? }
      latest = ranked.max_by(&:slot_begins)
      latest && { year: latest.slot_year, rank: latest.training_rank }
    end

    # The row's lead chip already says a Personnel flag is raised, so a rank chip
    # repeating it is noise -- upstream dropped it too (@hidePersonnelFlag in
    # port/components/unified-flagging-row.hbs). Dropped only while the flag is
    # raised, so a flag from an earlier year still gets a chip of its own.
    def visible_ranks(ranks, personnel_issue)
      return ranks unless personnel_issue

      ranks.reject { |entry| entry[:team] == "personnel" && entry[:rank] == FLAG }
    end

    def build_rank_strip(team_ranks, training)
      entries = team_ranks.map { |type, info| info.merge(team: type) }
      entries << training.merge(team: "training") if training
      entries.sort_by { |entry| [-(RANK_SEVERITY[entry[:rank]] || 0), TEAM_ORDER.index(entry[:team])] }
    end

    # Most recent bonk or self-bonk, in any year. Not clipped to the page year:
    # upstream's mentor lookup ignores the year entirely, and a bonk is what
    # decides both the flag and the row's group -- clipping it silently moved
    # people into "Other potential Alphas" on historical views.
    def latest_bonk(mentorships)
      bonked = mentorships.select do |_mentor_year, mentorship|
        [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].include?(mentorship[:status])
      end
      return nil if bonked.empty?

      mentor_year, mentorship = bonked.max_by { |mentor_year, _| mentor_year }
      { year: mentor_year, status: mentorship[:status] }
    end

    # Upstream collapses an ended-but-failed training into "training pending";
    # "not passed" is called out separately here so a failed session is not
    # mistaken for one still to come. It means anything but a pass: a no-show,
    # a not-passed and a session no one scored all read "not passed".
    def training_status_for_year(trainings, year)
      this_year = trainings.select { |training| training.slot_year == year }
      return "none" if this_year.empty?

      ended = this_year.select(&:slot_has_ended)
      return "pending" if ended.empty?
      return "trained" if ended.any?(&:training_passed)

      "not passed"
    end

    # Teams with at least one human-written note, carrying the latest note's
    # timestamp so the collapsed row can answer "is there anything new here?"
    # without expanding. Upstream hid pills for Normal/unranked teams; they are
    # kept (badged quietly) so the row never conceals that notes exist.
    def summarize_note_teams(notes, team_ranks)
      notes.group_by(&:type).filter_map do |type, rows|
        next unless TEAM_TYPES.include?(type)

        # filter_map: created_at is nullable, and max_by would raise comparing nil.
        { team: type, rank: team_ranks.dig(type, :rank), latest_at: rows.filter_map(&:created_at).max }
      end.sort_by { |entry| TEAM_TYPES.index(entry[:team]) }
    end

    def alpha_signup_years_for(person_id)
      PersonSlot.joins(:slot)
                .where(person_id: person_id, slot: { position_id: Position::ALPHA })
                .pluck("slot.begins_year")
                .to_set
    end

    # Years the person taught an In-Person Training session, by the same
    # definition TrainerStatus.taught? uses: signed up on one of the Trainer
    # positions and marked attended, on an active slot.
    def taught_years_for(person_id, year)
      Slot.active
          .joins(:trainer_status)
          .where(position_id: Position::TRAINERS[Position::TRAINING], begins_year: ..year)
          .where(trainer_status: { person_id: person_id, status: TrainerStatus::STATUS_ATTENDED })
          .distinct
          .pluck(:begins_year)
    end

    # Who, of `person_ids`, signed up for an Alpha shift in `year` -- upstream's
    # `alpha_slots` reduced to the boolean the post-season page asks of it.
    # The bulk twin of `alpha_signup_years_for` above, which answers the
    # every-year question for one person on their own page.
    def alpha_signup_ids_for_year(person_ids, year)
      PersonSlot.joins(:slot)
                .where(person_id: person_ids, slot: { position_id: Position::ALPHA, begins_year: year })
                .distinct
                .pluck(:person_id)
                .to_set
    end

    # Who might hold a fact for `year`: anyone with a note, an intake row, a
    # bonk or self-bonk row, or a trainer's rank or note on one of the year's
    # sessions. Loose on purpose -- `year_facts_for` decides, from the rows the
    # page shows, who actually does.
    def recorded_candidate_ids(year, person_ids)
      sessions = Slot.where(position_id: Position::TRAINING, begins_year: year).select(:id)

      [
        PersonIntakeNote.where(year:, is_log: false),
        PersonIntake.where(year:),
        PersonMentor.where(mentor_year: year, position_id: Position::ALPHA,
                           status: [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK]),
        TraineeStatus.where(slot_id: sessions).where.not(rank: [nil, 0]),
        TraineeNote.where(slot_id: sessions, is_log: false)
      ].flat_map { |relation| only_people(relation, person_ids).distinct.pluck(:person_id) }.uniq
    end

    # `relation` limited to `person_ids` when the caller asks about only those.
    def only_people(relation, person_ids)
      person_ids ? relation.where(person_id: person_ids) : relation
    end

    # The viewed year's facts for one person, read off the rows
    # summarize_person reads, so they claim nothing the pane cannot open:
    #   year_notes: [{ team:, latest_at: }, ...] in TEAM_ORDER -- the four
    #               teams' notes filed for the year and, as Training, the
    #               trainer's notes on the year's sessions that have ended
    #               (the pane shows them only then). latest_at is nil when
    #               no note carries a timestamp; the team still counts.
    #   year_ranks: { team => [rank, ...] } -- an intake team's rank for the
    #               year, and one per ranked session that has ended, in
    #               session order: a retake year has two.
    #   year_bonk:  the year's mentor verdict when it is a bonk or self-bonk --
    #               PersonMentor.year_verdict of the year's rows, the verdict
    #               the pane's history and the bonk chip read too.
    def year_facts_for(year, intakes:, notes:, mentorships:, trainings:)
      sessions = trainings.select { |training| training.slot_year == year && training.slot_has_ended }
                          .sort_by(&:slot_begins)
      by_team = notes.select { |note| note.year == year }.group_by(&:type)
      trainer_notes = sessions.flat_map { |training| (training.training_notes || []).reject(&:is_log) }
      by_team["training"] = trainer_notes if trainer_notes.any?

      intake = intakes.find { |row| row.year == year }
      ranks = {}
      TEAM_TYPES.each do |team|
        rank = intake&.public_send("#{team}_rank")
        ranks[team] = [rank] if rank
      end
      session_ranks = sessions.map { |training| training.training_rank.to_i }.select(&:positive?)
      ranks["training"] = session_ranks if session_ranks.any?

      verdict = mentorships.dig(year, :status)

      {
        year_notes: TEAM_ORDER.filter_map do |team|
          { team:, latest_at: by_team[team].filter_map(&:created_at).max } if by_team[team]
        end,
        year_ranks: ranks,
        year_bonk: (verdict if [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].include?(verdict))
      }
    end

    # A training status answers a pipeline question. For whoever had no
    # session in `year` (their status is "none") and was not in its intake
    # pipeline -- set to Auditor, Prospective or Alpha during it, or holding
    # one of those now -- it becomes nil: a Ranger listed for a Personnel note
    # owes no sign-up, and "No training sign-up" in red would read as a mark.
    def clear_training_status_outside_pipeline(summaries, year)
      unsessioned = summaries.select { |summary| summary[:training_status] == "none" }
      return if unsessioned.empty?

      pipeline = PersonStatus.where(person_id: unsessioned.map { |summary| summary[:person].id },
                                    new_status: INTAKE_STATUSES)
                             .where_year("created_at", year).distinct.pluck(:person_id).to_set
      unsessioned.each do |summary|
        person = summary[:person]
        next if pipeline.include?(person.id) || INTAKE_STATUSES.include?(person.status)

        summary[:training_status] = nil
      end
    end

    def apply_mentor_history(pnv_history, mentors, person_id, year, alpha_signup_years)
      return if mentors.blank?

      mentors.each do |mentor_year, mentorship|
        pnv_history[mentor_year] = {
          training_status: "none",
          mentor_status: mentorship[:status] || "none",
          # Upstream bug (Intake.php applyMentorHistory): checks the person's
          # id against the *set of years* they have an alpha signup in,
          # instead of checking whether `mentor_year` is in that set. Kept
          # faithful to upstream -- applyAlphaShifts (real timesheet data,
          # below) is what actually drives this column for worked shifts.
          have_alpha_shift: mentor_year == year && alpha_signup_years.include?(person_id)
        }
      end
    end

    def apply_training_history(pnv_history, trainings, statuses, alpha_signup_years)
      return if trainings.blank?

      trainings.each do |training|
        train_year = training.slot_year
        is_new = !pnv_history.key?(train_year)
        entry = ensure_history_year(pnv_history, train_year)

        entry[:was_auditor] = true if is_new && was_auditor_in_year?(statuses, train_year)

        # training_status only ever advances toward "pass" -- once a person
        # has passed, a later/duplicate training row must not downgrade it.
        if entry[:training_status] != "pass"
          entry[:training_status] = if training.slot_has_ended
                                       training.training_passed ? "pass" : "no pass"
                                    else
                                       "pending"
                                    end
        end

        entry[:have_alpha_shift] ||= alpha_signup_years.include?(train_year)
      end
    end

    def apply_personnel_flags(pnv_history, intake_years, year)
      personnel_issue = false

      intake_years.each do |r|
        next unless r.personnel_rank == FLAG

        personnel_issue = true if r.year == year
        ensure_history_year(pnv_history, r.year)[:personnel_issue] = true
      end

      personnel_issue
    end

    def apply_alpha_shifts(pnv_history, alpha_entries)
      return if alpha_entries.blank?

      alpha_entries.each_key { |alpha_year| ensure_history_year(pnv_history, alpha_year)[:have_alpha_shift] = true }
    end

    def apply_status_history(pnv_history, statuses)
      return if statuses.blank?

      statuses.each do |status_row|
        history_year = status_row.created_at.year
        is_new = !pnv_history.key?(history_year)
        entry = ensure_history_year(pnv_history, history_year)
        entry[:was_auditor] = true if is_new && was_auditor_in_year?(statuses, history_year)
      end
    end

    # Teaching a session counts as being trained for the year (Training::PASS
    # is "passed or taught"), but it is shown as its own status so a trainer's
    # year is not read as a trainee pass. Applied last: a year the person also
    # attended as a trainee keeps that record, and no other column is touched.
    def apply_taught_years(pnv_history, taught_years)
      taught_years.each do |taught_year|
        entry = ensure_history_year(pnv_history, taught_year)
        entry[:training_status] = "taught" if [nil, "none"].include?(entry[:training_status])
      end
    end

    # Was the person an auditor as of `year` -- i.e. is AUDITOR the status
    # of the latest status-history row at or before `year`? Assumes `statuses`
    # is sorted ascending by created_at.
    def was_auditor_in_year?(statuses, year)
      latest = statuses.take_while { |s| s.created_at.year <= year }.last
      latest.present? && latest.new_status == Person::AUDITOR
    end

    def ensure_history_year(pnv_history, year)
      pnv_history[year] ||= {}
    end

    # Normalize every touched year to the full pnv_history shape, sort
    # ascending, and compute passed_previously. Mirrors the Ember route walk
    # (port/unified-flagging-route.js setupController): passedPreviously is only
    # ever assigned on non-"pass" years, so a year whose mentor_status is "pass"
    # always renders via its own badge -- never as "active status" -- even when
    # the person also passed in an earlier year.
    def finalize_pnv_history(pnv_history)
      passed_seen = false

      pnv_history.sort.map do |year, entry|
        is_pass = entry[:mentor_status] == PersonMentor::STATUS_PASS
        row = {
          year: year,
          training_status: entry[:training_status] || "none",
          mentor_status: entry[:mentor_status] || "none",
          have_alpha_shift: entry[:have_alpha_shift] || false,
          was_auditor: entry[:was_auditor] || false,
          personnel_issue: entry[:personnel_issue] || false,
          passed_previously: !is_pass && passed_seen
        }

        passed_seen = true if is_pass

        row
      end
    end
  end
end
