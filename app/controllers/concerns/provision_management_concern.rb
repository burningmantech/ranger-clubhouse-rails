# frozen_string_literal: true

# Shared provision-management behaviour for the admin interfaces that let staff
# review and edit a person's provisions (meals, showers, event radios): the
# Tickets & Provisions hub, the BMID page, and future pages.
#
# Provision CRUD lives in Person::ProvisionsController and always returns to the
# page the admin came from. That origin is threaded through the provision links
# as an +origin+ param and resolved here against a fixed allow-list, so a stray
# value can never redirect off-page.
module ProvisionManagementConcern
  extend ActiveSupport::Concern

  # origin value => path helper the provision pages return to.
  PROVISION_ORIGINS = {
    "tickets_provisions" => :person_tickets_provisions_path,
    "bmid" => :person_bmid_path
  }.freeze

  DEFAULT_PROVISION_ORIGIN = "tickets_provisions"

  # Human label for the origin page, used for back links.
  PROVISION_ORIGIN_LABELS = {
    "tickets_provisions" => "Tickets & Provisions",
    "bmid" => "BMID"
  }.freeze

  # Load a person's provisions for display, plus the summary package.
  #
  # The package always summarises the usable (available/claimed/submitted)
  # provisions, even when +showing_all+ pulls expired/cancelled ones into the
  # list for the table.
  #
  # @return [Array(Array<Provision>, Provision::Package)]
  def load_provisions(person, showing_all: false)
    provisions = Provision.find_for_query(person_id: person.id,
                                          status: showing_all ? "all" : nil).to_a
    package = Provision.build_package(
      provisions.select { |provision| Provision::CAN_USE_STATUSES.include?(provision.status) }
    )
    [provisions, package]
  end

  # The origin page for provision CRUD, from the request (allow-listed).
  def provisions_origin
    PROVISION_ORIGINS.key?(params[:origin]) ? params[:origin] : DEFAULT_PROVISION_ORIGIN
  end

  # Where provision CRUD returns after save/cancel/destroy.
  def provisions_return_path(person)
    public_send(PROVISION_ORIGINS.fetch(provisions_origin), person)
  end

  # Label for the origin page, used on the provision new/edit back links.
  def provisions_origin_label
    PROVISION_ORIGIN_LABELS.fetch(provisions_origin)
  end
end
