# frozen_string_literal: true

# person.email held 50 characters while every other email column holds 255,
# so an applicant's address could fail to copy into the account made for it.
class WidenPersonEmail < ActiveRecord::Migration[8.1]
  def up
    change_column :person, :email, :string, limit: 255
  end

  def down
    change_column :person, :email, :string, limit: 50
  end
end
