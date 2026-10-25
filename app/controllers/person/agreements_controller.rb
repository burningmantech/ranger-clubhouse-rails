# frozen_string_literal: true

# View the agreements a person has signed, and administratively correct the
# signature flags. Admins may check/uncheck for the current year only;
# Event Management gets a read-only view.
class Person::AgreementsController < ApplicationController
  layout "person"

  include PersonConcern

  before_action :setup_year

  authorize_ability :view_agreements,
                    roles: [Role::EVENT_MANAGEMENT],
                    deny_to: :agreements_deny_path,
                    message: "Admin or Event Management role required to view agreements."

  authorize_ability :manage_agreements,
                    roles: [], admin: true,
                    only: %i[update],
                    deny_to: :agreements_index_path,
                    message: "Admin permission required to update agreements."

  require_current_year_for only: %i[update],
                           deny_to: :agreements_index_path,
                           message: "Agreements may only be changed for the current year."

  def index
    @years = years_with_current(PersonEvent.where(person_id: @person.id).distinct.pluck(:year).compact)
    @can_admin = can?(:manage_agreements)
    @can_edit = @is_current_year && @can_admin
    @annual_agreements, @lifetime_agreements =
      Agreements.retrieve(@person, year: @year, include_hidden: @can_admin)
                .partition { |agreement| agreement.term == Agreements::TERM_ANNUAL }
  end

  def update
    person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)
    agreement_params.each do |tag, value|
      Agreements.admin_set_signature(@person, tag, value == "1", person_event:)
    end

    redirect_to agreements_index_path, success: "Agreements updated."
  end

  private

  def agreement_params
    params.expect(agreements: [*Agreements::DOCUMENTS.keys])
  end

  def agreements_deny_path
    person_path(@person)
  end

  def agreements_index_path
    person_agreements_path(@person, year: @year)
  end
end
