# frozen_string_literal: true

# Who may stand a Sandman shift this year, and what everyone else still needs.
class Scheduling::SandmanQualifiedController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  # The two roles that read the qualification reports. Sandman training and
  # affidavits are Event Management's to chase.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required " \
                          "to view the sandman qualifications report."

  # The first year worth offering. Left at the default, the selector would list
  # decades of years holding no sandman shifts at all.
  self.year_floor = 2008

  # The ways of narrowing the list, as they are spelled in the URL. What each
  # one is called on screen is the helper's to say.
  SHOW_QUALIFIED = "qualified"
  SHOW_UNQUALIFIED = "unqualified"
  SHOW_SIGNED_UP = "signed-up"
  SHOW_SIGNED_UP_QUALIFIED = "signed-up-qualified"
  SHOW_SIGNED_UP_UNQUALIFIED = "signed-up-unqualified"
  SHOW_MISSING_TRAINING = "missing-training"
  SHOW_MISSING_AFFIDAVIT = "missing-affidavit"
  SHOW_MISSING_EXPERIENCE = "missing-experience"

  SHOW_FILTERS = [SHOW_QUALIFIED, SHOW_UNQUALIFIED, SHOW_SIGNED_UP,
                  SHOW_SIGNED_UP_QUALIFIED, SHOW_SIGNED_UP_UNQUALIFIED,
                  SHOW_MISSING_TRAINING, SHOW_MISSING_AFFIDAVIT,
                  SHOW_MISSING_EXPERIENCE].freeze

  before_action :setup_year

  def index
    @report = SandmanQualifiedReport.build(year: @year)

    respond_to do |format|
      format.html do
        # Only the filter actually narrowing the list, so the chips, the
        # clear-all link, and the year selector all agree about what is on.
        @filter_params = UiComponents::FilterBarHelper.active_filters(show: show_param)
        @shown_rows = filtered_rows(@report.rows)
      end

      # Everyone, never the filtered view: an export named for the year that
      # quietly held back most of it is one no one can trust.
      format.csv do
        send_csv(csv_rows(@report), filename: "#{@year}-sandman-qualified.csv")
      end
    end
  end

  private

  # Anything the page does not offer shows everyone. A stale bookmark or a typo
  # would otherwise narrow nothing while still drawing a chip claiming it did,
  # and `?show[]=x` arrives as an Array that no lookup matches.
  def show_param
    UiComponents::FilterBarHelper.known_filter(params[:show], offered_filters)
  end

  # A check the Clubhouse is not asking for has no shortfall to open, so the
  # filter that would show it is not on offer either.
  def offered_filters
    dropped = []
    dropped << SHOW_MISSING_AFFIDAVIT unless @report.affidavit_required?
    dropped << SHOW_MISSING_EXPERIENCE unless @report.experience_required?

    SHOW_FILTERS - dropped
  end

  # Filtered in Ruby: the whole list is already loaded to total it, and a second
  # trip to the database could only disagree with the counts on screen.
  def filtered_rows(rows)
    case @filter_params[:show]
    when SHOW_QUALIFIED then rows.select(&:qualified?)
    when SHOW_UNQUALIFIED then rows.reject(&:qualified?)
    when SHOW_SIGNED_UP then rows.select(&:signed_up)
    when SHOW_SIGNED_UP_QUALIFIED then rows.select(&:qualified_signed_up?)
    when SHOW_SIGNED_UP_UNQUALIFIED then rows.select(&:unqualified_signed_up?)
    when SHOW_MISSING_TRAINING then rows.reject(&:trained)
    when SHOW_MISSING_AFFIDAVIT then rows.reject(&:affidavit)
    when SHOW_MISSING_EXPERIENCE then rows.reject(&:experience)
    else rows
    end
  end

  # One row per person, in the order the page lists them. A check the Clubhouse
  # is not asking for is left out of the export as well as off the page, so the
  # file says exactly what the report was measuring.
  def csv_rows(report)
    header = ["Callsign", "#{@year} Trained"]
    header << "Affidavit" if report.affidavit_required?
    header << "Experience (#{report.cutoff_year} or later)" if report.experience_required?
    header += ["#{@year} Signed Up", "Qualified"]

    rows = [header]

    report.rows.each do |row|
      cells = [row.callsign, csv_yes_no(row.trained)]
      cells << csv_yes_no(row.affidavit) if report.affidavit_required?
      cells << csv_yes_no(row.experience) if report.experience_required?
      cells += [csv_yes_no(row.signed_up), csv_yes_no(row.qualified?)]

      rows << cells
    end

    rows
  end
end
