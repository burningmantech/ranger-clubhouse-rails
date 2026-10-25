# frozen_string_literal: true

# Provision CRUD — the actions and the form behind them — shared by every page
# that administers Provision records: the person-scoped pages reached from
# Tickets & Provisions and BMID, and the ticketing crew's all-provisions list.
#
# The actions are identical everywhere; only how a record is found and where the
# admin came from differ, so each including controller supplies five hooks:
#
#   provision_person       the owner a new provision is created for
#   find_provision         how an existing record is looked up
#   provision_form_path    where the form posts, and what Delete deletes
#   provision_return_path  where Save, Cancel, and Delete go afterwards
#   provision_return_label how that destination is named on the back link
#
# The templates live in app/views/common/provisions/; each controller keeps a
# one-line stub that renders them.
#
# A controller that routes neither :new nor :create — the ticketing list, which
# leaves creation to the person pages because a new provision needs a person
# picked first — simply never reaches those two actions or provision_person.
module ProvisionCrudConcern
  extend ActiveSupport::Concern

  included do
    before_action :set_provision, only: %i[edit update destroy]

    helper_method :provision_form_path, :provision_return_path, :provision_return_label
  end

  # A provision starts available and earned in the current year. The expiry
  # default of three years out matches how long an earned provision keeps.
  def new
    year = Current.year
    type = Provision::ALL_TYPES.include?(params[:type]) ? params[:type] : Provision::MEALS

    @provision = Provision.new(
      person_id: provision_person.id,
      type: type,
      status: Provision::AVAILABLE,
      source_year: year,
      expires_on: year + 3
    )
    @provision.item_count = 1 if type == Provision::EVENT_RADIO
  end

  def create
    @provision = Provision.new(provision_params)
    @provision.person_id = provision_person.id

    if @provision.save
      redirect_to provision_return_path,
                  success: "Provision #{@provision.display_ref} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @provision.update(provision_params)
      redirect_to provision_return_path,
                  success: "Provision #{@provision.display_ref} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @provision.destroy!
    redirect_to provision_return_path,
                success: "Provision #{@provision.display_ref} deleted."
  end

  private

  def set_provision
    @provision = find_provision
  end

  def provision_params
    params.expect(provision: [:type, :status, :source_year, :expires_on, :item_count,
                              :pre_event_meals, :event_week_meals, :post_event_meals,
                              :is_allocated, :additional_comments])
  end
end
