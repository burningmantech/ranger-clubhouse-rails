# frozen_string_literal: true

# Training › Mentoring: the year's mentoring numbers, who is on a mentee shift
# right now, and the way into the mentoring pages. Read-only. Its verdict
# counts come from the Verdicts report, so the two pages agree.
class Training::Mentoring::LandingController < Training::Mentoring::BaseController
  def index
    @verdicts = ArtMentoring::VerdictsReport.new(@shifts)
    @multiple_shifts = ArtMentoring::MultipleShiftsReport.new(@shifts)
  end
end
