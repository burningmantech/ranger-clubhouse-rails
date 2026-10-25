# frozen_string_literal: true

# The year selector's shared plumbing for the Asset Management pages. All five
# offer a list of years and all five have to survive a garbled ?year=, but they
# disagree about which year to open on when the request names none it can use:
# an inventory page wants the newest year holding inventory, a chase list wants
# the newest year that still has something to chase. The guard is shared here;
# the fallback is each page's own answer, via default_year.
module AssetYearScopeConcern
  extend ActiveSupport::Concern

  private

  # to_s before presence: params[:year] can arrive as an Array or a nested Hash
  # (?year[]=2026), and those are present? but have no #to_i.
  def resolve_selected_year(years, requested_year)
    return nil if years.blank?

    year = requested_year.to_s.presence&.to_i
    return year if years.include?(year)

    default_year(years)
  end

  # The newest year offered. Right for a page whose year list is built from the
  # very rows it renders, so the newest one always has something to show.
  # Pages whose newest year can come up empty override this.
  def default_year(years)
    years.first
  end
end
