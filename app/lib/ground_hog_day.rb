# frozen_string_literal: true

# Winds a copy of the database back to one moment during the event and holds it
# there, so training runs against a Clubhouse that looks like the real one in
# the middle of the burn: people on site, shifts under way, radios checked out.
#
# Run this against a copy. Run against the real database it would destroy it.
class GroundHogDay
  # The environment variable that names the moment. Its presence is also what
  # tells the Clubhouse it is the training server.
  ENVIRONMENT_VAR = "RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"

  # The password for the three practice accounts, when one is provided.
  HQ_PASSWORD_VAR = "RANGER_CLUBHOUSE_HQ_TRAINING_PASSWORD"

  # People who were around between these dates count as being on site.
  ON_PLAYA_START = [8, 20].freeze
  ON_PLAYA_END = [9, 10].freeze

  # Whoever the welcome announcement is signed by. Any account will do; this one
  # is used when it is there.
  ANNOUNCEMENT_AUTHOR_ID = 4594

  ANNOUNCEMENT_MESSAGE = "Remember the temporal prime directive, do not muck up the timeline by " \
                         "killing your own grandparent in the past."

  # Switched on so training covers the parts of the Clubhouse that only run
  # during the event, and so nothing the copy sends can reach anybody.
  TRUE_SETTINGS = [
    Setting::BROADCAST_CLUBHOUSE_SANDBOX,
    Setting::BROADCAST_MAIL_SANDBOX,
    Setting::BROADCAST_SMS_SANDBOX,
    Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
    Setting::HQ_WINDOW_INTERFACE_ENABLED,
    Setting::MOTOR_POOL_PROTOCOL_ENABLED,
    Setting::RADIO_CHECKOUT_AGREEMENT_ENABLED,
    Setting::RADIO_INFO_AVAILABLE,
    Setting::TIMESHEET_CORRECTION_ENABLE
  ].freeze

  # The practice accounts, and the training each one is given credit for.
  HQ_TRAINING_ACCOUNTS = {
    "hqworkertest@nomail.none" => [Position::HQ_FULL_TRAINING],
    "hqshorttest@nomail.none" => [Position::HQ_FULL_TRAINING, Position::HQ_LEADS_SHORTS_TRAINING],
    "hqleadtest@nomail.none" => [Position::HQ_FULL_TRAINING, Position::HQ_LEADS_SHORTS_TRAINING]
  }.freeze

  HQ_POSITIONS = [Position::HQ_WINDOW, Position::HQ_SHORT, Position::HQ_LEAD].freeze

  HQ_SLOT_POSITIONS = [Position::HQ_LEAD, Position::HQ_SHORT,
                       Position::HQ_WINDOW, Position::HQ_WINDOW_PRE_EVENT].freeze

  CATCH_ALL_DESCRIPTION = "Ground Hog Day Catch All"

  # How many people the catch-all training session can hold: everybody.
  CATCH_ALL_MAX = 10_000

  class << self
    # The day and time to hold at. Refuses anything that is not one, rather than
    # carrying nothing along to whatever reads it next.
    def parse_moment(value)
      return value unless value.is_a?(String)

      parsed = begin
        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      parsed || raise(DatabaseDump::Error, "#{value.inspect} is not a day and time")
    end

    # Wind the database back to the given moment.
    #
    # @param moment [Time, String] the day and time to hold at
    def build(moment)
      moment = parse_moment(moment)
      year = moment.year

      people_ids = people_who_were_there(year)
      reopen_timesheets(moment)
      remove_what_had_not_happened_yet(moment, year)
      put_people_on_site(people_ids, year)
      # put_people_on_site, and RedactDatabase before this, change on_site with
      # update_all. No one made those changes, so no creator.
      PersonOnSite.reconcile(at: moment)
      add_welcome_announcement(moment, year)
      apply_settings
      set_up_hq_training(year)
    end

    # Sign every active Ranger up for a training session and pass them, so
    # anybody can take part in training without being turned away for it.
    def train_actives(year)
      slot = Slot.create!(active: true, description: CATCH_ALL_DESCRIPTION,
                          position_id: Position::TRAINING,
                          begins: Time.local(year, 1, 1, 10), ends: Time.local(year, 1, 1, 11),
                          max: CATCH_ALL_MAX, min: 1, timezone: "America/Los_Angeles", signed_up: 0)

      Person.where(status: Person::ACTIVE).in_batches(of: 100) do |batch|
        ids = batch.pluck(:id)
        PersonSlot.insert_all(ids.map { |id| { slot_id: slot.id, person_id: id } })
        TraineeStatus.insert_all(ids.map do |id|
          { slot_id: slot.id, person_id: id, rank: 2, status: TraineeStatus::STATUS_PASSED, notes: "Passed in training" }
        end)
        PersonRole.insert_all(ids.map { |id| { person_id: id, role_id: Role::EVENT_MANAGEMENT_ON_PLAYA } })
      end

      slot.update_column(:signed_up, PersonSlot.where(slot_id: slot.id).count)
      slot
    end

    # What the day's training database is called.
    def training_database_dump_name(moment)
      "training-#{parse_moment(moment).strftime('%Y-%m-%d')}.sql.gz"
    end

    # Put the training server back to the start of the day. Everything anybody
    # did to it since the last reload is thrown away, which is the point.
    def reload_training_database!
      moment = ENV[ENVIRONMENT_VAR]
      if moment.blank?
        raise DatabaseDump::Error, "#{ENVIRONMENT_VAR} is not set, so there is no training database to reload"
      end

      file = Rails.root.join(training_database_dump_name(moment))
      raise DatabaseDump::Error, "The training database file #{file} is not there" unless File.exist?(file)

      # The file drops only the tables it holds, so a table added since it was
      # made would keep its rows from one day to the next. Every table is dropped
      # first, bar the queue and cache tables this job and the server run on.
      connection = ActiveRecord::Base.connection
      connection.disable_referential_integrity do
        connection.tables.grep_v(/\Asolid_/).each { connection.drop_table(it) }
      end
      DatabaseDump.load_gzip(DatabaseDump.primary_config, from: file)
      Rails.cache.clear
      file
    end

    private

    # Anybody signed up for a shift during the event, or who rangered at all
    # that year, was there.
    def people_who_were_there(year)
      window = Time.local(year, *ON_PLAYA_START)..Time.local(year, *ON_PLAYA_END)

      ids = PersonSlot.joins(:slot)
                      .where(slot: { begins: window.begin.., ends: ..window.end })
                      .distinct.pluck(:person_id)
      ids | Timesheet.all.where_year("on_duty", year).distinct.pluck(:person_id)
    end

    # A shift that had not started yet never happened, and one still running at
    # the moment we stopped at is still running.
    def reopen_timesheets(moment)
      # Deleted in bulk, so what hangs off each entry has to be named here --
      # otherwise the notes and history stay behind pointing at nothing.
      not_yet = Timesheet.where("on_duty > ?", moment)
      TimesheetNote.where(timesheet_id: not_yet.select(:id)).delete_all
      TimesheetLog.where(timesheet_id: not_yet.select(:id)).delete_all
      not_yet.delete_all

      Timesheet.where("off_duty > ?", moment)
               .update_all(off_duty: nil, review_status: Timesheet::STATUS_UNVERIFIED)
    end

    def remove_what_had_not_happened_yet(moment, year)
      # A forced sign-in is recorded as a note on the entry, and the entries it
      # belongs to are gone. There is no way to ask for that in the usual way.
      TimesheetLog.where(created_at: moment..)
                  .where("json_extract(data, '$.forced') is not null")
                  .delete_all
      TimesheetMissing.where(created_at: moment..).delete_all
      PersonOnSite.where(created_at: moment..).delete_all

      later_years = Slot.where(begins_year: (year + 1)..)
      PersonSlot.where(slot_id: later_years.select(:id)).delete_all
      TraineeStatus.where(slot_id: later_years.select(:id)).delete_all
      later_years.delete_all

      # Built the way the database stores its own times, so the boundary falls on
      # midnight rather than an hour either side of it.
      next_year = Time.local(year + 1, 1, 1)
      PositionCredit.where(start_time: next_year..).delete_all
      Asset.where(created_at: next_year..).delete_all

      PersonAsset.where("checked_out > ?", moment).delete_all
      PersonAsset.where(checked_in: moment..).update_all(checked_in: nil, check_in_person_id: nil)
    end

    def put_people_on_site(people_ids, year)
      Person.where(id: people_ids).update_all(on_site: true, behavioral_agreement: true)

      if people_ids.any?
        PersonEvent.insert_all(people_ids.map do |id|
          { person_id: id, year: year, signed_motorpool_agreement: true, asset_authorized: true }
        end)
      end

      PersonEvent.where(year: year).update_all(signed_motorpool_agreement: true, asset_authorized: true)
    end

    def add_welcome_announcement(moment, year)
      author_id = Person.exists?(ANNOUNCEMENT_AUTHOR_ID) ? ANNOUNCEMENT_AUTHOR_ID : Person.minimum(:id)
      return if author_id.nil?

      written_at = Time.zone.local(year, 8, 1, 12, 0, 0)
      Motd.create!(subject: "Welcome to #{moment.strftime(DateTimeHelper::LONG_DATE)}!",
                   message: ANNOUNCEMENT_MESSAGE,
                   person_id: author_id,
                   for_rangers: true, for_pnvs: true, for_auditors: true,
                   expires_at: Time.zone.local(2099, 9, 1, 12, 0, 0),
                   created_at: written_at, updated_at: written_at)
    end

    def apply_settings
      values = TRUE_SETTINGS.index_with("true").merge(Setting::DASHBOARD_PERIOD => "event")
      RedactDatabase.write_settings(values)
    end

    def set_up_hq_training(year)
      password = ENV[HQ_PASSWORD_VAR]

      HQ_TRAINING_ACCOUNTS.each do |email, position_ids|
        person = Person.find_by(email:)
        if person.nil?
          Rails.logger.warn("The practice account #{email} is not in this database")
          next
        end

        pass_training(person, position_ids, year)
        person.update_column(:password, Person.new.tap { |p| p.password = password }.password) if password.present?
      end

      clear_sign_in_requirement
      clear_hq_slot_links(year)
    end

    def pass_training(person, position_ids, year)
      position_ids.each do |position_id|
        slot = Slot.where(position_id:, active: true, begins_year: year).first
        if slot.nil?
          Rails.logger.warn("There is no #{year} training session for position #{position_id}")
          next
        end

        PersonSlot.insert_all([{ slot_id: slot.id, person_id: person.id }])
        trainee_status = TraineeStatus.first_or_new_for_session(person.id, slot.id)
        trainee_status.status = TraineeStatus::STATUS_PASSED
        trainee_status.save(validate: false)
      end
    end

    # Training accounts are not on the roster for these positions, and being
    # turned away at sign-in is not what the practice is for.
    def clear_sign_in_requirement
      Position.where(id: HQ_POSITIONS).update_all(require_signin_for_roles: false)
    end

    # The links point at the real event's paperwork.
    def clear_hq_slot_links(year)
      Slot.where(begins_year: year, position_id: HQ_SLOT_POSITIONS).update_all(url: "")
    end
  end
end
