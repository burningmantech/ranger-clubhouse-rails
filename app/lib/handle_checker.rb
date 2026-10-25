# frozen_string_literal: true

# Checks a proposed handle against existing callsigns and reserved handles.
#
# A proposed handle may conflict because it sounds like, is spelled like,
# contains, or is contained by a name already in use. Each rule reports its own
# conflicts; the caller decides which rules and which kinds of names to show.
#
# Ported from the Ember handle checker (utils/handle-rules.js and
# utils/handle-conflict.js). Rule messages, priorities and ordering match the
# Ember version.
class HandleChecker
  PRIORITY_HIGH = "high"
  PRIORITY_MEDIUM = "medium"
  PRIORITY_LOW = "low"

  PRIORITY_ORDER = { PRIORITY_HIGH => 1, PRIORITY_MEDIUM => 2, PRIORITY_LOW => 3 }.freeze

  # Person statuses whose callsigns are checked on a first visit. Past
  # prospective callsigns start unchecked; the handle type checkbox brings
  # them back. A status added to Person is checked here automatically.
  DEFAULT_CHECKED_STATUSES = (Person::ALL_STATUSES - [Person::PAST_PROSPECTIVE]).freeze

  # A name the proposed handle is compared against: either a person's callsign
  # or a reserved handle. entity_type is a HandleReservation reservation type,
  # or "<status> ranger" for a callsign.
  Handle = Data.define(:name, :entity_type, :person_id, :vintage, :reason) do
    def person? = person_id.present?
  end

  # Marks where the conflicting handle's name sits in a conflict description.
  # Rules describe themselves in segments rather than one interpolated string
  # so a caller can style or link the name: "Boilermaker contains Boiler"
  # gives no reliable way to tell which "Boiler" is the conflicting handle.
  HANDLE_NAME = :handle_name

  # A problem a rule found with the proposed handle.
  Conflict = Data.define(:candidate_name, :parts, :priority, :rule_id, :conflicting_handle) do
    # The description as plain text.
    def description = parts.map { |part| (part == HANDLE_NAME) ? conflicting_handle.name : part }.join

    # Rule ordering: Substring is first per 2019 request from Threepio. No
    # input yet on ordering of the other rules, so they sort by id.
    def sort_key
      [
        PRIORITY_ORDER.fetch(priority),
        (rule_id == Rules::Substring.rule_id) ? 0 : 1,
        rule_id,
        (conflicting_handle&.name || description).downcase
      ]
    end
  end

  # Rule ordering: Substring is first per 2019 request from Threepio.
  def self.rule_classes
    [
      Rules::Substring,
      Rules::MinLength,
      Rules::PhoneticAlphabet,
      Rules::EditDistance,
      Rules::AmericanSoundex,
      Rules::DoubleMetaphone,
      Rules::EyeRhyme,
      Rules::ExperimentalEyeRhyme
    ]
  end

  def self.rule_ids = rule_classes.map(&:rule_id)

  def self.default_rule_ids = rule_classes.select(&:default_enabled?).map(&:rule_id)

  # [rule id, rule name] pairs, in the order rules run.
  def self.rule_options = rule_classes.map { |rule| [rule.rule_id, rule.rule_name] }

  attr_reader :handles

  # handles: defaults to every callsign plus every active reserved handle.
  def initialize(handles = self.class.build_handles)
    @handles = handles
    @rules = {}
  end

  # All entity types present in the pool. Callsign types sort ahead of reserved
  # handle types, alphabetically within each group.
  def entity_types
    @entity_types ||= handles.map(&:entity_type).uniq.sort_by do |type|
      [HandleReservation::TYPE_LABELS.key?(type) ? 1 : 0, type]
    end
  end

  # Entity types checked on a first visit: every reserved handle type, plus
  # the callsign statuses in DEFAULT_CHECKED_STATUSES.
  def default_entity_types
    checked = DEFAULT_CHECKED_STATUSES.map { |status| "#{status} ranger" }
    entity_types.select { |type| HandleReservation::TYPE_LABELS.key?(type) || checked.include?(type) }
  end

  # Conflicts for a proposed handle, most serious first.
  #
  # Each rule runs against every handle; entity_types and include_vintage
  # filter what comes back. Filtering the results rather than the pool matches
  # the Ember behavior, where a vintage handle is reported even when its status
  # is switched off, and where the Substring rule's exact match fallback still
  # sees the whole pool.
  def check(name, rule_ids: nil, entity_types: nil, include_vintage: true)
    name = name.to_s.strip
    return [] if name.empty?

    shown_types = entity_types&.to_set
    conflicts = rules(rule_ids).flat_map { |rule| rule.check(name) }
    conflicts.select! { |conflict| show?(conflict, shown_types, include_vintage) }
    conflicts.sort_by!(&:sort_key)
    conflicts
  end

  # Rules are built on demand and cached. No rule reads another's results, so
  # skipping a disabled rule gives the same answer as running and discarding
  # it -- and skipping the eye rhyme rules avoids indexing every handle by
  # syllable, which is by far the most expensive part of a check.
  def rules(rule_ids = nil)
    ids = rule_ids || self.class.rule_ids
    self.class.rule_classes
        .select { |klass| ids.include?(klass.rule_id) }
        .map { |klass| @rules[klass.rule_id] ||= klass.new(handles) }
  end

  class << self
    def build_handles
      person_handles + reservation_handles
    end

    # Every callsign in the system. Statuses are kept as separate entity types
    # so the caller can narrow them; vintage callsigns are flagged because they
    # are retired from use no matter what status the person holds.
    def person_handles
      Person.where.not(callsign: [nil, ""])
            .pluck(:id, :callsign, :status, :vintage)
            .map do |id, callsign, status, vintage|
        Handle.new(name: callsign, entity_type: "#{status} ranger", person_id: id, vintage: vintage, reason: nil)
      end
    end

    def reservation_handles
      HandleReservation.active
                       .pluck(:handle, :reservation_type, :reason)
                       .map do |handle, reservation_type, reason|
        Handle.new(name: handle, entity_type: reservation_type, person_id: nil, vintage: false, reason: reason.presence)
      end
    end
  end

  private def show?(conflict, shown_types, include_vintage)
    handle = conflict.conflicting_handle
    return true if handle.nil?
    return true if include_vintage && handle.vintage

    shown_types.nil? || shown_types.include?(handle.entity_type)
  end

  # Each rule indexes the handle pool its own way and reports conflicts for a
  # proposed handle. Ported rule for rule from utils/handle-rules.js.
  module Rules
    class Base
      def self.rule_id = raise(NotImplementedError)
      def self.rule_name = raise(NotImplementedError)
      def self.default_enabled? = true

      def initialize(handles)
        @handles = handles
      end

      def rule_id = self.class.rule_id

      # Returns Conflict objects for the proposed handle.
      def check(name) = raise(NotImplementedError)

      private

      attr_reader :handles

      # parts: description segments; HANDLE_NAME stands in for the conflicting
      # handle's name.
      def conflict(candidate_name, parts, priority, conflicting_handle = nil)
        Conflict.new(candidate_name:, parts: Array(parts), priority:, rule_id:, conflicting_handle:)
      end
    end

    # Points out names which are a substring match, e.g. Boiler:Boilermaker.
    class Substring < Base
      def self.rule_id = "substring"
      def self.rule_name = "Substring"

      def initialize(handles)
        super
        @normalized = {}
        @basic_normalized = {}
        handles.each do |handle|
          # Processed by the phonetic alphabet rule instead.
          next if handle.entity_type == HandleReservation::TYPE_PHONETIC_ALPHABET

          normalized = normalize(handle.name)
          basic = basic_normalize(handle.name)
          # A handle of only punctuation normalizes away, and an empty key
          # would match every proposed handle.
          @normalized[normalized] = handle if normalized.present?
          @basic_normalized[basic] = handle if basic.present?
        end
      end

      def check(raw_name)
        name = normalize(raw_name)
        return [] if name.empty?

        conflicts = scan(name, raw_name)
        return conflicts unless conflicts.empty?

        exact_match(basic_normalize(raw_name), raw_name)
      end

      private

      def scan(name, raw_name)
        @normalized.filter_map do |target, handle|
          if name == target
            in_use(raw_name, handle)
          elsif name.length < target.length && target.include?(name)
            build(raw_name, handle,
                  [HANDLE_NAME, " contains #{raw_name}"],
                  ["The slur ", HANDLE_NAME, " contains #{raw_name}"],
                  ["The obscenity ", HANDLE_NAME, " contains #{raw_name}"])
          elsif name.length > target.length && name.include?(target)
            build(raw_name, handle,
                  ["#{raw_name} contains ", HANDLE_NAME],
                  ["#{raw_name} contains the slur ", HANDLE_NAME],
                  ["#{raw_name} contains the obscenity ", HANDLE_NAME])
          end
        end
      end

      def exact_match(name, raw_name)
        handle = @basic_normalized[name] if name.present?
        handle ? [in_use(raw_name, handle)] : []
      end

      def in_use(raw_name, handle)
        build(raw_name, handle,
              [HANDLE_NAME, " is already in use"],
              [HANDLE_NAME, " is a slur"],
              [HANDLE_NAME, " is considered obscene"],
              high_priority: true)
      end

      def build(raw_name, handle, message, slur_message, obscene_message, high_priority: false)
        case handle.entity_type
        when HandleReservation::TYPE_OBSCENE
          conflict(raw_name, obscene_message, PRIORITY_HIGH, handle)
        when HandleReservation::TYPE_SLUR
          conflict(raw_name, slur_message, PRIORITY_HIGH, handle)
        else
          conflict(raw_name, message, high_priority ? PRIORITY_HIGH : PRIORITY_MEDIUM, handle)
        end
      end

      # Abbreviations are usually pronounced letter-by-letter, so don't flag
      # phonemes that happen to include them. Transform all-caps words to
      # space-separated letters and split on punctuation so "Sparkle" doesn't
      # contain "LE" while allowing "DPW Bob" to match "D P W" or "D-P-W".
      # This isn't perfect, though: "Tall Eagle" contains "LE".
      def normalize(name)
        name.strip
            .gsub(/\b[A-Z]{2,}\b/) { |word| word.chars.join(" ") }
            .downcase
            .gsub(/\W+/, " ")
            .strip
      end

      def basic_normalize(name) = name.downcase.gsub(/\W+/, "").strip
    end

    # Warns about handles that are really short words, though initials like JC
    # are allowed.
    class MinLength < Base
      def self.rule_id = "min-length"
      def self.rule_name = "Minimum length"

      def check(name)
        return [] if name.strip.empty?

        if !name.match?(/[a-z]/i)
          [conflict(name, "should have letters", PRIORITY_MEDIUM)]
        elsif name.length < 3 && !name.match?(/\A[A-Z]{2}\z/)
          [conflict(name, "might be too short", PRIORITY_HIGH)]
        else
          []
        end
      end
    end

    # Warns about names which consist entirely of NATO phonetic alphabet words,
    # e.g. Tango Charlie.
    class PhoneticAlphabet < Base
      def self.rule_id = "phonetic-alphabet"
      def self.rule_name = "Phonetic alphabet"

      def initialize(handles)
        super
        words = handles.filter_map do |handle|
          normalize(handle.name).presence if handle.entity_type == HandleReservation::TYPE_PHONETIC_ALPHABET
        end.uniq
        @regex = /\A(#{words.map { Regexp.escape(_1) }.join("|")})+\z/i if words.any?
      end

      def check(name)
        return [] if @regex.nil? || name.strip.empty?
        return [] unless normalize(name).match?(@regex)

        [conflict(name, "consists entirely of NATO phonetic alphabet words", PRIORITY_HIGH)]
      end

      private

      # Remove all space and punctuation; the check runs all words together.
      def normalize(name) = name.gsub(/[^A-Za-z]/, "").downcase
    end

    # Finds handles within a Levenshtein edit distance of one.
    class EditDistance < Base
      MAX_DISTANCE = 1

      def self.rule_id = "edit-distance"
      def self.rule_name = "Edit distance"

      def initialize(handles)
        super
        @normalized = {}
        handles.each do |handle|
          normalized = normalize(handle.name)
          @normalized[normalized] = handle if normalized.present?
        end
      end

      def check(raw_name)
        name = normalize(raw_name)
        return [] if name.empty?

        lower_name = raw_name.downcase
        @normalized.filter_map do |target, handle|
          next if (name.length - target.length).abs > MAX_DISTANCE
          # Text::Levenshtein.distance clamps its result to the max argument
          # rather than bailing out, so compare the true distance.
          next unless Text::Levenshtein.distance(name, target) <= MAX_DISTANCE
          next if lower_name == handle.name.downcase

          conflict(raw_name, ["is spelled like ", HANDLE_NAME], PRIORITY_MEDIUM, handle)
        end
      end

      private

      def normalize(name) = name.strip.downcase.gsub(/\W+/, "")
    end

    # Groups rules that index handles by a phonetic encoding.
    class PhoneticBase < Base
      def initialize(handles)
        super
        @hashed = {}
        handles.each do |handle|
          encode(handle.name).each { |code| (@hashed[code] ||= []) << handle }
        end
      end

      def check(name)
        lower_name = name.downcase
        encode(name).flat_map { |code| @hashed[code] || [] }
                    .uniq
                    .reject { |handle| handle.name.downcase == lower_name }
                    .map { |handle| conflict(name, ["may sound like ", HANDLE_NAME], PRIORITY_MEDIUM, handle) }
      end

      private

      # Returns the phonetic codes a name is indexed under.
      def encode(name) = raise(NotImplementedError)
    end

    # Matches names using the old American Soundex phonetic algorithm.
    #
    # From http://en.wikipedia.org/wiki/Soundex
    # 1. The first letter of the name is the letter of the Soundex code, and is
    #    not coded to a number.
    # 2. Replace consonants with digits as follows (after the first letter):
    #    b, f, p, v => 1; c, g, j, k, q, s, x, z => 2; d, t => 3; l => 4;
    #    m, n => 5; r => 6; h, w are not coded.
    # 3. Two adjacent letters with the same number are coded as a single
    #    number. Letters with the same number separated by an h or w are also
    #    coded as a single number.
    # 4. Continue until you have one letter and three numbers. If you run out
    #    of letters, fill in 0s until there are three numbers.
    class AmericanSoundex < PhoneticBase
      MAX_LENGTH = 6 # the official soundex implementation is 4

      VOWEL = -1
      NOT_CODED = -2 # H and W do not separate matching letters

      CODES = {
        "AEIOUY" => VOWEL,
        "HW" => NOT_CODED,
        "BFPV" => 1,
        "CGJKQSXZ" => 2,
        "DT" => 3,
        "L" => 4,
        "MN" => 5,
        "R" => 6
      }.flat_map { |letters, value| letters.chars.map { |letter| [letter, value] } }.to_h.freeze

      def self.rule_id = "american-soundex"
      def self.rule_name = "American Soundex"

      private

      def encode(name)
        code = soundex(name)
        code.empty? ? [] : [code]
      end

      def soundex(name)
        letters = name.upcase.gsub(/[^A-Z]+/, "")
        return "" if letters.empty?

        code = letters[0]
        previous = numeric_value(code)
        letters[1..].each_char do |letter|
          break if code.length >= MAX_LENGTH

          value = numeric_value(letter)
          code += value.to_s if value.positive? && value != previous
          previous = value unless value == NOT_CODED
        end
        code.ljust(MAX_LENGTH, "0")
      end

      def numeric_value(letter) = CODES[letter]
    end

    # Matches names using the Double Metaphone phonetic algorithm.
    class DoubleMetaphone < PhoneticBase
      def self.rule_id = "double-metaphone"
      def self.rule_name = "Double Metaphone"

      private

      def encode(name)
        # The alternate code is only set for names matching certain patterns.
        # Unencodable names (e.g. all numeric) come back blank.
        primary, alternate = Text::Metaphone.double_metaphone(name)
        return [] if primary.blank?

        [primary, alternate].compact_blank.uniq
      end
    end

    # A syllable consists of an onset and a rime. A rime consists of a nucleus
    # and a coda. Onset and coda are consonant clusters, nucleus is a vowel or
    # a dipthong: "breath" = {onset: br, rime: {nucleus: ea, coda: th}}.
    # For long vowels in English orthography, the silent_ending may be "e".
    Syllable = Data.define(:onset, :nucleus, :coda, :silent_ending) do
      def rime = nucleus + coda + silent_ending
    end

    # Identifies names which contain syllables that rhyme. These are "eye
    # rhymes" because they're based on spelling rather than true pronunciation.
    # By matching any rhyming syllable, this produces a lot of false positives.
    class EyeRhymeBase < Base
      def initialize(handles)
        super
        @rime_index = {}
        handles.each do |handle|
          syllables(handle.name).filter_map { |syllable| syllable.rime.presence }.each do |rime|
            (@rime_index[rime] ||= []) << handle
          end
        end
      end

      def check(name)
        syllables = syllables(name)
        return [] if syllables.empty?

        rhymes = syllables.flat_map { |syllable| @rime_index.fetch(syllable.rime, []) }.tally

        rhymes.filter_map do |handle, count|
          next if count.to_f / syllables.length < conflict_percent

          conflict(name, describe(count), PRIORITY_MEDIUM, handle)
        end
      end

      private

      # Ratio of rhyming syllables to total syllables required for a conflict,
      # from 0 (at least one syllable rhymes) to 1 (all syllables rhyme).
      def conflict_percent = raise(NotImplementedError)

      def describe(count)
        if count == 1
          ["has a syllable rhyming with ", HANDLE_NAME]
        else
          ["shares #{count} rhyming syllables with ", HANDLE_NAME]
        end
      end

      def syllables(text)
        text = text.strip
        return [] if text.empty?

        words(text).flat_map { |word| word_syllables(word.downcase) }
      end

      # Split words on non-alphanumeric, CamelCase, and numbers. Probably does
      # the wrong thing with non-ascii letters.
      def words(text)
        text.split(/[\W_]+/)
            .reject(&:empty?)
            .flat_map { |word| word.split(/([A-Z][a-z]*|\d+)/).reject(&:empty?) }
      end

      # Work backwards, consume silent e, then coda, then nucleus, then onset.
      # If onset is preceded by more than one cluster, pick the optimal
      # coda/onset breaking point.
      def word_syllables(word)
        return [] unless word.match?(/[a-z]/) # all numeric or something

        syllables = []
        clusters = word.split(/([aeiouy]+|[^aeiouy]+)/).reject(&:empty?)
        until clusters.empty?
          if clusters.length == 1
            rime = clusters.pop
            nucleus, coda = vowels_only?(rime) ? [rime, ""] : ["", rime]
            syllables << Syllable.new(onset: "", nucleus:, coda:, silent_ending: "")
            next
          end

          # English orthography: assume an e after a consonant is silent if
          # there's a preceding vowel.
          silent_ending = (clusters.length > 2 && clusters.last == "e") ? clusters.pop : ""

          onset = coda = ""
          if vowels_only?(clusters.last)
            nucleus = clusters.pop
          else
            coda = clusters.pop
            nucleus = clusters.pop
            raise "Unexpected consonant nucleus in #{word}" unless vowels_only?(nucleus)
          end

          if clusters.length == 1
            onset = clusters.pop
            raise "Unexpected vowel onset in #{word}" if vowels_only?(onset)
          elsif clusters.length > 2
            head, onset = split_consonants(clusters.pop)
            clusters << head if head.present? # coda for the next round
          end

          # Collapse double consonants, since they typically sound like single
          # consonants ("barbel" rhymes with "bar bell" for our purposes).
          # Don't collapse double vowels, because they usually indicate
          # different phonemes ("moon" doesn't rhyme with "mon").
          syllables << Syllable.new(onset: collapse_doubles(onset), nucleus:,
                                    coda: collapse_doubles(coda), silent_ending:)
        end
        syllables
      end

      def split_consonants(cluster)
        raise "Expected consonants, got #{cluster}" if cluster.empty? || vowels_only?(cluster)
        return ["", cluster] if cluster.length == 1

        split_point = (cluster.length / 2.0).round
        [cluster[0...split_point], cluster[split_point..]]
      end

      def vowels_only?(cluster) = cluster.match?(/\A[aeiouy]+\z/)

      def collapse_doubles(cluster)
        index = 1
        while index < cluster.length
          cluster = cluster[0, index] + cluster[(index + 1)..] if cluster[index] == cluster[index - 1]
          index += 1
        end
        cluster
      end
    end

    class EyeRhyme < EyeRhymeBase
      def self.rule_id = "eye-rhyme"
      def self.rule_name = "Eye rhymes"
      def self.default_enabled? = false

      private

      def conflict_percent = 0.0
    end

    class ExperimentalEyeRhyme < EyeRhymeBase
      def self.rule_id = "experimental-eye-rhyme"
      def self.rule_name = "Experimental eye rhymes"

      private

      def conflict_percent = 0.5
    end
  end
end
