# frozen_string_literal: true

module Person::StatusesHelper
  # One colour vocabulary for person status, shared by every roster and report
  # that shows one.
  #
  # Six helpers used to badge this same fact six different ways -- "retired"
  # was amber on one page, gray on another and absent on a third, and three
  # training reports painted "active" green on four rows in five. Colour that
  # means something different per page means nothing, and colour spent on the
  # majority row cannot mark the minority one.
  #
  # So statuses are grouped by what the reader has to do about them, not by
  # whether they sound like good or bad news, and each group gets exactly one
  # colour:
  #
  #   norm     -- "active", and nothing else. The settled majority gets no
  #               badge and no colour at all; the status prints as plain text.
  #               This is what buys the other three their force.
  #   pipeline -- somebody on the way in, with work attached to them right now.
  #               Signal Blue, the app's action colour, for the rows that carry
  #               an action.
  #   reduced  -- was a Ranger, still reachable, not currently standing. Amber:
  #               chase-able.
  #   context  -- a standing fact about who this person is, with nothing to do
  #               about it: they are finished, or they were never a volunteer
  #               Ranger in the first place. Plain graphite, deliberately
  #               chromaless.
  #   anomaly  -- a status this app does not know, including the "deleted"
  #               fallback a report substitutes for a person row that is gone.
  #               The only red.
  #
  # Every badge carries an icon as well as its colour, because colour alone
  # fails a colourblind reader and a sunlit phone on playa, and the status word
  # itself always prints -- as stored, never titleized.
  STATUS_STANDINGS = {
    pipeline: { variant: :primary, icon: "user-clock" },
    reduced: { variant: :warning, icon: "circle-pause" },
    context: { variant: :secondary, icon: "circle-minus" },
    anomaly: { variant: :error, icon: "triangle-exclamation" }
  }.freeze

  # Deprecated statuses are mapped too: the enum refuses them now, but
  # historical rows still carry them and a report that finds one should read it
  # as history rather than as an anomaly.
  STATUS_STANDING = {
    Person::ACTIVE => :norm,

    Person::ALPHA => :pipeline,
    Person::PROSPECTIVE => :pipeline,
    Person::PROSPECTIVE_WAITLIST => :pipeline,

    Person::INACTIVE => :reduced,
    Person::INACTIVE_EXTENSION => :reduced,
    Person::AUDITOR => :reduced,
    Person::PAST_PROSPECTIVE => :reduced,

    # Echelon is Burning Man org staff rather than a volunteer Ranger: rare on
    # a roster, and worth saying so, but not a status anyone chases.
    Person::ECHELON => :context,
    Person::RETIRED => :context,
    Person::RESIGNED => :context,
    Person::BONKED => :context,
    Person::UBERBONKED => :context,
    Person::DISMISSED => :context,
    Person::SUSPENDED => :context,
    Person::DECEASED => :context,
    Person::VINTAGE => :context
  }.freeze

  def person_status_standing(status) = STATUS_STANDING.fetch(status, :anomaly)

  def person_status_norm?(status) = person_status_standing(status) == :norm

  # A status for a column that has to render something on every row. The norm
  # prints as plain text so the exceptions are the only coloured things in the
  # column.
  def person_status_badge(status, size: "sm")
    standing = person_status_standing(status)
    return tag.span(status, class: "whitespace-nowrap") if standing == :norm

    variant, icon = STATUS_STANDINGS.fetch(standing).values_at(:variant, :icon)
    ui_badge(status, variant, icon:, icon_type: :solid, size:)
  end

  # A status for a roster row where status is incidental -- an eight-hundred
  # person list reads "active" nearly all the way down, and a chip on every row
  # is eight hundred chips saying nothing. Only the exception is badged.
  def person_status_exception_badges(status, size: "base")
    person_status_norm?(status) ? [] : [person_status_badge(status, size:)]
  end

  # A person's status as a report table cell reads it.
  def person_status_label(person) = person_status_badge(person.status)

  # The warning arrives as markup already, with the statuses inside it escaped
  # where they were filled in. Marking it safe again here would be the point
  # where a status could stop being text, so it is passed along as it comes.
  def status_warning_modals_for(old_status)
    StatusChangeWarnings.warnings_for(old_status:).transform_values do |warning|
      confirm_modal(
        title: warning[:title],
        message: warning[:message]
      ).fetch(:turbo_confirm)
    end
  end
end
