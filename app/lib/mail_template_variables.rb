# frozen_string_literal: true

# Which values a mail template reads.
#
# Read out of the template itself rather than kept in a list somewhere, so the
# names shown to whoever is editing can never fall out of step with what the
# message actually uses.
module MailTemplateVariables
  # A value printed, or tested by a condition.
  READS = /\{\{-?\s*([a-z_][\w.]*)|\{%-?\s*(?:if|elsif|unless)\s+([a-z_][\w.]*)/

  # A loop, which invents a name of its own for one item of a list.
  LOOPS = /\{%-?\s*for\s+([a-z_]\w*)\s+in\s+([a-z_][\w.]*)/

  module_function

  # Every name a template reads, in alphabetical order. Names a loop invented
  # are shown as they are written, since that is how an editor will meet them.
  def in(*sources)
    source = sources.compact.join("\n")

    source.scan(READS).flatten.compact.uniq.sort
  end

  # Which list each loop walks, by the name it gives one item.
  def loops_in(*sources)
    sources.compact.join("\n").scan(LOOPS).to_h { |item, list| [item, list] }
  end
end
