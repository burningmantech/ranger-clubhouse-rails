# frozen_string_literal: true

# DaisyUI Modal Helper
# Uses native <dialog> element with DaisyUI modal classes
# Stimulus controller for programmatic show/hide
# See: https://daisyui.com/components/modal/
#
# Options for `modal`:
#   :id           - DOM id (auto-generated if omitted)
#   :placement    - "top", "bottom", or "center" (default)
#   :closable     - whether backdrop/escape closes the dialog (default true)
#   :close_button - set false to suppress the auto-appended footer close button
#   :size         - :sm, :md (default), :lg, :xl, or :full — controls modal-box max-width
#   :class        - extra classes merged onto the <dialog> element
#
module ModalHelper
  MODAL_HEADER = "modal-header-bar"
  MODAL_TITLE = "modal-title-text"
  MODAL_BODY = "modal-body-content"
  MODAL_FOOTER = "modal-footer-bar"

  SIZE_CLASSES = {
    sm: "max-w-sm",
    md: "max-w-md",
    lg: "max-w-2xl",
    xl: "max-w-4xl",
    full: "max-w-full"
  }.freeze

  def modal(options = {}, &block)
    modal_id = options.delete(:id) || "modal-#{SecureRandom.hex(4)}"
    close_button = options.delete(:close_button)
    placement = options.delete(:placement) || "center"
    closable = options.delete(:closable) != false
    size = options.delete(:size) || :md
    size_class = SIZE_CLASSES[size] || SIZE_CLASSES[:md]

    modal_classes = ["modal size-auto max-h-none max-w-none overflow-y-auto", modal_placement_class(placement), options.delete(:class)].compact.join(" ").squish

    options[:id] = modal_id
    options[:class] = modal_classes
    options["data-controller"] = "modal"
    options["data-modal-closable-value"] = closable.to_s

    content_tag :dialog, options do
      inner = content_tag(:div, class: "modal-box #{size_class}".squish) do
        modal_builder = ModalBuilder.new(self, modal_id)
        content = capture(modal_builder, &block)
        unless modal_builder.footer_seen || close_button == false
          content += modal_builder.footer { modal_builder.close_button }
        end
        content
      end

      if closable
        inner += content_tag(:form, method: "dialog", class: "modal-backdrop") do
          content_tag(:button, "close")
        end
      end

      inner
    end
  end

  # The scaffold every Turbo form dialog shares: the turbo-frame wrapper, a
  # modal without the auto-appended close footer (the form supplies its own),
  # and the title. The block renders the body. Partials that are streamed
  # into an existing "modal" frame pass frame: false. Other modal options
  # (size:, placement:, ...) pass through.
  def modal_dialog(title:, id: nil, frame: "modal", **options, &block)
    dialog = modal(id:, close_button: false, **options) do |m|
      m.title(title) + m.body(&block)
    end
    frame ? turbo_frame_tag(frame) { dialog } : dialog
  end

  # The standard dialog-form footer: a submit plus a Cancel that closes the
  # dialog. Pass the form builder to submit through it; without one a bare
  # submit_button is used. Extra options (variant:, ...) go to the submit.
  # Footers with more than one submit keep an explicit button_row.
  def modal_form_footer(form = nil, submit:, close: "Cancel", **submit_options)
    button_row do
      control = form ? form.submit(submit, **submit_options) : submit_button(submit, **submit_options)
      control + modal_close_button(close)
    end
  end

  def modal_close_dialog
    turbo_empty_frame "modal"
  end

  def modal_close_button(label = "Close")
    button_action label, :secondary, data: { action: "modal#hide" }
  end

  def confirm_modal(options = {})
    method = options[:method] || "get"

    {
      turbo_confirm: confirm_modal_dialog(options),
      turbo_method: method,
      turbo: "true"
    }
  end

  # Just the dialog markup for data-turbo-confirm — for callers that manage
  # their own submission, such as a submit button inside a form, where
  # turbo_method must not appear.
  #
  # The return value is a plain String on purpose, and marking it html_safe
  # would reopen a hole. This markup is not written into the page: it is
  # written into an attribute, read back out, and handed to innerHTML. The
  # browser decodes an attribute once when it reads it, so a value that is
  # already safe-marked arrives at innerHTML with its escaping stripped, and a
  # name someone chose for themselves -- a callsign, a title -- becomes live
  # markup. Left as a plain String, Rails escapes it going in, the browser's
  # decode takes that layer back off, and what reaches innerHTML is the dialog
  # with the borrowed text still escaped inside it.
  #
  # The same counting applies to what comes in. A plain message is escaped here
  # and arrives as text, which is what nearly every caller wants. A message
  # already marked safe is carried through as markup -- so anything borrowed
  # inside it has to have been escaped where it was put there, the way
  # StatusChangeWarnings fills its wording in with `%`. Marking a message safe
  # to get bold text, with a name or a title interpolated into it, is where
  # this stops holding.
  def confirm_modal_dialog(options = {})
    title = options[:title] || "Confirm"
    message = options[:message] || "Continue?"
    confirm_label = options[:confirm_label] || "Confirm"
    cancel_label = options[:cancel_label] || "Cancel"
    # Destructive confirmations pass variant: :error so the button that does the
    # damage does not look like the safe default.
    confirm_variant = options[:variant] || :primary

    dialog = modal do |m|
      safe_join([
                  m.title(title),
                  m.body { message },
                  m.footer do
                    safe_join([
                                button_action(confirm_label, confirm_variant, id: "turbo-confirm-button"),
                                button_action(cancel_label, :secondary, id: "turbo-cancel-button")
                              ])
                  end
                ])
    end

    String.new(dialog)
  end

  def modal_placement_class(placement)
    case placement
    when "top"
      "modal-top"
    when "bottom"
      "modal-bottom"
    else
      "modal-middle"
    end
  end

  # Builder DSL for constructing modal content sections (title, body, footer).
  class ModalBuilder
    include ButtonHelper
    include IconHelper

    attr_reader :template, :modal_id, :footer_seen

    def initialize(template, modal_id)
      @template = template
      @modal_id = modal_id
      @footer_seen = false
    end

    def title(header = nil, options = {}, &block)
      @template.content_tag :div, class: MODAL_HEADER do
        options[:class] = "#{MODAL_TITLE} #{options[:class]}".squish
        icon_html = fa_icon(:xmark, :solid, class: "w-3 h-4", "aria-hidden": "true") +
                    @template.content_tag(:span, "Close modal", class: "sr-only")
        heading = @template.content_tag(:h3, options) do
          block_given? ? @template.capture(&block) : header
        end
        close_btn = @template.button_action(icon_html, :ghost,
                                            class: "btn-circle", data: { action: "modal#hide" })
        heading + close_btn
      end
    end

    def body(options = {}, &block)
      options[:class] = "#{MODAL_BODY} #{options[:class]}".squish
      @template.content_tag :div, options do
        @template.capture(&block) if block_given?
      end
    end

    def footer(options = {}, &block)
      @footer_seen = true
      options[:class] = "#{MODAL_FOOTER} #{options[:class]}".squish
      @template.button_row options do
        @template.capture(&block)
      end
    end

    def close_button(label = "Close")
      @template.button_action(label, :secondary, data: { action: "modal#hide" })
    end
  end
end
