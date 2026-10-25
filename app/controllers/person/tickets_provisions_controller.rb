# frozen_string_literal: true

# Ticketing administration hub for a person: access documents (tickets,
# vehicle passes, SAPs) and provisions (meals, showers, radios), plus a
# read-only view of how the person's Tickets & Stuff page appears to them.
class Person::TicketsProvisionsController < ApplicationController
  layout "person"

  include PersonConcern
  include ProvisionManagementConcern

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to administer ticketing records."

  def show
    @showing_all_documents = params[:documents] == "all"
    @showing_all_provisions = params[:provisions] == "all"

    @documents = AccessDocument.find_for_query(person_id: @person.id,
                                               status: @showing_all_documents ? "all" : nil).to_a
    @provisions, @provision_package = load_provisions(@person, showing_all: @showing_all_provisions)
    @ticketing_period = Setting.get_value(Setting::TICKETING_PERIOD)
    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, Current.year)
  end

  # Read-only replica of the person's /me/tickets hub. Unlike the real page,
  # viewing it does not stamp ticketing_last_visited_at.
  def dashboard
    @ticketing_info = TicketingInfo.new
    @ticket_package = TicketAndProvisionsPackage.new(@person.id)
    @missing_bpguid = @person.missing_bpguid?
  end
end
