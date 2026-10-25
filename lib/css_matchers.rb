# frozen_string_literal: true

# What counts as a palette colour, an arbitrary value or an !important -- and,
# for bin/css_check, which utilities a stylesheet declares and which it compiled.
#
# These live apart from bin/css_census.rb so they can be tested. They need no
# gems and no Rails, which is the census's own constraint: it is a plain script
# and must stay runnable as one.
#
# Every rule here has been wrong once. The palette pattern was anchored so
# tightly that it matched none of the colours U5 deleted -- a `dark:` prefix, a
# directional infix or an `/opacity` suffix all made a raw colour invisible --
# and the arbitrary-value rule counted `has-[:checked]:` variants as values.
module CssMatchers
  # A palette colour rarely appears bare. Three things sit around it:
  #
  #   a variant prefix     dark:  hover:  lg:  group-hover:   (any number)
  #   a directional infix  border-l-  border-t-  divide-x-
  #   an opacity modifier  /50  /10
  #
  # `neutral` is in the hue list, but a shade is required, so daisyUI's semantic
  # `bg-neutral` stays clean while `bg-neutral-600` does not.
  VARIANT_PREFIX = /(?:[a-z0-9@_-]+:)*/
  SIDE_INFIX     = /(?:-[trblxyse])?/
  OPACITY_SUFFIX = %r{(?:/\d{1,3})?}
  COLOR_UTILS    = /bg|text|border|ring|ring-offset|from|via|to|decoration|outline|divide|
                    placeholder|accent|caret|fill|stroke|shadow/x
  HUES           = /slate|gray|grey|zinc|stone|neutral|red|orange|amber|yellow|lime|green|emerald|
                    teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose/x

  PALETTE = /\A#{VARIANT_PREFIX}(?:#{COLOR_UTILS})#{SIDE_INFIX}-(?:#{HUES})-\d{2,3}#{OPACITY_SUFFIX}\z/
  BARE_BW = /\A#{VARIANT_PREFIX}(?:bg|text|border|ring|fill|stroke|divide)#{SIDE_INFIX}-
              (?:white|black)#{OPACITY_SUFFIX}\z/x

  # Both of the rules below describe the utility, not the variants in front of
  # it, and a variant can carry brackets of its own (`has-[:checked]:`) with a
  # colon inside them. So: the last colon at bracket depth zero ends the
  # variants, and what follows is the utility.
  def self.utility_part(token)
    depth = 0
    start = 0
    token.each_char.with_index do |c, i|
      case c
      when "[" then depth += 1
      when "]" then depth -= 1
      when ":" then start = i + 1 if depth.zero?
      end
    end
    token[start..] || ""
  end

  def self.palette?(token) = token.match?(PALETTE) || token.match?(BARE_BW)
  def self.arbitrary?(token) = utility_part(token).match?(/-\[[^\]]+\]/)

  def self.important?(token)
    utility = utility_part(token)
    utility.start_with?("!") || utility.end_with?("!")
  end

  # Which string literals in a code file are worth asking classy? about at all.
  # A class list may open with an important, so a leading ! starts one too --
  # "!text-sidebar-active ..." went uncounted until it did.
  CODE_STRING = /(["'])([a-z!][^"'\n]*)\1/

  # A class list can also live in a Ruby constant or a Stimulus value, where
  # nothing marks it as one. A string counts only when every token is
  # class-shaped AND at least one is recognisably a utility -- which keeps out
  # "app/assets/x.css", "created_at desc" and prose, while letting in
  # "!text-sidebar-active !border-r-[5px]" and "flex items-start gap-2".
  CLASSY_TOKEN = %r{\A!?[a-z0-9][a-z0-9!:/\[\].,%_-]*\z}
  UTILITY_HEAD = /\A!?(?:[a-z0-9@_-]+:)*!?(?:
      bg|text|border|ring|from|via|to|fill|stroke|shadow|w|h|size|min|max|
      p|px|py|pt|pb|pl|pr|ps|pe|m|mx|my|mt|mb|ml|mr|ms|me|space|gap|
      grid|col|row|flex|items|justify|self|order|z|place|
      rounded|opacity|duration|delay|transition|translate|scale|rotate|
      overflow|truncate|whitespace|break|font|leading|tracking|align|list|
      hidden|block|inline|absolute|relative|sticky|fixed|table|contents|
      btn|badge|alert|card|input|select|textarea|checkbox|toggle|range|file-input|
      tab|tabs|menu|navbar|drawer|dropdown|modal|join|stat|steps|breadcrumbs|tooltip|
      avatar|loading|skeleton|divider|collapse|chat|timeline|progress|radial-progress|
      mask|indicator|swap|carousel|hero|footer|box|icon|toast|sidebar|label|link|
      cursor|pointer|sr|not-sr|appearance|resize|outline|ease|animate
    )(?:-|\z)/x

  def self.classy?(value)
    tokens = value.to_s.split(/\s+/).reject(&:empty?)
    tokens.size >= 2 &&
      tokens.all? { |t| t.match?(CLASSY_TOKEN) } &&
      tokens.any? { |t| t.match?(UTILITY_HEAD) }
  end

  # A placeholder touching a class name in JS: `chip${...}`, `badge-${...}`,
  # `${...}-active`. Tailwind reads app/javascript as text and takes whole words
  # only, so the name it needed is never there to take. Looked for only where JS
  # sets classes -- an HTML class attribute, className, a classList call --
  # because a template literal anywhere else is a URL, an id or a sentence. A
  # comment sets nothing, so an example quoted in one is left alone.
  JS_CLASS_VALUE = /\bclass=(["'])(.*?)\1|\bclass(?:Name\s*\+?=|List\.\w+\()\s*`([^`]*)`/
  JS_GLUE        = /[\w-]\$\{|\$\{[^{}]*\}[\w-]/
  JS_COMMENT     = %r{\A\s*(?://|/?\*)}

  def self.glued_js_class?(line)
    !line.match?(JS_COMMENT) && line.scan(JS_CLASS_VALUE).flatten.compact.any? { |value| value.match?(JS_GLUE) }
  end

  # The rest reads stylesheets rather than class tokens, for bin/css_check.
  #
  # Every style rule in a compiled stylesheet: its selector, and the blocks it
  # sits inside, outermost first. A rule opens at `{` and the stack unwinds at
  # `}`, minified or not, which holds because the build puts no brace in a
  # string.
  def self.each_rule(css)
    enclosing = []
    css.scan(/([^{};]+)\{|\}/) do |(prelude)|
      next enclosing.pop unless prelude

      prelude = prelude.strip
      yield prelude, enclosing unless prelude.empty? || prelude.start_with?("@")
      enclosing << prelude
    end
  end

  # The class names a selector uses, unescaped (".lg\:p-4" -> "lg:p-4").
  def self.selector_classes(selector)
    selector.scan(/\.((?:\\.|[\w-])+)/).map { |(name)| name.gsub(/\\(.)/, '\1') }
  end

  # The utilities a compiled stylesheet carries: every class with a rule inside
  # `@layer utilities`, which is where Tailwind emits them -- its own, daisyUI's
  # and each @utility this app declares. A variant in front does not make a
  # different utility (`.hover\:text-stone-muted` compiles text-stone-muted),
  # and nor does an important.
  #
  # Asking the layer rather than the whole sheet is the point. A hand-written
  # rule can go on naming a class after its utility has stopped compiling:
  # `.ac-option, .ac-filter-chip { transition: none }` kept .ac-filter-chip in
  # the stylesheet for eleven days while the chips it styles rendered bare.
  def self.compiled_utilities(css)
    names = Set.new
    each_rule(css) do |selector, enclosing|
      next unless enclosing.include?("@layer utilities")

      selector_classes(selector).each { |name| names << utility_part(name).delete("!") }
    end
    names
  end

  # The names a stylesheet's source declares with @utility. Comments go first:
  # one that quotes a declaration declares nothing. A functional utility
  # (`@utility tab-*`) has no one class to look for and is left out.
  def self.declared_utilities(source)
    source.gsub(%r{/\*.*?\*/}m, "").scan(/@utility\s+([\w-]+)\s*\{/).flatten
  end

  # Where the code writes a utility, by name. Any spelling counts -- behind a
  # variant, in a selector, glued to a placeholder (`chip${...}`, the spelling
  # Tailwind cannot read) -- except a longer name that merely contains it:
  # flex-center-gap-2 is not a use of flex-center.
  def self.written(name) = /(?<![\w-])#{Regexp.escape(name)}(?![\w-])/
end
