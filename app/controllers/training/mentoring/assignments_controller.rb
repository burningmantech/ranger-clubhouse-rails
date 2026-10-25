# frozen_string_literal: true

# Training › Mentoring › Mentor Assignment. The index picks a mentoring shift;
# show is one shift's roster, where each mentee is paired with one mentor and
# the result and notes are recorded; save writes that roster. A shift still to
# come shows its sign-ups and takes no save. See ArtMentoring::Shifts for how
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
  # response to a form submission: a refused row, or -- for a graduate-role
  # holder passing someone the pass can still grant something to -- the pass
  # question. Nothing is written until it is answered; its Record Pass button
  # sends the same rows again with `confirmed` and the chosen grants.
  def save
    unless @group
      return redirect_to(shift_path, error: "No one has signed in for that shift yet, so there is nothing to record.")
    end

    @submitted = submitted_rows
    assignment = ArtMentoring::Assignment.new(@shifts, @group, @submitted)
    @pass_offers = assignment.row_errors.empty? ? pass_offers_to_ask(assignment) : {}
    return render(:show, status: :unprocessable_entity) if @pass_offers.any?

    @result = assignment.save!(grants: submitted_grants)
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

  # The roster arrives as walks[<timesheet id>][mentor_ids[]|status|notes], the
  # keyed-hash shape this app's other many-row forms use. The hash comes off the
  # wire, so both levels are checked before anything is read.
  def submitted_rows
    rows = params[:walks]
    return {} unless rows.respond_to?(:each_pair)

    rows.each_pair.filter_map do |timesheet_id, attributes|
      next unless attributes.respond_to?(:permit)

      id = IdList.id(timesheet_id)
      next unless id

      values = attributes.permit(:status, :notes, mentor_ids: [])
      # A form sends each line break as CR LF; the textarea's maxlength counted
      # it as one, and so does the length check.
      [id, ArtMentoring::Assignment::Row.new(timesheet_id: id, status: values[:status].to_s,
                                             mentor_ids: Array(values[:mentor_ids]).filter_map { |value| IdList.id(value) },
                                             notes: values[:notes].to_s.gsub("\r\n", "\n").strip,
                                             mentor_malformed: !IdList.clean?(values[:mentor_ids]))]
    end.to_h
  end

  # Whom to ask before saving: a graduate-role holder who has not answered yet,
  # about each mentee this save newly passes -- and the one whose Grant Team
  # Positions button was pressed -- who still has something to gain from it.
  # @return [Hash{Integer => ArtMentoring::Pass::Offer}] by timesheet id
  def pass_offers_to_ask(assignment)
    return {} if params[:confirmed].present? || !can_graduate?

    asked = assignment.newly_passed
    grant_for = IdList.id(params[:grant_for])
    asked += assignment.passed.select { |entry| entry.id == grant_for } if grant_for
    @shifts.pass.offers(asked.uniq)
  end

  # The pass dialog's answers, grants[<timesheet id>][join|revoke]. Read only
  # from a graduate-role holder's answered save: a crafted one from anyone else
  # grants nothing.
  def submitted_grants
    grants = params[:grants]
    return {} unless params[:confirmed].present? && can_graduate? && grants.respond_to?(:each_pair)

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
