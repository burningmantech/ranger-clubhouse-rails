# frozen_string_literal: true

# Moves a person's status, for a list of callsigns at once.
#
# Upstream's PersonStatusHandler, where the action id *is* the status being set
# -- "active", "alpha", "retired" -- so there is nothing to parse off the line
# and no second field to get wrong.
#
# The whitelist is what upstream's ACTIONS map amounts to: a page can only
# offer an id from its own frozen list, but `apply` writes the status with
# validation skipped, so a mistyped id here would go straight at the column. The
# database enum would refuse it on commit; raising at boot names the typo
# instead of turning it into one failed line per callsign.
class BulkUpload::StatusHandler < BulkUpload::Handler
  def initialize(...)
    super
    return if Person::ALL_STATUSES.include?(action.id)

    raise ArgumentError, "#{self.class} cannot set person status [#{action.id}]"
  end

  # The one handler that does NOT refuse a locked account, because moving a
  # person out of one is the job: deceased, dismissed, resigned, suspended and
  # uberbonked are exactly the statuses a reinstatement starts from, and
  # refusing them left no bulk path back. Upstream reaches the same place by
  # accident -- its check runs after the handler has already assigned the new
  # status, so it reads the status being moved to rather than the one being
  # moved from. Every other action still refuses a locked account outright.
  def refuses_locked_statuses? = false

  # No preload: `status` is one of the four columns the batch's narrow person
  # projection already carries, so there is nothing left to fetch.
  #
  # :change and never :replace, even though a status always lands on top of one
  # that is already there. `replace` is the preview's amber warning that a write
  # is covering an existing record; a person holds exactly one status and moving
  # it is the entire point of this page, so amber on every row would say nothing.
  def decide(entry)
    return entry.decide(:invalid, "This action takes a callsign only") unless bare?(entry)

    current = entry.person.status
    return entry.decide(:no_change, "Already #{current}") if current == action.id

    entry.decide(:change, "#{current} → #{action.id}")
  end

  # Assigning the column is the whole write.
  #
  # CRITICAL: do not call PersonStatusManagement from here. Person's after_save
  # `log_status_change` hook already fires it for a saved status change, and that
  # is what writes the person_status history row and grants or strips the
  # positions, roles and team memberships the new status carries. Calling it here
  # as well would apply every one of those side effects twice. Upstream is built
  # the same way -- Person::updated calls changeStatus -- which is why its
  # handler also does nothing but assign the column.
  #
  # Re-found whole because entry.person is the batch's four-column projection.
  # Validation is skipped for upstream's reason (saveWithoutValidation): a record
  # with an unrelated validation problem -- a missing address, no emergency
  # contact -- must still be able to have its status corrected, and correcting
  # the status is often what lets the rest of the record be repaired at all.
  def apply(entry)
    person = Person.find(entry.person.id)
    person.status = action.id
    person.audit_reason = reason
    person.save!(validate: false)
  end
end
