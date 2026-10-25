# frozen_string_literal: true

class Person::LanguagesController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_role [Role::ADMIN, Role::VC, Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA]

  before_action :require_edit_permission, only: %i[new create edit update destroy]
  before_action :set_language, only: %i[edit update destroy]

  helper_method :profile_index_path, :language_url, :language_edit_url, :language_new_url, :languages_index_url, :can_edit_languages?

  def profile_index_path = person_profile_path(@person)
  def language_url(language) = person_profile_language_path(@person, language)
  def language_edit_url(language) = edit_person_profile_language_path(@person, language)
  def language_new_url = new_person_profile_language_path(@person)
  def languages_index_url = person_profile_languages_path(@person)
  def can_edit_languages? = has_role?([Role::ADMIN, Role::VC])

  def index
    render template: "profile_languages/index", locals: { person: @person }
  end

  def new
    render template: "profile_languages/new",
           locals: { person: @person, language: PersonLanguage.new(proficiency: PersonLanguage::PROFICIENCY_UNKNOWN) }
  end

  def edit
    render template: "profile_languages/edit", locals: { person: @person, language: @language }
  end

  def create
    language = PersonLanguage.new(language_params)
    language.person_id = @person.id
    if language.save
      ui_flash_successful "Language", "created"
      redirect_to action: :index
    else
      render template: "profile_languages/new",
             locals: { person: @person, language: },
             status: :unprocessable_entity
    end
  end

  def update
    if @language.update(language_params)
      ui_flash_successful "Language", "updated"
      @person.person_language.reload
      redirect_to action: :index
    else
      ui_flash_submit_error
      render template: "profile_languages/edit",
             locals: { person: @person, language: @language },
             status: :unprocessable_entity
    end
  end

  def destroy
    @language.destroy
    ui_flash_successful "Language", "deleted"
    @person.person_language.reload
    redirect_to action: :index
  end

  private

  def require_edit_permission
    return true if can_edit_languages?
    redirect_to person_profile_path(@person), alert: "You are not permitted to edit languages for this person."
    false
  end

  def language_params
    params.expect(person_language: [:language_name, :language_custom, :proficiency])
  end

  def set_language
    @language = @person.person_language.find(params.expect(:id))
  end
end
