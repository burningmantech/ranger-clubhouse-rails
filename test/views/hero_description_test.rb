# frozen_string_literal: true

require "test_helper"

# Every hero_panel description under app/views is one sentence, in every
# rendering (design-rules > Hero Panel Description Rule). A description block
# with if/elsif/else or case/when is judged one path at a time, so a branch
# that is itself one sentence passes; a computed description: (a helper's or a
# table's value) is guarded where that value lives, and skipped here.
class HeroDescriptionTest < ActiveSupport::TestCase
  TAG = /<%(?<mod>==|[=\-#])?(?<code>.*?)-?%>/m
  OPENER = /\A(if|unless|case)\b/
  SEPARATOR = /\A(elsif|else|when)\b/
  BLOCK_KEYWORD = /\A(if|unless|case|while|until|for|begin)\b/
  DO_TAIL = /\bdo\s*(\|[^|]*\|)?\s*\z/
  ABBREVIATIONS = /\b(e\.g|i\.e|etc|vs|a\.m|p\.m|Mr|Mrs|Ms|Dr|St|No|approx|incl)\.(?=\s)/i

  Token = Struct.new(:kind, :mod, :code, :text, :line)

  test "every hero_panel description is one sentence in every rendering" do
    offenders = Dir.glob(Rails.root.join("app/views/**/*.erb")).sort.flat_map do |path|
      src = File.read(path)
      next [] unless src.include?("hero_panel")

      rel = Pathname(path).relative_path_from(Rails.root)
      descriptions(tokenize(src)).flat_map do |line, renderings|
        renderings.filter_map do |text|
          count = sentences(text).size
          "#{rel}:#{line} renders #{count} sentences: #{text}" if count > 1
        end
      end
    end

    assert_empty offenders, offenders.join("\n")
  end

  private

  def tokenize(src)
    tokens = []
    pos = 0
    src.scan(TAG) do
      m = Regexp.last_match
      tokens << Token.new(:text, nil, nil, src[pos...m.begin(0)], nil) if m.begin(0) > pos
      tokens << Token.new(:tag, m[:mod], m[:code].strip, m[0], src[0...m.begin(0)].count("\n") + 1)
      pos = m.end(0)
    end
    tokens << Token.new(:text, nil, nil, src[pos..], nil) if pos < src.size
    tokens
  end

  def code_tag?(token) = token.kind == :tag && token.mod.nil?

  # [line, renderings] for each description of each hero_panel call: the
  # description: kwarg, or the panel.description block inside the call's block.
  def descriptions(tokens)
    tokens.each_with_index.flat_map do |t, i|
      next [] unless t.kind == :tag && t.mod != "#" && t.code.match?(/\bhero_panel\b/)

      found = []
      kwarg = kwarg_description(t.code)
      found << [t.line, [kwarg]] if kwarg
      if (var = t.code[DO_TAIL, 1]&.delete("| "))
        inner = tokens[(i + 1)...(matching_end(tokens, i) || tokens.size)]
        inner.each_with_index do |it, k|
          next unless it.kind == :tag && it.mod != "#" && it.code.match?(/\b#{Regexp.escape(var)}\.description\b/) && it.code.match?(DO_TAIL)

          found << [it.line, renderings(inner[(k + 1)...(matching_end(inner, k) || inner.size)])]
        end
      end
      found
    end
  end

  # The description: kwarg as text, VALUE standing in for interpolation; nil
  # when there is none or it is computed.
  def kwarg_description(code)
    ruby = code.match?(DO_TAIL) ? "#{code}\nend" : code
    call = find_call(Prism.parse(ruby).value, :hero_panel) or return
    hash = call.arguments&.arguments&.grep(Prism::KeywordHashNode)&.first
    assoc = hash&.elements&.find { |e| e.is_a?(Prism::AssocNode) && e.key.is_a?(Prism::SymbolNode) && e.key.unescaped == "description" }
    case (value = assoc&.value)
    when Prism::StringNode then plain_text(value.unescaped)
    when Prism::InterpolatedStringNode
      plain_text(value.parts.map { |p| p.is_a?(Prism::StringNode) ? p.unescaped : " VALUE " }.join)
    end
  end

  def find_call(node, name)
    return node if node.is_a?(Prism::CallNode) && node.name == name

    node.compact_child_nodes.each do |child|
      found = find_call(child, name)
      return found if found
    end
    nil
  end

  # Every text a block can render: one per path through its conditionals, so a
  # sentence outside an if is counted together with each branch inside it.
  def renderings(body)
    paths = [+""]
    i = 0
    while i < body.size
      t = body[i]
      if code_tag?(t) && t.code.match?(OPENER)
        stop = matching_end(body, i) || body.size
        alternatives = branches(body[(i + 1)...stop]).flat_map { |b| renderings(b) }
        paths = paths.product(alternatives).map { |a, b| a + " " + b }
        i = stop + 1
      else
        piece = t.kind == :text ? t.text : (t.mod&.start_with?("=") ? " VALUE " : " ")
        paths.each { |p| p << piece }
        i += 1
      end
    end
    paths.map { |p| plain_text(p) }
  end

  # The branches between an opener and its end, split at the elsif/else/when
  # tags that sit at the opener's own depth.
  def branches(tokens)
    depth = 0
    tokens.each_with_object([[]]) do |t, list|
      if code_tag?(t)
        if depth.zero? && t.code.match?(SEPARATOR)
          list << []
          next
        end
        depth += delta(t.code)
      end
      list.last << t
    end
  end

  # Index of the tag that closes the block opened at tokens[i].
  def matching_end(tokens, i)
    depth = 0
    (i...tokens.size).each do |j|
      t = tokens[j]
      next unless t.kind == :tag && t.mod != "#"

      depth += delta(t.code)
      return j if depth.zero? && j > i
    end
    nil
  end

  def delta(code)
    opens = 0
    opens += 1 if code.match?(BLOCK_KEYWORD) && !code.match?(/\bend\s*\z/)
    opens += 1 if code.match?(DO_TAIL)
    opens - (code.match?(/\Aend\b/) ? 1 : 0)
  end

  def plain_text(fragment)
    fragment
      .gsub(/<[^>]+>/, " ")
      .gsub(/&[mn]dash;/, "—").gsub(/&(rsquo|lsquo|apos|#39);/, "’").gsub(/&[lr]dquo;/, "\"")
      .gsub("&middot;", "·").gsub("&amp;", "&").gsub(/&[a-z]+;|&#\d+;/, " ")
      .gsub(/\s+/, " ").strip
  end

  def sentences(text)
    guarded = text.gsub(ABBREVIATIONS) { Regexp.last_match(0).tr(".", "․") }
    guarded.split(/(?<=[.!?])["')\]]*\s+(?=\S)/).map { |s| s.tr("․", ".") }.reject(&:empty?)
  end
end
