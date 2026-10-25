# frozen_string_literal: true

# Add/edit/delete per-team intake notes and rank changes for a single PNV.
# Ported from IntakeController::appendNote/updateNote/deleteNote
# (port/api/IntakeController.php). The class-level gate below is the outer
# "could this person conceivably write ANY team's note" check; the actual
# per-team write permission is enforced by check_intake_permissions!, which
# mirrors IntakeController::checkIntakePermissions.
class Person::IntakeNotesController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_role [Role::ADMIN, Role::INTAKE, Role::REGIONAL_MANAGEMENT, Role::VC, Role::MENTOR],
                 message: "You are not authorized to manage intake notes."

  PERMISSION_ROLE_FOR_TYPE = {
    "vc" => Role::VC,
    "mentor" => Role::MENTOR,
    "personnel" => Role::ADMIN,
    "rrn" => Role::REGIONAL_MANAGEMENT
  }.freeze

  # The pipeline pages a note can be filed from: what the form's "back to"
  # control calls each, which route helper leads back, whether that page is
  # year-scoped (year-scoped pages get origin_year back as ?year= so the
  # reader returns to the season they were reviewing), and whether it selects
  # a person. A review-pane page (`selects`) takes the person back as
  # ?person=, which fills its pane and scrolls to the line; the Convert
  # Prospectives table takes a #person-N anchor, which lands beside the row on
  # a link visit but is dropped after a form submission (design-layouts >
  # Returning the Reader to One Record). One entry per token -- label, path, and whitelist
  # membership can never disagree. Registering a token without wiring its
  # return is impossible by construction; see #intake_notes_origin_params and
  # #intake_notes_return_path.
  ORIGIN_RETURNS = {
    "vc" => { label: "Unified Flagging", route: :vc_unified_flagging_path, year_scoped: true, selects: true },
    "mentoring" => { label: "Potential Alphas", route: :mentoring_potential_alphas_path, year_scoped: false,
                     selects: true },
    "mentoring_convert" => { label: "Convert Prospectives", route: :mentoring_convert_prospectives_path,
                             year_scoped: false },
    "mentoring_post_season" => { label: "Post Season Summary", route: :mentoring_post_season_summary_path,
                                 year_scoped: true, selects: true }
  }.freeze

  before_action :set_person_intake_note, only: %i[edit update destroy]

  helper_method :intake_notes_return_path, :intake_notes_origin_params, :intake_notes_return_label

  def new
    return unless check_intake_permissions!(params[:type])

    @form = build_form
    # Pre-select the team's existing rank for the year, matching the Ember
    # modal (intake-note-edit.js seeds noteForm.ranking from the current rank)
    # so the dropdown reflects the real state instead of always "No Ranking".
    @form.ranking = @form.current_rank
    @team_history = team_history(params[:type])
  end

  def create
    attrs = intake_note_form_params
    # The new-note form only posts the type nested under intake_note_form (see
    # app/views/person/intake_notes/new.html.erb's hidden field) -- there is no
    # top-level ?type= on this request the way there is on `new`'s GET link, so
    # checking params[:type] alone always read nil here and silently fell back
    # to requiring Role::INTAKE for every team. Mirrors build_form's own lookup.
    return unless check_intake_permissions!(attrs[:type] || params[:type])

    @form = build_form(attrs)

    if @form.save(actor: Current.person)
      redirect_to intake_notes_return_path, success: "Note saved."
    else
      @team_history = team_history(@form.type)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return unless ensure_not_log_note("Cannot update a log note.")

    check_intake_permissions!(@person_intake_note.type)
  end

  def update
    return unless ensure_not_log_note("Cannot update a log note.")
    return unless check_intake_permissions!(@person_intake_note.type)

    if @person_intake_note.update(person_intake_note_params)
      redirect_to intake_notes_return_path, success: "Note updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return unless check_intake_permissions!(@person_intake_note.type)
    return unless ensure_not_log_note("Not authorized to delete note.")

    @person_intake_note.destroy!
    redirect_to intake_notes_return_path, success: "Note deleted."
  end

  private

  # Notes are reachable from the person's own page and from the per-person
  # detail frame on each pipeline page; all of them have to be returned to. The
  # origin is a fixed token rather than a URL so nothing user-supplied reaches
  # redirect_to. `origin_year` is the *page* year and is deliberately distinct
  # from the form's own `year` (the note's event year); the mentoring page has
  # no year of its own and ignores it on the way back.
  def intake_notes_origin_params
    origin = params[:origin]
    return {} unless ORIGIN_RETURNS.key?(origin)

    { origin: origin, origin_year: params[:origin_year].presence || Current.year }
  end

  # No origin (opened from the person's own page) returns there.
  def intake_notes_return_path
    origin = intake_notes_origin_params
    entry = ORIGIN_RETURNS[origin[:origin]]
    return person_unified_flagging_path(@person) unless entry

    args = entry[:selects] ? { person: @person.id } : { anchor: "person-#{@person.id}" }
    args[:year] = origin[:origin_year] if entry[:year_scoped]
    public_send(entry[:route], **args)
  end

  def intake_notes_return_label
    ORIGIN_RETURNS.dig(intake_notes_origin_params[:origin], :label) || @person.callsign
  end

  # Port of IntakeController::checkIntakePermissions.
  def check_intake_permissions!(type)
    role = PERMISSION_ROLE_FOR_TYPE.fetch(type, Role::INTAKE)
    return true if has_role?([Role::ADMIN, role])

    redirect_to intake_notes_return_path, error: "Not authorized"
    false
  end

  def ensure_not_log_note(message)
    return true unless @person_intake_note.is_log

    redirect_to intake_notes_return_path, error: message
    false
  end

  def set_person_intake_note
    @person_intake_note = PersonIntakeNote.where(person_id: @person.id).find(params[:id])
  end

  def build_form(attrs = {})
    type = attrs[:type] || params[:type]
    year = attrs[:year] || params[:year] || Current.year

    IntakeNoteForm.new(
      attrs.merge(
        type: type,
        year: year,
        person: @person,
        current_rank: current_rank_for(type, year)
      )
    )
  end

  # Guards against a malformed/missing ?type= on a direct link -- upstream's
  # Ember page always supplies a valid type, so there is no PHP equivalent to
  # port here; this just avoids an unguarded public_send on a bad param.
  def current_rank_for(type, year)
    return nil unless PersonIntakeNote::TYPES.include?(type)

    PersonIntake.find_for_person_year_or_new(@person.id, year.to_i).public_send("#{type}_rank")
  end

  def team_history(type)
    Intake.history_for_person(@person, Current.year, rrn_only: false)[:teams][type]
  end

  def intake_note_form_params
    params.expect(intake_note_form: [:type, :year, :note, :ranking]).to_h
  end

  def person_intake_note_params
    params.expect(person_intake_note: [:note])
  end
end
