# frozen_string_literal: true

# Me › Trainer/Mentor Feedback (upstream me/trainer-feedback): what trainees,
# mentees, Alphas and fellow trainers said about the signed-in person, a year
# at a time. Open to anyone signed in, by design: it is read-only and shows
# only the reader's own feedback -- upstream's policy admits the subject alone,
# so there is no id to check.
#
# One page where upstream had two: its index of years is the year selector
# here, and the Alpha survey, which upstream reached through a link of its
# own, sits with the rest of its year.
class Me::FeedbackController < ApplicationController
  layout "me"

  helper_method :session_url

  def index
    @years = TrainerFeedbackReport.years(current_user.id)
    # A year with feedback in it, or else the newest one with something to
    # show: a stale or malformed ?year= opens that rather than an error.
    requested = @years.find { |year| year.to_s == params[:year] }
    @year, @rows = requested ? [requested, TrainerFeedbackReport.for_year(current_user.id, requested)] : newest_feedback
    # The sessions as slots: SurveyBuilder's session responses carry no timezone.
    @slots = Slot.where(id: @rows.flat_map(&:session_ids)).index_by(&:id)
  end

  private

  # The newest year with something to show. A year can hold answers and still
  # nothing a report can place -- answers on a session deleted since lose
  # their slot -- so it is passed over rather than opened on an empty page.
  def newest_feedback
    @years.each do |year|
      rows = TrainerFeedbackReport.for_year(current_user.id, year)
      return [year, rows] if rows.any?
    end
    [@years.first, []]
  end

  # common/surveys/_session_label links a session to its page where the host
  # has one. Session pages belong to the training interface, not to /me.
  def session_url(_slot) = nil
end
