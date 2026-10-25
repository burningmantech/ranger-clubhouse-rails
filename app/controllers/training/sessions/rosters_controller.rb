# frozen_string_literal: true

# Adding and removing people on the session's rosters (trainees, and
# trainers via their matched trainer slots). All writes go through
# Scheduling::Signup so capacity, requirement, and multiple-enrollment rules
# hold; blocked verdicts come back in the dialog with a force option --
# trainers and admins may override, exactly the upstream shiftManage flow.
class Training::Sessions::RostersController < Training::Sessions::BaseController
  before_action :authorize_roster_adjustment

  KINDS = %w[trainee trainer].freeze

  # Statuses the add-person search never surfaces (upstream person/search
  # exclude_statuses), and so create refuses.
  EXCLUDED_SEARCH_STATUSES = [
    Person::DECEASED, Person::DISMISSED, Person::BONKED, Person::RETIRED, Person::UBERBONKED
  ].freeze
  SEARCH_LIMIT = 10

  # The search dialog. Re-rendered into the modal frame by its own GET form
  # each time the query changes.
  def new
    @kind = kind_param
    @query = params[:q].to_s.strip
    @results = search_people if @query.length >= PersonSearch::MIN_QUERY_LENGTH
    if @kind == "trainer"
      @trainer_slot_id = params[:trainer_slot_id].presence&.to_i ||
                         @training_session.trainer_groups.first&.slot&.id
    end
  end

  def create
    person = Person.find_by(id: params[:person_id])
    slot = target_slot
    unless person && slot
      return render turbo_stream: [
        ui_toast_stream("Unable to determine the person or slot to add.", :error),
        modal_close_dialog
      ]
    end

    # Ahead of Scheduling::Signup, as on the Alpha roster: the dialog never
    # offers these people, and a status is not a verdict "Add Anyway" can force.
    if EXCLUDED_SEARCH_STATUSES.include?(person.status)
      return redirect_to session_return_path,
                         error: "#{person.callsign} is #{person.status}, so they cannot be added to a training session."
    end

    result = Scheduling::Signup.add(person, slot, params[:force] == "1")

    case (verdict = result.verdict)
    when Scheduling::Verdict::Accepted
      redirect_to session_return_path,
                  success: "#{person.callsign} added to the session."
    when Scheduling::Verdict::AlreadyExists
      redirect_to session_return_path,
                  warning: "#{person.callsign} is already signed up."
    else
      update_modal("training/sessions/rosters/blocked",
                   { person:, slot:, kind: kind_param, verdict:, status: result.status })
    end
  end

  def destroy
    person = Person.find_by(id: params[:person_id])
    slot = target_slot
    unless person && slot
      return redirect_to session_return_path, error: "Unable to determine who to remove."
    end

    # want_to_force: trainers may pull people after the session has started
    # (scoring happens during and after the day); Signup still decides.
    result = Scheduling::Signup.remove(person, slot, true)

    case (verdict = result.verdict)
    when Scheduling::Verdict::Removed
      redirect_to session_return_path,
                  success: "#{person.callsign} removed from the session."
    when Scheduling::Verdict::OutsideWindow
      redirect_to session_return_path,
                  error: "The session has #{verdict.ended ? "ended" : "started"} and #{person.callsign} could not be removed."
    when Scheduling::Verdict::MissingSignup
      redirect_to session_return_path, error: "#{person.callsign} is not signed up."
    else
      redirect_to session_return_path, error: "The removal failed [#{result.status}]."
    end
  end

  private

  # PersonSearch owns matching (phonetic callsigns, FKAs, names) and the
  # email-visibility gate -- email hits only for viewers the rest of the app
  # lets read addresses.
  def search_people
    groups = PersonSearch.execute(
      {
        query: @query,
        search_fields: "callsign,fka,name,last",
        exclude_statuses: EXCLUDED_SEARCH_STATUSES,
        limit: SEARCH_LIMIT
      },
      can_view_email: Current.can_view_email?
    )
    groups.flat_map { |group| group[:people] }.uniq.first(SEARCH_LIMIT)
  end

  def kind_param
    KINDS.include?(params[:kind]) ? params[:kind] : "trainee"
  end

  # Trainees join the session slot itself; trainers join one of the matched
  # trainer group slots -- never an arbitrary slot id from the request.
  def target_slot
    return @training_session.slot if kind_param == "trainee"

    wanted = params[:trainer_slot_id].to_i
    group = @training_session.trainer_groups.find { |g| g.slot.id == wanted } ||
            @training_session.trainer_groups.first
    group&.slot
  end
end
