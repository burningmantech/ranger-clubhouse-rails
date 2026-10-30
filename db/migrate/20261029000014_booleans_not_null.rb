# frozen_string_literal: true

# Four yes/no columns allowed NULL as a third answer nobody asked for; every
# reader treats NULL as no, so they become NOT NULL DEFAULT false. Only
# position.on_sl_report held any (73 of 224 positions), set to false first.
# bmid.org_vehicle_insurance is left as it is by the owner's ruling (2026-10-29).
class BooleansNotNull < ActiveRecord::Migration[8.1]
  COLUMNS = [[:position, :on_sl_report], [:bmid, :showers], [:person, :vintage], [:access_document, :access_any_time]].freeze

  def up
    COLUMNS.each do |table, column|
      execute "UPDATE #{table} SET #{column} = 0 WHERE #{column} IS NULL"
      change_column table, column, :boolean, null: false, default: false
    end
  end

  def down
    COLUMNS.each do |table, column|
      change_column table, column, :boolean, null: true, default: column == :on_sl_report ? nil : false
    end
  end
end
