# frozen_string_literal: true

# The shift types the Shift Coverage report can be run for, and the posts
# (columns) each one shows. They were constants in ShiftCoverageReport; they
# are rows now so Admin and Tech Ninja can change them without a deploy.
#
# Seeded with exactly what those constants held, so the report reads the same
# the day this runs. Position ids are literals so the migration keeps working
# whatever the Position constants do later. Each position_ids entry is
# [position_id] or [position_id, label]: the label is printed after the
# callsign of anyone on that position -- how one post carries a position and
# its junior version without hiding which is which.
class CreateShiftCoverageTables < ActiveRecord::Migration[8.1]
  GROUPS = [
    # Burn Quad Lead (114) has no shifts of its own any more, so it has no
    # column, but it stays in the total in case any are ever scheduled again.
    # Troubleshooters are left out of the total on purpose: some of them are in
    # the city rather than on the perimeter.
    { slug: "perimeter", title: "Burn Perimeter", base_position_ids: [19], posts: [
      { title: "Burn Command", position_ids: [[99]] },
      { title: "Sandman", position_ids: [[61]] },
      { title: "Art Car", position_ids: [[125]] },
      { title: "Perimeter", position_ids: [[19]] },
      { title: "Perimeter #", position_ids: [[19]], count_only: true },
      { title: "Total #", position_ids: [[99], [114], [61], [125], [19]], count_only: true },
      { title: "Troubleshooter", position_ids: [[91]] }
    ] },
    # Rows come from Dirt, Dirt Post-Event and Operator Smooth shifts.
    { slug: "command", title: "Command", base_position_ids: [2, 120, 142], posts: [
      { title: "OOD", position_ids: [[10]] },
      { title: "DOOD", position_ids: [[87]] },
      { title: "RSL", position_ids: [[12]] },
      { title: "RSCI", position_ids: [[25]] },
      { title: "RSCIM", position_ids: [[93]] },
      { title: "WESL", position_ids: [[109]] },
      { title: "Opr", position_ids: [[56], [142, "Smooth"]] },
      { title: "TS", position_ids: [[91], [127, "Mentee"], [147, "TSLEAL"]] },
      { title: "LEAL", position_ids: [[7], [116, "Partner"]] },
      { title: "GDL", position_ids: [[14], [126, "Intern"]] },
      { title: "Tow", position_ids: [[20], [69, "Mentee"]] },
      { title: "Sanc", position_ids: [[54], [123, "Mentee"]] },
      { title: "GerPatLd", position_ids: [[76]] },
      { title: "GerPat", position_ids: [[75], [122]] },
      { title: "Dirt", position_ids: [[2], [107]], count_only: true },
      { title: "GD", position_ids: [[4]], count_only: true },
      { title: "RNR", position_ids: [[11], [115]], count_only: true },
      { title: "Burn", position_ids: [[19], [125], [99], [114], [61]], count_only: true }
    ] },
    { slug: "echelon", title: "Echelon", base_position_ids: [17], posts: [
      { title: "Echelon Lead", position_ids: [[81]] },
      { title: "Echelon Field", position_ids: [[17]] },
      { title: "Lead Training", position_ids: [[111]] }
    ] },
    { slug: "gerlach-patrol", title: "Gerlach Patrol", base_position_ids: [75], posts: [
      { title: "GP Lead", position_ids: [[76]] },
      { title: "GP Rangers", position_ids: [[75]] },
      { title: "GP Green Dot", position_ids: [[122]] }
    ] },
    # Sanctuary Host (68) is left out: the Green Dot cadre retired the position.
    { slug: "gd", title: "Green Dot", base_position_ids: [4], posts: [
      { title: "GDL", position_ids: [[14]] },
      { title: "GDL Intern", position_ids: [[126]] },
      { title: "GD Dirt", position_ids: [[4]] },
      { title: "GD Mentors", position_ids: [[40]] },
      { title: "GD Mentees", position_ids: [[50]] },
      { title: "Sanctuary", position_ids: [[54]] },
      { title: "Sanc Mentee", position_ids: [[123]] },
      { title: "Gerlach GD", position_ids: [[122]] }
    ] },
    # Rows come from HQ Short and HQ Window Pre-Event shifts, not HQ Window.
    { slug: "hq", title: "HQ Window", base_position_ids: [33, 117], posts: [
      { title: "Lead", position_ids: [[32], [118]] },
      { title: "Short", position_ids: [[33]] },
      { title: "Window", position_ids: [[3], [117]] },
      { title: "Runner", position_ids: [[18]] }
    ] },
    # The Intercept Operator position (66) gave way to Operator shifts (56)
    # scheduled for Intercept hours, so both are read as one column.
    # Interceptors are named, then tallied -- the pairing every other kind of
    # shift uses for a position worth both.
    { slug: "intercept", title: "Intercept", base_position_ids: [5], posts: [
      { title: "Dispatch", position_ids: [[6]] },
      { title: "Interceptors", position_ids: [[5]] },
      { title: "Int. Drivers", position_ids: [[229]] },
      { title: "Count", position_ids: [[5]], count_only: true }
    ] },
    # Rows come from Mentor and Alpha shifts.
    { slug: "mentor", title: "Mentors", base_position_ids: [9, 1], posts: [
      { title: "Lead", position_ids: [[15]] },
      { title: "Short", position_ids: [[35]] },
      { title: "Mentor", position_ids: [[9]] },
      { title: "Mitten", position_ids: [[67]] },
      { title: "Apprentice", position_ids: [[70]] },
      { title: "Khaki", position_ids: [[86]] },
      { title: "Radio", position_ids: [[72]] },
      { title: "Alpha", position_ids: [[1]] },
      { title: "QM", position_ids: [[84]] }
    ] },
    { slug: "pre-event", title: "Pre-Event", base_position_ids: [53], posts: [
      { title: "OOD", position_ids: [[10]] },
      { title: "RSL", position_ids: [[83]] },
      { title: "TS", position_ids: [[149]] },
      { title: "Dirt", position_ids: [[53]] },
      { title: "Dirt Count", position_ids: [[53]], count_only: true }
    ] },
    { slug: "post-event", title: "Post-Event", base_position_ids: [120], posts: [
      { title: "OOD", position_ids: [[10]] },
      { title: "RSL", position_ids: [[12]] },
      { title: "TS", position_ids: [[91]] },
      { title: "GD", position_ids: [[4]] },
      { title: "DPW", position_ids: [[105]] },
      { title: "Dirt", position_ids: [[120]] },
      { title: "Dirt Count", position_ids: [[120]], count_only: true }
    ] },
    { slug: "rsci-mentor", title: "RSCI Mentor/Mentee", base_position_ids: [92], posts: [
      { title: "RSCI Mentors", position_ids: [[92]] },
      { title: "RSCI Mentees", position_ids: [[93]] }
    ] },
    { slug: "troubleshooter", title: "Troubleshooter", base_position_ids: [91, 149], posts: [
      { title: "Troubleshooter", position_ids: [[91]] },
      { title: "TS Mentor", position_ids: [[128]] },
      { title: "TS Mentee", position_ids: [[127]] },
      { title: "TS LEAL", position_ids: [[147]] },
      { title: "TS Pre-Event", position_ids: [[149]] }
    ] }
  ].freeze

  # Seeding through the live models would tie this migration to whatever they
  # validate years from now.
  class Group < ActiveRecord::Base
    self.table_name = "shift_coverage_group"
  end

  class Post < ActiveRecord::Base
    self.table_name = "shift_coverage_position"
  end

  def up
    create_table :shift_coverage_group do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.json :base_position_ids, null: false
      t.integer :sort_index, null: false
      t.index :slug, unique: true
    end

    create_table :shift_coverage_position do |t|
      t.string :title, null: false
      t.json :position_ids, null: false
      t.boolean :count_only, null: false, default: false
      t.bigint :shift_coverage_group_id, null: false
      t.integer :sort_index, null: false
      t.index :shift_coverage_group_id
    end

    GROUPS.each_with_index do |group, group_index|
      group_id = Group.create!(slug: group[:slug], title: group[:title],
                               base_position_ids: JSON.generate(group[:base_position_ids]),
                               sort_index: group_index + 1).id

      Post.insert_all(group[:posts].each_with_index.map { |post, post_index|
        { shift_coverage_group_id: group_id, title: post[:title],
          position_ids: JSON.generate(post[:position_ids]),
          count_only: post.fetch(:count_only, false), sort_index: post_index + 1 }
      })
    end
  end

  def down
    drop_table :shift_coverage_position
    drop_table :shift_coverage_group
  end
end
