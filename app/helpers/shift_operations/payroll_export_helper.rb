# frozen_string_literal: true

module ShiftOperations
  module PayrollExportHelper
    # How each status looks. The wording lives on the shift itself, so the
    # badge and the checking file cannot spell it differently.
    STATUS_STYLES = {
      verified: [:success, "circle-check"],
      unverified: [:error, "circle-exclamation"],
      still_on_duty: [:warning, "clock"]
    }.freeze

    # Colour alone never carries the status -- each badge names itself and
    # carries its own icon.
    def payroll_status_badge(shift)
      variant, icon = STATUS_STYLES[shift.status]
      ui_badge(shift.status_label, variant, icon:, icon_type: :solid)
    end

    # The whole request as hidden fields, so a control sitting outside the main
    # form can resubmit the same report with one thing changed.
    def payroll_query_fields(form, except: nil)
      values = form.query_params[PayrollExportForm::PARAM_SCOPE].except(*Array(except))

      safe_join(values.flat_map do |name, value|
        field = "#{PayrollExportForm::PARAM_SCOPE}[#{name}]"
        # A list needs a field per value, named so the page reads it back as a
        # list. One field holding the array would arrive as the string it
        # prints as, and match nothing.
        if value.is_a?(Array)
          value.map { |item| hidden_field_tag("#{field}[]", item, id: nil) }
        else
          hidden_field_tag(field, value, id: nil)
        end
      end)
    end

    # What the folded parameter panel says about itself, so the window and the
    # rules can be read without opening it.
    def payroll_parameter_summary(form, positions)
      from = form.parsed_start_time
      to = form.parsed_end_time
      return "Choose a pay period and the positions to include." unless from && to

      breaks = if form.break_after.to_i.positive?
                 "#{form.break_duration} min break after #{pluralize(form.break_after, "hour")}"
               else
                 "No meal breaks"
               end

      # The chosen count is the set actually reported on, not what the address
      # asked for -- a link naming positions since retired would otherwise
      # count them and read "30 of 27 positions".
      chosen = (form.position_ids & positions.map(&:id)).size

      "#{from.strftime(DateTimeHelper::MONTH_DAY_TIME)} to #{to.strftime(DateTimeHelper::MONTH_DAY_TIME)}" \
        " · #{breaks} · #{chosen} of #{positions.size} positions"
    end

    # A person's card heading: who they are, what payroll knows them by, what
    # still needs checking, and their hours.
    def payroll_person_heading(person)
      tag.div(class: "flex flex-wrap items-center gap-x-3 gap-y-1 w-full") do
        safe_join([
                    person_display_link(person.record, person.id),
                    tag.span("Paycom Employee ID #{person.employee_id}", class: "text-stone-muted"),
                    payroll_review_badge(person),
                    tag.span("Total #{hour_minute_format(person.total_duration)}",
                             class: "ms-auto text-heading")
                  ].compact)
      end
    end

    # Fed the whole roster, never the narrowed one, so the picker can always
    # move straight from one person to another.
    def payroll_person_options(roster)
      [["Everyone", ""]] + roster.map { |person| [person.callsign, person.id] }
    end

    # A download link carrying the report the page is showing. Anything not yet
    # checked off is asked about first -- once a file reaches payroll, fixing it
    # is somebody else's afternoon.
    def payroll_export_link(label, csv_variant, form, style: :secondary, review_count: 0)
      url = shift_operations_payroll_export_path(
        form.query_params.merge(variant: csv_variant, format: :csv)
      )
      # turbo: false on every download. Left to Turbo, the click fetches the
      # file, finds it is not HTML, throws it away and reloads the same address
      # -- so the whole report is built twice for one download.
      options = { data: { turbo: false } }

      if review_count.positive?
        # Deliberately not data-turbo-confirm: Turbo submits a link carrying one
        # as a form, and reads the reply in JavaScript, so the file never
        # reaches the reader. The controller asks first and then navigates.
        options[:data] = options[:data].merge(
          controller: "download-confirm",
          action: "click->download-confirm#confirm",
          download_confirm_message_value: confirm_modal_dialog(
                             title: "Export Entries Needing Review",
            message: "#{pluralize(review_count, "entry")} " \
                     "#{(review_count == 1) ? "is" : "are"} unverified or still " \
                     "on duty. Export anyway?",
            confirm_label: "Export"
          )
        )
      end

      # export_csv_link carries the icon and the 36px floor every other export
      # in the app gets; this one only adds the download and confirm behavior.
      export_csv_link(url, label, options.merge(variant: style))
    end

    private

    # Helper names share one namespace across the whole application, so even a
    # private one is spelled for this page.
    def payroll_review_badge(person)
      return nil unless person.needs_review_count.positive?

      ui_badge("#{pluralize(person.needs_review_count, "entry")} to check", :warning,
               icon: "circle-exclamation", icon_type: :solid)
    end
  end
end
