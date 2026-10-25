# frozen_string_literal: true

# Read-only, current-year twin of Person::TrainingController — the online course,
# in-person training, and ART status rendered inside the HQ Window Interface shell,
# replacing the sidebar item that used to link out to /person/:id/training.
#
# Deliberately view-only: managing the online course record needs the Tech Ninja or
# Trainer role, which the window operator is not assumed to hold, so no write routes
# exist under /hq and the Moodle account tools stay on the person page.
class Hq::TrainingController < ApplicationController
  include HqConcern

  # No body needed: HqConcern#load_hq_shell already loads @event_info for the
  # current year, which is the whole of this page's data.
  def index; end
end
