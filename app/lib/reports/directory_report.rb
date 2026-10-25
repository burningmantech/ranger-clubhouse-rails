# frozen_string_literal: true

require "ostruct"

class DirectoryReport
  # Generates directory data for active Cadre and Delegation teams, plus any
  # other team explicitly flagged for the directory.
  # Returns array of team OpenStruct objects with members and their overseer positions
  # Council Cadre (team id 6) is always first in the list
  def self.execute
    # include_in_directory is how a plain team joins the directory -- it is the
    # checkbox on the Team Records page, and upstream's DirectoryReport ORs it
    # with the type test the same way. Without it that checkbox does nothing.
    # TeamManagement.directory_listed? is the row-level twin of this condition;
    # the admin grid's Directory chip asks it, so the two must stay in step.
    teams = Team.where(type: TeamManagement::DIRECTORY_TYPES)
                .or(Team.where(include_in_directory: true))
                .where(active: true)
                .order(:title)
                .includes(members: :avatar_photo_attachment)
                .all

    directory = []
    council = nil

    teams.each do |team|
      next if team.members.empty?

      # Find overseer positions for team members
      member_ids = team.members.pluck(:id)

      overseer_positions = Position.joins(:person_position)
        .where(person_position: { person_id: member_ids })
        .where(team_id: team.id, active: true)
        .where("position.title LIKE ? OR position.title LIKE ?", "%manager", "%supervisor")
        .select("position.id", "position.title", "person_position.person_id")
        .order(:title)

      # Group overseer positions by person_id for efficient lookup
      overseer_positions_by_person = overseer_positions.group_by(&:person_id)

      cadre = build_team_directory(team, overseer_positions_by_person)

      # Council Cadre gets special treatment - always appears first
      if team.id == Team::COUNCIL_CADRE
        council = cadre
      else
        directory << cadre
      end
    end

    # Put council first if it exists
    directory.unshift(council) if council

    directory
  end

  class TeamDirectory
    attr_reader :id, :title, :email, :description, :members

    def initialize(id:, title:, email:, description:, members:)
      @id = id
      @title = title
      @email = email
      @description = description
      @members = members
    end
  end

  class TeamMember
    attr_reader :person, :overseer_positions

    def initialize(person:, overseer_positions:)
      @person = person
      @overseer_positions = overseer_positions
    end
  end

  # Build an team directory with members and their overseer positions
  # @param team [Team] The team object
  # @param overseer_positions_by_person [Hash] Hash mapping person_id to array of positions
  # @return [TeamDirectory]

  def self.build_team_directory(team, overseer_positions_by_person)
    members = team.members.map do |person|
      TeamMember.new(person:, overseer_positions: overseer_positions_by_person[person.id])
    end

    TeamDirectory.new(id: team.id, title: team.title, members:, email: team.email, description: team.description)
  end
end
