# frozen_string_literal: true

require "securerandom"
module WordUtils
  # Normalize word
  def self.normalize_word(word)
    return "" if word.blank?

    # Convert & to 'and'
    normalized = word.gsub(/&/, " and ")
    # Convert diacritics
    normalized = convert_diacritics(normalized)
    # Remove non-word characters and convert to lowercase
    normalized.gsub(/\W/, "").downcase
  end

  # Convert diacritics to ASCII
  def self.convert_diacritics(word)
    # Handle copyright symbol, and remove diacritical marks
    word.gsub(/©/, "@").unicode_normalize(:nfd).gsub(/[\u0300-\u036f]/, "")
  end

  # Spell out numbers in a string
  def self.spell_out_numbers(word)
    word.strip.scan(/\d+|\D+/).map do |token|
      if /\d+/.match?(token)
        token.to_i.localize(:en).spellout
      else
        token
      end
    end.join
  end

  # Split comma-separated values
  def self.split_commas(str)
    return [] if str.blank?
    str.split(/\s*,\s*/).reject(&:blank?)
  end


  def self.metaphone(word)
    Text::Metaphone.double_metaphone(spell_out_numbers(word))[0].gsub(/\s+/, "")
  end
end
