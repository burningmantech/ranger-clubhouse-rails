# frozen_string_literal: true

# Clubhouse 1's column widths: a 25-character legal name (the application
# holds 255, so a longer name could not be copied into its account; the
# longest on file is 24), a 25-character asset description (three sit at the
# limit) and a 40-character position title (longest 36). Widened to 50, 64 and
# 64; the models and forms say the same. The two name columns go in one ALTER.
class WidenNameAndTitleColumns < ActiveRecord::Migration[8.1]
  def up
    resize(names: 50, description: 64, title: 64)
  end

  def down
    resize(names: 25, description: 25, title: 40)
  end

  private

  def resize(names:, description:, title:)
    change_table :person, bulk: true do |t|
      t.change :first_name, :string, limit: names, null: false
      t.change :last_name, :string, limit: names, null: false
    end
    change_column :asset, :description, :string, limit: description, comment: "placed by staff"
    change_column :position, :title, :string, limit: title, null: false
  end
end
