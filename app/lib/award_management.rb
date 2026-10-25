# frozen_string_literal: true

# Award Management module
#
# Reconstructs a person's Service Recognition Awards from the records that back them:
# team membership logs, trainer (taught session) records, and worked timesheets.
#
# Ported from Laravel's App\Lib\AwardManagement.
#
# NOTE: The two entry points (.rebuild_all and .rebuild_for_person_id) are deliberate
# no-ops -- their bodies are commented out upstream and are kept commented out here so
# this matches production Laravel. Automated grants are not switched on yet. The
# reconstruction machinery below is live and complete; enabling automated grants is a
# matter of uncommenting the entry-point bodies.
module AwardManagement
  # The year the team logs came online.
  TEAM_LOG_START = 2022

  class << self
    # Rebuild the awards for every active person who has a team log, a taught session,
    # or an existing award.
    #
    # @return [void]
    def rebuild_all
      # TODO: Revisit when ready for automated grants. Existing awards might be getting zapped.
      #
      # position_ids = retrieve_position_ids
      # teams_by_person = retrieve_team_logs(nil).group_by(&:person_id)
      # awards_by_person = PersonAward.all.group_by(&:person_id)
      #
      # if position_ids
      #   taught_years = retrieve_trainer_records(nil, position_ids).group_by(&:person_id)
      #   timesheets_by_person = Timesheet.select(:person_id, :on_duty, :position_id)
      #                                   .where(position_id: position_ids)
      #                                   .includes(:position)
      #                                   .group_by(&:person_id)
      # else
      #   taught_years = nil
      #   timesheets_by_person = nil
      # end
      #
      # person_ids = teams_by_person.keys + awards_by_person.keys
      # person_ids += taught_years.keys if taught_years
      # person_ids.uniq!
      #
      # Person.where(status: Person::ACTIVE_STATUSES, id: person_ids).find_each do |person|
      #   reconstruct_awards(person,
      #                      awards_by_person[person.id] || [],
      #                      position_ids,
      #                      taught_years&.[](person.id),
      #                      teams_by_person[person.id],
      #                      timesheets_by_person&.[](person.id))
      # end
    end

    # Rebuild the awards for a single person.
    #
    # @param person_id [Integer] the person whose awards should be rebuilt
    # @param save_person [Boolean] true if the person's year columns should be written back
    # @return [void]
    def rebuild_for_person_id(person_id, save_person: true)
      # TODO: Revisit when ready for automated grants. Existing awards might be getting zapped.
      #
      # person = Person.find(person_id)
      # awards = PersonAward.where(person_id: person_id).to_a
      # position_ids = retrieve_position_ids
      # teams = retrieve_team_logs(person_id)
      #
      # if position_ids
      #   taught_years = retrieve_trainer_records(person_id, position_ids)
      #   # ... find what eligible timesheets were worked.
      #   timesheets = Timesheet.select(:on_duty, :position_id)
      #                         .where(person_id: person_id, position_id: position_ids)
      #                         .includes(:position)
      #                         .to_a
      # else
      #   taught_years = nil
      #   timesheets = nil
      # end
      #
      # reconstruct_awards(person, awards, position_ids, taught_years, teams, timesheets,
      #                    save_person: save_person)
    end

    # Walk everything that backs an award -- team logs, taught sessions, worked timesheets --
    # granting any award that is missing, and recompute the person's award years.
    #
    # @param person [Person] the person being reconstructed
    # @param awards [Enumerable<PersonAward>, nil] the person's existing awards
    # @param position_ids [Array<Integer>, nil] positions which auto-grant awards
    # @param taught_years [Enumerable, nil] trainer records from .retrieve_trainer_records
    # @param teams [Enumerable<PersonTeamLog>, nil] team logs from .retrieve_team_logs
    # @param timesheets [Enumerable<Timesheet>, nil] timesheets worked on auto-granting positions
    # @param save_person [Boolean] true if the person's year columns should be written back
    # @return [void]
    def reconstruct_awards(person, awards, position_ids, taught_years, teams, timesheets, save_person: true)
      current_year = Current.year
      person_id = person.id

      existing_team_years = {}
      existing_position_years = {}
      existing_special_years = []

      awards&.each do |award|
        if award.team_id
          # Team awards predating the logs have nothing to back them up, so leave them be.
          next if award.year < TEAM_LOG_START

          (existing_team_years[award.team_id] ||= {})[award.year] = award
        elsif award.position_id
          (existing_position_years[award.position_id] ||= {})[award.year] = award
        else
          existing_special_years << award.year
        end
      end

      years = existing_special_years.uniq

      teams&.each do |team_log|
        end_year = team_log.left_on ? team_log.left_on.year : current_year
        team_id = team_log.team_id

        (team_log.joined_on.year..end_year).each do |year|
          years << year
          remove_year(year, team_id, existing_team_years)
          create_if_missing(person_id, :team_id, team_id, year, awards,
                            team_log.team.awards_grants_service_year)
        end
      end

      # existing_team_years.each_value do |team_years|
      #   team_years.each_value do |award|
      #     award.audit_reason = "no team history found"
      #     award.destroy
      #   end
      # end

      # Find the eligible positions
      if position_ids.present?
        # Inspect trainer records.
        taught_years&.each do |taught_year|
          year = taught_year.begins_year
          years << year
          remove_year(year, taught_year.position_id, existing_position_years)
          create_if_missing(person_id, :position_id, taught_year.position_id, year, awards,
                            taught_year.awards_grants_service_year)
        end

        granted_years = {}
        timesheets&.each do |timesheet|
          year = timesheet.on_duty.year
          position_id = timesheet.position_id
          remove_year(year, position_id, existing_position_years)
          # A position only earns one award per year no matter how many shifts were worked.
          next if granted_years[position_id]&.include?(year)

          years << year
          create_if_missing(person_id, :position_id, position_id, year, awards,
                            timesheet.position.awards_grants_service_year)
          (granted_years[position_id] ||= []) << year
        end
      end

      # existing_position_years.each_value do |position_years|
      #   position_years.each_value do |award|
      #     award.audit_reason = "No backing trainer status or timesheet found"
      #     award.destroy
      #   end
      # end

      person.years_of_awards = years.uniq.sort
      YearsManagement.save_person(person, "awards rebuild") if save_person
    end

    # Grant an award unless the person already holds one for the same entity and year.
    #
    # @param person_id [Integer] the person to grant to
    # @param column [Symbol] :team_id or :position_id -- what the award is for
    # @param value [Integer] the team or position id
    # @param year [Integer] the year being recognized
    # @param awards [Enumerable<PersonAward>, nil] the person's existing awards
    # @param is_service_year [Boolean] true if the award counts towards years of service
    # @return [void]
    def create_if_missing(person_id, column, value, year, awards, is_service_year)
      return if awards&.any? { |a| a.person_id == person_id && a[column] == value && a.year == year }

      PersonAward.create(
        :person_id => person_id,
        column => value,
        :year => year,
        :awards_grants_service_year => is_service_year,
        :notes => "automatic creation"
      )
    end

    # Forget an existing award, marking it as still backed by a record.
    #
    # @param year [Integer] the year to forget
    # @param entity_id [Integer] the team or position id
    # @param existing [Hash] entity id => { year => PersonAward }, mutated in place
    # @return [void]
    def remove_year(year, entity_id, existing)
      existing[entity_id]&.delete(year)
    end

    # The positions which automatically grant an award when worked or taught.
    #
    # @return [Array<Integer>, nil] nil if no position auto-grants
    def retrieve_position_ids
      Position.where(awards_auto_grant: true).pluck(:id).presence
    end

    # The sessions a person (or everyone) taught on an award granting position.
    #
    # @param person_id [Integer, nil] limit to a person, or nil for everyone
    # @param position_ids [Array<Integer>] the positions to look at
    # @return [Array<TrainerStatus>] rows carrying begins_year, position_id, awards_grants_service_year
    def retrieve_trainer_records(person_id, position_ids)
      sql = TrainerStatus.joins(trainer_slot: :position)
                         .where(position: { id: position_ids })
                         .where(trainer_status: { status: TrainerStatus::STATUS_ATTENDED })
                         .select("trainer_status.person_id",
                                 "slot.begins_year",
                                 "slot.position_id",
                                 "position.awards_grants_service_year")
      sql = sql.where(trainer_status: { person_id: person_id }) if person_id
      sql.to_a
    end

    # The team membership logs for teams which automatically grant an award.
    #
    # @param person_id [Integer, nil] limit to a person, or nil for everyone
    # @return [Array<PersonTeamLog>] with team preloaded
    def retrieve_team_logs(person_id)
      sql = PersonTeamLog.joins(:team).includes(:team).where(team: { awards_auto_grant: true })
      sql = sql.where(person_team_log: { person_id: person_id }) if person_id
      sql.to_a
    end
  end
end
