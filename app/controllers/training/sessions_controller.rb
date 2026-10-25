# frozen_string_literal: true

# The training interface landing page (Ember training/index) and the
# session management page reads (Ember training/session/index plus the
# signup-sheet and trainers-report print views).
class Training::SessionsController < Training::BaseController
  # How many blank walk-in entries to print. A count of blanks, not a
  # pagination constant -- the sheet lets CSS decide where pages break.
  SIGNUP_SHEET_WALK_IN_ROWS = 8

  # Deliberately NO trainees-per-page constant. Slicing the roster into fixed
  # pages and printing "Page N of M" cannot stay true: a block grows when a
  # long name wraps past its row budget, so the section spills onto an extra
  # physical sheet that repeats the same label and carries no masthead
  # (measured: 34 sign-ups at 12/page printed 4 sheets claiming "of 3", the
  # second one unlabelled). Instead every block carries `break-inside: avoid`
  # and the browser paginates; the table's running-head row repeats natively,
  # so each sheet identifies itself. A physical page count cannot be computed
  # server-side at all; the "Page N of M" footer comes from CSS counters in a
  # named @page rule's margin boxes, the way #trainers_report does it.

  before_action :load_session, only: [:show, :signup_sheet, :trainers_report]

  def index
    @upcoming_sessions, @past_sessions = Training::SessionList.execute(@training, @year)
  end

  def show
  end

  # Printable sign-up sheet: a signing block per trainee; ART sessions get
  # a walk-in section (dirt trainings forbid walk-ins). The print views render
  # chrome-free (a class-level `layout ..., only:` would REPLACE the
  # inherited "training" layout for every other action).
  def signup_sheet
    @walk_in_rows = SIGNUP_SHEET_WALK_IN_ROWS
    render layout: "print"
  end

  # Printable trainer's report: the roster banded by cohort -- dirt sessions
  # get Veterans / Binaries / Prospectives / Auditors, ART sessions get
  # Veterans / ART Prospectives / Auditors -- each band sorted years
  # descending then callsign, plus the teams legend and (dirt only) the
  # full-day contact callout for inactive/retired Rangers.
  def trainers_report
    @trainee_bands = trainee_bands
    @full_day_callsigns = full_day_callsigns
    @team_legend = @training_session.team_legend
    render layout: "print"
  end

  private

  # Ordered [label, trainees] bands; empty bands stay so the printed report
  # shows "(0)" states.
  def trainee_bands
    labels = if @training_session.art?
               ["Veterans", "ART Prospectives", "Auditors"]
             else
               ["Veterans", "Binaries", "Prospectives", "Auditors"]
             end
    bands = labels.index_with { [] }
    @training_session.trainees.each { |trainee| bands[band_label_for(trainee)] << trainee }
    bands.map { |label, trainees| [label, sort_for_report(trainees)] }
  end

  # Band precedence keeps the partition total -- every trainee lands in
  # exactly one band.
  def band_label_for(trainee)
    @training_session.art? ? art_band_label(trainee) : dirt_band_label(trainee)
  end

  # Auditor status wins over the position-derived prospective flag -- a
  # status-auditor holding no ART-trained position has BOTH set and must not
  # print as a prospective ART member (mirrors dirt_band_label's precedence).
  def art_band_label(trainee)
    return "Auditors" if trainee.is_auditor
    return "ART Prospectives" if trainee.is_art_prospective

    "Veterans"
  end

  # Binaries is the remainder (active with under two years) -- the precedence
  # means a non-active trainee with a year or less still falls to Binaries.
  def dirt_band_label(trainee)
    return "Auditors" if trainee.is_auditor
    return "Prospectives" if trainee.is_prospective

    trainee.years > 1 ? "Veterans" : "Binaries"
  end

  # The dirt callout contact list: inactive and retired sign-ups, callsigns
  # only (their emails stay on the roster detail lines).
  def full_day_callsigns
    return [] if @training_session.art?

    @training_session.trainees
                     .select { |trainee| trainee.is_inactive || trainee.is_retired }
                     .map { |trainee| trainee.person.callsign }
                     .sort_by(&:downcase)
  end

  def sort_for_report(trainees)
    trainees.sort_by { |t| [-t.years, t.person.callsign.downcase] }
  end
end
