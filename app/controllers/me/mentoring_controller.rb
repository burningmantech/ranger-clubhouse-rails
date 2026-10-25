# frozen_string_literal: true

class Me::MentoringController < ApplicationController
  include MentorHelper
  include MentoringConcern
  layout "me"
end
