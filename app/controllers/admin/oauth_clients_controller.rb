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
      show_new_secret "Client #{@client.client_id} created."
      return
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    # The second submit button asks for a fresh secret along with the save, so
    # a secret typed beside it is dropped unread rather than hashed and thrown
    # away. The fresh one is made only once the rest of the form passes, so a
    # refused save never leaves a secret on the page that was never stored.
    @client.assign_attributes(params[:new_secret].present? ? client_params.except(:secret) : client_params)
    new_secret = params[:new_secret].present? && @client.valid?
    @client.generate_secret if new_secret

    if @client.save
      if new_secret
        show_new_secret "Client #{@client.client_id} saved with a new secret."
      else
        redirect_to admin_oauth_clients_path, success: "Client #{@client.client_id} updated."
      end
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @client.destroy
    redirect_to admin_oauth_clients_path, success: "Client #{@client.client_id} deleted."
  end

  private

  # The list, with the secret just made on it, this once. Rendered from the
  # POST rather than reached by a redirect: the row keeps a digest, so no GET
  # could show the secret again -- and at 422, since Turbo drops a 200 answer
  # to a form.
  def show_new_secret(message)
    flash.now[:success] = message
    index
    render :index, status: :unprocessable_entity
  end

  def set_client
    @client = OauthClient.find(params.expect!(:id))
  end

  def client_params
    params.expect(oauth_client: [:client_id, :description, :secret, :redirect_uri])
  end
end
