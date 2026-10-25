# frozen_string_literal: true

class Me::LanguagesController < ApplicationController
  layout "me"

  # Part of the profile, which past prospectives keep.
  skip_before_action :confine_past_prospective

  before_action :set_language, only: [:edit, :update, :destroy]

  helper_method :profile_index_path, :language_url, :language_edit_url, :language_new_url, :languages_index_url, :can_edit_languages?

  def profile_index_path = me_profile_path
  def language_url(language) = me_profile_language_path(language)
  def language_edit_url(language) = edit_me_profile_language_path(language)
  def language_new_url = new_me_profile_language_path
  def languages_index_url = me_profile_languages_path
  def can_edit_languages? = true

  def index
    render template: "profile_languages/index", locals: { person: current_user }
  end

  def new
    render template: "profile_languages/new",
           locals: { person: current_user, language: PersonLanguage.new(proficiency: PersonLanguage::PROFICIENCY_UNKNOWN) }
  end

  def edit
    render template: "profile_languages/edit", locals: { person: current_user, language: @language }
  end

  def create
    language = PersonLanguage.new(language_params)
    language.person_id = current_user.id
    if language.save
      ui_flash_successful "Language", "created"
      redirect_to action: :index
    else
      render template: "profile_languages/new",
             locals: { person: current_user, language: },
             status: :unprocessable_entity
    end
  end

  def update
    if @language.update(language_params)
      ui_flash_successful "Language", "updated"
      current_user.person_language.reload
      redirect_to action: :index
    else
      ui_flash_submit_error
      render template: "profile_languages/edit",
             locals: { person: current_user, language: @language },
             status: :unprocessable_entity
    end
  end

  def destroy
    @language.destroy
    ui_flash_successful "Language", "deleted"
    current_user.person_language.reload
    redirect_to action: :index
  end

  private

  def language_params
    params.expect(person_language: [:language_name, :language_custom, :proficiency])
  end

  def set_language
    @language = current_user.person_language.find(params.expect(:id))
  end
end
