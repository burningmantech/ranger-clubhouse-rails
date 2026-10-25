# frozen_string_literal: true

# The passkeys people sign in with: one row for each phone, laptop, password
# manager or security key registered on an account.
#
# Only the public half of a passkey is kept, so nothing here lets anyone sign
# in. Clubhouse 2 shares this database and knows nothing of this table, which
# is why there is no foreign key: it can delete a person without asking.
class CreatePersonPasskey < ActiveRecord::Migration[8.1]
  def change
    create_table :person_passkey do |t|
      t.bigint :person_id, null: false
      # Set when an Admin enrolled the key on someone's behalf; empty when the
      # person added it themselves.
      t.bigint :added_by_person_id
      # The id the passkey presents at sign-in, as base64url text. Capitals
      # matter in it and the database's usual collation ignores them, so this
      # column compares byte for byte. 1364 characters is the longest the
      # standard allows (1023 bytes), and ASCII keeps that inside the index.
      t.string :external_id, limit: 1364, null: false, charset: "ascii", collation: "ascii_bin"
      t.text :public_key, null: false
      # Counts up on a security key and stays at zero on a synced passkey.
      t.bigint :sign_count, null: false, default: 0, unsigned: true
      t.string :nickname, limit: 50, null: false
      # The make and model of what holds the passkey. Not shown anywhere yet,
      # and kept because it can only be read at the moment of registration.
      t.string :aaguid, limit: 36
      t.datetime :last_used_at
      t.timestamps

      t.index :person_id
      t.index :added_by_person_id
      t.index :external_id, unique: true
    end
  end
end
