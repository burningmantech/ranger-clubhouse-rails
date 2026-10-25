# frozen_string_literal: true

# Request-time menu categories for the per-position training interface
# (/training/:slug) -- the one dynamic exception to the frozen compile-time
# constants in Menus. One category per active training position, in the
# exact Menus:: shape, so MenuBuilder, the mega menu, and the sidebar
# renderer consume them unchanged.
#
# Paths are concrete strings ("/training/green-dot", built from
# Training.slug), not route-helper symbols, because each resolves against a
# specific position. MegaMenu.linkable? admits them as app-relative paths, so
# training links and categories can be starred like any other.
# MegaMenu.tracked_paths stays static; Training::BaseController#tracked_page?
# records the visits instead.
#
# Visibility mirrors the Laravel TrainingPolicy view rule via standard
# visible_if role gates: admins see every category, In-Person Training takes
# Trainer, Mentor, or VC, and each ART needs its composed ART interface role.
# No caching: one small query per mega-menu render -- and per page for a
# person with no static category, whom MegaMenu.offered? asks about these
# last -- and role checks are
# already cached per person.
module TrainingMenu
  # Title of the second section, which holds the training's reports
  REPORTS_TITLE = "Reports"

  module_function

  # Category definitions for every active training position, In-Person
  # Training first, then the ARTs by title. Visibility is left to
  # MenuBuilder, same as the static MEGA_CATEGORIES. Eligibility is
  # Training.training_position? -- the same rule the controller resolver
  # enforces, so the menu can never list a position whose URL 404s.
  def definitions
    positions = Position.where(type: Position::TYPE_TRAINING, active: true)
                        .select { |position| Training.training_position?(position) }
    positions.sort_by! { |p| [(p.id == Position::TRAINING) ? 0 : 1, category_title(p)] }
    positions.map { |position| definition(position) }
  end

  # The category for one training position; also renders as the training
  # layout's sidebar menu. Remaining Phase 2 report items land here as those
  # pages ship. Sessions' active_prefix claims only the session/ subtree so
  # sibling report pages light their own item, not both.
  def definition(position)
    title = category_title(position)
    slug = Training.slug(position)
    {
      title:,
      description: "#{position.title} sessions and reports",
      icon: "graduation-cap",
      visible_if: { roles: Training.view_roles(position) },
      sections: [
        {
          title:,
          items: [
            { title: "Sessions", path: "/training/#{slug}", year_scoped: true,
              active_prefix: "/training/#{slug}/session",
              description: "The year's #{position.title} sessions, sign-ups, and trainer teams" },
            # ART mentoring trainings only, on the same flag the controllers
            # check. active_prefix keeps it lit on the pages beneath it.
            (
              if position.has_art_mentoring
                { title: "Mentoring", path: "/training/#{slug}/mentoring", year_scoped: true,
                  active_prefix: true,
                  description: "Pair mentors with mentees on shift and record how each mentee shift went" }
              end),
            # Not year_scoped: one document stands for the position, not for a
            # year. active_prefix keeps it lit while its own editor is open.
            { title: "Trainer Resources", path: "/training/#{slug}/resources",
              active_prefix: true,
              description: "The document #{position.title} publishes for its trainers" }
          ].compact
        },
        {
          title: REPORTS_TITLE,
          # A carried ?year= puts a query on the link, which then lights only
          # on that exact query; the reports with a filter bar take
          # active_prefix so they stay lit once a filter adds its own params.
          items: [
            # ART-only, the inverse of the two In-Person items below: upstream's
            # TrainingPolicy refuses the endpoint unless is_art, and In-Person
            # Training has no ART interface role to hold. The controller
            # redirects a typed In-Person URL for the same reason.
            (
              if Training.art?(position)
                { title: "All Trainee Notes", path: "/training/#{slug}/all-notes", year_scoped: true, active_prefix: true,
                  description: "Trainer notes on everyone who passed this year's sessions" }
              end),
            { title: "Capacity", path: "/training/#{slug}/capacity", year_scoped: true,
              description: "How full each session is — seats, sign-up mix, and pass counts" },
            { title: "Completed Training", path: "/training/#{slug}/completed-training", year_scoped: true,
              active_prefix: true,
              description: "Who passed each of the year's sessions" },
            # Only Tow Truck and Green Dot grant mentee positions; the Ember
            # sidebar gates this link on the same has_mentees flag, and the
            # controller redirects any other slug. Not year_scoped -- the
            # report is current standing, not a year's activity.
            (
              if Training.has_mentees?(position)
                { title: "Current Mentees", path: "/training/#{slug}/mentees",
                  description: "Who still holds a mentee position, and when they last rangered it" }
              end),
            { title: "Multiple Enrollments", path: "/training/#{slug}/multiple-enrollments", year_scoped: true,
              description: "Trainees signed up for more than one session" },
            # Only In-Person Training has ever had an online course
            # (position.has_online_course exists as a column, but nothing
            # writes it), so the item stays off the ART categories. Roles come
            # from the same authority as the controller gate, and are tighter
            # than the category's view_roles on purpose: Dirt Mentors and VCs
            # see the tree but not this report.
            (
              if position.id == Position::TRAINING
                { title: "Online Course Progress", path: "/training/#{slug}/online-course-progress",
                  year_scoped: true, active_prefix: true,
                  visible_if: { roles: Training.online_course_progress_roles(position) },
                  description: "Who enrolled in the year's online course, and who has finished it" }
              end),
            # Survey management is its own role family, tighter than the
            # category's view_roles -- a Dirt Mentor sees the tree but not the
            # feedback. active_prefix keeps the item lit on report and
            # per-trainer pages underneath it.
            { title: "Surveys", path: "/training/#{slug}/surveys", year_scoped: true,
              active_prefix: true,
              visible_if: { roles: Training.survey_management_roles(position) },
              description: "Feedback trainees and trainers gave on the year's sessions" },
            { title: "Trained, No Rangering", path: "/training/#{slug}/trained-no-work", year_scoped: true, active_prefix: true,
              description: "Who trained but never rangered a shift that requires it" },
            { title: "Trainer Attendance", path: "/training/#{slug}/trainer-attendance", year_scoped: true,
              description: "Who taught — or missed — each of the year's sessions" },
            # Intake data is global, not per-training, and the page reads
            # In-Person Training history specifically -- so, like upstream's
            # non-ART-only sidebar link, it stays off the ART categories (the
            # controller redirects an ART slug too). Roles come from the same
            # authority as that controller's gate and are tighter than the
            # category's view_roles: a Trainer sees the tree, but a PNV's
            # personnel flags and mentor bonks need Intake.
            (
              if position.id == Position::TRAINING
                { title: "Unified Flagging", path: "/training/#{slug}/unified-flagging",
                  year_scoped: true,
                  visible_if: { roles: Training.unified_flagging_roles(position) },
                  description: "Ranks, flags, and notes the intake teams left on this year's Prospectives and Alphas" }
              end),
            { title: "Untrained People", path: "/training/#{slug}/untrained-people", year_scoped: true, active_prefix: true,
              description: "Who signed up for a shift that requires it but is not trained yet" }
          ].compact
        }
      ]
    }
  end

  # Position::TRAINING is "In-Person Training"; every other training position
  # is "ART " + its title with the "Training" token stripped (position 179 is
  # titled "Training - Radio Practice"). The stripped title is the same one
  # the URL slug parameterizes, so a category always matches its path.
  def category_title(position)
    return "In-Person Training" if position.id == Position::TRAINING

    "ART #{Training.strip_training_token(position.title)}"
  end
end
