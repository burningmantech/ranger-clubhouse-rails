# frozen_string_literal: true

# Three values that let their holder sign in were kept as typed, so a read of
# the database was a sign-in: the password-reset token (person.tpassword), a
# website's client secret (oauth_client.secret) and the sign-in code it redeems
# (oauth_code.code).
#
# The reset token goes away: Person now signs one (generates_token_for), so
# there is nothing to store. The secret becomes a bcrypt digest and the code a
# SHA-256 digest, each compared against what is presented. Codes live two
# minutes, so the rows are dropped rather than converted; a secret already on
# file is hashed in place, and keeps letting its website in.
#
# Down puts the columns back, but a hashed secret cannot be unhashed: after a
# rollback each client needs Save with New Secret.
class HashSignInSecrets < ActiveRecord::Migration[8.1]
  class MigrationOauthClient < ActiveRecord::Base
    self.table_name = "oauth_client"
  end

  class MigrationOauthCode < ActiveRecord::Base
    self.table_name = "oauth_code"
  end

  def change
    remove_column :person, :tpassword, :string, limit: 64
    remove_column :person, :tpassword_expire, :integer

    rename_column :oauth_client, :secret, :secret_digest
    up_only do
      MigrationOauthClient.reset_column_information
      MigrationOauthClient.find_each do |client|
        client.update_column(:secret_digest, BCrypt::Password.create(client.secret_digest))
      end
      MigrationOauthCode.delete_all
    end

    rename_column :oauth_code, :code, :code_digest
    rename_index :oauth_code, "oauth_code_oauth_client_id_code_unique",
                 "index_oauth_code_on_oauth_client_id_and_code_digest"
  end
end
