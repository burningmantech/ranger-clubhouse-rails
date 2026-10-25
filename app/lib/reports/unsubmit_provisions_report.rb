# frozen_string_literal: true

# People who look like they should have their provisions un-submitted.
#
# Someone who claimed or submitted earned provisions but never rangered that
# year did not consume them; before the post-event cleanup marks those
# provisions used, this report recommends returning them to available. The
# context columns (ticket, SAP, BMID, sign-ups) help the operator judge whether
# the person really was a no-show.
#
# Port of the Laravel ProvisionUnsubmitRecommendationReport behind the Ember
# vc/access-documents/unsubmit-provisions page. Upstream's sign-up lookup
# joined person_slot.person_id against slot.id -- garbage -- so its signed_up
# flag never meant anything; this port joins the slot properly.
class UnsubmitProvisionsReport
  # One candidate: their earned claimed/submitted provisions plus the no-show
  # context. ticket is the person's claimed or submitted SPT or Staff
  # Credential, nil when they hold neither.
  Row = Data.define(:person, :provisions, :ticket, :has_sap, :bmid, :signed_up) do
    # Cell text resolved once for both the table and the CSV export so the two
    # can never disagree (the arrival_label convention).
    def ticket_summary
      "#{ticket.display_ref} #{ticket.short_type_label} #{ticket.status}" if ticket
    end

    def provision_summaries
      provisions.map { |provision| "#{provision.display_ref} #{provision.type_label} #{provision.status}" }
    end
  end

  # Statuses that mean "spoken for but not yet consumed".
  CONSUMABLE_STATUSES = [Provision::CLAIMED, Provision::SUBMITTED].freeze

  TICKET_TYPES = [AccessDocument::STAFF_CREDENTIAL, AccessDocument::SPT].freeze

  # @param year [Integer] the event year being cleaned up
  # @return [Array<Row>] sorted by callsign, case-insensitively
  def self.execute(year)
    new(year).execute
  end

  def initialize(year)
    @year = year
  end

  def execute
    provisions = Provision.where(status: CONSUMABLE_STATUSES, is_allocated: false)
                          .includes(:person)
                          .order(:type)
                          .group_by(&:person_id)
    return [] if provisions.empty?

    ids = provisions.keys
    worked = worked_ids(ids)
    tickets = tickets_by_person(ids)
    saps = sap_holder_ids(ids)
    bmids = submitted_bmid_ids(ids)
    signups = signed_up_ids(ids)

    provisions.filter_map { |person_id, rows|
      person = rows.first.person
      next if person.nil? || worked.include?(person_id)

      ticket = tickets[person_id]
      Row.new(person:, provisions: rows, ticket:,
              has_sap: saps.include?(person_id) || ticket&.type == AccessDocument::STAFF_CREDENTIAL,
              bmid: bmids.include?(person_id),
              signed_up: signups.include?(person_id))
    }.sort_by { |row| row.person.callsign.downcase }
  end

  private

  def worked_ids(ids)
    Timesheet.where(person_id: ids).for_year(@year).distinct.pluck(:person_id).to_set
  end

  def tickets_by_person(ids)
    AccessDocument.where(person_id: ids, type: TICKET_TYPES,
                         status: [AccessDocument::CLAIMED, AccessDocument::SUBMITTED])
                  .order(:id)
                  .index_by(&:person_id)
  end

  def sap_holder_ids(ids)
    AccessDocument.where(person_id: ids, type: AccessDocument::SAP,
                         status: [AccessDocument::CLAIMED, AccessDocument::SUBMITTED])
                  .distinct.pluck(:person_id).to_set
  end

  def submitted_bmid_ids(ids)
    Bmid.where(person_id: ids, year: @year, status: Bmid::SUBMITTED).distinct.pluck(:person_id).to_set
  end

  # Non-training sign-ups for the year: evidence the person meant to ranger.
  #
  # Written as "the slot's position is not one of the Training positions"
  # rather than a join onto position.type != 'Training'. position.type is
  # nullable, and in SQL a NULL type is not "not Training" -- it is unknown, so
  # the comparison dropped the row and the person lost a sign-up they have.
  def signed_up_ids(ids)
    PersonSlot.joins(:slot)
              .where(person_id: ids, slot: { begins_year: @year })
              .where.not(slot: { position_id: Position.by_type(Position::TYPE_TRAINING)
                                                      .select(:id) })
              .distinct.pluck(:person_id).to_set
  end
end
