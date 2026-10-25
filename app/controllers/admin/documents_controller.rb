# frozen_string_literal: true

# The documents the Clubhouse displays elsewhere: agreements people sign, the
# contact and dashboard link sections, and the bookmark pages the kiosks show.
class Admin::DocumentsController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  before_action :set_document, only: [:body, :edit, :update, :destroy]

  def index
    @documents = Document.find_all.to_a
    @referenced_tags = Document.referenced_tags
  end

  # Turbo frame target: renders one document the way the pages that display it
  # do. The list asks for these one at a time, so opening it does not render
  # every document at once.
  def body
    render layout: false
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    @document.person_create_id = Current.person_id
    @document.person_update_id = Current.person_id

    if @document.save
      redirect_to admin_documents_path, success: "Document #{@document.tag} created."
      return
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    @document.assign_attributes(document_params)
    # Only a real change earns a new byline. Saving a form no one edited should
    # not make it look like someone rewrote the document.
    @document.person_update_id = Current.person_id if @document.changed?

    if @document.save
      redirect_to admin_documents_path, success: "Document #{@document.tag} updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @document.destroy
    redirect_to admin_documents_path, success: "Document #{@document.tag} deleted."
  end

  private

  def set_document
    @document = Document.find(params.expect!(:id))
  end

  def document_params
    params.expect(document: [:tag, :description, :body, :refresh_time])
  end
end
