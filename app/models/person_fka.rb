# frozen_string_literal: true

class PersonFka < ApplicationRecord
  self.table_name = "person_fka"

  belongs_to :person

  # Don't search on past prospective or auditor callsign formats.
  IRRELEVANT_REGEXP = /(\S\d{2,4}|\d{2,4}B|\(NR\))$/

  validates :person_id, presence: true
  validates :fka, presence: true, length: { maximum: 255 }

  # Port of PersonFka::filterOutIrrelevant. Takes callsign *strings* (callers
  # pluck :fka first), not records -- the stored is_irrelevant column is the
  # equivalent test for a loaded association.
  #
  # @param names [Array<String>, nil]
  # @return [Array<String>]
  def self.filter_out_irrelevant(names)
    return [] if names.blank?

    names.reject { |name| IRRELEVANT_REGEXP.match?(name) }
  end

  def fka=(callsign)
    callsign = callsign.strip
    self.is_irrelevant = IRRELEVANT_REGEXP.match(callsign).present?
    self.fka_normalized = WordUtils.normalize_word(callsign)
    self.fka_soundex = WordUtils.metaphone(fka_normalized)
    super
  end
end
