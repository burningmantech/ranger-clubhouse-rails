# frozen_string_literal: true

# Position record administration: the save and destroy rules the Ember
# admin/positions page got from the Laravel Position model's boot() hooks,
# validation rules, and save() overrides.
#
# They live here rather than on Position because the model is frozen for the
# translation. Each method notes what should move onto the model when it
# reopens.
module PositionManagement
  # The API's rule ('title' => 'required|string|max:40'), which matches the
  # column. Ember's form caps the input at the same 40.
  TITLE_MAX = 40
  SHORT_TITLE_MAX = 6
  # Column limits. Upstream validates neither, so a shorter cap here would
  # reject rows the Laravel writers legitimately store.
  CONTACT_EMAIL_MAX = 200
  PAYCODE_MAX = 20
  RESOURCE_TAG_MAX = 255

  DELETE_REASON = "Position deletion"
  SAVE_REASON = "Position record edit"

  # Booleans the schema declares NOT NULL. A blank checkbox casts to nil and
  # would reach MariaDB as a NotNullViolation 500. on_sl_report is deliberately
  # absent: it is the one nullable flag, and 73 live rows are NULL.
  BOOLEAN_COLUMNS = %i[
    active alert_when_becomes_empty alert_when_no_trainers all_rangers allow_echelon
    auto_sign_out awards_auto_grant awards_eligible awards_grants_service_year count_hours
    cruise_direction deselect_on_team_join has_art_mentoring has_online_course
    is_art_mentee is_art_mentor is_checkin_time_restricted
    mvr_eligible mvr_signup_eligible new_user_eligible no_payroll_hours_adjustment
    no_training_required not_timesheet_eligible on_trainer_report
    prevent_multiple_enrollments pvr_eligible require_signin_for_roles
    require_training_for_roles
  ].freeze

  # Numbers the schema declares NOT NULL. Both are number fields on the form and
  # both cast a cleared input to nil, which the model lets through (it validates
  # numericality with allow_nil) and MariaDB then rejects with a 500. Clearing
  # the hour cap is the obvious way to say "no cap", so this is reachable.
  #
  # The messages name their own field: config/locales/en.yml sets
  # `errors.format: "%{message}"`, so nothing prefixes the attribute.
  NOT_NULL_NUMBERS = {
    min: "Minimum per slot cannot be blank -- enter 0 for no minimum",
    sign_out_hour_cap: "Hour cap cannot be blank -- enter 0 for no cap"
  }.freeze

  # Roles too dangerous to hand out through a position without already holding
  # them. Upstream guards the same pair in PositionController#bulkGrantRevoke,
  # and TeamManagement guards them on the team side.
  GUARDED_ROLE_IDS = [Role::ADMIN, Role::TECH_NINJA].freeze

  # Columns upstream stores as NULL rather than "" (its BlankIfEmptyAttribute
  # on paycode() and resourceTag()). The Laravel writers still share these
  # tables, so a blank one written here would make `where(paycode: nil)`
  # disagree depending on who saved the row.
  NULL_IF_EMPTY = %i[paycode resource_tag contact_email short_title].freeze

  module_function

  # Validate and persist, syncing permission grants when the actor may change
  # them. Errors land on the position so the form redisplays them; returns
  # false instead of raising, like ActiveRecord#save.
  #
  # Move to Position when it reopens: the cross-field validations and the
  # awards zeroing as a before_save.
  def save(position, role_ids: nil, is_tech_ninja: false)
    NULL_IF_EMPTY.each { |column| position[column] = position[column].presence }
    preserve_null_sl_report(position)

    desired_roles = IdList.parse(role_ids) if is_tech_ninja && role_ids
    return false unless valid?(position, desired_roles)

    # Upstream's saving() hook. The two automation columns are meaningless
    # without awards eligibility, and leaving them set would let the automation
    # fire against a position that is no longer eligible.
    unless position.awards_eligible
      position.awards_auto_grant = false
      position.awards_grants_service_year = false
    end

    creating = position.new_record?
    changes = position.changes.except("created_at", "updated_at")

    ApplicationRecord.transaction do
      position.save!
      # desired_roles is nil when the form never offered the field (a non-Tech
      # Ninja edit), and [] when a Tech Ninja cleared every box -- only the
      # latter should revoke.
      Membership.update_position_roles(position.id, desired_roles, SAVE_REASON) if desired_roles
      # Upstream's Position model is auditModel = true, so the Laravel app has
      # been writing position-create / position-update rows to this shared
      # table all along. Without this the trail simply stops at the port.
      if creating || changes.any?
        ActionLog.record(Current.person, creating ? "position-create" : "position-update",
                         SAVE_REASON, changes.merge("id" => position.id))
      end
    end

    # Positions feed RoleManager's per-person role cache and the position
    # lookups the dashboard leans on. Upstream flushes on every position save
    # for the same reason.
    Rails.cache.clear
    true
  end

  # Delete the position and everything that points at it. Returns false with an
  # error on the position when it carries service history -- see deletable?.
  #
  # The row goes with a callback-free `position.delete` rather than
  # `position.destroy`: the cascade below revokes each permission grant through
  # Membership so every revocation leaves its own audit entry, and letting the
  # model's dependent: :destroy run as well would take the slots a second time.
  def destroy(position)
    return false unless deletable?(position)

    position_id = position.id
    title = position.title
    counts = child_counts(position)

    ApplicationRecord.transaction do
      slot_ids = Slot.where(position_id:).pluck(:id)
      # Destroyed one at a time rather than deleted in bulk: each slot takes
      # its sign-ups, trainer statuses, and trainee statuses with it through
      # its own dependent: :destroy associations.
      Slot.where(position_id:).find_each(&:destroy!)
      # Slot only cascades trainer_status through trainer_slot_id, so a trainer
      # whose own shift sits on another position is left holding a row that
      # names a session that no longer exists.
      TrainerStatus.where(slot_id: slot_ids).find_each(&:destroy!) if slot_ids.any?
      # Upstream deletes person_position and person_award rows outright on
      # delete (no per-row audit), so the grant history is not rewritten here
      # either -- but PersonAward's after_destroy recomputes the person's
      # years of awards, and a bulk delete would leave those years counting
      # awards that no longer exist.
      PersonAward.where(position_id:).find_each(&:destroy!)
      PersonPosition.where(position_id:).delete_all
      PositionLineupMember.where(position_id:).delete_all
      # The Shift Coverage definitions hold position ids inside JSON lists, out
      # of a foreign key's reach, so each model is asked to let go of this one.
      ShiftCoverageGroup.remove_position(position_id, reason: DELETE_REASON)
      ShiftCoveragePosition.remove_position(position_id, reason: DELETE_REASON)
      # None of these carry a nullable position_id, so there is nothing to
      # release: an orphan here is a row no page can reach and no admin can
      # remove. PositionCredit rows also sit in a cached per-year map.
      PositionCredit.where(position_id:).delete_all
      PersonOnlineCourse.where(position_id:).delete_all
      OnlineCourse.where(position_id:).delete_all
      # These two are nullable, so the surveys themselves survive.
      Survey.where(position_id:).update_all(position_id: nil)
      Survey.where(mentoring_position_id: position_id).update_all(mentoring_position_id: nil)
      # Revoked through Membership rather than deleted in bulk, so each lost
      # permission grant leaves its own audit entry -- the same path save takes.
      Membership.update_position_roles(position_id, [], DELETE_REASON)
      # Upstream NULLs the children's parent_position_id. It leaves
      # training_position_id dangling, which then names a position that no
      # longer exists on every edit form and training lookup -- NULLed here on
      # purpose.
      Position.where(parent_position_id: position_id).update_all(parent_position_id: nil)
      release_trained_positions(position_id)
      Timesheet.where(desired_position_id: position_id).update_all(desired_position_id: nil)
      # person_position_log rows are kept: they are the audit trail of who was
      # granted this position and when, and upstream keeps them too. Their
      # titles fall back to "Position #id" once the row is gone.
      position.delete
      ActionLog.record(Current.person, "position-delete", DELETE_REASON,
                       { position_id:, title: }.merge(counts))
    end

    # Everyone who held this position loses whatever permissions it granted,
    # and those role sets are cached per person.
    Rails.cache.clear
    true
  end

  # A position whose hours people actually rangered is not deletable. Both
  # timesheet.position_id and timesheet_missing.position_id are NOT NULL, so
  # there is nothing to release, and deleting the rows would erase service
  # history that feeds appreciations, awards and payroll. Retiring the position
  # with the Active flag is the way to take it out of circulation.
  def deletable?(position)
    return true unless position.persisted?

    count = service_history_count(position.id)
    return true if count.zero?

    position.errors.add(:base,
                        "This position cannot be deleted: #{count} timesheet #{"entry".pluralize(count)} " \
                        "#{count == 1 ? "names" : "name"} it. Mark it inactive instead -- " \
                        "deleting it would erase service history.")
    false
  end

  def service_history_count(position_id)
    Timesheet.where(position_id:).count + TimesheetMissing.where(position_id:).count
  end

  # Dropping the training a position points at also has to drop the requirement
  # to have passed it. RoleManager reads require_training_for_roles together
  # with training_position_id: with the id NULLed and the flag still set, the
  # position confers nothing (as in Clubhouse 2), so every holder would lose its
  # roles with no training left to pass. The flag would also fail the
  # position's own validation, leaving it unsaveable.
  def release_trained_positions(position_id)
    Position.where(training_position_id: position_id)
            .update_all(training_position_id: nil, require_training_for_roles: false)
  end

  # What a delete would take with it. Read once for the confirmation dialog and
  # again for the audit entry, so both name the same numbers.
  def child_counts(position)
    return EMPTY_COUNTS.dup unless position.persisted?

    # A subquery rather than a plucked id list: a long-lived position carries
    # thousands of slots, and this runs on every edit-form render.
    slots = Slot.where(position_id: position.id)
    slot_ids = slots.select(:id)

    {
      slot_count: slots.count,
      signup_count: PersonSlot.where(slot_id: slot_ids).count,
      trainee_count: TraineeStatus.where(slot_id: slot_ids).count,
      trainer_count: TrainerStatus.where(slot_id: slot_ids).count,
      grant_count: PersonPosition.where(position_id: position.id).count,
      award_count: PersonAward.where(position_id: position.id).count,
      child_count: Position.where(parent_position_id: position.id).count,
      trained_count: Position.where(training_position_id: position.id).count,
      lineup_count: PositionLineupMember.where(position_id: position.id).count,
      shift_coverage_type_count: ShiftCoverageGroup.listing_position(position.id).size,
      shift_coverage_post_count: ShiftCoveragePosition.listing_position(position.id).size,
      timesheet_count: service_history_count(position.id)
    }
  end

  EMPTY_COUNTS = {
    slot_count: 0, signup_count: 0, trainee_count: 0, trainer_count: 0,
    grant_count: 0, award_count: 0, child_count: 0, trained_count: 0,
    lineup_count: 0, shift_coverage_type_count: 0, shift_coverage_post_count: 0, timesheet_count: 0
  }.freeze

  # on_sl_report is the one nullable flag on the table, and a checkbox posts its
  # hidden "0" companion whether or not the reader touched it. Without this,
  # saving any of the NULL rows for an unrelated reason rewrites NULL to false
  # and logs a change no one made. Nothing here reads the two differently, so
  # the third state is left alone rather than normalized away -- the Laravel
  # writers still share this column.
  def preserve_null_sl_report(position)
    position.on_sl_report = nil if position.on_sl_report == false && position.on_sl_report_was.nil?
  end

  # Position validates title, short_title, min, max, and type already. What is
  # checked here is everything else the columns or upstream require: the three
  # cross-field rules from the Laravel model's save() override, the two
  # validations that only ever existed in the Ember form, and the NOT NULL
  # booleans a cleared checkbox would send as nil.
  #
  # desired_roles is nil unless the actor may change permission grants.
  def valid?(position, desired_roles = nil)
    # Runs first because it clears the error set. The model owns the three
    # cross-field rules (training position required, no_training_required
    # conflict, parent-is-self); repeating them here reported every one of them
    # to the reader twice, in two different wordings.
    position.valid?

    validate_lengths(position)
    validate_numbers(position)
    validate_references(position)

    BOOLEAN_COLUMNS.each do |column|
      position.errors.add(column, "must be true or false") if position[column].nil?
    end

    NOT_NULL_NUMBERS.each do |column, message|
      position.errors.add(column, message) if position[column].nil?
    end

    position.errors.add(:team_category, "The team category is not valid.") unless TEAM_CATEGORIES.include?(position.team_category)

    validate_roles(position, desired_roles) if desired_roles

    position.errors.empty?
  end

  TEAM_CATEGORIES = [
    Position::TEAM_CATEGORY_PUBLIC,
    Position::TEAM_CATEGORY_ALL_MEMBERS,
    Position::TEAM_CATEGORY_OPTIONAL
  ].freeze

  def validate_lengths(position)
    { contact_email: CONTACT_EMAIL_MAX, paycode: PAYCODE_MAX,
      resource_tag: RESOURCE_TAG_MAX }.each do |column, limit|
      value = position[column]
      position.errors.add(column, "must be #{limit} characters or fewer") if value.present? && value.length > limit
    end
  end

  # The three foreign keys the form offers are all `optional: true` and the
  # table carries no database foreign keys, so nothing rejects an id naming no
  # row -- upstream validates all three with `exists:`. Without this the index
  # renders "No team" and "Position #999998" placeholders for a position that
  # looks saved.
  REFERENCES = {
    team_id: [Team, "The chosen team no longer exists"],
    parent_position_id: [Position, "The chosen parent position no longer exists"],
    training_position_id: [Position, "The chosen training position no longer exists"]
  }.freeze

  def validate_references(position)
    REFERENCES.each do |column, (model, message)|
      id = position[column]
      next if id.blank? || model.exists?(id:)

      position.errors.add(column, message)
    end
  end

  # Validated by the Ember form alone upstream, so the API accepts both -- but
  # a negative cap signs people out the moment they sign in, and a malformed
  # address silently drops every notification the position sends.
  def validate_numbers(position)
    cap = position.sign_out_hour_cap
    position.errors.add(:sign_out_hour_cap, "The hour cap must be zero or more hours.") if cap.present? && cap.negative?

    email = position.contact_email
    return if email.blank? || email.match?(URI::MailTo::EMAIL_REGEXP)

    position.errors.add(:contact_email, "The contact email is not a valid email address.")
  end

  # position_role carries no foreign key, so an id naming no role would only
  # fail deep inside PositionRole.add -- rolling back the reader's other edits
  # and landing them on a bare error page. Granting a role is also how a
  # position hands everyone holding it that role, so the two that could
  # escalate a whole roster need the actor to already hold them.
  def validate_roles(position, desired_roles)
    unknown = desired_roles - Role.where(id: desired_roles).pluck(:id)
    position.errors.add(:role_ids, "The role grants include #{unknown.sort.join(", ")}, which name no role.") if unknown.any?

    held = position.persisted? ? PositionRole.find_all_for_position(position.id).pluck(:role_id) : []
    (desired_roles - held).intersection(GUARDED_ROLE_IDS).each do |role_id|
      next if Current.person&.has_role?(role_id)

      title = Role.find_by(id: role_id)&.title || "Role ##{role_id}"
      position.errors.add(:role_ids, "You cannot grant #{title}: you do not hold it yourself.")
    end
  end
end
