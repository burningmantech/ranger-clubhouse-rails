# frozen_string_literal: true

# The intake pipeline's roster is read from status history -- whoever was *set
# to* Prospective or Alpha during the year (Intake.roster_ids_for_year, porting
# upstream). person_status has no fixture file in this repo, so any test that
# expects someone to appear on a pipeline page has to put them there first.
#
# `new_status` is what the audit row records: Prospective by default (entering
# the pipeline), Alpha for a conversion, or one of Intake::WASHED_OUT_STATUSES
# for someone who left it -- which is what /mentoring/alpha-status excludes.
module IntakeTestHelper
  def place_in_pipeline(target, *years, new_status: Person::PROSPECTIVE)
    years.each do |year|
      PersonStatus.create!(person_id: target.id, old_status: Person::AUDITOR,
                           new_status: new_status,
                           created_at: Time.zone.local(year, 6, 1, 12, 0, 0))
    end
  end
end
