# frozen_string_literal: true

# Who may become an Alpha, and the act of making them one. Ported from
# port/api/ProspectiveNewVolunteer.php, which backs the Mentors' bulk
# conversion page (/mentoring/convert-prospectives).
#
# Eligibility lives here alone, and both callers go through `trained_person_ids`
# -- the page draws its roster from it, and `convert` re-checks every submitted
# id against it. A row the page offers and a row the POST accepts therefore
# cannot diverge.
module ProspectiveConversion
  # Written to the status-history audit trail, verbatim from upstream.
  AUDIT_REASON = "Mentor bulk convert"

  module_function

  # Who can be converted at all, before training is considered. Shared by the
  # roster query and the conversion so "convertible" has one definition.
  def eligible_scope
    Person.where(status: Person::PROSPECTIVE)
  end

  # Everyone the page may offer: Prospectives who passed a `year` training
  # session. `among` narrows to a submitted selection.
  #
  # @return [Array<Integer>]
  def eligible_ids(year, among: nil)
    scope = among ? eligible_scope.where(id: among) : eligible_scope

    # Plucked rather than passed as a relation: did_ids_pass_for_year guards on
    # `blank?`, which would load the whole scope to answer.
    trained_person_ids(scope.pluck(:id), year)
  end

  # Who among `people` passed a `year` training session.
  #
  # Training owns the check: `did_ids_pass_for_year` resolves which slots count
  # as this training through `Training.session_position_ids`, the single
  # authority the session pages and the other reports already share, so a fold
  # added there cannot leave this page behind. It also counts trainers who
  # attended, which upstream's trainee-only query did not -- a vacuous
  # difference here, since a Prospective cannot hold a trainer position.
  #
  # Deliberately not restricted to ended sessions: upstream checks `passed`
  # alone, so someone marked passed before their session formally ends is
  # eligible. Their row chips "training pending" -- Intake's training status
  # does require an ended slot -- which is honest about where they stand.
  #
  # @param people [Array<Integer>, ActiveRecord::Relation]
  # @param year [Integer]
  # @return [Array<Integer>]
  def trained_person_ids(people, year)
    Training.did_ids_pass_for_year(people, Position::TRAINING, year).keys
  end

  # Make trained Prospectives into Alphas, in one transaction with the rows
  # locked. The submitted list is stale by definition -- another mentor may have
  # converted or bonked someone since the page was drawn -- so ids that are no
  # longer eligible are dropped rather than trusted.
  #
  # Saving is what grants the Alpha position: PersonStatusManagement, reached
  # through Person's status callback, writes the status-history row and the
  # position grant.
  #
  # @param ids [Array<Integer>] the people a mentor checked
  # @param year [Integer]
  # @return [Array<Person>] the people actually converted, by callsign
  def convert(ids, year)
    Person.transaction do
      # Locked before the training check, so no one's status can move between
      # being judged eligible and being converted.
      people = eligible_scope.where(id: ids).order(:callsign).lock.to_a
      eligible = trained_person_ids(people.map(&:id), year)

      people.select { |person| eligible.include?(person.id) }.each do |person|
        person.status = Person::ALPHA
        person.audit_reason = AUDIT_REASON
        person.save!(validate: false)
      end
    end
  end
end
