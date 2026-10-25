# frozen_string_literal: true

# /hq/:person_id — pure redirector for the HQ Window Interface (Ember
# port/routes/hq/index.js): a person already on site goes to shift
# check in/out, otherwise to on-site registration.
class Hq::IndexController < ApplicationController
  include HqConcern

  # The redirector never renders the shell.
  skip_before_action :load_hq_shell

  def show
    if @person.on_site
      redirect_to hq_shift_manage_path(@person)
    else
      redirect_to hq_site_registration_path(@person)
    end
  end
end
