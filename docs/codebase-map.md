# Codebase Map

This note is a fast orientation guide for future sessions. It points to the files and directories that matter most when changing common areas of the app.

## Stack

- Rails 8.1 on ruby 4.0
- MariaDB via `mysql2`
- Importmap, Turbo, Stimulus
- Tailwind 4, Sass, DaisyUI
- Minitest, Capybara, Selenium
- RuboCop, Brakeman

Primary references:

- [AGENTS.md](../AGENTS.md)
- [docs/DESIGN-GUIDE.md](./DESIGN-GUIDE.md)
- [docs/UI-COMPONENTS.md](./UI-COMPONENTS.md)
- [docs/MENUS.md](./MENUS.md)

## Read First

- [AGENTS.md](../AGENTS.md)
- [config/routes.rb](../config/routes.rb)
- [app/controllers/application_controller.rb](../app/controllers/application_controller.rb)
- [app/controllers/concerns/authentication.rb](../app/controllers/concerns/authentication.rb)
- [app/lib/menu_builder.rb](../app/lib/menu_builder.rb)
- [test/test_helper.rb](../test/test_helper.rb)

## Structure

- `app/controllers`: request handling, with most self-service features under `app/controllers/me`
- `app/forms`: form objects for validation and orchestration
- `app/helpers`: helper-first UI layer, including shared components and form builders
- `app/lib`: domain logic and menu definitions
- `app/views`: ERB templates and partials
- `config`: routes, initializers, framework wiring
- `test`: controller and system test coverage

## Key Conventions

- Auth is enforced globally and restored from `cookies.signed[:session_id]`
- UI is helper-first rather than component-class-first
- Form objects are used heavily for workflow and validation
- Menus are data-driven and filtered by a builder
- `/me` is the main logged-in user area
- Project-specific guidance lives in `AGENTS.md` (imported by `.claude/CLAUDE.md`) and the docs in this folder

## Where To Change X

### Auth, Login, Logout, Password Reset

Start here:

- [config/routes.rb](../config/routes.rb)
- [app/controllers/sessions_controller.rb](../app/controllers/sessions_controller.rb)
- [app/controllers/concerns/authentication.rb](../app/controllers/concerns/authentication.rb)
- [app/controllers/application_controller.rb](../app/controllers/application_controller.rb)
- [app/forms/login_form.rb](../app/forms/login_form.rb)
- [app/forms/password_reset_form.rb](../app/forms/password_reset_form.rb)
- [app/forms/password_update_form.rb](../app/forms/password_update_form.rb)
- [test/controllers/sessions_controller_test.rb](../test/controllers/sessions_controller_test.rb)

### New `/me` Feature or Route

Start here:

- [config/routes.rb](../config/routes.rb)
- [app/controllers/me](../app/controllers/me)
- [app/views/me](../app/views/me)
- [app/controllers/me_controller.rb](../app/controllers/me_controller.rb)
- [app/controllers/me/dashboard_controller.rb](../app/controllers/me/dashboard_controller.rb)

Typical end-to-end path:

1. Add the route under the `namespace :me` block in [config/routes.rb](../config/routes.rb).
2. Create or update the controller under [app/controllers/me](../app/controllers/me).
3. Add views under [app/views/me](../app/views/me).
4. If the feature needs navigation, add the item to the matching `*_SECTION` constant's `:items` in [app/lib/menus.rb](../app/lib/menus.rb). `Menus::ME` (the sidebar) and the mega menu's `MY_CLUBHOUSE` category share those sections; see the `menus` skill.
5. Add controller and system coverage under [test/controllers/me](../test/controllers/me) and [test/system/me](../test/system/me).

### Profile

Start here:

- [app/controllers/me/profile_controller.rb](../app/controllers/me/profile_controller.rb)
- [app/views/profile](../app/views/profile)
- [test/controllers/me/profile_controller_test.rb](../test/controllers/me/profile_controller_test.rb)
- [test/system/me/profile_test.rb](../test/system/me/profile_test.rb)

### Messages

Start here:

- [app/controllers/me/messages_controller.rb](../app/controllers/me/messages_controller.rb)
- [app/views/me/messages](../app/views/me/messages)
- [app/forms/message_form.rb](../app/forms/message_form.rb)
- [app/forms/message_reply_form.rb](../app/forms/message_reply_form.rb)
- [app/forms/find_recipient_form.rb](../app/forms/find_recipient_form.rb)
- [test/system/me/messages_recipient_autocomplete_test.rb](../test/system/me/messages_recipient_autocomplete_test.rb)

Notes:

- This area is partial-heavy and Turbo-aware.
- Inspect the templates before changing controller behavior for thread or autocomplete changes.

### Schedule and Sign-Ups

Start here:

- [app/controllers/me/schedule_controller.rb](../app/controllers/me/schedule_controller.rb)
- [app/controllers/me/available_sign_ups_controller.rb](../app/controllers/me/available_sign_ups_controller.rb)
- [app/views/me/schedule](../app/views/me/schedule)
- [app/views/me/available_sign_ups](../app/views/me/available_sign_ups)

### Timesheet

Start here:

- [app/controllers/me/timesheet_controller.rb](../app/controllers/me/timesheet_controller.rb)
- [app/views/layouts/me/timesheet.html.erb](../app/views/layouts/me/timesheet.html.erb)
- [app/views/me/timesheet](../app/views/me/timesheet)

### Menus and Navigation

Start here:

- [app/lib/menus.rb](../app/lib/menus.rb)
- [app/lib/menu_builder.rb](../app/lib/menu_builder.rb)
- [app/helpers/menu_helper.rb](../app/helpers/menu_helper.rb)
- [app/helpers/sidebar_helper.rb](../app/helpers/sidebar_helper.rb)
- [app/helpers/navbar_helper.rb](../app/helpers/navbar_helper.rb)
- [docs/MENUS.md](./MENUS.md)

### Shared UI and Forms

Start here:

- [app/helpers/ui_components_helper.rb](../app/helpers/ui_components_helper.rb)
- [app/helpers/ui_components](../app/helpers/ui_components)
- [app/helpers/form_helper.rb](../app/helpers/form_helper.rb)
- [app/helpers/page_layout_helper.rb](../app/helpers/page_layout_helper.rb)
- [app/helpers/table_helper.rb](../app/helpers/table_helper.rb)
- [docs/UI-COMPONENTS.md](./UI-COMPONENTS.md)
- [docs/form_helper.md](./form_helper.md)

## Tests

Start here:

- [test/test_helper.rb](../test/test_helper.rb)
- [test/support/authentication_test_helper.rb](../test/support/authentication_test_helper.rb)
- [test/application_system_test_case.rb](../test/application_system_test_case.rb)
- [test/support/system_test_helpers.rb](../test/support/system_test_helpers.rb)

Useful examples:

- [test/controllers/sessions_controller_test.rb](../test/controllers/sessions_controller_test.rb)
- [test/controllers/me/profile_controller_test.rb](../test/controllers/me/profile_controller_test.rb)
- [test/system/me/profile_test.rb](../test/system/me/profile_test.rb)
- [test/system/me/messages_recipient_autocomplete_test.rb](../test/system/me/messages_recipient_autocomplete_test.rb)
