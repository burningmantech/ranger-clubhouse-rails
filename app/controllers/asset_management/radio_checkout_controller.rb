# frozen_string_literal: true

# Radios held past the fourteen-hour limit (Ember reports/radio-checkout port).
# The page splits on the one thing that decides whether a long checkout matters:
# Rangers with an event-radio provision may keep a radio all event, everyone
# else is overdue. Two sections, no cohort control -- see RadioCheckoutReport
# for the upstream checkbox this replaces.
class AssetManagement::RadioCheckoutController < ApplicationController
  include AssetYearScopeConcern
  include CsvExportConcern

  layout "asset_management"

  # The after-action audit is a second view of the same list rather than a
  # second page, so it rides on a param and is part of the view's identity:
  # every link on the page carries it. Upstream's checkbox lost the view on any
  # reload, and would lose it here on a year change too. Named exactly as the
  # Radio Assets sibling names its own toggle.
  SUMMARY_VIEW = "summary"

  # The eligible cohort is an audit list, not a chase list, and it is long: 428
  # rows for 2024 in the summary view, each of which ui_table turns into its own
  # stacked card below the lg breakpoint. The overdue list above it is short by
  # construction and is never cut. The CSV carries every row either way.
  ELIGIBLE_DISPLAY_LIMIT = 100

  # Upstream: ADMIN or EDIT_ASSETS (AssetPolicy::before) or EVENT_MANAGEMENT
  # (AssetPersonPolicy::radioCheckoutReport), named here exactly, as on the
  # three sibling reports.
  #
  # Upstream's own policy names EVENT_MANAGEMENT alone, but AssetPolicy::before
  # already hands EDIT_ASSETS every asset page, and this report reads nothing
  # the sibling ledgers do not already show them.
  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  def index
    load_report

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: csv_filename) }
    end
  end

  private

  def load_report
    @available_years = checkout_years
    @year = resolve_selected_year(@available_years, params[:year])
    # This page's year list is a strict subset of its four siblings' -- they
    # browse every year holding any asset -- and the sidebar carries the year
    # the reader was on. Arriving from a year whose radios never left the cage
    # lands on a different year, so the page has to say so.
    @requested_year = requested_other_year
    @summary_view = params[:view] == SUMMARY_VIEW
    @rows = RadioCheckoutReport.execute(year: @year, event_summary: @summary_view)
    # The split the page is built on. Eligible holders are not a problem to
    # solve, so they sit below the people who are.
    @eligible_rows, @overdue_rows = @rows.partition(&:eligible)
    @eligible_shown = @eligible_rows.first(ELIGIBLE_DISPLAY_LIMIT)
    @index_params = { year: @year, view: (SUMMARY_VIEW if @summary_view) }.compact_blank
  end

  # The year that was asked for and could not be shown, when it is a real
  # inventory year rather than a typo -- a garbled param already falls back
  # silently and has nothing to explain. Mirrors the Radio Assets sibling.
  def requested_other_year
    requested = params[:year].to_s.presence&.to_i
    return nil if requested.nil? || requested == @year || @available_years.include?(requested)

    Asset.exists?(year: requested) ? requested : nil
  end

  # Years that recorded a radio checkout, newest first -- this page has nothing
  # to say about a year whose radios never left the cage. Read off asset.year
  # like the Asset History sibling rather than off the checkout date: the two
  # agree in practice (the cage issues a year's radios during that year's
  # event) and this needs no SQL date function to ask.
  #
  # Upstream hardcodes a 2010 floor and a pandemic skip; the data decides here,
  # and 2020 and 2021 hold no asset rows at all so the pandemic skips itself.
  def checkout_years
    PersonAsset.joins(:asset)
               .where(asset: { type: Asset::TYPE_RADIO })
               .distinct
               .pluck("asset.year")
               .sort
               .reverse
  end

  # The newest year that still has a radio out, not merely the newest year that
  # recorded a checkout: the first scan of next year's radios makes that year
  # years.first while last year's strays -- the recovery list the quartermaster
  # is here for -- are still unaccounted for. Matches the Assets Outstanding
  # sibling. The fourteen-hour limit is deliberately not applied here; it needs
  # a SQL date function to ask, an open checkout is the signal that matters, and
  # a year that has one but none yet overdue still reaches its own empty state.
  def default_year(years)
    unreturned_years(years).max || years.first
  end

  def unreturned_years(years)
    PersonAsset.where(checked_in: nil)
               .joins(:asset)
               .where(asset: { year: years, type: Asset::TYPE_RADIO })
               .distinct
               .pluck("asset.year")
  end

  # The view travels in the filename: exporting the chase list and then the
  # summary otherwise hands the reader two files with one name.
  def csv_filename
    parts = [@year, (SUMMARY_VIEW if @summary_view), "radio-checkout.csv"]

    parts.compact.join("-")
  end

  # Both cohorts in one file, with the verdict as a column -- the split is a
  # reading aid, not two different reports, and a spreadsheet can sort on it.
  #
  # Upstream emits the check-in columns only in its wider mode, keyed to
  # `event_summary || include_eligible` -- of which only the first is a real
  # query param, since the checkbox beside it binds `include_qualified`. So in
  # practice they appear there exactly when "Report as Event Summary" is ticked.
  # A CSV pays nothing for a column, so they are always emitted here and read
  # blank while a radio is out. Hours stay decimal, as upstream's export has them.
  def csv_rows
    rows = [["Callsign", "Barcode", "Duration (Hours)", "Checked Out", "Checked Out By",
             "Checked In", "Checked In By", "Check-out Forced?", "Event Radio?",
             "Event Radio Eligible?"]]

    @rows.each do |row|
      checkout = row.checkout
      rows << [
        helpers.person_display_name(row.person, checkout.person_id, blank: nil),
        row.asset.barcode,
        helpers.hour_format(row.duration),
        checkout.checked_out&.iso8601,
        helpers.person_display_name(checkout.check_out_person, checkout.check_out_person_id,
                                    blank: nil),
        checkout.checked_in&.iso8601,
        helpers.person_display_name(checkout.check_in_person, checkout.check_in_person_id,
                                    blank: nil),
        checkout.check_out_forced? ? "Yes" : "No",
        row.asset.perm_assign? ? "Yes" : "No",
        row.eligible ? "Yes" : "No"
      ]
    end

    rows
  end
end
