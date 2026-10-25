# frozen_string_literal: true

# Manage a person's certifications and external trainings.
class Person::CertificationsController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_ability :manage_certifications,
                    roles: [Role::CERTIFICATION_MGMT],
                    only: %i[new create edit update destroy],
                    deny_to: :certifications_deny_path,
                    message: "Admin or Certification Management role required to administer certification records."

  before_action :set_person_certification, only: %i[show edit update destroy]

  def index
    @person_certifications = PersonCertification.find_for_query(person_id: @person.id)
                                                .references(:certification)
                                                .order("certification.title")
    @can_manage = can?(:manage_certifications)
  end

  def show
  end

  def new
    @person_certification = PersonCertification.new(person_id: @person.id)
    load_certifications
  end

  def create
    @person_certification = PersonCertification.new(certification_params)
    @person_certification.person_id = @person.id
    @person_certification.recorder_id = Current.person_id

    if @person_certification.save
      redirect_to person_certifications_path(@person), success: "Certification created."
    else
      load_certifications
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_certifications
  end

  def update
    if @person_certification.update(certification_params)
      redirect_to person_certifications_path(@person), success: "Certification updated."
    else
      load_certifications
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @person_certification.certification.title
    @person_certification.destroy!
    redirect_to person_certifications_path(@person), success: "#{title} certification deleted."
  end

  private

  def set_person_certification
    @person_certification = PersonCertification.with_relationships
                                               .where(person_id: @person.id)
                                               .find(params[:id])
  end

  def load_certifications
    @certifications = Certification.order(:title)
  end

  def certification_params
    params.expect(person_certification: [:certification_id, :card_number, :issued_on, :trained_on, :notes])
  end

  def certifications_deny_path
    person_certifications_path(@person)
  end
end
