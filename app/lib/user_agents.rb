# frozen_string_literal: true

# Reads a browser's User-Agent header. UserAgentParser.parse builds a new parser
# on every call, reading and compiling the gem's whole pattern file (about 10 ms),
# so one is built once and kept for the process. It only reads once built, so
# threads can share it.
module UserAgents
  module_function

  # The browser and its operating system. The device is left out: nothing here
  # shows it, and its patterns are a third of the work.
  def parse(user_agent)
    @parser ||= UserAgentParser::Parser.new
    @parser.parse_ua(user_agent, @parser.parse_os(user_agent))
  end
end
