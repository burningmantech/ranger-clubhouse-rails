# frozen_string_literal: true

module ProfilePolicyConcern
  extend ActiveSupport::Concern

  included do
    attr_accessor :is_me

    helper_method :viewing_self?,
                  :can_edit_profile?,
                  :can_view_identity_basics?,
                  :can_view_contact_methods?,
                  :can_view_mailing_address?,
                  :can_view_camp?,
                  :can_view_clothing?,
                  :can_view_bmid?,
                  :can_view_languages?,
                  :can_view_emergency_contact_section?,
                  :should_show_emergency_contact_denial?,
                  :can_view_alert_preferences?,
                  :can_edit_alert_preferences?,
                  :can_upload_bmid_photo?
  end

  private

  def viewing_self?
    @is_me
  end

  def can_edit_profile?
    viewing_self? || has_role?([Role::ADMIN, Role::VC])
  end

  def can_view_identity_basics?
    viewing_self? || has_role?([Role::ADMIN, Role::VC]) || Current.event_management?
  end

  def can_view_contact_methods?
    viewing_self? || has_role?([Role::ADMIN, Role::VC])
  end

  def can_view_mailing_address?
    viewing_self? || has_role?([Role::ADMIN, Role::VC, Role::VIEW_PII])
  end

  def can_view_camp?
    can_view_identity_basics?
  end

  def can_view_clothing?
    can_view_identity_basics?
  end

  def can_view_bmid?
    can_view_identity_basics?
  end

  def can_view_languages?
    can_view_identity_basics?
  end

  def can_view_emergency_contact_section?
    viewing_self? || has_role?([Role::ADMIN, Role::VC]) || Current.can_view_emergency_contact?
  end

  def should_show_emergency_contact_denial?
    !can_view_emergency_contact_section?
  end

  def can_view_alert_preferences?
    viewing_self? || Current.admin?
  end

  def can_edit_alert_preferences?
    viewing_self? || has_role?(Role::ADMIN)
  end

  def can_upload_bmid_photo?
    viewing_self? || has_role?([Role::ADMIN, Role::VC])
  end
end
