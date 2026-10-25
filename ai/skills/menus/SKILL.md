---
name: menus
description: Define navigation menus with visibility rules based on user status, roles, and computed conditions. Use when creating or modifying sidebar/navbar menus, adding menu items, or implementing role-based menu visibility.
---

# Clubhouse 3 Menu System

This skill provides guidance for working with the hash-based menu abstraction system.

## Critical Rules

**NEVER do these:**
- Add menu items directly in layout ERB files
- Use inline conditionals (`if current_user.is_ranger?`) for menu visibility
- Create class-based menu objects - use hashes only
- Use string paths when symbol route helpers exist

**ALWAYS do these:**
- Define menus in `app/lib/menus.rb` using frozen hash constants
- Use symbol paths (e.g., `:me_profile_path`) not string URLs
- Add visibility rules via `:visible_if` hash
- Give every item a short `:description` (shown by the mega menu)
- Update both `docs/MENUS.md` and this skill when modifying `app/lib/menu_builder.rb`

## When to Use This Skill

- Adding new menu items to existing menus
- Creating new menu definitions (Admin, HQ, etc.)
- Implementing role-gated menu sections
- Building nested/tree menu structures
- Troubleshooting menu visibility issues

## Quick Reference

### Adding a Menu Item

```ruby
# In app/lib/menus.rb, add to the appropriate section's :items array:
{ title: "New Feature", path: :me_new_feature_path,
  description: "One-line summary shown in the mega menu" }
```

### Year-Scoped Items

Sidebar links drop query params, so navigating between year-scoped pages
(e.g. `/bmid/manage?year=2024` → `/bmid/export`) resets to the current year.
Items whose controller reads `params[:year]` opt in with `year_scoped: true`
— the sidebar then carries the request's `?year=` (4-digit shape check only;
range validation stays with the page). String paths (`TrainingMenu`) carry
it too. Do NOT add it to items that ignore `params[:year]`. A link with a
query lights only on that exact query, so a page whose filters add params
needs `active_prefix: true` beside it (as below) to stay lit.

```ruby
{ title: "Export Badges", path: :bmid_export_path, active_prefix: true, year_scoped: true,
  description: "Review the qualified badges and send a print batch to Eventree" }
```

### Scoped Active Prefixes

`active_prefix:` also accepts a String or a route-helper Symbol (resolved the
same way as `:path`): the item stays active for descendants of THAT prefix
instead of its own path. Use it when a landing item's sibling pages live
underneath the landing's path, so both would otherwise light up:

```ruby
# /training/in-person/capacity must NOT light the Sessions item, but
# /training/in-person/session/123 must.
{ title: "Sessions", path: "/training/in-person",
  active_prefix: "/training/in-person/session" }
```

### Adding with Visibility

```ruby
# Status-based (person.is_ranger? OR person.is_echelon?)
{ title: "Rangers Only", path: :ranger_path,
  visible_if: { status: [:is_ranger?, :is_echelon?] } }

# Role-based (Current.has_role?)
{ title: "Admin Only", path: :admin_path,
  visible_if: { roles: [Role::ADMIN] } }

# Computed condition (from @menu_context[:computed])
{ title: "Vehicles", path: :vehicles_path,
  visible_if: { computed: :show_vehicles } }

# NOT status (hidden for auditors)
{ title: "Not for Auditors", path: :path,
  visible_if: { not_status: [:is_auditor?] } }
```

### Adding a Computed Condition

1. Update `ApplicationController#build_menu_items`:

```ruby
@menu_context = {
  person: current_user,
  computed: {
    show_vehicles: VehicleEligibility.is_person_eligible?(current_user.id, Current.year),
    your_new_condition: YourLogic.check(current_user)  # Add here
  }
}
```

2. Reference in menu:

```ruby
{ title: "Feature", path: :path, visible_if: { computed: :your_new_condition } }
```

### Creating a New Section

```ruby
# Regular section (with header and divider)
{
  title: "Section Name",
  items: [
    { title: "Item 1", path: :path1 },
    { title: "Item 2", path: :path2 },
  ]
}

# Submenu (header only, no divider)
{
  title: "Submenu Name",
  submenu: true,
  visible_if: { status: [:is_ranger?] },  # Optional
  items: [...]
}
```

### Creating a New Menu

```ruby
# In app/lib/menus.rb
module Menus
  HQ = {
    sections: [
      {
        title: "HQ Menu",
        items: [
          { title: "Dashboard", path: :hq_root_path, root: true },
        ]
      },
      {
        title: "Users",
        submenu: true,
        visible_if: { roles: [Role::ADMIN, Role::VIEW_PII] },
        items: [
          { title: "People", path: :hq_people_path },
        ]
      }
    ]
  }.freeze
end
```

### Mega-Menu Categories

Menu groups double as mega-menu categories via top-level keys (only the mega
menu reads them; sidebar/navbar renderers only read `:sections`). Sections
shared with the sidebar are extracted into `*_SECTION` constants and composed
both ways (see `Menus::ME` vs `Menus::MY_CLUBHOUSE`).

