# frozen_string_literal: true

# Three flags for ART mentoring, where an ART's mentors are paired with its
# mentees on shift: the training that does it (has_art_mentoring), and the
# mentor and mentee positions it pairs (is_art_mentor, is_art_mentee).
#
# A training finds those two positions on its own team, not through their
# training_position_id (ruled 2026-10-21). Pointing a position's
# training_position_id at an ART also makes everyone holding it need that
# ART's pass to sign in (SignInBlocker#check_for_training), and Troubleshooter
# Training records no passes, so linking Troubleshooter Mentor and Prospective
# that way would block every one of their holders.
#
# The two cadres that mentor on shift today are flagged by literal id --
# migrations do not load app code -- the pairs Training::MENTORING_POSITIONS
# named until now: Green Dot Training 101 with Green Dot Mentor 40 and Green Dot
# Mentee 50 (the Green Dot Team), and Troubleshooter Training 94 with
# Troubleshooter Mentor 128 and Troubleshooter Prospective 127 (the
# Troubleshooter Team). On a database without those rows nothing changes.
#
# One ALTER TABLE each way (bulk: true): MariaDB DDL is not transactional.
class AddArtMentoringFlagsToPosition < ActiveRecord::Migration[8.1]
  def up
    change_table :position, bulk: true do |t|
      t.boolean :has_art_mentoring, null: false, default: false
      t.boolean :is_art_mentor, null: false, default: false
      t.boolean :is_art_mentee, null: false, default: false
    end

    execute "UPDATE position SET has_art_mentoring = 1 WHERE id IN (94, 101)"
    execute "UPDATE position SET is_art_mentor = 1 WHERE id IN (40, 128)"
    execute "UPDATE position SET is_art_mentee = 1 WHERE id IN (50, 127)"
  end

  def down
    change_table :position, bulk: true do |t|
      t.remove :has_art_mentoring, :is_art_mentor, :is_art_mentee
    end
  end
end
