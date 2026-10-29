# frozen_string_literal: true

# Person#authenticate re-hashed a salted-SHA1 password to Argon2 only when its
# holder next signed in, so 5,200 of 6,820 rows (every account dormant since
# the switch) still held a hash that cracks offline. Those rows, and the few
# placeholder values that never verified, are blanked: the account keeps its
# passkeys and its email, and its holder sets a new password through Forgot.
#
# Nothing to restore on the way down: the point is that the hashes are gone.
class RetireSha1Passwords < ActiveRecord::Migration[8.1]
  class MigrationPerson < ActiveRecord::Base
    self.table_name = "person"
  end

  def change
    up_only do
      MigrationPerson.where.not(MigrationPerson.arel_table[:password].matches("$argon2%")).update_all(password: "")
    end
  end
end
