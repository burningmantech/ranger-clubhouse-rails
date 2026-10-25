# frozen_string_literal: true

# Adding and removing sign-ups on one Alpha shift. Writes go through
# Scheduling::Signup so capacity, position, and multiple-enrollment rules
# hold; blocked verdicts come back in the dialog with a force option, which
# Mentors hold for Alpha slots (Scheduling::Signup.can_force_schedule_change).
#
# One rule is stricter than upstream by decree: only Alpha and Prospective
# accounts may be added. Upstream states it in the dialog and never checks,
# so a Ranger searched up by name could be signed onto a mentee shift. Here
# the check runs server-side and force does not bypass it -- forcing is for
# capacity and window rules, not for who belongs on an Alpha shift.
class Mentoring::AlphaSchedule::RostersController < Mentoring::AlphaSchedule::BaseController
  before_action :load_slot

  # Statuses the search never surfaces (upstream person/search
  # exclude_statuses for this page, which adds past prospective to the usual
  # five -- someone who already left the pipeline is not coming back onto a
  # shift).
  EXCLUDED_SEARCH_STATUSES = [
    Person::DECEASED, Person::DISMISSED, Person::BONKED, Person::RETIRED,
    Person::UBERBONKED, Person::PAST_PROSPECTIVE
  ].freeze

  SEARCH_LIMIT = 10

  # The search dialog, re-rendered into the modal frame by its own GET form
  # each time the query changes.
  def new
    @query = params[:q].to_s.strip
    @results = search_people if @query.length >= PersonSearch::MIN_QUERY_LENGTH
  end

  def create
    person = Person.find_by(id: params[:person_id])
    unless person
      return render turbo_stream: [
        ui_toast_stream("Unable to determine who to add.", :error),
        modal_close_dialog
      ]
    end

    # Ahead of Scheduling::Signup on purpose: an ineligible status is not a
    # scheduling verdict and must not reach the force path.
    unless AlphaShiftRoster.addable?(person)
      return redirect_to shift_path,
                         error: "#{person.callsign} is #{person.status}. Only Alpha and Prospective accounts may be added to an Alpha shift."
    end

    result = Scheduling::Signup.add(person, @slot, params[:force] == "1")

    case (verdict = result.verdict)
    when Scheduling::Verdict::Accepted
      redirect_to shift_path, success: "#{person.callsign} added to the shift."
    when Scheduling::Verdict::AlreadyExists
      redirect_to shift_path, warning: "#{person.callsign} is already signed up."
    else
      update_modal("mentoring/alpha_schedule/rosters/blocked",
                   { person:, verdict:, status: result.status })
    end
  end

  def destroy
    person = Person.find_by(id: params[:person_id])
    return redirect_to shift_path, error: "Unable to determine who to remove." unless person

    # want_to_force: mentors adjust rosters during the shift itself, so a
    # started shift must not freeze the roster. Signup still decides.
    result = Scheduling::Signup.remove(person, @slot, true)

    case (verdict = result.verdict)
    when Scheduling::Verdict::Removed
      redirect_to shift_path, success: "#{person.callsign} removed from the shift."
    when Scheduling::Verdict::OutsideWindow
      redirect_to shift_path,
                  error: "The shift has #{verdict.ended ? "ended" : "started"} and #{person.callsign} could not be removed."
    when Scheduling::Verdict::MissingSignup
      redirect_to shift_path, error: "#{person.callsign} is not signed up for this shift."
    else
      redirect_to shift_path, error: "The removal failed [#{result.status}]."
    end
  end

  private

  # Mutations respond to turbo form submissions; re-rendering the dialog with
  # the page's "modal" frame updated is the standard failure path. Lives here
  # rather than on the shell base because only this controller mutates -- the
  # same shape Training::Sessions::BaseController uses.
  def update_modal(partial, locals)
    render turbo_stream: turbo_stream.update("modal", partial:, locals:),
           status: :unprocessable_entity
  end

  def shift_path
    mentoring_alpha_schedule_shift_path(@slot)
  end

  # PersonSearch owns matching (phonetic callsigns, FKAs, names) and the
  # email-visibility gate -- email hits only for viewers the rest of the app
  # lets read addresses.
  def search_people
    groups = PersonSearch.execute(
      {
        query: @query,
        search_fields: "callsign,fka,name,last,email",
        exclude_statuses: EXCLUDED_SEARCH_STATUSES,
        limit: SEARCH_LIMIT
      },
      can_view_email: Current.can_view_email?
    )
    groups.flat_map { |group| group[:people] }.uniq.first(SEARCH_LIMIT)
  end
end
