# frozen_string_literal: true

# Training › Mentoring › Mentor Assignment. The index picks a mentoring shift;
# show is one shift's roster, where each mentee is paired with mentors, the
# result and each mentor's notes are recorded, and the general notes about the
# mentee are read and added to; save writes that roster. A shift still to come
# shows its sign-ups and takes no save. See ArtMentoring::Shifts for how
# timesheet entries become shifts.
#
# Writes need the ART's trainer role (can_manage_session?, ruled 2026-10-21)
# in any year: a past year's walks are corrected here too (ruled 2026-10-22).
# What a pass can also
# grant -- the team, its Recommended positions, losing the mentee position --
# needs the ART's graduate role (can_graduate?) as well.
class Training::Mentoring::AssignmentsController < Training::Mentoring::BaseController
  before_action :authorize_session_management, only: :save
  before_action :load_shift, only: %i[show save]

  def index; end

  def show; end

  # A clean save comes back to the same shift (post/redirect/get). Anything
  # else re-renders it at 422 with what was typed, because Turbo drops a 200
  # response to a form submission: a refused row, or the pass question -- for a
  # graduate-role holder passing someone the pass can still grant something
  # to, and for anyone passing a mentee with no mentor selected. Nothing is
  # written until it is answered; each of its buttons sends the same rows
  # again with `confirmed` naming the answer, and the chosen grants.
  def save
    unless @group
      return redirect_to(shift_path, error: "No one has signed in for that shift yet, so there is nothing to record.")
    end

    @typed_notes = submitted_general_notes
    assignment = ArtMentoring::Assignment.new(@shifts, @group, submitted_rows, general_notes: @typed_notes)
    # The rows the page shows again as typed, should it come back.
    @submitted = assignment.typed_rows
    @pass_question = pass_question(assignment) if assignment.row_errors.empty?
    return render(:show, status: :unprocessable_entity) if @pass_question

    @result = assignment.save!(written_by: current_user, grants: submitted_grants,
                               record_without_mentor: !answered?(Training::MentoringHelper::PROMOTE_WITHOUT_VERDICT))
    return redirect_to(shift_path, success: saved_message(@result)) if @result.ok?

    # The save rolled back, but its edits stay on the walks Shifts loaded: read
    # the shift again, so the page shows what is stored beside what was typed.
    load_shifts
    @group = @shifts.group(params[:key].to_s) || @group
    render :show, status: :unprocessable_entity
  end

  private

  def load_shift
    key = params[:key].to_s
    @group = @shifts.group(key)
    @upcoming = @shifts.upcoming_shift(key) unless @group
    return if @group || @upcoming

    redirect_to training_mentoring_assignment_path(training_slug, year: @year),
                error: "That mentoring shift was not found in #{@year}."
  end

  def shift_path
    training_mentoring_assignment_shift_path(training_slug, params[:key], year: @year)
  end

  # The general notes about the roster's mentees, every year's, by person id.
  # Read when the roster renders, so a refused save -- which reads the shift
  # again -- shows them as stored, and a save that redirects reads none.
  helper_method def general_notes
    @general_notes ||= PersonMentoringNote.for_people(@group.first_entries.map(&:person_id)).group_by(&:person_id)
  end

  # The roster arrives as walks[<timesheet id>][status|was] and, per mentor
  # slot, walks[<timesheet id>][mentors][<slot>][id|notes|loaded_id] -- the
  # keyed-hash shape this app's other many-row forms use. `was` and
  # `loaded_id` are what the row and the slot held when the page was drawn
  # (ArtMentoring::Assignment). The hash comes off the wire, so every level is
  # checked before anything is read.
  def submitted_rows
    rows = params[:walks]
    return {} unless rows.respond_to?(:each_pair)

    rows.each_pair.filter_map do |timesheet_id, attributes|
      id = IdList.id(timesheet_id)
      next unless id && attributes.respond_to?(:each_pair)

      status, was = attributes.values_at(:status, :was).map { |value| value if value.is_a?(String) }
      slots = mentor_slots(attributes[:mentors])
      mentors = Array(slots).map do |slot|
        ArtMentoring::Shifts::WalkMentor.new(id: IdList.id(slot[:id]), notes: ArtMentoring::Assignment.clean(slot[:notes]),
                                             loaded_id: IdList.id(slot[:loaded_id]))
      end
      # A row without its slots, or with slots in any other shape, is
      # malformed: never a request to clear them.
      [id, ArtMentoring::Assignment::Row.new(timesheet_id: id, status: status.to_s, mentors:, was: was.presence,
                                             mentor_malformed: !slots || !IdList.clean?(slots.map { |slot| slot[:id].to_s }))]
    end.to_h
  end

  # A row's mentor slots in the form's order: nil unless each came keyed by its
  # number with nothing but text in it, the one shape the form sends. A bare
  # value, a word for a key or a list where an id goes would otherwise read as
  # a slot left blank.
  def mentor_slots(slots)
    return unless slots.respond_to?(:each_pair)

    pairs = slots.each_pair.sort_by { |slot, _mentor| slot.to_i }
    pairs.map(&:last) if pairs.any? && pairs.all? { |slot, mentor| slot.match?(/\A\d+\z/) && text_only?(mentor) }
  end

  def text_only?(value) = value.respond_to?(:each_pair) && value.each_pair.all? { |_key, text| text.is_a?(String) }

  # A new general note per mentee, general_notes[<person id>]; a blank box adds none.
  def submitted_general_notes
    notes = params[:general_notes]
    return {} unless notes.respond_to?(:each_pair)

    notes.each_pair.filter_map do |person_id, text|
      id = IdList.id(person_id)
      note = ArtMentoring::Assignment.clean(text) if text.is_a?(String)
      [id, note] if id && note.present?
    end.to_h
  end

  # What to ask before saving, until it is answered: a graduate-role holder,
  # about each mentee this save newly passes -- and the one whose Grant Team
  # Positions button was pressed -- who still has something to gain from it;
  # and anyone, about each mentee passed with no mentor selected.
  # @return [ArtMentoring::Pass::Question, nil] nil when there is nothing to ask
  def pass_question(assignment)
    return if params[:confirmed].present?

    without_mentor = assignment.passed_without_mentor
    grant_for = IdList.id(params[:grant_for])
    offers = {}
    if can_graduate?
      asked = assignment.newly_passed + without_mentor
      asked += assignment.passed.select { |entry| entry.id == grant_for } if grant_for
      offers = @shifts.pass.offers(asked.uniq)
    end
    question = ArtMentoring::Pass::Question.new(offers:, without_mentor: without_mentor.to_h { [it.id, it.person] },
                                                granting: grant_for.present?)
    question if question.any?
  end

  # Which of the pass question's buttons answered it.
  def answered?(label) = params[:confirmed] == label

  # The pass dialog's answers, grants[<timesheet id>][join|revoke]. Read only
  # from a graduate-role holder's answered save, and not from Record Pass but
  # Not Promote: a crafted one from anyone else grants nothing.
  def submitted_grants
    grants = params[:grants]
    return {} unless params[:confirmed].present? && can_graduate? && grants.respond_to?(:each_pair)
    return {} if answered?(Training::MentoringHelper::RECORD_PASS_NOT_PROMOTE)

    grants.each_pair.filter_map do |timesheet_id, choice|
      id = IdList.id(timesheet_id)
      next unless id && choice.respond_to?(:permit)

      values = choice.permit(:join, :revoke)
      [id, { join: values[:join] == "1", revoke: values[:revoke] == "1" }]
    end.to_h
  end

  def saved_message(result)
    parts = []
    parts << "Recorded #{helpers.pluralize(result.saved_count, "mentee")}" if result.saved_count.positive?
    parts << "cleared #{helpers.pluralize(result.cleared_count, "mentee")}" if result.cleared_count.positive?
    sentences = parts.any? ? ["#{parts.to_sentence.upcase_first}."] : []
    if result.noted_count.positive?
      sentences << (result.noted_count == 1 ? "General note added." : "#{result.noted_count} general notes added.")
    end
    sentences += result.granted.map { |person, done| pass_sentence(person, done) }
    sentences.any? ? sentences.join(" ") : "Nothing had changed, so nothing was recorded."
  end

  # "Lodestar joined the Green Dot Team, with Dirt - Green Dot and Green Dot
  # Sanctuary, and no longer holds Green Dot Mentee."
  def pass_sentence(person, grant)
    pass = @shifts.pass
    positions = pass.recommended_positions.map(&:title)
    joined = "joined the #{pass.team.title}#{", with #{positions.to_sentence}," if positions.any?}"
    revoked = "no longer holds #{grant.revoked.map(&:title).to_sentence}"

    return "#{person.callsign} #{revoked}." unless grant.joined
    return "#{person.callsign} #{joined.delete_suffix(",")}." if grant.revoked.empty?

    "#{person.callsign} #{joined} and #{revoked}."
  end
end
