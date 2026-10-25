# frozen_string_literal: true

# Renders one mail template against the values a mailer supplied.
#
# Liquid reads plain values only, and prints them exactly as it finds them, so
# two things happen on the way in. Keys become strings, because that is what
# Liquid looks a value up by. And for an HTML part every string is escaped, so
# something a person typed cannot bring markup with it; text already prepared as
# HTML is left alone, so nothing is escaped twice. A plain text part is never
# escaped, because there the escapes would show.
module MailTemplateRenderer
  module_function

  def render(source, values, escape_html: true)
    Liquid::Template.parse(source).render!(prepare(values, escape_html))
  end

  def prepare(value, escape_html)
    case value
    when Hash
      value.to_h { |key, item| [key.to_s, prepare(item, escape_html)] }
    when Array
      value.map { |item| prepare(item, escape_html) }
    when String
      escape_html ? ERB::Util.html_escape(value) : value
    else
      value
    end
  end
end
