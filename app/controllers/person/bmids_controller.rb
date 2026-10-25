# frozen_string_literal: true

# BMID (Burning Man ID badge) administration for a single person and the current
# event year. The badge record often does not exist yet: Bmid.find_for_person_manage
# returns the saved row or a fresh unsaved one, so the page always renders a form
# that Creates (INSERT) or Updates (UPDATE) the same person+year badge. Rows are
# also materialised later, in bulk, at BMID export time.
class Person::BmidsController < ApplicationController
  layout "person"

  include PersonConcern
  include ProvisionManagementConcern

  # Editing a badge requires the BMID-editing roles (VC is view-only elsewhere).
  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  def show
    load_bmid_form
  end

  def create
    save_bmid
  end

  def update
    save_bmid
  end

  private

  # Build (or fetch) the badge for this person+year and persist the form fields,
  # snapshotting the current provisions onto the printed meals/showers columns.
  def save_bmid
    @bmid = Bmid.find_for_person_manage(@person.id, Current.year)
    was_new = @bmid.new_record?
    @bmid.assign_attributes(bmid_params)
    @bmid.load_provision_package(current_provision_package)

    if @bmid.save
      redirect_to person_bmid_path(@person),
                  success: was_new ? "BMID created." : "BMID updated."
    else
      load_bmid_form
      render :show, status: :unprocessable_entity
    end
  end

  def load_bmid_form
    @bmid ||= Bmid.find_for_person_manage(@person.id, Current.year)
    @ticketing_info = TicketingInfo.new
    @showing_all_provisions = params[:provisions] == "all"
    @provisions, @provision_package = load_provisions(@person, showing_all: @showing_all_provisions)
  end

  def current_provision_package
    load_provisions(@person).last
  end

  def bmid_params
    params.expect(bmid: [:status, :title1, :title2, :title3, :team, :notes, :admission_date])
  end
end
