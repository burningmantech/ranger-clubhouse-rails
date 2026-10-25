# frozen_string_literal: true

# The other websites people can sign in to with their Clubhouse account.
# Tech Team only: the secrets on this page are what let a website finish a
# sign-in.
class Admin::OauthClientsController < ApplicationController
  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to manage OAuth clients."

  before_action :set_client, only: [:edit, :update, :destroy]

  def index
    @clients = OauthClient.ordered.to_a
  end

  def new
    @client = OauthClient.new
  end

  def create
    @client = OauthClient.new(client_params)

    if @client.save
      redirect_to admin_oauth_clients_path, success: "Client #{@client.client_id} created."
      return
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    @client.assign_attributes(client_params)
    # The second submit button asks for a fresh secret along with the save. It
    # is made only once the rest of the form passes, so a refused save never
    # leaves a secret on the page that was never stored.
    new_secret = params[:new_secret].present? && @client.valid?
    @client.generate_secret if new_secret

    if @client.save
      saved = new_secret ? "saved with a new secret" : "updated"
      redirect_to admin_oauth_clients_path, success: "Client #{@client.client_id} #{saved}."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @client.destroy
    redirect_to admin_oauth_clients_path, success: "Client #{@client.client_id} deleted."
  end

  private

  def set_client
    @client = OauthClient.find(params.expect!(:id))
  end

  def client_params
    params.expect(oauth_client: [:client_id, :description, :secret, :redirect_uri])
  end
end
