# frozen_string_literal: true

# Applies a status change to a single access document owned by a person, banking
# or releasing related tickets and vehicle passes as needed. Ported from the
# Laravel AccessDocumentController::updateStatus / applyStatusChange.
#
# Any update to a ticket triggers a check of the person's other tickets and
# vehicle passes so a claimed pass is never left dangling and the system cannot
# be gamed into handing out a vehicle pass without a claimed ticket.
#
# Usage:
#   AccessDocumentStatusChange.new(person_id:, document:, status:).call
class AccessDocumentStatusChange
  # Raised when the requested status change is not permitted for the document.
  class InvalidTransition < StandardError; end

  STATUSES = [
    AccessDocument::QUALIFIED,
    AccessDocument::CLAIMED,
    AccessDocument::BANKED
  ].freeze

  VEHICLE_PASS_TYPES = [
    AccessDocument::VEHICLE_PASS_SP,
    AccessDocument::VEHICLE_PASS_GIFT
  ].freeze

  # @param person_id [Integer] owner of the document
  # @param document [AccessDocument] the document whose status is changing
  # @param status [String] the requested status
  def initialize(person_id:, document:, status:)
    @person_id = person_id
    @document = document
    @status = status
  end

  # Apply the change within a transaction.
  #
  # @return [Array<AccessDocument>] the person's affected rows
  # @raise [InvalidTransition]
  def call
    rows = load_rows
    ad = rows.find { |row| row.id == @document.id }
    raise InvalidTransition, "Document not found" unless ad

    AccessDocument.transaction do
      apply(ad, rows)
    end

    rows
  end

  private

  # The person's active tickets and passes, excluding LSD items which are never
  # user-adjustable.
  def load_rows
    AccessDocument
      .where(person_id: @person_id)
      .where(status: STATUSES)
      .where.not(type: [AccessDocument::LSD, AccessDocument::VEHICLE_PASS_LSD])
      .to_a
  end

  def apply(ad, rows)
    case @status
    when AccessDocument::BANKED
      validate_banked(ad)
    when AccessDocument::CLAIMED
      apply_claimed(ad, rows)
    when AccessDocument::QUALIFIED
      validate_qualified(ad)
    else
      raise InvalidTransition, "Unknown status action"
    end

    ad.status = @status
    ad.audit_reason = "status changed to #{@status}"
    ad.save!(validate: false)

    revert_gamed_vehicle_passes(rows)
  end

  # Only regular tickets (SPT / Staff Credential) in an active status may be banked.
  def validate_banked(ad)
    return if ad.regular_ticket? && AccessDocument::ACTIVE_STATUSES.include?(ad.status)

    raise InvalidTransition, "Illegal type and status combination"
  end

  def apply_claimed(ad, rows)
    unless [AccessDocument::QUALIFIED, AccessDocument::BANKED, AccessDocument::CLAIMED].include?(ad.status)
      raise InvalidTransition, "Document is not banked, claimed, or qualified"
    end

    if ad.regular_ticket?
      bank_other_tickets(ad, rows)
      release_mismatched_vehicle_passes(ad, rows)
    elsif VEHICLE_PASS_TYPES.include?(ad.type)
      release_other_vehicle_passes(ad, rows)
    end
  end

  # A claimed regular ticket banks the person's other SPT / Staff Credential tickets.
  def bank_other_tickets(ad, rows)
    rows.each do |ticket|
      next if ticket.id == ad.id
      next unless [AccessDocument::STAFF_CREDENTIAL, AccessDocument::SPT].include?(ticket.type)

      ticket.status = AccessDocument::BANKED
      ticket.audit_reason = "other ticket claimed"
      ticket.save!(validate: false)
    end
  end

  # Releasing the vehicle pass that does not match the claimed ticket type:
  # a Staff Credential releases the SP vehicle pass; an SPT releases the Gift vehicle pass.
  def release_mismatched_vehicle_passes(ad, rows)
    rows.each do |pass|
      next unless VEHICLE_PASS_TYPES.include?(pass.type)

      if ad.staff_credential? && pass.type == AccessDocument::VEHICLE_PASS_SP
        release_pass(pass, "staff credential claimed - released SP VP")
      elsif ad.type == AccessDocument::SPT && pass.type == AccessDocument::VEHICLE_PASS_GIFT
        release_pass(pass, "SP ticket claimed - released Gift VP")
      end
    end
  end

  # Claiming a vehicle pass releases the person's other vehicle passes.
  def release_other_vehicle_passes(ad, rows)
    rows.each do |pass|
      next if pass.id == ad.id
      next unless VEHICLE_PASS_TYPES.include?(pass.type)

      release_pass(pass, "other vehicle pass claimed")
    end
  end

  # Only SAP, Vehicle Pass, or Gift documents may be reverted to qualified, and only from claimed.
  def validate_qualified(ad)
    allowed = [AccessDocument::SAP, AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::VEHICLE_PASS_SP, AccessDocument::GIFT]
    unless allowed.include?(ad.type)
      raise InvalidTransition, "Document is not a SAP, Vehicle Pass nor Gift Ticket."
    end

    raise InvalidTransition, "Document is not claimed." unless ad.status == AccessDocument::CLAIMED
  end

  # Anti-gaming rule: if the person has no available (unbanked) ticket, revert any
  # claimed vehicle passes back to qualified so no one keeps a pass without a ticket.
  def revert_gamed_vehicle_passes(rows)
    return unless AccessDocument.no_available_tickets?(@person_id)

    rows.each do |vp|
      next unless vp.status == AccessDocument::CLAIMED && VEHICLE_PASS_TYPES.include?(vp.type)

      release_pass(vp, "all tickets were banked")
    end
  end

  def release_pass(pass, reason)
    pass.status = AccessDocument::QUALIFIED
    pass.audit_reason = reason
    pass.save!(validate: false)
  end
end
