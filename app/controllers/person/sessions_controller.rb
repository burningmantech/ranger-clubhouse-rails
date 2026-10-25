# frozen_string_literal: true

require "user_agent_parser"

class Person::SessionsController < ApplicationController
  layout "person"

  include PersonConcern

  helper_method :user_agent_format

  authorize_role [Role::ADMIN]

  def index
    @sessions = @person.sessions.order(created_at: :desc)
  end

  def destroy
    @person.sessions.find(params[:id]).destroy

    redirect_to person_sessions_path(@person), success: "Session revoked."
  end

  private

  def user_agent_format(ua)
    parsed = UserAgentParser.parse(ua)
    "#{parsed.os} #{parsed}"
  end
end
