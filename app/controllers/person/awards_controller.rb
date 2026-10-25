# frozen_string_literal: true

# Manage a person's service recognition awards.
#
# Viewing is open to anyone who may see the person; granting, editing, deleting and
# rebuilding require the Award Management role (or Admin).
class Person::AwardsController < ApplicationController
  layout "person"

  include PersonConcern

  # What a row recognizes. Each type names the person_award column that carries it, and is
  # the ?type= value new/create are given to pick which entity select to render.
  AWARD_TYPES = %w[team position special].freeze

  authorize_ability :manage_awards,
                    roles: [Role::AWARD_MANAGEMENT],
                    only: %i[new create edit update destroy rebuild],
                    deny_to: :awards_deny_path,
                    message: "Admin or Award Management role required to grant service recognition awards."

  before_action :set_award_type, only: %i[new create]
  before_action :set_person_award, only: %i[edit update destroy]

  def index
    groups = PersonAward.find_for_query(person_id: @person.id).group_by { |award| award_type_for(award) }

    @team_awards = groups.fetch("team", [])
    @position_awards = groups.fetch("position", [])
    @special_awards = groups.fetch("special", [])

    @years_of_service = @person.years_of_service || []
    @years_of_awards = @person.years_of_awards || []

    @can_manage = can?(:manage_awards)
  end

  def new
    @person_award = PersonAward.new(person_id: @person.id, year: Current.year)
    load_entity_options
  end

  def create
    @person_award = PersonAward.new(award_params)
    @person_award.person_id = @person.id
    @person_award.creator_person_id = Current.person_id

    if @person_award.save
      redirect_to person_awards_path(@person), success: "Award granted."
    else
      load_entity_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_entity_options
  end

  def update
    if @person_award.update(award_params)
      redirect_to person_awards_path(@person), success: "Award updated."
    else
      load_entity_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @person_award.title
    @person_award.destroy!
    redirect_to person_awards_path(@person), success: "#{title} award deleted."
  end

  # Regrant the awards the person's team and position history entitles them to. Deliberately
  # a no-op for now -- see AwardManagement.
  def rebuild
    AwardManagement.rebuild_for_person_id(@person.id)
    redirect_to person_awards_path(@person), success: "Awards rebuilt."
  end

  private

  def set_person_award
    @person_award = PersonAward.where(person_id: @person.id).find(params[:id])
    @award_type = award_type_for(@person_award)
  end

  # new/create are told which kind of award is being granted; anything else is a bad link.
  def set_award_type
    @award_type = params[:type].presence_in(AWARD_TYPES)
    return true if @award_type

    redirect_to person_awards_path(@person), error: "Unknown award type."
    false
  end

  # Mirrors the precedence in PersonAward.award_category_info so every row lands in exactly
  # one of the three tables.
  def award_type_for(person_award)
    if person_award.team_id.present?
      "team"
    elsif person_award.position_id.present?
      "position"
    else
      "special"
    end
  end

  # The form renders exactly one entity select -- the one the type names -- so only that
  # type's rows are worth fetching.
  def load_entity_options
    @entity_options = case @award_type
                      when "team"
                        entity_options(Team.where(awards_eligible: true).order(:title))
                      when "position"
                        entity_options(Position.awards_eligible.order(:title))
                      else
                        Award.order(:title).map { |award| [award.title, award.id] }
                      end
  end

  # A retired team/position may still be granted for a past year, so it stays selectable --
  # flagged rather than hidden, matching the Ember page.
  def entity_options(rows)
    rows.map { |row| [helpers.title_marking_inactive(row), row.id] }
  end

  # notes is NOT NULL in the database, so a blank textarea must land as "" and never nil.
  def award_params
    params.expect(person_award: [:award_id, :position_id, :team_id, :year, :awards_grants_service_year, :notes])
          .tap { |permitted| permitted[:notes] = permitted[:notes].to_s }
  end

  def awards_deny_path
    person_awards_path(@person)
  end
end
