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
end
