# frozen_string_literal: true

# BMID > Badge Titles: the list of titles a position earns on a badge, and the
# Set BMID Titles run that stamps them onto the year's badges.
#
# Deliberately not year-scoped, unlike its siblings in this namespace. The list
# itself is not a per-year thing, and the run only ever touches the current
# year -- see BmidTitleAssignment.
class Bmid::TitlesController < ApplicationController
  layout "bmid"

  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # The select option that hands the line over to the text box beside it.
  CUSTOM = "custom"

  before_action :set_title, only: %i[edit update destroy move]
  before_action :load_positions, only: %i[new create edit update]

  def index
    @titles_by_line = BmidTitle.includes(:position).ordered.group_by(&:title_line)
    @total_count = @titles_by_line.values.sum(&:size)
  end

  def new
    @title = BmidTitle.new(title_line: 1, sort_index: 1)
  end

  def create
    @title = BmidTitle.new(title_params)

    if @title.save
      redirect_to bmid_titles_path, success: "Badge title created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @title.update(title_params)
      redirect_to bmid_titles_path, success: "Badge title updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @title.destroy!

    redirect_to bmid_titles_path,
                success: "Badge title deleted. Badges already carrying it keep it."
  end

  # Step a title up or down its line's order of preference. A move that cannot
  # happen -- the end of the line, reached from a stale page -- just re-renders
  # the list, which then shows the truth.
  def move
    unless BmidTitle::MOVE_DIRECTIONS.include?(params[:direction])
      redirect_to bmid_titles_path, alert: "A badge title can only be moved up or down."
      return
    end

    @title.move!(params[:direction])

    redirect_to bmid_titles_path(anchor: "bmid-title-#{@title.id}")
  end

  # Preview: what every qualified holder's badge would say if the titles were
  # applied right now, with every line editable first.
  def set
    @year = current_year
    @rows = BmidTitleAssignment.preview(@year)
    @titles = BmidTitle.includes(:position).ordered.to_a
    @titles_by_line = @titles.group_by(&:title_line)
  end

  # The results a GET cannot re-derive -- once the titles are written, asking
  # again shows nothing to do. Rendered at 422 because Turbo drops a 200 form
  # response. See project-standards.
  def apply
    @year = current_year
    @rows = BmidTitleAssignment.apply(@year, submitted_titles)

    render :apply, status: :unprocessable_entity
  end

  private

  def set_title
    @title = BmidTitle.find(params[:id])
  end

  def load_positions
    @positions = Position.order(:title)
  end

  def title_params
    params.expect(bmid_title: [:title, :title_line, :sort_index, :position_id])
  end

  # The preview posts one pair of fields per badge line, keyed
  # "<person id>-<line>": a choice, and the text box the CUSTOM choice hands
  # over to.
  #
  # Every value is a string an EDIT_BMIDS admin chose, whether they picked it
  # off the list or typed it, so the only thing to enforce here is the column's
  # limit. Which people and lines may be written is settled by
  # BmidTitleAssignment, which re-derives them rather than trusting the form.
  #
  # @return [Hash{Integer=>Hash{Integer=>String,nil}}]
  def submitted_titles
    customs = string_params(:custom_titles)

    string_params(:titles).each_with_object({}) do |(key, choice), submitted|
      person_id, line = key.split("-", 2).map(&:to_i)
      next unless BmidTitle::TITLE_LINES.include?(line)

      value = choice == CUSTOM ? customs[key] : choice
      (submitted[person_id] ||= {})[line] = value.to_s.strip.first(BmidTitle::TITLE_LIMIT).presence
    end
  end

  # A flat key => string hash from the params. Anything nested or otherwise
  # malformed is dropped.
  def string_params(name)
    params.permit(name => {})[name].to_h.select { |_key, value| value.is_a?(String) }
  end
end
