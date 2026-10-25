# frozen_string_literal: true

# Administer a person's access documents (tickets, vehicle passes, SAPs).
#
# Unlike the self-service claim/bank flow (AccessDocumentStatusChange), admin
# edits are plain saves — the model callbacks handle delivery-method defaults,
# clearing fields that don't apply to the type, and comment prepending.
class Person::AccessDocumentsController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to administer ticketing records."

  before_action :set_document, only: %i[edit update destroy history]
  before_action :set_ticketing_info, only: %i[new edit]

  def new
    year = Current.year
    @document = AccessDocument.new(
      person_id: @person.id,
      type: AccessDocument::SPT,
      status: AccessDocument::QUALIFIED,
      source_year: year,
      expiry_date: year + 3,
      delivery_method: AccessDocument::DELIVERY_NONE
    )
  end

  def create
    @document = AccessDocument.new(document_params)
    @document.person_id = @person.id

    if @document.save
      redirect_to person_tickets_provisions_path(@person),
                  success: "Access document #{@document.display_ref} created."
    else
      set_ticketing_info
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @document.update(document_params)
      redirect_to person_tickets_provisions_path(@person),
                  success: "Access document #{@document.display_ref} updated."
    else
      set_ticketing_info
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy!
    redirect_to person_tickets_provisions_path(@person),
                success: "Access document #{@document.display_ref} deleted."
  end

  def history
    @changes = @document.access_document_changes.includes(:changer_person).order(:created_at, :id)
  end

  private

  def set_document
    @document = AccessDocument.find_for_person(@person.id, params[:id])
  end

  def set_ticketing_info
    @ticketing_info = TicketingInfo.new
  end

  def document_params
    params.expect(access_document: [:type, :status, :source_year, :expiry_date, :delivery_method,
                                    :admission_date, :name, :additional_comments])
  end
end
