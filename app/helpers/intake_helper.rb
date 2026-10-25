# frozen_string_literal: true

# View helpers for the Unified Flagging (intake) page: per-team display
# metadata, rank badges (port/components/intake-ranking.hbs), and the
# training/mentee status badges ported from
# port/helpers/{training-status-badge,training-pass-badge,mentee-status-badge}.js.
module IntakeHelper
  # Keyed in Intake::TEAM_ORDER, so a select built from these keys lists the
  # teams in the order a row does.
  TEAM_META = {
    "personnel" => { label: "Personnel", icon: "user-tie" },
    "rrn" => { label: "RRN", icon: "globe" },
    "vc" => { label: "VC", icon: "user-group" },
    # Training has no PersonIntakeNote stream of its own -- it appears only as
    # a rank and a read-only note group.
    "training" => { label: "Training", icon: "chalkboard-user" },
    # Section headings read as a team ("Mentors"); the pipeline-page chips read
    # as one person's standing with that team ("Mentor 2026").
    "mentor" => { label: "Mentors", chip_label: "Mentor", icon: "handshake" }
  }.freeze

  # Ported from port/components/intake-note-edit.js rankingOptions.
  RANKING_OPTIONS = [
    ["No Ranking", ""],
    ["1 - Green (Above Average)", 1],
    ["2 - Normal (Average)", 2],
    ["3 - Yellow (Below Average)", 3],
    ["4 - FLAG", 4]
  ].freeze

  # Ported from port/components/intake-note-edit.js personnelRankingOptions --
  # only the option-4 label differs (personnel FLAGs alert other teams).
  PERSONNEL_RANKING_OPTIONS = [
    ["No Ranking", ""],
    ["1 - Green (Above Average)", 1],
    ["2 - Normal (Average)", 2],
    ["3 - Yellow (Below Average)", 3],
    ["4 - FLAG (will alert other teams)", 4]
  ].freeze

  # Colors/icons ported from port/components/intake-ranking.hbs. Rank 4 uses
  # :error (there is no ui_badge "dark"/"neutral" variant to port the
  # upstream UiBadge @type="dark" literally) since it is the most severe rank
  # and error is the closest existing semantic token -- no new color added.
  RANK_BADGE = {
    1 => { label: "Rank 1/Green", variant: :success, icon: "award", icon_type: :solid },
    2 => { label: "Rank 2/Normal", variant: :secondary },
    3 => { label: "Rank 3/Yellow", variant: :warning, icon: "bell", icon_type: :regular },
    4 => { label: "Rank 4/FLAG", variant: :error, icon: "flag", icon_type: :solid }
  }.freeze

  # Ported from port/helpers/training-status-badge.js. Upstream's "pending"
  # maps to a badge type not offered by ui_badge (:info); mapped to :warning
  # instead, matching how PersonMentor::STATUS_PENDING is already badged
  # elsewhere (see MentorHelper::MENTOR_STATUS).
  TRAINING_STATUS_BADGE = {
    "none" => { label: "no training sign-up", variant: :secondary },
    "no pass" => { label: "training not passed", variant: :error },
    "pass" => { label: "training passed", variant: :success },
    "taught" => { label: "taught training", variant: :success },
    "pending" => { label: "training pending", variant: :warning }
  }.freeze

  # Ported from port/helpers/mentee-status-badge.js MentorStatusLabels
  # (minus "none", handled separately below).
  MENTEE_STATUS_BADGE = {
    PersonMentor::STATUS_PENDING => { label: "verdict pending", variant: :secondary },
    PersonMentor::STATUS_PASS => { label: "mentor passed", variant: :success },
    PersonMentor::STATUS_BONK => { label: "mentor bonked", variant: :error },
    PersonMentor::STATUS_SELF_BONK => { label: "self-bonked", variant: :error }
  }.freeze

  # The training outcome on a pipeline row, ported from
  # port/components/{intake-chip,intake-rank-strip}.hbs. Every chip pairs its
  # colour with an icon and wording so nothing reads by colour alone. The
  # convert-prospectives table still draws the chip; the review lines and pane
  # write the outcome as a word on their gray line (intake_training_status_text), where
  # `text_class` is that word's tone and "trained" -- the expected state --
  # carries no colour at all.
  TRAINING_STATUS_CHIP = {
    "trained" => { label: "trained", variant: :success, icon: "check" },
    "not passed" => { label: "training not passed", variant: :error, icon: "xmark", text_class: "text-error" },
    "pending" => { label: "training pending", variant: :warning, icon: "hourglass-half", text_class: "text-warning" },
    "none" => { label: "no training sign-up", variant: :error, icon: "ban", text_class: "text-error" }
  }.freeze

  def intake_team_label(type)
    TEAM_META.dig(type, :label) || type.to_s.titleize
  end

  def intake_team_chip_label(type)
    TEAM_META.dig(type, :chip_label) || intake_team_label(type)
  end

  def intake_training_status_chip(status)
    info = TRAINING_STATUS_CHIP.fetch(status, TRAINING_STATUS_CHIP["none"])
    ui_badge(info[:label], info[:variant], icon: info[:icon])
  end

  # The training outcome as a word with an icon for the row's gray line:
  # "Trained" is the expected state and carries no colour; the exceptions keep
  # the chip's icon and tone so none of them rests on colour alone.
  def intake_training_status_text(status)
    info = TRAINING_STATUS_CHIP.fetch(status, TRAINING_STATUS_CHIP["none"])
    tag.span(class: class_names("whitespace-nowrap", info[:text_class])) do
      safe_join([fa_icon(info[:icon], :solid, end: 1), info[:label].upcase_first])
    end
  end

  # The most serious mark against a person, which is what the row's one
  # coloured chip shows: a raised Personnel flag, else an uber-bonk, else the
  # latest bonk, else a worst rank of 3 or 4. Read off Intake's own fields
  # (personnel_issue, bonk, worst_rank and the worst-first strip) rather than
  # re-derived, and Intake#display_group counts the same marks, so the chip and
  # the group agree. nil when the latest ranks are calm -- someone marked in an
  # earlier year, which is who the pipeline pages' third group holds.
  def intake_lead_kind(summary)
    return :personnel if summary[:personnel_issue]
    return :uberbonk if summary[:person].status == Person::UBERBONKED
    return :bonk if summary[:bonk]

    :rank if summary[:worst_rank].to_i >= Intake::BELOW_AVERAGE
  end

  def intake_lead_signal(summary)
    case intake_lead_kind(summary)
    when :personnel then ui_badge("Personnel flag", :error, icon: "flag")
    when :uberbonk then ui_badge("uber-bonked", :error, icon: "hand")
    when :bonk then intake_bonk_chip(summary[:bonk])
    when :rank then intake_rank_chip(summary[:ranks].first)
    end
  end

  # "RRN 4/FLAG (2024) · Training 1/Green (2023)": every latest rank in team
  # order, as text for the row's gray line. The strip itself stays worst-first,
  # which is what the lead chip and the convert-prospectives cell read.
  def intake_ranks_text(ranks)
    ranks.sort_by { |entry| Intake::TEAM_ORDER.index(entry[:team]) }.map do |entry|
      label = RANK_BADGE.dig(entry[:rank], :label)&.delete_prefix("Rank ") || entry[:rank]
      "#{intake_team_chip_label(entry[:team])} #{label} (#{entry[:year]})"
    end.join(" · ")
  end

  # "Personnel Jun 08, 2025 · VC Mar 20, 2025": which teams have written
  # something and how recently, in the team order Intake already gives them.
  # The date is what lets a coordinator skip opening the row. A team whose
  # notes carry no timestamp (the columns allow NULL) is named alone.
  def intake_notes_text(note_teams)
    note_teams.map { |entry| [intake_team_chip_label(entry[:team]), mdy_format(entry[:latest_at]).presence].compact.join(" ") }
              .join(" · ")
  end

  def intake_bonk_label(bonk)
    "#{bonk[:year]} #{bonk[:status] == PersonMentor::STATUS_SELF_BONK ? "self-bonked" : "mentor bonked"}"
  end

  def intake_bonk_chip(bonk)
    ui_badge(intake_bonk_label(bonk), :error, icon: "hand")
  end

  # One team's latest rank, e.g. "3/Yellow &middot; Training 2026".
  def intake_rank_chip(entry)
    team = "#{intake_team_chip_label(entry[:team])} #{entry[:year]}"
    info = RANK_BADGE[entry[:rank]]
    return ui_badge(team, :secondary) unless info

    ui_badge("#{info[:label].delete_prefix("Rank ")} · #{team}", info[:variant],
             icon: info[:icon], icon_type: info[:icon_type] || :solid)
  end

  # "This team has written something, and here is how recent it is" -- the date
  # is what lets a coordinator skip opening the row.
  def intake_note_pill(entry)
    ui_badge("#{intake_team_chip_label(entry[:team])} note · #{mdy_format(entry[:latest_at])}",
             RANK_BADGE.dig(entry[:rank], :variant) || :secondary,
             icon: "note-sticky", icon_type: :regular)
  end

  def intake_team_icon(type)
    TEAM_META.dig(type, :icon) || "note-sticky"
  end

  def intake_ranking_options(type)
    type == "personnel" ? PERSONNEL_RANKING_OPTIONS : RANKING_OPTIONS
  end

  def intake_rank_badge(rank)
    info = RANK_BADGE[rank]
    return ui_badge("No Rank", :secondary) unless info

    ui_badge(info[:label], info[:variant], icon: info[:icon], icon_type: info[:icon_type] || :solid)
  end

  def training_status_badge(status)
    info = TRAINING_STATUS_BADGE[status] || { label: status.to_s, variant: :warning }
    ui_badge(info[:label], info[:variant])
  end

  # The badge on one ended training session, read from its stored verdict. Only
  # a no-show has a word of its own; a session no one scored reads "training not
  # passed", as this page always has -- the person is still untrained.
  def training_pass_badge(status)
    return ui_badge("training no-show", :error) if status == TraineeStatus::STATUS_NO_SHOW

    training_status_badge(status == TraineeStatus::STATUS_PASSED ? "pass" : "no pass")
  end

  def mentee_status_badge(account_status, mentor_status, have_alpha_shift)
    return ui_badge("UBERBONKED", :error) if account_status == Person::UBERBONKED
    return "no alpha sign-up" unless have_alpha_shift
    return ui_badge("has alpha sign-up", :success) if mentor_status == "none"

    info = MENTEE_STATUS_BADGE[mentor_status] || { label: mentor_status.to_s, variant: :warning }
    ui_badge(info[:label], info[:variant])
  end

  # Max-by-year rank lookup for a single team's ascending {year:, rank:, ...}
  # array (as returned by Intake.history_for_person's :teams values) -- nil
  # rank entries are skipped so a later notes-only year doesn't shadow an
  # earlier year's actual rank.
  def latest_team_rank(team_notes)
    return nil if team_notes.blank?

    team_notes.reverse_each do |entry|
      return entry[:rank] if entry[:rank]
    end

    nil
  end

  # Client-side mirror of Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE
  # / check_intake_permissions!, for display purposes only (show/hide the
  # Edit/Delete/Add controls) -- the controller re-checks server-side
  # regardless. References the controller's own constant rather than
  # duplicating the role table.
  def can_write_intake_notes?(type)
    role = Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE.fetch(type, Role::INTAKE)
    has_role?([Role::ADMIN, role])
  end
end
