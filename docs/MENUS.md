# Menu Abstraction API Reference

Complete reference for the Clubhouse 3 hash-based menu abstraction system. This system provides renderer-agnostic menu definitions that can be rendered by both the sidebar and navbar.

**Related Files:**
- Menu Builder: `app/lib/menu_builder.rb`
- Menu Definitions: `app/lib/menus.rb`
- Mega Menu Logic: `app/lib/mega_menu.rb`
- Menu Helper: `app/helpers/menu_helper.rb`
- Sidebar Renderer: `app/helpers/sidebar_helper.rb`
- Navbar Renderer: `app/helpers/navbar_helper.rb`
- Mega Menu Renderer: `app/helpers/mega_menu_helper.rb`
- AI Skill: `.claude/skills/menus/SKILL.md`

---

## Architecture Overview

```
Menu Definition (Hash)
        │
        ▼
   MenuBuilder  ──────────────────┐
        │                         │
        ▼                         ▼
   MenuHelper            Visibility Filtering
        │
        ├──────────────────┬───────────────────┐
        ▼                  ▼                   ▼
 SidebarHelper       NavbarHelper       MegaMenuHelper
 (sidebar_render_menu) (navbar_render_menu) (app/views/me/menu)
        │                  │                   │
        ▼                  ▼                   ▼
  Vertical Sidebar   Navbar Dropdowns    Mega Menu Dialog
```

**Key Principle:** Menu definitions are pure data. The Builder filters by visibility. Renderers transform filtered data into UI-specific markup.

---

## Menu Definition Structure

### Top-Level Hash

```ruby
{
  use_person: false,  # Optional. Resolve route helpers with @person when true
  sections: [...]  # Array of section hashes
}.freeze
```

### Section Hash

| Key | Type | Description |
|-----|------|-------------|
| `:title` | String | Section header text |
| `:submenu` | Boolean | If true, renders as submenu header (no divider) |
| `:items` | Array | Array of item hashes (menu links) |
| `:sections` | Array | Array of nested section hashes (multilevel submenus) |
| `:visible_if` | Hash | Visibility conditions (see below) |

A section can have both `:items` and `:sections` - items render first, then nested sections.

### Item Hash

| Key | Type | Description |
|-----|------|-------------|
| `:title` | String | Display text (required) |
| `:description` | String | Short description shown by the mega menu. Ignored by sidebar/navbar renderers. |
| `:path` | Symbol/String | Route helper symbol (e.g., `:me_profile_path`) or URL string. |
| `:visible_if` | Hash | Visibility conditions (see below) |
| `:root` | Boolean | Mark as root path for active state detection |
| `:active_prefix` | Boolean/String/Symbol | Keep the sidebar item active for descendant routes that share this path prefix. A String (or a route-helper Symbol, resolved like `:path`) matches that prefix instead of the item's own path — for landing items whose sibling pages live underneath them (e.g. the training Sessions item claims only its `session/` subtree so the sibling report items win their own pages). |
| `:year_scoped` | Boolean | Carry the current request's `?year=` (when it is a plausible 4-digit year) onto the sidebar link, so navigating between year-scoped pages keeps the selected year. Opt-in — only for items whose controller reads `params[:year]`. Works on String paths too (appended with `?` or `&`). The link then lights only on that exact query, so pair it with `active_prefix: true` when the page adds params of its own (filters). |
| `:icon` | Symbol | FontAwesome icon name |
| `:badge` | String | Badge text to display |
| `:badge_variant` | Symbol | Badge color (`:error`, `:success`, `:warning`, `:info`) |

Any additional keys are passed through to the renderer's item method.

### Visibility Conditions

| Key | Type | Description |
|-----|------|-------------|
| `:status` | Array | Person status methods to check (OR logic). E.g., `[:is_ranger?, :is_echelon?]` |
| `:not_status` | Array | Person status methods that must ALL return false |
| `:roles` | Array | Role constants to check (OR logic). E.g., `[Role::ADMIN, Role::VIEW_PII]` |
| `:computed` | Symbol | Key in context's `:computed` hash that must be truthy |
| `:proc` | Proc | Lambda receiving context, must return truthy |

All conditions are combined with AND logic (all must pass).

---

## MenuBuilder Module

### Methods

#### `build(menu_definition, context)`

Filters a menu definition based on visibility rules.

```ruby
sections = MenuBuilder.build(Menus::ME, @menu_context)
```

