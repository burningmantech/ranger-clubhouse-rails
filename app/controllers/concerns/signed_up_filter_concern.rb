# frozen_string_literal: true

# The tri-state "signed up for this event?" filter shared by the Quartermaster
# roster pages (Events Rangered, Potential Swag).
#
# Only the filter mechanics live here. What "signed up" MEANS is each report's
# own business and the two do not agree: Events Rangered reads
# person.years_of_signups, which counts trainings, while Potential Swag queries
# non-training sign-ups only. Both hand this concern a plain boolean on the row.
module SignedUpFilterConcern
  extend ActiveSupport::Concern

  SIGNED_UP_YES = "yes"
  SIGNED_UP_NO = "no"
  SIGNED_UP_VALUES = [SIGNED_UP_YES, SIGNED_UP_NO].freeze

  private

  # Anything else -- including the "0" a stray checkbox would post -- is not a
  # filter.
  def signed_up_filter
    if SIGNED_UP_VALUES.include?(params[:signed_up])
      params[:signed_up]
    else
      UiComponents::FilterBarHelper::ALL_FILTER
    end
  end

  def signed_up_match?(row, signed_up)
    signed_up == UiComponents::FilterBarHelper::ALL_FILTER ||
      row.signed_up == (signed_up == SIGNED_UP_YES)
  end
end
