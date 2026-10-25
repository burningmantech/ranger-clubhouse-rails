# frozen_string_literal: true

# The ART Current Mentees page (Ember training/:position_id/mentees). Slug
# resolution and the view gate come from the base controller -- upstream's
# TrainingPolicy::mentees wants ART_INTERFACE_BASE | position.id, which is this
# app's ART_TRAINER_BASE (the same 0x1000000 bit) and exactly what
# Training.view_roles already demands of an ART. So the inherited gate is the
# whole role check for reading; revoking layers on can_graduate?, which is
# byte-for-byte upstream's revokeMenteePositions rule.
#
# Not year-scoped: the report is current standing, and upstream takes no year.
class Training::MenteesController < Training::BaseController
  include CsvExportConcern

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER
  # How stale a grant has to be before the rangering filter calls it out. Last
  # year still counts as current -- the event has only just happened.
  STALE_AFTER_YEARS = 2

  REVOKE_REASON = "ART mentee position revoke"
  RESTORE_REASON = "ART mentee position revoke undone"

  before_action :require_mentee_training
  before_action :authorize_graduation, only: %i[destroy restore]

  def index
    @report = Training::MenteesReport.execute(@training)
    @filter_params = filter_params
    @people = filtered(@report.people)
    @status_counts = @report.people.group_by(&:status).transform_values(&:size)
    @never_count = @report.people.count(&:never_rangered?)
    @stale_count = @report.people.count { |mentee| stale?(mentee) }

    respond_to do |format|
      format.html
      # The export is the whole report, not the current view -- the filters
      # narrow the page to work through, the CSV is the record of the roster.
      format.csv { send_csv(csv_rows, filename: "#{training_slug}-current-mentees.csv") }
    end
  end

  # Revoke every mentee position this training grants, upstream's all-at-once
  # behavior: the mentorship ends as a whole, not one position at a time.
  # PersonPosition.remove_ids_from_person writes the ActionLog, closes the open
  # person_position_log rows, and drops future sign-ups for the positions.
  def destroy
    person = mentee_person
    unless person
      redirect_to training_mentees_path(training_slug),
                  error: "That person does not hold any #{@training.title} mentee positions."
      return
    end

    # Captured BEFORE the delete: the replacement row keeps showing the grant
    # years, which are the record of what was just revoked. Re-reading after
    # would render a row of "Not granted".
    @mentee = Training::MenteesReport.execute(@training, only: [person.id]).people.first

    PersonPosition.remove_ids_from_person(person.id, mentee_position_ids, REVOKE_REASON)

    respond_to do |format|
      format.turbo_stream
      # Non-Turbo fallback: the whole roster, re-read.
      format.html do
        redirect_to training_mentees_path(training_slug),
                    success: "#{person.callsign}'s mentee positions revoked."
      end
    end
  end

  # Undo a mis-clicked revoke. This RE-GRANTS rather than resurrecting the
  # closed person_position_log rows: the revoke happened, and the audit trail
  # keeps saying so. The restored grant is therefore dated today, which is why
  # the button only stands in for the row that was just revoked -- it is an
  # undo, not a way to rewrite history.
  def restore
    person = Person.find_by(id: params[:person_id])
    position_ids = restorable_position_ids

    if person.nil? || position_ids.empty?
      redirect_to training_mentees_path(training_slug),
                  error: "There are no #{@training.title} mentee positions to restore."
      return
    end

    PersonPosition.add_ids_to_person(person.id, position_ids, RESTORE_REASON)

    @mentee = Training::MenteesReport.execute(@training, only: [person.id]).people.first

    respond_to do |format|
      format.turbo_stream
      format.html do
        redirect_to training_mentees_path(training_slug),
                    success: "#{person.callsign}'s mentee positions restored."
      end
    end
  rescue AuthorizationError => e
    redirect_to training_mentees_path(training_slug), error: e.message
  end

  private

  # What the revoked row said was taken, narrowed to this training's own mentee
  # positions. The ids arrive from the client, so the intersection is what stops
  # a hand-edited request from granting an arbitrary position.
  def restorable_position_ids
    IdList.parse(params[:position_ids]) & mentee_position_ids
  end

  # In-Person has no mentee positions and neither does every ART -- Sandman
  # graduates straight to Sandman. Upstream hides the sidebar link on the same
  # condition and its report returns an empty response; this catches the typed
  # URL. The menu item uses Training.has_mentees? too, so the two cannot drift.
  def require_mentee_training
    return if Training.has_mentees?(@training)

    redirect_to training_path(training_slug),
                error: "#{@training.title} does not have mentee positions."
  end

  def mentee_position_ids
    @mentee_position_ids ||= Training.mentee_position_ids(@training)
  end

  # Only someone who actually holds one of the positions may be revoked, so a
  # hand-typed person id cannot strip positions from an arbitrary account.
  def mentee_person
    Person.joins(:person_position)
          .where(person_position: { position_id: mentee_position_ids })
          .find_by(id: params[:person_id])
  end

  def filter_params
    { status: params[:status].presence || ALL_FILTER,
      rangering: params[:rangering].presence || ALL_FILTER,
      callsign: params[:callsign].to_s.strip }
  end

  # In memory: the report is already a small array, and re-querying would have
  # to re-derive the whole thing.
  def filtered(people)
    status = @filter_params[:status]
    rangering = @filter_params[:rangering]
    callsign = @filter_params[:callsign].downcase

    people.select do |mentee|
      (status == ALL_FILTER || mentee.status == status) &&
        matches_rangering?(mentee, rangering) &&
        (callsign.blank? || mentee.callsign.downcase.include?(callsign))
    end
  end

  def matches_rangering?(mentee, rangering)
    case rangering
    when "never" then mentee.never_rangered?
    when "stale" then stale?(mentee)
    else true
    end
  end

  # Stale means they DID range a mentee position, but not for a couple of
  # seasons. Disjoint from never-rangered on purpose: the two counts describe
  # different people, and a filter that returned both would answer neither
  # question cleanly.
  def stale?(mentee)
    year = mentee.last_rangered_year
    year.present? && year <= Current.year - STALE_AFTER_YEARS
  end

  # Two columns per position, matching upstream's export shape. "Rangered"
  # replaces upstream's "Last Worked" -- nothing downstream reads this file.
  def csv_rows
    header = ["Callsign", "Status"]
    @report.positions.each do |position|
      header << "#{position.title} Granted" << "#{position.title} Last Rangered"
    end

    @report.people.each_with_object([header]) do |mentee, rows|
      row = [mentee.callsign, mentee.status]
      mentee.grants.each do |grant|
        row << (grant.granted? ? (grant.granted_year || "unknown") : "not granted")
        row << (grant.last_rangered_year || "never")
      end
      rows << row
    end
  end
end
