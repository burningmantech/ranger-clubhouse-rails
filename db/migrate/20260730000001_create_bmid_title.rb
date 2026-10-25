class CreateBmidTitle < ActiveRecord::Migration[8.1]
  # Seeded from the upstream Laravel constant App\Models\Bmid::BADGE_TITLES.
  # sort_index follows the order that constant listed the positions in, since
  # upstream had no tie-breaker of its own: whichever person_position row came
  # back last won. Troubleshooter LEAL (title 2) is commented out upstream and
  # is left out here.
  #
  # Position ids are literals so the migration keeps working whatever the
  # Position constants do later.
  SEEDS = [
    { position_id: 12, title_line: 1, sort_index: 4, title: "Shift Lead" },
    { position_id: 106, title_line: 1, sort_index: 3, title: "Department Manager" },
    { position_id: 37, title_line: 1, sort_index: 2, title: "Operations Manager" },
    { position_id: 10, title_line: 1, sort_index: 1, title: "Officer of the Day" },
    { position_id: 21, title_line: 3, sort_index: 1, title: "007" }
  ].freeze

  # Seeding through the live model would tie this migration to whatever
  # BmidTitle validates years from now.
  class Seed < ActiveRecord::Base
    self.table_name = "bmid_title"
  end

  def up
    create_table :bmid_title do |t|
      t.string :title, null: false, limit: 64
      t.integer :title_line, null: false, limit: 2
      t.integer :sort_index, null: false, limit: 2
      t.bigint :position_id, null: false, unsigned: true
      t.timestamps

      # Position first so the one index also answers "what titles does this
      # position earn?". One title line per position is the uniqueness the
      # feature needs: a position cannot earn two titles on the same line.
      t.index [:position_id, :title_line], unique: true
    end

    now = Time.current
    Seed.insert_all(SEEDS.map { |seed| seed.merge(created_at: now, updated_at: now) })
  end

  def down
    drop_table :bmid_title
  end
end
