# frozen_string_literal: true

# HQ-scoped twin of Person::MessagesController — the Ranger's mailbox rendered
# inside the HQ Window Interface shell, so handing over unread messages at the
# window (a shift check-out checklist task) never ejects the operator to
# /person/:id/messages.
#
# Deliberately NOT gated on Event Management the way the /person page is:
# HqConcern's Admin / Shift Management gate stands, which is the whole point —
# delivering messages is the window worker's job, and the person-page link-out
# it replaces was invisible to the Shift-Management-only operator. Adding an
# authorize_role call here would REPLACE that gate rather than narrow it.
#
# Include order is load-bearing twice over. HqConcern first: inclusion order
# sets before_action order, and its set_person must run before MessagesConcern's
# set_message and MessageDirectionConcern's set_direction, both of which read
# @person. MessageDirectionConcern last: its methods override MessagesConcern's
# hook defaults, which only works if it is included after.
class Hq::MessagesController < ApplicationController
  include HqConcern
  include MessagesConcern
  include MessageDirectionConcern

  # Actions that only ever answer turbo-streams or redirect, plus the two that
  # answer a fragment as well as the page (below). Letting the shell loader run
  # on them would silently eat the operator's once-per-person entry warning
  # modal (load_hq_shell consumes session[:hq_warned_person_id]).
  # :create keeps the shell — it re-renders :new on a validation error.
  skip_before_action :load_hq_shell,
                     only: %i[index show find_recipient search_callsigns suggest_callsigns select_callsign
                              toggle_read toggle_archive create_reply]

  # :index answers the shell page, the folder-switch turbo-stream (the folder
  # tabs carry data-turbo-stream) and the thread page's lazy list frame; :show
  # answers the shell page and the pane-frame request a row's link makes. Only
  # the page renders the layout the shell data feeds. Without the split, every
  # folder click and every thread selected would pay for a PersonEventInfo,
  # banners, photo, and a full EventSummaryReport that are then thrown away.
  #
  # One guard per action, each asking exactly what that action branches on. A
  # guard that asks what the request looks like instead skips the shell where
  # the action still renders the page: Turbo's form submissions accept
  # turbo-stream first, and the GET that follows create's redirect to :show
  # keeps that Accept, so a turbo-stream test on :show rendered the thread page
  # without its shell (nil @banners → 500 after every message sent).
  #
  # These wrappers exist because re-registering `before_action :load_hq_shell`
  # here would not add a second, narrower callback — ActiveSupport::Callbacks
  # keys on the filter, so it REPLACES HqConcern's registration and its options,
  # silently leaving :new with no shell at all (nil @banners → 500).
  # Distinct filter names sidestep that.
  before_action :load_hq_shell_for_index_page, only: :index
  before_action :load_hq_shell_for_thread_page, only: :show

  private

  # Asks "is this a fragment?" rather than "is this HTML?" on purpose. A client
  # sending Accept: */* (curl, uptime checks, a bare fetch) gets request.format
  # == Mime::ALL, whose .html? is FALSE — yet respond_to still renders the HTML
  # branch, which needs the shell. Asking the negative question is the only form
  # that holds for all three Accept headers.
  def load_hq_shell_for_index_page
    load_hq_shell unless request.format.turbo_stream? || list_request?
  end

  # :show has no turbo-stream answer: anything but the pane request gets the page.
  def load_hq_shell_for_thread_page
    load_hq_shell unless pane_request?
  end

  def message_owner
    @person
  end

  def messages_route_prefix
    "hq"
  end

  def messages_route_args
    [@person]
  end
end
