# frozen_string_literal: true

# Each including controller sets @back_to_url, @back_to_label and @signups_url.
module QualificationsConcern
  def qualifications
    progression = TicketsAndProvisionsProgress.new(@person)
    @qualifications = QualificationsPresenter.new(progression.items, shiny_penny: progression.is_shiny_penny)
    @ineligible_duration = progression.ineligible_duration.positive? ? progression.ineligible_duration : nil

    render "common/qualifications/index"
  end
end
