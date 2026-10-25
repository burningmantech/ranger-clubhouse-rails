# frozen_string_literal: true

module ProfileSubjectConcern
  extend ActiveSupport::Concern
  include ProfilePolicyConcern

  PERMITTED_FIELDS = %i[
    first_name mi last_name preferred_name gender_identity gender_custom
    pronouns pronouns_custom home_phone alt_phone email camp_location
    emergency_contact callsign_pronounce street1 apt street2 country city
    state zip tshirt_swag_id tshirt_secondary_swag_id long_sleeve_swag_id
  ].freeze

  SECTION_IDS = %w[identity-info mailing-address camp emergency-contact clothing].freeze
  EDIT_NOT_ELIGIBLE_SECTIONS = %w[camp emergency_contact clothing].freeze

  included do
    before_action :validate_section, only: %i[edit update]
    before_action :require_edit_permission, only: %i[edit update]
    before_action :require_section_visible, only: %i[edit update]
    before_action :check_section_edit_for_eligible, only: %i[edit update]
    before_action :retrieve_person_event, if: -> { action_name == "index" || action_name == "show" }

    helper_method :subject_person,
                  :profile_index_path,
                  :profile_edit_section_path,
                  :profile_section_path,
                  :profile_photos_new_path,
                  :profile_photos_path,
                  :profile_photo_crop_path,
                  :profile_photo_path,
                  :profile_languages_path,
                  :profile_alerts_edit_path,
                  :profile_password_edit_path,
                  :profile_passkeys_path,
                  :profile_mark_reviewed_path
  end

  def render_profile_show
    @alerts = PersonAlert.find_all_for_person(subject_person.id) if can_view_alert_preferences?
    render template: "profile/show", locals: { person: subject_person }
  end

  def edit
    locals = load_clothing_options.merge(person: subject_person)
    render template: "profile/#{@section_name}_edit", locals: locals
  end

  def update
    if subject_person.update(profile_params)
      ui_flash_successful "Profile", "updated"
      after_successful_update
      redirect_to profile_index_path
    else
      ui_flash_submit_error
      # A form answered with a plain 200 is thrown away rather than shown, so a
      # rejected save has to say so with its status or the person sees nothing
      # happen at all.
      render template: "profile/#{@section_name}_edit",
             locals: load_clothing_options.merge(person: subject_person),
             status: :unprocessable_entity
    end
  end

  private

  def subject_person
    raise NotImplementedError, "#{self.class} must define #subject_person"
  end

  def profile_index_path
    raise NotImplementedError, "#{self.class} must define #profile_index_path"
  end

  def profile_edit_section_path(_section_id)
    raise NotImplementedError, "#{self.class} must define #profile_edit_section_path"
  end

  def profile_section_path(_section_id)
    raise NotImplementedError, "#{self.class} must define #profile_section_path"
  end

  def profile_photos_new_path
    nil
  end

  def profile_photos_path
    nil
  end

  def profile_photo_crop_path(_photo)
    nil
  end

  def profile_photo_path(_photo)
    nil
  end

  def profile_languages_path
    nil
  end

  def profile_alerts_edit_path
    nil
  end

  def profile_password_edit_path
    nil
  end

  def profile_passkeys_path
    nil
  end

  def profile_mark_reviewed_path
    nil
  end

  def after_successful_update
    # Hook for subclasses (e.g., admin route logs the change).
  end

  def profile_params
    params.expect(person: [*PERMITTED_FIELDS])
  end

  def validate_section
    @section_id = params[:section_id]
    if @section_id.blank? || !SECTION_IDS.include?(@section_id)
      head :unprocessable_entity
      return false
    end
    @section_name = @section_id.underscore
    true
  end

  def require_edit_permission
    return true if can_edit_profile?

    redirect_to profile_index_path, alert: "You are not permitted to edit this profile."
    false
  end

  def require_section_visible
    visible = case @section_name
              when "identity_info"     then can_view_identity_basics?
              when "mailing_address"   then can_view_mailing_address?
              when "camp"              then can_view_camp?
              when "emergency_contact" then can_view_emergency_contact_section?
              when "clothing"          then can_view_clothing?
              else false
              end
    return true if visible

    redirect_to profile_index_path, alert: "Section not available."
    false
  end

  def check_section_edit_for_eligible
    return true if subject_person.is_contributor_or_applicant?
    if EDIT_NOT_ELIGIBLE_SECTIONS.include?(@section_name)
      redirect_to profile_index_path, error: "You are not permitted to edit that section"
      return false
    end
    true
  end

  def retrieve_person_event
    @person_event = PersonEvent.first_or_new_for_person_year(subject_person.id, Current.year)
  end

  def load_clothing_options
    return {} unless @section_name == "clothing"
    shirt_select_options(Swag.retrieve_shirts, true)
  end
end
