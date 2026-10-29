# frozen_string_literal: true

# Read-only history of a person's team memberships and position grants
# (MembershipHistory). Gated as the Overview is: its Teams & Positions section
# already shows every viewer today's lists, and this page adds the dates.
class Person::MembershipHistoryController < ApplicationController
  layout "person"

  include PersonConcern

  def show
    @history = MembershipHistory.new(@person)
  end
end
