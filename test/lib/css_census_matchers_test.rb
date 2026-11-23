# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/css_matchers")

# Every rule in CssMatchers has been wrong once. The palette pattern was
# anchored so tightly that it saw none of the colours U5 deleted -- a `dark:`
# prefix, a directional infix or an `/opacity` suffix each made a raw colour
# invisible -- and the arbitrary-value rule counted `has-[:checked]:` variants
# as values. These are the cases that were silently passing.
class CssCensusMatchersTest < ActiveSupport::TestCase
  test "a palette colour is caught through variants, sides and opacity" do
    ["border-l-green-500", "dark:border-l-green-400", "bg-green-50/50",
     "dark:bg-green-900/10", "border-l-amber-500", "dark:text-stone-100",
     "bg-neutral-100", "hover:lg:bg-gray-700/40", "bg-white", "print:bg-white",
     "text-white/80"].each do |token|
      assert CssMatchers.palette?(token), "expected #{token} to read as a palette colour"
    end
  end

  # The patterns once carried their own idea of a variant, which knew no
  # brackets, slashes or stars, and nothing about an important. Every one of
  # these compiled and read as clean.
  test "a palette colour is caught behind any variant, an important or a bracketed opacity" do
    ["[&_th]:bg-red-500", "has-[:checked]:bg-red-500", "data-[state=open]:bg-red-500",
     "group-hover/item:text-gray-500", "*:bg-gray-100", "2xl:bg-red-500", "!bg-red-500", "bg-blue-500!",
     "bg-red-500/[0.5]", "bg-green-500/(--o)"].each do |token|
      assert CssMatchers.palette?(token), "expected #{token} to read as a palette colour"
    end
  end

  test "the newer hues and the shadow and ring colours are palette too" do
    ["bg-mauve-500", "text-olive-500", "bg-mist-500", "bg-taupe-500", "inset-shadow-red-500",
     "inset-ring-red-500", "text-shadow-red-500", "drop-shadow-red-500"].each do |token|
      assert CssMatchers.palette?(token), "expected #{token} to read as a palette colour"
    end

    ["text-shadow-sm", "inset-shadow-sm", "ring-offset-2", "shadow-sm"].each do |token|
      assert_not CssMatchers.palette?(token), "expected #{token} to be clean"
    end
  end

  test "semantic tokens and this app's own names stay clean" do
    ["bg-base-100", "bg-neutral", "text-primary", "border-success/30",
     "ring-signature-edge", "bg-chrome/80", "text-sidebar-content",
     "bg-hero-tile", "text-stone-muted", "card-standard"].each do |token|
      assert_not CssMatchers.palette?(token), "expected #{token} to be clean"
    end
  end

  test "an arbitrary value counts but an arbitrary variant does not" do
    ["p-[13px]", "lg:w-[50%]", "w-[calc(100%-2rem)]"].each do |token|
      assert CssMatchers.arbitrary?(token), "expected #{token} to count as an arbitrary value"
    end

    ["has-[:checked]:bg-primary", "has-[:checked]:text-primary-content"].each do |token|
      assert_not CssMatchers.arbitrary?(token), "expected #{token} to be a variant, not a value"
    end
  end

  # A value is not the only arbitrary thing. A modifier and a whole property
  # are too, and neither has a `-[` in it. The (--name) shorthand is the house
  # way to pass a dynamic number, so it stays clean.
  test "an arbitrary modifier and an arbitrary property count as well" do
    ["text-base/[1.3]", "bg-red-500/[0.5]", "[mask-type:luminance]", "lg:[--gutter:2rem]"].each do |token|
      assert CssMatchers.arbitrary?(token), "expected #{token} to count as arbitrary"
    end

    ["w-(--progress-fill)", "[&_th]:bg-base-200", "top-1/2"].each do |token|
      assert_not CssMatchers.arbitrary?(token), "expected #{token} to be clean"
    end
  end

  test "important is found in either Tailwind spelling, before or after a variant" do
    ["!pt-0", "hidden!", "hover:!bg-primary", "lg:hidden!"].each do |token|
      assert CssMatchers.important?(token), "expected #{token} to read as important"
    end

    assert_not CssMatchers.important?("bg-base-100")
  end

  # The scan pattern decides what classy? even gets asked about. It required a
  # leading letter, so a list opening with an important was never offered --
  # which is how three !important utilities in sidebar_helper stayed off the
  # ratchet for as long as they existed.
  test "a class list opening with an important is still offered to classy?" do
    code = %(class_names(x, "!text-sidebar-active !border-r-[5px]"))

    matched = code.scan(CssMatchers::CODE_STRING).map(&:last)

    assert_includes matched, "!text-sidebar-active !border-r-[5px]"
    assert CssMatchers.classy?(matched.first)
  end

  test "a code string counts as classes only when it looks like a utility list" do
    ["flex items-start gap-2", "!text-sidebar-active !border-r-[5px]",
     "btn btn-ghost btn-sm"].each do |value|
      assert CssMatchers.classy?(value), "expected #{value.inspect} to read as a class list"
    end

    ["app/assets/stylesheets/fontawesome-subset.css", "created_at desc",
     "position.title asc", "Ranger Secret Clubhouse", "circle-check"].each do |value|
      assert_not CssMatchers.classy?(value), "expected #{value.inspect} not to read as classes"
    end
  end

  # A helper takes class lists under more keys than class:. Reading that one key
  # left the login field's icon classes -- eight of them, written out five
  # times -- outside every count.
  test "a class list is read from any key ending in class" do
    code = %(f.text_field :email, icon_class: "absolute inset-y-0 text-warning", wrapper_class: 'login-field', class: "login-input")

    assert_equal ["absolute inset-y-0 text-warning", "login-field", "login-input"],
                 code.scan(CssMatchers::CLASS_KWARG).map(&:last)
  end

  test "a key that only mentions class is not a class list" do
    [%q(belongs_to :lead, class_name: "Person"), %q(subclass: "wide"), %q(classy: "flex gap-2")].each do |code|
      assert_no_match CssMatchers::CLASS_KWARG, code
    end
  end

  # A key can end in class and still hold something else: the request log's
  # filter labels have `status_class: "Outcome"`.
  test "a value with a capital outside brackets is a label, not a class list" do
    assert CssMatchers.class_list?("flex gap-2 bg-[#FFF] content-['Hi']")
    assert_not CssMatchers.class_list?("Outcome")
    assert_not CssMatchers.class_list?("Request Outcome")
  end

  # The search dialog's filter chips rendered bare for eleven days. The line
  # that built their class glued the name to a placeholder, so Tailwind never
  # read it and @utility ac-filter-chip was not emitted. bin/css_check passed
  # throughout: it asked whether the name had left the stylesheet, and the
  # reduced-motion block still wrote it.
  GLUED_CHIP = %q(chip.className = `ac-filter-chip${option.active ? " ac-filter-chip-active" : ""}`)

  # That build, cut down to the shape that fooled the check.
  CHIP_NOT_EMITTED = <<~'CSS'
    @layer utilities{.flex{display:flex}.ac-option{cursor:pointer}@media (hover:hover){.hover\:text-stone-muted:hover{color:red}.ac-option:hover{color:blue}}.pt-0\!{padding-top:0!important}}
    .ac-filter-chip-active:hover{color:blue}@media (prefers-reduced-motion:reduce){.ac-option,.ac-filter-chip{transition:none}}
  CSS

  test "a utility is compiled only when the utilities layer has a rule for it" do
    compiled = CssMatchers.compiled_utilities(CHIP_NOT_EMITTED)

    assert_includes compiled, "ac-option"
    assert_not_includes compiled, "ac-filter-chip", "a hand-written rule naming the class is not its utility"
    assert_not_includes compiled, "ac-filter-chip-active"
  end

  test "a variant or an important in front is still the same utility" do
    compiled = CssMatchers.compiled_utilities(CHIP_NOT_EMITTED)

    assert_includes compiled, "text-stone-muted"
    assert_includes compiled, "pt-0"
  end

  # CompiledStylesheetTest holds its lists by the class as written, so the
  # variant and the important have to survive -- and a comment in front of the
  # layer must not hide it, which is how a real build opens.
  test "a compiled class keeps its variant and its important" do
    classes = CssMatchers.utility_classes("/*! tailwindcss */#{CHIP_NOT_EMITTED}")

    assert_includes classes, "hover:text-stone-muted"
    assert_includes classes, "pt-0!"
    assert_not_includes classes, "ac-filter-chip-active", "a rule outside the utilities layer is not a compiled class"
  end

  # CSS writes a class that opens with a digit as a hex escape and a space, and
  # escapes a brace or a semicolon inside an arbitrary value. Read as plain
  # text, `2xl:bg-red-500` came back as "32" and the other two were cut short,
  # so nothing written that way could reach a list.
  test "an escaped selector is read back as the class that was written" do
    css = <<~'CSS'
      @layer utilities{.\32 xl\:bg-red-500{color:red}.content-\[\'\{\}\'\]{--tw-content:""}.bg-\[url\(\'\/a\;b\.png\'\)\]{color:red}}
    CSS

    assert_equal ["2xl:bg-red-500", "content-['{}']", "bg-[url('/a;b.png')]"].to_set, CssMatchers.utility_classes(css)
  end

  test "declared utilities come from the source, not from the comments around it" do
    source = <<~CSS
      /* @utility cannot be nested. The old @utility inline-flex-center { } is gone. */
      @utility ac-filter-chip {
          @apply inline-flex items-center;
      }
      @utility tab-* { tab-size: --value(integer); }
    CSS

    assert_equal ["ac-filter-chip"], CssMatchers.declared_utilities(source)
  end

  test "a utility is written wherever its whole name is, however it is glued" do
    written = CssMatchers.written("ac-filter-chip")

    [GLUED_CHIP, %q(class_names("ac-filter-chip", active)), %q(class="hover:ac-filter-chip"),
     %q(querySelectorAll(".ac-filter-chip")), "%w[ac-option ac-filter-chip]"].each do |line|
      assert_match written, line
    end

    # A longer name is another class. Counting it is the substring trap that
    # gave inline-flex-center thirteen users it never had.
    [%q(chip.classList.add("ac-filter-chip-active")), %q(class="inline-ac-filter-chip")].each do |line|
      assert_no_match written, line
    end
  end

  test "a class name glued to a JS placeholder is caught where JS sets classes" do
    [GLUED_CHIP, "el.classList.add(`badge-${variant}`)",
     %q(row.innerHTML = `<td class="${tone}-content">`)].each do |line|
      assert CssMatchers.glued_js_class?(line), "expected #{line} to read as a glued class name"
    end

    # The fix, a placeholder standing as a whole word, a comment quoting the
    # mistake, and the template literals that were never class lists: a storage
    # key and a sentence.
    [%q(chip.className = option.active ? "ac-filter-chip ac-filter-chip-active" : "ac-filter-chip"),
     "el.className = `ac-option ${extra}`",
     %q(bar.innerHTML = `<span class="ac-searching">${label}</span>`),
     "    // not #{GLUED_CHIP}",
     "const key = `ac-recents-${this.recentsKeyValue}`",
     %q(announcer.textContent = `${count} result${count === 1 ? "" : "s"} available`)].each do |line|
      assert_not CssMatchers.glued_js_class?(line), "expected #{line} to be clean"
    end
  end
end