**Parameters:**
- `menu_definition` - Hash with `:sections` key
- `context` - Hash with `:person` and `:computed` keys

**Returns:** Array of filtered section hashes

#### `visible?(item, context)`

Checks if an item or section should be visible.

```ruby
MenuBuilder.visible?(item_hash, @menu_context)
```

**Returns:** Boolean

---

## MenuHelper Module

Renderer-agnostic utilities included by sidebar and navbar helpers.

### Methods

#### `menu_build(menu_definition, context)`

Wrapper for `MenuBuilder.build`.

#### `menu_uses_person?(menu_definition)`

Returns whether the menu definition resolves route helpers with `@person`.

#### `menu_resolve_path(path, use_person: false, year_scoped: false)`

Resolves a symbol or string path to a URL. With `year_scoped: true`, appends
the current request's `?year=` when it looks like a 4-digit year (range
validation stays with each page's controller).

```ruby
url = menu_resolve_path(:me_profile_path)  # => "/me/profile"
url = menu_resolve_path(:person_path, use_person: true)  # => "/person/123"
url = menu_resolve_path("/custom/path")     # => "/custom/path"
url = menu_resolve_path(nil)                # => ""
url = menu_resolve_path(:bmid_export_path, year_scoped: true)  # => "/bmid/export?year=2024" when viewing 2024
url = menu_resolve_path("/training/in-person/capacity", year_scoped: true)  # => "/training/in-person/capacity?year=2024"
```

#### `menu_item_options(item)`

Extracts render options from item hash, removing menu-specific keys.

```ruby
options = menu_item_options(item)
# Returns item.except(:title, :path, :visible_if, :sections, :submenu,
#                     :use_person, :active_prefix, :description, :confirm,
#                     :year_scoped)
```

#### `menu_item_active_prefix?(item)`

Returns whether an item should stay active for matching route prefixes.

#### `menu_each_section(sections, depth: 0, &block)`

Iterates sections recursively, yielding section and depth.

```ruby
menu_each_section(sections) do |section, depth|
  puts "#{' ' * depth}#{section[:title]}"
end
```

---

## SidebarHelper Methods

### `sidebar_render_menu(menu_definition, context, theme: "me")`

Renders a menu for the sidebar (vertical layout).

```erb
<% sidebar_menu :me do %>
  <%= sidebar_render_menu(Menus::ME, @menu_context) %>
<% end %>
```

**Parameters:**
- `menu_definition` - Hash with `:sections` key (e.g., `Menus::ME`)
- `context` - Hash with `:person` and `:computed` keys
- `theme` - Theme name for styling (`:me`, `:admin`, `:hq`)

---

## Menu Context

The context hash passed to menu rendering:

```ruby
@menu_context = {
  person: current_user,      # Person model instance
  computed: {
    show_vehicles: true,     # Pre-computed conditions
    # Add more as needed
  }
}
```

Set in `ApplicationController#build_menu_items`.

---

## Examples

### Basic Menu Definition

```ruby
module Menus
  Example = {
    sections: [
      {
        title: "Main Menu",
        items: [
          { title: "Dashboard", path: :dashboard_path, root: true },
          { title: "Profile", path: :profile_path },
          { title: "Schedule", path: :schedule_path, active_prefix: true },
        ]
      }
    ]
  }.freeze
end
```

### Status-Based Visibility

```ruby
{
  title: "Ranger Tools",
  path: :tools_path,
  visible_if: { status: [:is_ranger?, :is_echelon?] }
}
```

### Role-Based Visibility

```ruby
{
  title: "Admin Panel",
  path: :admin_path,
  visible_if: { roles: [Role::ADMIN] }
}
```

### Computed Condition

```ruby
# In controller:
@menu_context = {
  person: current_user,
  computed: { has_pending_tasks: Task.pending.exists? }
}

# In menu definition:
{
  title: "Tasks",
  path: :tasks_path,
  badge: "!",
  visible_if: { computed: :has_pending_tasks }
}
```

### Multilevel Submenus

```ruby
{
  title: "Admin",
  sections: [
    {
      title: "User Management",
      submenu: true,
      visible_if: { roles: [Role::ADMIN] },
      items: [
        { title: "Users", path: :admin_users_path },
        { title: "Roles", path: :admin_roles_path },
      ]
    }
  ]
}
```

### Custom Proc Visibility

```ruby
{
  title: "Special Feature",
  path: :special_path,
  visible_if: {
    proc: ->(ctx) { ctx[:person].created_at < 1.year.ago }
  }
}
```

