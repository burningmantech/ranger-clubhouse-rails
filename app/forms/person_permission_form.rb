# frozen_string_literal: true

# Form object for the person permission (manual role grant) editor.
class PersonPermissionForm
  include ActiveModel::Model

  attr_reader :role_ids

  def initialize(attributes = {})
    super()
    assign_attributes(attributes || {})
  end

  def assign_attributes(attributes)
    values = attributes.respond_to?(:to_h) ? attributes.to_h.symbolize_keys : {}
    self.role_ids = values[:role_ids]
  end

  def role_ids=(value)
    @role_ids = IdList.parse(value)
  end

  def persisted?
    false
  end

  # Apply the desired set of directly-granted roles to the person.
  #
  # Only the Tech Team may grant or revoke the Tech Ninja role, so for anyone
  # else the person's current Tech Ninja state is preserved regardless of what
  # was submitted (its checkbox is disabled in the UI and never posts).
  def save(actor:, person:, is_tech_ninja:)
    current = PersonRole.find_role_ids_for_person(person.id)
    desired = role_ids.dup

    unless is_tech_ninja
      desired.delete(Role::TECH_NINJA)
      desired << Role::TECH_NINJA if current.include?(Role::TECH_NINJA)
    end

    ApplicationRecord.transaction do
      PersonRole.add_ids_to_person(person.id, desired - current, update_reason)
      PersonRole.remove_ids_from_person(person.id, current - desired, update_reason)
    end

    true
  rescue ActiveRecord::ActiveRecordError => e
    errors.add(:base, e.message.presence || "Unable to update permissions.")
    false
  end

  private

  def update_reason
    "Person permission edit"
  end
end
