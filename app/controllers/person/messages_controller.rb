# frozen_string_literal: true

# Person-management view of a person's mailbox. Event Management holders see
# the mailbox exactly as the person does — though viewing never changes the
# person's read state — and may compose in either direction. The mailbox
# behavior is MessagesConcern; the two-way compose is MessageDirectionConcern.
# The HQ-window twin of this page is Hq::MessagesController.
class Person::MessagesController < ApplicationController
  layout "person"

  include PersonConcern
  include MessagesConcern
  include MessageDirectionConcern

  # Equivalent to Current.has_event_management? — both check these two roles.
  # Replaces PersonConcern's broader person-management role list; plain admins
  # without Event Management are denied.
  authorize_role [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA],
                 message: "Event Management permission is required to view messages."

  before_action :may_view_messages?

  private

  def message_owner
    @person
  end

  def messages_route_prefix
    "person"
  end

  def messages_route_args
    [@person]
  end

  def may_view_messages?
    return true if can_view_messages?
    redirect_to person_path(@person), error: "You are not authorized to view another's Clubhouse Messages."
    false
  end
end