---

## Adding a New Menu

1. Add a frozen constant to `app/lib/menus.rb`:

```ruby
module Menus
  YOUR_MENU = {
    sections: [
      # Define sections here
    ]
  }.freeze
end
```

2. Use in layout:

```erb
<% sidebar_menu :your_theme do %>
  <%= sidebar_render_menu(Menus::YOUR_MENU, @menu_context) %>
<% end %>
```

3. Add any new computed conditions to `ApplicationController#build_menu_items`.

---

## Mega Menu

The navbar mega menu (`app/views/application/_mega_menu.html.erb`) renders
`Menus::MEGA_CATEGORIES` — an ordered list of **category groups** — followed by
one request-time category per active training position (`TrainingMenu`), into
a full-screen `<dialog>` opened from the top navbar. `Menus::PERSON` is
deliberately excluded.

### Category Group Shape

A category group is a menu-definition hash with extra top-level keys, read
only by the mega menu (sidebar/navbar renderers only read `:sections`):

```ruby
AGREEMENTS = {
  title: "Agreements",                  # Category name; parameterized into the panel key and its "category:" favorite
  description: "Signed agreements ...", # Shown in the mobile category index
  icon: "file-signature",               # FontAwesome icon name
  visible_if: { roles: [Role::ADMIN] }, # Optional category-level gate
  sections: [...]                       # Regular sections/items
}.freeze

MEGA_CATEGORIES = [MY_CLUBHOUSE, USER, ADMIN, AGREEMENTS, ...].freeze
```

**Gate the category only when every item admits exactly the same people.** A
category gate hides the whole category, including items gated for other roles
(an Admin-only gate on `Menus::ADMIN` hid OAuth Clients from the Tech Ninjas it
is for), and the sidebar never reads it. When items differ, leave the category
ungated and give EVERY item the gate its controller enforces — an ungated item
is then offered to everyone. See `Menus::ADMIN`, `SHIFT_OPERATIONS`, and
`test/lib/admin_menu_test.rb`.

`test/lib/menu_category_gate_test.rb` enforces the first half: a category gate
that does not cover an item's gate fails the suite, naming the roles shut out.
Administration, People and Volunteer Coordinator each shipped with that defect.

An item's `roles:` must name what its controller actually admits, which is not
always the roles you can read off the page. A controller gating with
`authorize_ability` has no `authorized_roles` list to copy, and a role that is
upgraded into another by `RoleManager` — Event Management On Playa becomes
Event Management while its setting is on — belongs in the item's gate only if
the controller names the raw role too. Vehicle Paperwork listed the raw role,
so its holders saw the link year-round and were turned away all off-season.
See `test/lib/vehicles_menu_test.rb`.

Renaming a category's `title` changes its key, so `PersonFavorite.prune_stale!`
deletes everyone's star for that category the next time they open the menu —
the same accepted trade-off as a renamed route.

Sections are defined once as constants (e.g. `PRE_EVENT_SECTION`) and shared:
`Menus::ME` composes them for the sidebar while the category groups wrap them
for the mega menu. Categories whose sections/items are all filtered out are
pruned automatically.

### Supporting Pieces

| Purpose | Location |
|---------|----------|
| Category filtering + path resolution | `app/lib/mega_menu.rb` (`MegaMenu.categories`, `.offered?`, `.linkable_items`, `.tracked_paths`, `.category_key`) |
| Renderer helper | `app/helpers/mega_menu_helper.rb` |
| Frame + toggle controllers | `app/controllers/me/menu_controller.rb`, `app/controllers/me/favorites_controller.rb` |
| Favorites / recents storage | `PersonFavorite`, `PersonPageVisit` (keyed by resolved URL path; a starred category by `category:<panel key>`) |
| Visit tracking | `ApplicationController#track_page_visit` (after_action) via `#tracked_page?`, which `Training::BaseController` extends |
| Star form | `#mega-menu-star-form` in `app/views/me/menu/_content.html.erb`, submitted by every star |
| Dialog behavior, hotkey, live search filter | `app/javascript/controllers/mega_menu_controller.js` |
| Styles | `app/assets/stylesheets/components/mega-menu.css` |

