# frozen_string_literal: true

# What swag was handed out during an event, one row per person. (Ember
# reports/swag-distribution port.)
#
# Year-scoped, with an "All" choice covering every year on record -- the first
# page to use the year selector's include_all option. @year is nil for the
# all-years view and an Integer otherwise.
class Quartermaster::SwagDistributionController < ApplicationController
  include CsvExportConcern

  layout "quartermaster"

  # person_swag data starts in 2009. Upstream's selector floor of 2010 hides
  # its own 2009 rows except under All; passing the actual data years to the
  # selector retires that quirk.
  self.year_floor = 2009

  # Turns on both halves of the all-years choice at once: setup_year accepts the
  # sentinel, and the view reads this same flag for the selector's include_all.
  self.allow_all_years = true

  before_action :setup_year

  # Exactly upstream's PersonSwagPolicy#before: Admin and Quartermaster. No
  # incidental third role this time.
  authorize_role [Role::ADMIN, Role::QUARTERMASTER],
                 message: "Admin or Quartermaster role required to view swag distribution."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # Category params travel as strings; the report's canon is symbols.
  CATEGORY_VALUES = SwagDistributionReport::CATEGORIES.map(&:to_s).freeze

  # Upstream's per-person columns, ported from the Ember controller's
  # CSV_COLUMNS (its hash-literal build order differs; the columns are what
  # count), with Org Pins slotted before Other.
  CSV_HEADER = (["Callsign"] +
    SwagDistributionReport::CATEGORIES.map { |c| SwagDistributionReport::CATEGORY_TITLES[c] }).freeze

  def index
    @rows = SwagDistributionReport.execute(@year)
    @filter_params = { category: category_filter }
    @filtered = filtered(@rows, @filter_params[:category])

    respond_to do |format|
      format.html do
        @category_counts = SwagDistributionReport.category_counts(@rows)
        @item_count = @category_counts.values.sum
        # The years the selector offers: those with swag on record, clamped to
        # the window setup_year honours. @year joins them even when it has no
        # swag, because hero_panel drops year_options' own
        # inject-the-requested-year guard -- without this the selector would
        # show a year the page is not reporting on.
        @data_years = (SwagDistributionReport.years_on_record(year_floor..current_year) +
                       [@year]).compact.uniq.sort
      end
      format.csv do
        send_csv(csv_rows, filename: "#{@year || "all"}-swag-distribution.csv")
      end
    end
  end

  private

  # An unrecognised category falls back to ALL rather than rendering an empty
  # roster no one asked for. A recognised category that currently holds zero
  # items is kept: its chip explains the empty roster it delivers.
  def category_filter
    CATEGORY_VALUES.include?(params[:category]) ? params[:category] : ALL
  end

  # A category narrows to the people who received at least one such item; their
  # row still lists everything they got. The person is the unit of this report,
  # so filtering the lines themselves would misstate what someone was handed.
  def filtered(rows, category)
    return rows if category == ALL

    key = category.to_sym
    rows.select { |row| row.by_category.key?(key) }
  end

  # One row per person, each category cell the newline-joined titles or "-",
  # matching upstream. The export honours the category filter the same way the
  # roster does. Under All each title carries its year, for the same reason the
  # roster lines do -- see SwagDistributionReport.item_title.
  def csv_rows
    [CSV_HEADER] + @filtered.map do |row|
      [row.person.callsign] +
        SwagDistributionReport::CATEGORIES.map do |category|
          items = row.by_category[category]
          items ? items.map { |item| SwagDistributionReport.item_title(item, @year) }.join("\n") : "-"
        end
    end
  end
end
