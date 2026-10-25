# frozen_string_literal: true

# Shared shell for an ART's mentoring pages (/training/:slug/mentoring/...).
# Resolution, the view gate and @year come from Training::BaseController; on
# top, only a training flagged has_art_mentoring has these pages. The menu
# offers the item on the same flag (TrainingMenu), so a typed URL is all this
# catches.
class Training::Mentoring::BaseController < Training::BaseController
  before_action :require_art_mentoring
  before_action :load_shifts

  private

  def require_art_mentoring
    return if @training.has_art_mentoring

    redirect_to training_path(training_slug), error: "#{@training.title} does not pair mentors with mentees on shift."
  end

  # Every mentoring page reads the year through one ArtMentoring::Shifts.
  def load_shifts
    @shifts = ArtMentoring::Shifts.new(@training, @year)
  end
end