The menu is offered only to a person who can see some category beyond My
Clubhouse and Account (`MegaMenu.offered?`, over `MegaMenu::MENU_ONLY_CATEGORIES`
and then the training categories): My Clubhouse is the `/me` sidebar and Account
is the navbar's user dropdown, so a Ranger with no roles already has every link
it would show. `MegaMenuHelper#mega_menu_offered?` asks once per page. For
everyone else `application/_top_menu` renders the triggers, the dialog and the
`mega-menu` controller with its hotkey actions on the bar; for such a person it
renders none of them, and the first-sign-in tour drops its Menu step
(`me/dashboard/_onboarding`). `GET /me/menu` itself is not gated: nothing requests
it. `test/lib/mega_menu_test.rb` also pins the premise: `Menus::MY_CLUBHOUSE`
holds exactly `Menus::ME`'s sections.

The menu opens on **Favorites** (`MegaMenu::DEFAULT_PANEL`), from either grip
trigger or from **Ctrl+Shift+K / Cmd+Shift+K** (the unshifted chord belongs to
the global search bar). Closing it by any route, or picking a panel
(`mega_menu_controller#show`), clears the filter box: a star's re-render would
otherwise re-apply the stale filter and snap back to the results. A panel
picked from inside a panel it hides (a Favorites shortcut, the phone Categories
index, Back) hands focus to the new panel's first visible control.

Favorites and recently-visited entries store resolved URL paths and render by
intersecting with the currently *visible* links, so permission changes and
renamed routes and categories drop entries instead of leaking them. Favorites go further:
`PersonFavorite.prune_stale!` **deletes** rows whose path is no longer visible
every time the menu is built. Visibility includes transient gates (Settings,
computed flags), so a feature switched off for the off-season permanently
drops its favorites — an accepted trade-off. Excluded from starring
and visit tracking (see `MegaMenu.linkable?`): items with `:confirm`, items
whose `:path` is neither a route-helper symbol nor an app-relative String (a
single leading `/`; only `TrainingMenu` builds those), and items with
`data: { turbo_method: ... }` (non-GET actions like Logout and Clear Cache).
Other `:data` keys do not exclude an item. `MegaMenu.tracked_paths` holds the
static categories only; `Training::BaseController#tracked_page?` tracks a
training's own menu paths, matched exactly, with no query.

**Categories can be starred too.** The star sits beside the category panel's
`<h3>` (a sibling, so its label stays out of the heading's name), and is stored
in `person_favorite.path` as `category:<panel key>` (`MegaMenu.category_key`),
which can never collide with a path. A starred category shows in Favorites under
a "Categories" heading as a shortcut (`mega_category_index_button`) that opens
its panel, with its own star to unstar it there.

**Every star is a toggle button** (`MegaMenuHelper#mega_star_button`): a
`<button>` that submits the one hidden `#mega-menu-star-form` through `form=`
and its own `formaction`, with `aria-pressed` for the state and the same label
either way ("Favorite Capacity", "Favorite Account category"). One shared form
keeps a CSRF token per menu rather than per star. Turbo disables the submitting
button, which drops its focus, so the controller remembers the star on
`turbo:submit-start` and focuses its replacement after the re-render.

### Search

The header holds a search box instead of a title. A hidden `search` panel is
rendered once with every visible link, deduplicated by resolved path
(`MegaMenuHelper#mega_search_items`, which maps each resolved path to an
`[item, category title]` pair) and carrying a `data-search-text` attribute of the lowercased title
plus description. Each result names its category in parentheses after the
title. Favorites and Recently visited name it too, but only for a title that
appears twice in the same list (`MegaMenuHelper#mega_labeled` — each training's
"Capacity"); the star's label carries the same name. The category is passed to `me/menu/_item` as a **separate
`category_title:` local**, never merged into the item hash — `menu_item_options`
is a blacklist `except`, so any unrecognized item key is emitted verbatim as
an HTML attribute on the link. Typing filters those rows
in the browser — no request, no debounce. Clearing the box (or pressing
Escape, which the dialog's `cancel` handler intercepts while a query is
present) restores the panel the person was on. Unlike the favorites panels,
search includes non-favoritable items such as Logout.

---

## Design Decisions

- **Pure data**: Menu definitions are frozen hash constants with no behavior
- **Renderer-agnostic**: Same definition works with sidebar, navbar, or future renderers
- **Single source of truth**: One definition, multiple presentations
- **Symbol paths**: Route helpers stored as symbols, resolved at render time (request-time menus such as `TrainingMenu` use app-relative Strings)
- **Multilevel support**: Sections can nest via `:sections`
- **Empty pruning**: Sections/items with no visible content are automatically hidden
- **Immutable**: Menu hashes are frozen to prevent runtime modification
