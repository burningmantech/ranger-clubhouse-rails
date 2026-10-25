# frozen_string_literal: true

class Scheduling::PositionCreditsController < ApplicationController
  include CsvExportConcern

  layout "scheduling"

  authorize_role [Role::ADMIN], message: "Admin role required to manage position credits."

  before_action :setup_year
  before_action :set_position, only: %i[position timeline bulk_destroy]
  before_action :set_credit, only: %i[edit update destroy]

  # Attributes shared by every credit created from one submission of the new
  # form; the position comes from the multi-select instead.
  SHARED_ATTRS = %i[start_time end_time credits_per_hour description].freeze

  CSV_HEADINGS = ["Position", "Start", "End", "Credits", "Description"].freeze
  TIMELINE_CSV_HEADINGS = ["From", "To", "Hours", "Credits Per Hour", "Made Up Of"].freeze

  def index
    counts = PositionCredit.for_year(@year).reorder(nil).group(:position_id).count
    positions = Position.where(id: counts.keys).select(:id, :title).index_by(&:id)
    @groups = counts.map { |position_id, count|
      { position_id:,
        title: helpers.credit_position_title(positions[position_id], position_id),
        orphan: positions[position_id].nil?,
        count: }
    }.sort_by { |group| group[:title].downcase }
    @total_credits = counts.values.sum

    respond_to do |format|
      format.html
      format.csv do
        credits = PositionCredit.find_for_year(@year)
                                .sort_by { |credit| [credit.position&.title.to_s, credit.start_time] }
        send_csv(csv_rows(credits), filename: "#{@year}-position-credits.csv")
      end
    end
  end

  def position
    base = position_credits
    @total_count = base.count
    @day_options = base.pluck(:start_time).map(&:to_date).uniq.sort
    @filtering = params[:day].present?
    # The position is eager loaded for the CSV export's position column.
    @credits = apply_filters(base).includes(:position).to_a

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows(@credits), filename: "#{@year}-#{@position_title.parameterize}-position-credits.csv") }
    end
  end

  # Charts the position's credit rate over time; the CSV is the chart's rate table.
  def timeline
    credits = position_credits.to_a
    @timeline = Scheduling::CreditTimeline.new(credits) if credits.any?

    respond_to do |format|
      format.html
      format.csv do
        send_csv(timeline_csv_rows, filename: "#{@year}-#{@position_title.parameterize}-credit-timeline.csv")
      end
    end
  end

  def new
    @position_ids = IdList.parse(params[:position_id])
    @credit = PositionCredit.new(position_id: @position_ids.first)
    load_form_collections
  end

  # Creates one credit per selected position, mirroring the Ember bulk create.
  # The credits are identical apart from the position, so a single record
  # stands in for all of them when reporting validation errors.
  def create
    attrs = new_credit_params
    @position_ids = IdList.parse(attrs.delete(:position_id))
    @credit = PositionCredit.new(attrs.merge(position_id: @position_ids.first))
    @credit.validate

    if @position_ids.empty?
      # The belongs_to default reads as a bare "must exist" in the summary.
      @credit.errors.delete(:position)
      @credit.errors.add(:base, "Select at least one position for this credit.")
    end

    if @credit.errors.any?
      load_form_collections
      return render :new, status: :unprocessable_entity
    end

    credits = @position_ids.map { |id| PositionCredit.new(attrs.merge(position_id: id)) }
    PositionCredit.transaction { credits.each(&:save!) }

    redirect_to(credits.one? ? credit_position_path(credits.first) : scheduling_position_credits_path(year: @year),
                success: "#{credits.size} position #{"credit".pluralize(credits.size)} created.")
  end

  def edit
    load_form_collections
  end

  def update
    if @credit.update(credit_params)
      redirect_to credit_position_path(@credit), success: "Position credit updated."
    else
      load_form_collections
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    position_id = @credit.position_id
    @credit.destroy!

    redirect_to scheduling_position_credits_position_path(position_id, year: @year),
                success: "Position credit deleted."
  end

  def bulk_destroy
    credits = position_credits.where(id: IdList.parse(params[:credit_ids])).to_a

    if credits.empty?
      return redirect_to scheduling_position_credits_position_path(@position_id, year: @year),
                         error: "Select at least one position credit to delete."
    end

    PositionCredit.transaction { credits.each(&:destroy!) }

    redirect_to scheduling_position_credits_position_path(@position_id, year: @year),
                success: "#{credits.size} position #{"credit".pluralize(credits.size)} deleted."
  end

  private

  # The position page tolerates a deleted position so credits left orphaned by
  # one can still be listed and removed. A position that never had credits is
  # still a bad URL.
  def set_position
    @position_id = params[:position_id].to_i
    @position = Position.find_by(id: @position_id)
    @position_title = helpers.credit_position_title(@position, @position_id)
    return if @position || PositionCredit.exists?(position_id: @position_id)

    redirect_to scheduling_position_credits_path(year: @year), error: "The position could not be found."
  end

  def set_credit
    @credit = PositionCredit.find(params[:id])
  end

  # Narrows the position's credits by the day filter. Day values are matched
  # against the position's own credit start dates.
  def apply_filters(scope)
    day = @day_options.find { |date| date.iso8601 == params[:day] }
    day ? scope.where(start_time: day.all_day) : scope
  end

  def credit_position_path(credit)
    scheduling_position_credits_position_path(credit.position_id,
                                          year: credit.start_time.year,
                                          anchor: "credit-#{credit.id}")
  end

  def load_form_collections
    @positions = Position.ordered_by_title.select(:id, :title, :active).to_a
    @cancel_path = if @credit.position_id
                     scheduling_position_credits_position_path(@credit.position_id, year: @year)
                   else
                     scheduling_position_credits_path(year: @year)
                   end
  end

  def credit_params
    params.expect(position_credit: [*SHARED_ATTRS, :position_id])
  end

  # The new-credit form takes a list of positions, one credit each.
  def new_credit_params
    params.expect(position_credit: [*SHARED_ATTRS, position_id: []])
  end

  def timeline_csv_rows
    rows = [TIMELINE_CSV_HEADINGS]
    return rows unless @timeline

    @timeline.segments.each do |segment|
      rows << [
        segment.starts_at.strftime(DateTimeHelper::CSV_TIME),
        segment.ends_at.strftime(DateTimeHelper::CSV_TIME),
        helpers.hour_format(segment.minutes * 60),
        helpers.credit_format_short(segment.total),
        helpers.credit_segment_makeup(segment)
      ]
    end

    rows
  end

  # The position's credits for the year, the set the position page lists.
  def position_credits
    PositionCredit.for_year(@year).where(position_id: @position_id)
  end

  def csv_rows(credits)
    rows = [CSV_HEADINGS]

    credits.each do |credit|
      rows << [
        helpers.credit_position_title(credit.position, credit.position_id),
        credit.start_time&.iso8601,
        credit.end_time&.iso8601,
        format("%.2f", credit.credits_per_hour.to_f),
        credit.description
      ]
    end

    rows
  end
end