```ruby
AGREEMENTS = {
  title: "Agreements",                      # Category name; also its panel key and "category:" favorite
  description: "Signed agreements ...",     # Shown in the mobile category index
  icon: "file-signature",                   # FontAwesome icon name
  visible_if: { roles: [Role::ADMIN] },     # Optional category-level gate
  sections: [...]
}.freeze

# Ordered category list; add new groups here to surface them in the mega menu.
MEGA_CATEGORIES = [MY_CLUBHOUSE, USER, ADMIN, AGREEMENTS, ...].freeze
```

**Gate the category only when every item admits exactly the same people.** A
category gate hides the whole category, including items gated for other roles
(an Admin-only gate on `Menus::ADMIN` hid OAuth Clients from the Tech Ninjas it
is for), and the sidebar never reads it. When items differ, leave the category
ungated and give EVERY item the gate its controller enforces — an ungated item
is then offered to everyone. A category whose items are all hidden drops out on
its own. See `Menus::ADMIN`, `SHIFT_OPERATIONS`, and `test/lib/admin_menu_test.rb`.

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

The navbar offers the menu at all only to a person with a visible category
beyond `MY_CLUBHOUSE` and `USER` (`MegaMenu.offered?`; see `docs/MENUS.md` →
"Mega Menu"). A test that opens the menu gives its person a role first:
`MegaMenuTestHelper#offer_mega_menu_to`.

Favorites/recents key off resolved URL paths (`MegaMenu` in
`app/lib/mega_menu.rb`). Excluded from starring/visit tracking
(`MegaMenu.linkable?`): items with `:confirm`, `:path` values that are neither
symbols nor app-relative Strings (a single leading `/`), and items with
`data: { turbo_method: ... }` — other `:data` keys do NOT exclude. A category
can be starred too, keyed `category:<title.parameterize>`, so renaming a
category drops everyone's star for it.
See `docs/MENUS.md` → "Mega Menu".

### Multilevel Submenus

```ruby
{
  title: "Parent Section",
  sections: [
    {
      title: "Child Section",
      submenu: true,
      items: [...],
      sections: [
        {
          title: "Grandchild Section",
          submenu: true,
          items: [...]
        }
      ]
    }
  ]
}
```

## Using in Views

### Sidebar

```erb
<% sidebar_menu :me do %>
  <%= sidebar_render_menu(Menus::ME, @menu_context) %>
<% end %>
```

### Navbar (Future)

```erb
<%= navbar_render_menu(Menus::ME, @menu_context) %>
```

## Anti-Patterns

**WRONG - Inline conditionals in ERB:**
```erb
<% if current_user.is_ranger? %>
  <%= sidebar_item "Rangers", rangers_path %>
<% end %>
```

**RIGHT - Visibility in menu definition:**
```ruby
{ title: "Rangers", path: :rangers_path, visible_if: { status: [:is_ranger?] } }
```

---

**WRONG - String paths:**
```ruby
{ title: "Profile", path: "/me/profile" }
```

**RIGHT - Symbol paths:**
```ruby
{ title: "Profile", path: :me_profile_path }
```

---

**WRONG - Unfrozen hash:**
```ruby
Me = { sections: [...] }
```

**RIGHT - Frozen hash:**
```ruby
Me = { sections: [...] }.freeze
```

## File Locations

| Purpose | Location |
|---------|----------|
| Menu definitions | `app/lib/menus.rb` |
| Builder module | `app/lib/menu_builder.rb` |
| Mega menu logic | `app/lib/mega_menu.rb` |
| Shared utilities | `app/helpers/menu_helper.rb` |
| Sidebar rendering | `app/helpers/sidebar_helper.rb` |
| Navbar rendering | `app/helpers/navbar_helper.rb` |
| Mega menu rendering | `app/helpers/mega_menu_helper.rb` + `app/views/me/menu/` |
| Menu context setup | `app/controllers/application_controller.rb` |
| Full API reference | `docs/MENUS.md` |

## Visibility Logic Reference

| Condition | Operator | Example |
|-----------|----------|---------|
| `:status` | OR | Any status method returns true |
| `:not_status` | AND (negated) | ALL status methods return false |
| `:roles` | OR | Any role check passes |
| `:computed` | truthy | Context computed value is truthy |
| `:proc` | truthy | Lambda returns truthy |

Multiple conditions combine with AND logic.

## Person Status Methods

Common methods available on `person`:
- `is_ranger?` - Active, Inactive, Inactive Extension, Retired
- `is_echelon?` - Echelon status
- `is_auditor?` - Auditor status
- `is_applicant?` - Prospective, Alpha
- `is_active?` - Active only
- `can_work?` - Can work shifts

## Role Constants

Common roles in `Role::`:
- `ADMIN` - Full admin access
- `VIEW_PII` - Can view personal info
- `TRAINER` - Training cadre
- `MENTOR` - Mentoring cadre
- `VC` - Volunteer coordinator
- `TIMESHEET_MANAGEMENT` - Timesheet access

See `app/models/role.rb` for full list.
