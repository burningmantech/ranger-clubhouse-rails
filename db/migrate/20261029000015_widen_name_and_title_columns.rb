# frozen_string_literal: true

# Clubhouse 1's column widths: a 25-character legal name (the application
# holds 255, so a longer name could not be copied into its account; the
# longest on file is 24), a 25-character asset description (three sit at the
# limit) and a 40-character position title (longest 36). Widened to 50, 64 and
# 64; the models and forms say the same.
class WidenNameAndTitleColumns < ActiveRecord::Migration[8.1]
  COLUMNS = [
    [:person, :first_name, 25, 50, { null: false }],
    [:person, :last_name, 25, 50, { null: false }],
    [:asset, :description, 25, 64, { comment: "placed by staff" }],
    [:position, :title, 40, 64, { null: false }]
  ].freeze

  def up
    COLUMNS.each { |table, column, _was, now, opts| change_column table, column, :string, limit: now, **opts }
  end

  def down
    COLUMNS.each { |table, column, was, _now, opts| change_column table, column, :string, limit: was, **opts }
  end
end
