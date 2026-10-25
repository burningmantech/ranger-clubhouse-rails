# frozen_string_literal: true

# When the person finished, or dismissed, the first-sign-in tour of the
# Clubhouse (me/dashboard/_onboarding). Nil: not yet. An Admin or VC clears it
# from the person page to show the tour again.
class AddOnBoardedAtToPerson < ActiveRecord::Migration[8.1]
  def change
    add_column :person, :on_boarded_at, :datetime
  end
end
