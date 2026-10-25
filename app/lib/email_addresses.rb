# frozen_string_literal: true

module EmailAddresses
  DO_NOT_REPLY = "do-not-reply@burningman.org"
  MENTOR_CADRE = "ranger-mentorcadre-list@burningman.org"
  PERSONNEL = "ranger-personnel@burningman.org"
  TECH_CADRE = "ranger-tech-cadre@burningman.org"
  TICKETING = "ranger-ticketing-stuff@burningman.org"
  TRAINING_ACADEMY = "ranger-trainingacademy-list@burningman.org"
  VOLUNTEER_COORDINATORS_TEAM = "ranger-vc-list@burningman.org"

  # An address SES would take, as far as can be told before asking: the form
  # AWS documents, UserName@[SubDomain.]Domain.TopLevelDomain. It passes the
  # pattern the Clubhouse checks everywhere, and the rules that pattern lets
  # slide -- no leading, trailing or doubled dot before the @, a dot in the
  # domain (not name@gmailcom), and a last label of 2 or more letters or xn--
  # punycode (not an IP, a number or one letter). None of those could be
  # delivered. The mail library has the last word, in Rbs.to_line. nil is not
  # an address: the pattern refuses it before the rest is asked.
  def self.sendable?(address)
    URI::MailTo::EMAIL_REGEXP.match?(address) && !address.match?(/\A\.|\.\.|\.@/) &&
      address.match?(/@.+\.(?:[a-z]{2,}|xn--[a-z\d-]+)\z/i)
  end
end
