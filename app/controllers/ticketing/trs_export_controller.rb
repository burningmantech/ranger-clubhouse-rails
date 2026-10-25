# frozen_string_literal: true

# TRS export (Ember vc/access-documents/trs port): batches of claimed access
# documents for upload to the ticket vendor's Ticket Request System. The
# operator filters, selects rows, exports a CSV (stamping an audit comment on
# every exported document), uploads it to TRS, then marks the batch submitted.
#
# Both POSTs render their results with a 422 for the same reason the
# maintenance tasks do: the results are transient (the export CSV and ledgers
# cannot be re-derived by a GET) and Turbo drops a 200 form response.
class Ticketing::TrsExportController < ApplicationController
  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to export to TRS."

  def index
    @filter = TrsExport.find_filter(params[:filter]) || TrsExport.all_filter
    result = TrsExport.build_rows(@filter)
    @rows = result[:rows]
    @bad_documents = result[:bad_documents]
  end

  def export
    filter, ids = commit_params
    return if performed?

    @result = TrsExport.export!(filter, ids, Current.person)
    if @result[:rows].empty?
      return redirect_to ticketing_trs_export_path(filter: filter.slug),
                         alert: "None of the selected items are still exportable. Nothing was written."
    end

    @filter = filter
    render :export, status: :unprocessable_entity
  end

  def mark_submitted
    filter, ids = commit_params
    return if performed?

    @result = TrsExport.mark_submitted!(ids)
    if @result[:rows].empty?
      return redirect_to ticketing_trs_export_path(filter: filter.slug),
                         alert: "None of the selected items are still claimed. Nothing was changed."
    end

    @filter = filter
    render :mark_submitted, status: :unprocessable_entity
  end

  private

  # Validate the posted filter and checkbox ids, redirecting back to the index
  # with an alert on anything unusable. Combined rows post their document ids
  # comma-joined in one checkbox value; the ids are flattened here and the
  # rows re-derived server side, so stale client groupings cannot leak through.
  #
  # @return [Array(TrsExport::Filter, Array<Integer>)]
  def commit_params
    filter = TrsExport.find_filter(params[:filter])

    unless filter&.exportable?
      redirect_to ticketing_trs_export_path, alert: "Pick a specific filter before exporting."
      return
    end

    ids = IdList.parse(params.permit(ids: [])[:ids].to_a.flat_map { |value| value.split(",") })

    if ids.empty?
      redirect_to ticketing_trs_export_path(filter: filter.slug), alert: "Select at least one item."
    elsif ids.size > TrsExport::MAX_BATCH_SIZE
      redirect_to ticketing_trs_export_path(filter: filter.slug),
                  alert: "#{ids.size} items selected, which exceeds the TRS batch limit of " \
                         "#{TrsExport::MAX_BATCH_SIZE}. Select fewer items."
    end

    [filter, ids]
  end
end
