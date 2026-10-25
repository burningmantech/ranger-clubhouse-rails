# frozen_string_literal: true

require "digest"
require "fileutils"
require "set"

# The CSS refactor safety net (docs/css-dry-rules.md §3).
#
# Run the suite with CSS_SNAPSHOT=1 and every HTML or Turbo Stream response an
# integration test receives is written to tmp/css_snapshots/<test class>/<test>--<n>.html.
# bin/css_check diffs a run against tmp/css_snapshots_base.
#
# A snapshot keeps what a stylesheet or a script can see and drops what changes
# from run to run:
# - class tokens are sorted and de-duplicated, so reordering never shows up
# - only the attributes in KEEP survive (no href, src, value of hidden inputs, …)
# - digits, hex digests and month/day names are masked, because records created
#   in a test get fresh ids on every run and pages print today's date
# - <head>, scripts and hidden inputs (CSRF tokens) are left out
#
# Without the variable nothing is hooked and the suite runs as before.
module CssSnapshot
  DIR = Rails.root.join("tmp/css_snapshots")
  TEMPLATES_FILE = DIR.join("_rendered_templates.txt")
  MEDIA_TYPES = %w[text/html text/vnd.turbo-stream.html].freeze

  KEEP = %w[
    class style id for role type name value hidden open disabled checked selected readonly required multiple
    colspan rowspan scope headers popover popovertarget lang dir tabindex inert title alt placeholder width height
    data-controller data-action data-theme data-label
  ].freeze
  NOT_MASKED = %w[class role type scope lang dir data-controller data-action data-theme].freeze
  SKIPPED_ELEMENTS = %w[head script noscript meta link].freeze
  VOID_ELEMENTS = %w[area base br col embed hr img input source track wbr].freeze

  # SecureRandom.hex ids can come out all digits or all letters, and record ids
  # grow from run to run, so every hex-ish run collapses to the same "#".
  LONG_HEX = /\b[0-9a-f]{8,}\b/
  HEX_WITH_DIGIT = /[0-9a-f]*\d[0-9a-f]*/
  DATE_WORD = /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sept?(?:ember)?|
                Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?|Mon(?:day)?|Tue(?:s(?:day)?)?|Wed(?:nesday)?|
                Thu(?:r(?:s(?:day)?)?)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\b/x
  # A duration measured from the clock ("2 days 1 hour") ticks over between runs,
  # so its number and its plural are masked together.
  TIME_UNIT = /\d+ (second|minute|hour|day|week|month|year)s?\b/

  class << self
    def enabled? = ENV["CSS_SNAPSHOT"].present?

    # Everything the running view test has rendered (see ViewHook).
    def view_html = (@view_html ||= +"")

    def begin_test(test_class, test_name)
      slug = test_name.delete_prefix("test_").gsub(/[^\w-]+/, "_")[0, 90]
      @test = "#{test_class.gsub("::", "__")}/#{slug}-#{Digest::SHA1.hexdigest(test_name)[0, 6]}"
      @count = 0
    end

    def capture(request, response)
      return if response.body.blank?

      # The path only: query strings carry reset and OAuth tokens that differ every run.
      header = "<!-- #{request.request_method} #{mask(request.path)} -> #{response.status} -->\n"
      if MEDIA_TYPES.include?(response.media_type)
        write(header, response.body, stream: response.media_type.include?("turbo-stream"))
      elsif response.media_type == "application/json" && (html = embedded_html(response.body))
        # Autocomplete renders its result rows into JSON "html" fields.
        write(header, html, stream: true)
      end
    end

    # What an ActionView::TestCase rendered with render(partial: …), which never
    # passes through a request.
    def capture_rendered(html)
      write("<!-- rendered in a view test -->\n", html.to_s, stream: true) if html.present?
    end

    def normalize(html, stream: false)
      lines = []
      if stream
        Nokogiri::HTML5.fragment(html).children.each { |node| walk(node, 0, lines) }
      else
        doc = Nokogiri::HTML5(html)
        lines << "<html#{attributes(doc.root)}>" if doc.root
        walk(doc.at("body"), 0, lines) if doc.at("body")
      end
      lines.join("\n") << "\n"
    end

    def track_templates
      @templates = Set.new
      %w[render_template render_partial render_collection render_layout].each do |event|
        ActiveSupport::Notifications.subscribe("#{event}.action_view") do |*, payload|
          @templates << payload[:identifier].to_s.delete_prefix("#{Rails.root}/") if payload[:identifier]
        end
      end
      Minitest.after_run do
        FileUtils.mkdir_p(DIR)
        File.write(TEMPLATES_FILE, @templates.sort.join("\n") << "\n")
      end
    end

    private

    def write(header, html, stream:)
      return unless @test

      @count += 1
      path = DIR.join(@test, "#{@count}.html")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, header + normalize(html, stream:))
    rescue StandardError => e
      File.write(path, "css_snapshot failed: #{e.class}: #{e.message}\n") if path
    end

    def walk(node, depth, lines)
      pad = "  " * depth
      if node.text?
        text = mask_text(node.text)
        lines << "#{pad}#{text}" unless text.empty?
      elsif node.element?
        return if SKIPPED_ELEMENTS.include?(node.name)
        return if node.name == "input" && node["type"] == "hidden"

        lines << "#{pad}<#{node.name}#{attributes(node)}>"
        if node.name == "style"
          css = node.text.squish
          lines << "#{pad}  #{css}" unless css.empty?
        else
          node.children.each { |child| walk(child, depth + 1, lines) }
        end
        lines << "#{pad}</#{node.name}>" unless VOID_ELEMENTS.include?(node.name)
      end
    end

    def attributes(node)
      node.attribute_nodes.filter_map do |attr|
        name = attr.name
        next unless KEEP.include?(name) || name.start_with?("aria-") || name.match?(/\Adata-[\w-]+-target\z/)

        value = if name == "class" then attr.value.split.uniq.sort.join(" ")
                elsif NOT_MASKED.include?(name) then attr.value.squish
                else mask(attr.value.squish)
                end
        %( #{name}="#{value}")
      end.sort.join
    end

    def embedded_html(json)
      fragments = []
      collect = lambda do |value|
        case value
        when Hash then value.each_value(&collect)
        when Array then value.each(&collect)
        when String then fragments << value if value.lstrip.start_with?("<")
        end
      end
      collect.call(JSON.parse(json))
      fragments.join("\n").presence
    rescue JSON::ParserError
      nil
    end

    # Day and month names too: a timestamp's title tooltip turns over at
    # midnight just as its text does.
    def mask(value) = value.gsub(DATE_WORD, "D").gsub(LONG_HEX, "#").gsub(HEX_WITH_DIGIT, "#")

    def mask_text(text) = text.squish.gsub(DATE_WORD, "D").gsub(TIME_UNIT, '# \1s').gsub(/\d+/, "#")
  end

  # Names the snapshot files after the running test.
  module TestHook
    def before_setup
      super
      CssSnapshot.begin_test(self.class.name, name)
    end
  end

  # Captures each response right after the request that produced it.
  module SessionHook
    def process(...)
      super.tap { CssSnapshot.capture(request, response) }
    end
  end

  # Captures everything a view test renders as one snapshot, at the end. Since
  # Rails 8.1.4 `rendered` holds only the last render, so the hook keeps its own.
  # Cleared at teardown, not in begin_test, which runs after the setup blocks.
  module ViewHook
    def render(...)
      super.tap { |html| CssSnapshot.view_html << html.to_s }
    end

    def before_teardown
      CssSnapshot.capture_rendered(CssSnapshot.view_html)
      CssSnapshot.view_html.clear
      super
    end
  end
end

if CssSnapshot.enabled?
  ActionDispatch::IntegrationTest.include(CssSnapshot::TestHook)
  ActionDispatch::Integration::Session.prepend(CssSnapshot::SessionHook)
  ActionView::TestCase.include(CssSnapshot::TestHook, CssSnapshot::ViewHook)
  CssSnapshot.track_templates
end
