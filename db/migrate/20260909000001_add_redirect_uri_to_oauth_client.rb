# frozen_string_literal: true

# Where a website is sent back to with its sign-in code. Recorded here so the
# code goes only to the address the Tech Team wrote down, never to whatever a
# link asked for. Blank until a Tech Ninja fills it in, and blank means the
# website cannot sign anyone in.
class AddRedirectUriToOauthClient < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_client, :redirect_uri, :string, null: false, default: ""
  end
end
