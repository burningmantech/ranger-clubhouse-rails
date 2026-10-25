# frozen_string_literal: true

class TeamsPositions::PositionLineupsController < ApplicationController
  layout "teams_positions"

  # The lineup tab lived inside the Ember admin/positions page and was gated
  # with it; the API's PositionLineupPolicy defers to the same
  # Admin / Tech Ninja pair.
  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to manage position lineups."

  before_action :set_lineup, only: %i[edit update destroy]

  def index
    @lineups = PositionLineup.order(:description).to_a
    @positions_by_lineup = PositionLineupMember.where(position_lineup_id: @lineups.map(&:id))
                                               .joins(:position)
                                               .order("position.title")
                                               .pluck(:position_lineup_id, "position.title", "position.active")
                                               .group_by(&:first)
  end

  def new
    @lineup = PositionLineup.new
    load_form_collections
  end

  def create
    @lineup = PositionLineup.new(lineup_params)
    save_lineup(:new, "The position lineup has been created.")
  end

  def edit
    load_form_collections
  end

  def update
    @lineup.assign_attributes(lineup_params)
    save_lineup(:edit, "The position lineup has been updated.")
  end

  def destroy
    description = @lineup.description
    PositionLineupManagement.destroy(@lineup)

    redirect_to teams_positions_position_lineups_path, success: "#{description} deleted."
  end

  private

  def set_lineup
    @lineup = PositionLineup.find(params[:id])
  end

  def save_lineup(template, message)
    position_ids = submitted_position_ids

    if position_ids == :invalid
      @lineup.errors.add(:position_ids, "The positions were not submitted correctly.")
    elsif PositionLineupManagement.save(@lineup, position_ids:)
      return redirect_to teams_positions_position_lineups_path, success: message
    end

    load_form_collections
    render template, status: :unprocessable_entity
  end

  def load_form_collections
    @positions = Position.order(:title).to_a
    submitted = submitted_position_ids
    @position_ids = submitted.is_a?(Array) ? submitted : current_position_ids
    # Which other lineup already holds each position, so the picker can say so
    # before the reader submits rather than after.
    @lineup_by_position = PositionLineupMember.where.not(position_lineup_id: @lineup.id)
                                              .joins(:position_lineup)
                                              .pluck(:position_id, "position_lineup.description")
                                              .to_h
  end

  def current_position_ids
    return [] unless @lineup.persisted?

    PositionLineupMember.where(position_lineup_id: @lineup.id).pluck(:position_id)
  end

  # The same three states the position form's role grants use: nil when the
  # field was never offered, [] when every box was cleared, :invalid when what
  # arrived is not a list of ids.
  def submitted_position_ids
    return @submitted_position_ids if defined?(@submitted_position_ids)

    @submitted_position_ids = parse_position_ids
  end

  def parse_position_ids
    lineup = params[:position_lineup]
    return nil unless lineup.is_a?(ActionController::Parameters) && lineup.key?(:position_ids)

    raw = lineup[:position_ids]
    return :invalid unless IdList.clean?(raw)

    IdList.parse(raw)
  end

  def lineup_params
    params.expect(position_lineup: [:description])
  end
end
