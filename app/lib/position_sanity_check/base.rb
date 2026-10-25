# frozen_string_literal: true

# What every sanity check answers: how many issues it found, what they are,
# and how to settle the ones a reader picked.
#
# Subclasses implement #scope (a relation of the flagged rows), #build (one
# Finding per row of that relation), and #fix (settle one Finding, returning
# the messages to show). Checks that cannot be counted without building their
# findings override .count.
class PositionSanityCheck::Base
  # What one repair did to one person. messages is what the reader sees under
  # their row; error is set instead when the repair refused or failed.
  Result = Struct.new(:person_id, :callsign, :messages, :error, keyword_init: true)

  # Refusing to repair your own row, said in the results list.
  SELF_REPAIR_REFUSED = "Repairing your own access here is not allowed — " \
                        "ask another Admin to do it."

  class << self
    def count = scope.count

    def findings = scope.map { |row| build(row) }

    # Settle the findings the reader picked, and only those.
    #
    # The keys arriving from the form select from a freshly computed set --
    # they never say what to grant or revoke. Upstream posted the position and
    # team ids from the browser and granted whatever arrived, so a hand-rolled
    # POST could hand any position to anyone.
    #
    # Returns [results, skipped] -- skipped being how many submitted keys were
    # not findings at all. Which of those were settled by somebody else and
    # which were never findings is not knowable from here, and the page says so
    # rather than picking one and asserting it.
    def repair(keys)
      wanted = Array(keys).map(&:to_s).to_set
      selected = findings.select { wanted.include?(_1.key) }

      [selected.map { settle(_1) }, wanted.size - selected.size]
    end

    private

    # One finding, in its own transaction.
    #
    # Several repairs are two or three writes -- revoke the team's positions
    # AND the membership, strip positions AND teams AND permissions -- and
    # half of that is a worse state than either end of it. Every error is
    # caught, not just the authorization refusals: this action renders its
    # results from the POST precisely because a GET cannot re-derive them, so
    # an exception escaping the batch would destroy the only record of what
    # the first thirty rows did.
    def settle(finding)
      return Result.new(**identity(finding), error: SELF_REPAIR_REFUSED) if own_row?(finding)

      messages = ActiveRecord::Base.transaction { Array(fix(finding)) }
      Result.new(**identity(finding), messages:)
    rescue StandardError => e
      Result.new(**identity(finding), error: e.message)
    end

    # A revoke aimed at the reader themselves is refused.
    #
    # Nothing stops PersonPosition.remove_ids_from_person taking away a
    # position that carries the Admin role -- only the grant side is guarded --
    # so an Admin who selects everything on a revoke page can strip the role
    # that lets them open the page, and RoleManager purges the cache
    # immediately. Bulk Position Grant / Revoke refuses self-changes for the
    # same reason. Grant-band checks are left alone: handing yourself a
    # position you are already entitled to is not a hazard.
    def own_row?(finding)
      PositionSanityCheck.band(name.demodulize.underscore) == :revoke &&
        finding.person_id == Current.person&.id
    end

    def identity(finding) = { person_id: finding.person_id, callsign: finding.callsign }

    def scope = raise(NotImplementedError)

    def build(_row) = raise(NotImplementedError)

    def fix(_finding) = raise(NotImplementedError)

    def reason = PositionSanityCheck::REASON
  end
end
