# frozen_string_literal: true

# The three TRS formats the TRS export fills: the CSV columns each one carries,
# in the order the ticket vendor's import template lists them. The formats
# themselves are fixed (TrsExport picks one by slug), so there is nothing to
# add or delete, only columns to edit.
class Ticketing::TrsFormatsController < ApplicationController
  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to manage TRS formats."

  before_action :set_format, only: [:edit, :update]

  def index
    @formats = TrsFormat.in_order
    @filters_by_slug = TrsExport.filters_by_format_slug
  end

  def edit
  end

  # The grid saves the whole list, so a save from a page drawn before someone
  # else's save would put the old list back over theirs. The form carries the
  # fingerprint of the columns it was drawn from. A stale one saves nothing: the
  # rows come back as sent, under a notice, now carrying the fingerprint of the
  # format as it is, so saving again is a choice to replace it.
  def update
    rows = row_params
    @format.columns = TrsFormat.columns_from_rows(*paired_lists(rows))
    @stale = rows[:version] != @format.version
    return render(:edit, status: :unprocessable_entity) if @stale || !@format.save

    redirect_to ticketing_trs_formats_path, success: "#{@format.title} format saved."
  end

  private

  def set_format
    @format = TrsFormat.find_by!(slug: params.expect(:id))
  end

  # The grid's rows arrive as two lists side by side and are paired by
  # TrsFormat.columns_from_rows. Flat lists rather than a list of hashes:
  # expect drops the rows of a [[...]] list given single brackets.
  def row_params
    params.expect(trs_format: [:version, { row_headers: [], row_sources: [] }])
  end

  # The lists are paired by position, so one that came short would slide every
  # later source onto another column's header. The form always sends a value
  # for each control; anything else is a bad request, not a save.
  def paired_lists(rows)
    lists = rows.values_at(:row_headers, :row_sources).map { |list| Array(list) }
    raise ActionController::BadRequest, "The grid's rows do not line up." unless lists.map(&:size).uniq.one?

    lists
  end
end
