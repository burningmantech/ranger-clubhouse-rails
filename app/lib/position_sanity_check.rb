# frozen_string_literal: true

# Position, team, and role grants that contradict each other, and the repairs
# that settle them (Ember admin/position-sanity-checker port).
#
# Nine checks, one class each under this namespace. The registry here is what
# the controller, the helper, and the index all dispatch on, so adding a check
# means adding a class and one row.
#
# Checks are named lazily through #checker rather than being listed as
# constants in CHECKS. Naming an autoloaded class while this module's own body
# is running is how two autoloads deadlock each other.
module PositionSanityCheck
  # Reason recorded on every ActionLog row these repairs write, so an audit can
  # tell a sanity-checker revoke from a manager's.
  REASON = "position sanity checker repair"

  # key:     what the URL and the copy table are keyed by.
  # band:    what the reader has to do about it, which is how the index groups.
  # grouped: findings are shown under a heading per position or team, rather
  #          than in one flat table. Not the same as carrying a group_id --
  #          Team Positions has one and shows it as a column instead.
  CHECKS = [
    { key: :deactivated_accounts, band: :revoke },
    { key: :retired_accounts, band: :revoke },
    { key: :deactivated_positions, band: :revoke, grouped: true },
    { key: :deactivated_teams, band: :revoke, grouped: true },
    { key: :emyr, band: :revoke },
    { key: :missing_positions, band: :grant },
    { key: :team_positions, band: :grant },
    { key: :team_membership, band: :grant },
    { key: :shiny_pennies, band: :reconcile }
  ].freeze

  KEYS = CHECKS.map { _1[:key] }.freeze
  KEY_NAMES = KEYS.map(&:to_s).freeze
  BANDS = CHECKS.map { _1[:band] }.uniq.freeze

  class << self
    # The class answering one key, or nil. Nil rather than an exception: the
    # only caller that can be handed an unknown key is the router, and a stale
    # bookmark deserves the index with a reason rather than a 500.
    def checker(key)
      key = key.to_s
      # Compared as strings so an unrecognized URL segment is never interned,
      # and resolved with inherit: false so a key naming a class that does not
      # exist HERE raises instead of falling through to a top-level constant --
      # const_get("Person") on a module happily returns the Person model.
      return nil unless KEY_NAMES.include?(key)

      const_get(key.camelize, false)
    end

    def keys_in_band(band) = CHECKS.select { _1[:band] == band.to_sym }.map { _1[:key] }

    def band(key) = row(key)[:band]

    def grouped?(key) = row(key)[:grouped].present?

    def row(key) = CHECKS.find { _1[:key] == key.to_sym } || {}

    # {key => count} for the index board. Every check counts without building
    # its findings where its query allows it -- see each class's .count.
    def counts = KEYS.index_with { |key| checker(key).count }
  end
end
