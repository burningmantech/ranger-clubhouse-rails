# frozen_string_literal: true

class Me::AgreementsController < ApplicationController
  layout "me"

  before_action :retrieve_agreements
  before_action :find_agreement, only: [:show, :sign]

  def index
    @signed_count = @agreements.count(&:signed)
    @total_count = @agreements.size
    @pending_count = @agreements.count { |a| a.available && !a.signed }
  end

  def show
  end

  def sign
    Agreements.sign_agreement(current_user, @agreement.tag)
    redirect_to me_agreement_path(@agreement.tag), success: "Agreement signed."
  end

  private

  def retrieve_agreements
    @agreements = Agreements.retrieve(current_user)
  end

  def find_agreement
    tag = params.expect!(:id)
    @agreement = @agreements.find { |agreement| agreement.tag == tag }

    unless @agreement
      redirect_to me_agreements_path, error: "Agreement was not found."
      return false
    end

    unless @agreement.available
      redirect_to me_agreements_path, error: "Agreement is not available at this time."
      return false
    end

    @document = Document.find_id_or_tag(@agreement.tag)
    unless @document
      redirect_to me_agreements_path, error: "Agreement document was not found."
      return false
    end

    true
  end
end
