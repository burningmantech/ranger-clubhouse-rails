# Administration Interface UX/UI Plan (Categorized)

## Overview

This plan defines administration UX/UI direction for Clubhouse 3 before implementation.  
Administration surfaces are every route outside:
- `/me/**`
- `/sessions/**`
- password reset flows (`/password_reset/**`, `/password_resets/**`, and equivalent endpoints)

### Primary Goals

- Keep visual continuity with the existing end-user interface
- Support information-dense usage for trained admins on desktop and mobile
- Split design guidelines and skills into end-user and administration categories
- Keep administration guidelines derived from end-user guidelines and evolve incrementally
- Use existing UI components for administration interfaces

---

## 1. Design Guideline Categories

### Category A: End-User Guidelines (Source Baseline)

Applies to `/me`, sessions, and password reset flows.

Core characteristics:
- Maximum clarity and guided flows
- Strong ADHD-oriented scaffolding patterns
- Full accessibility baseline and cognitive support
- Lower-density defaults with explicit instructional context

Primary guideline/skill sources:
- `design-rules`
- `design-foundations`
- `design-layouts`
- `design-components`
- `design-forms`
- `design-content`
- `menus`
- `project-standards`

### Category B: Administration Guidelines (Derived Profile)

Applies to all non-`/me`, non-session, non-password-reset routes.

Core characteristics:
- Starts from end-user baseline first
- Trained-user assumptions and denser information presentation
- Reduced instructional overhead where safe
- Same accessibility baseline retained

Administration deltas (current):
- Denser layout patterns are allowed where readability remains strong
- Guidance copy can be shorter and more operational
- Self-explanatory sections are targeted to risky or complex pages

Administration deltas (future):
- Only added after real interface usage reveals a clear gap
- Must remain backward-compatible with end-user surfaces
- Must be documented in this plan as explicit admin overrides

---

## 2. Skill Categories and Usage Model

### End-User Skill Category

Use these as the canonical baseline:
1. `design-rules`
2. `design-foundations`
3. `design-layouts`
4. `design-components`
5. `design-forms`
6. `design-content`
7. `menus`
8. `project-standards`

### Administration Skill Category

For now, administration uses the same skills and helper ecosystem, with this plan defining override intent:
1. `design-rules` (applies unchanged)
2. `design-foundations` (applies unchanged unless explicit admin override is approved)
3. `design-layouts` (same breakpoint strategy)
4. `design-components` (existing component library only)
5. `design-forms` (existing form builder patterns; denser composition only)
6. `design-content` (shorter operational copy allowed)
7. `menus` (role-based admin menu growth)
8. `project-standards` (applies unchanged)

### Governance Rule

Administration guidelines are not a separate design system. They are an additive profile on top of end-user guidelines, updated gradually as the project matures.

---

## 3. Success Criteria

1. Guideline categories are explicit: end-user baseline and admin derived profile
2. Skill categories are explicit with inheritance from end-user standards
3. Admin interface recommendations include options with pros/cons and clear recommendations
4. Admin interfaces use existing UI components in current planning scope
5. Multi-dashboard strategy and self-explanatory page strategy are both defined
6. No plan direction introduces regressions for existing end-user interfaces

---

## 4. Best-Practice Principles for Admin Interfaces

1. Query-first list views (search/filter/sort/pagination behavior)
2. Dense but scannable presentation
3. Predictable role-aware navigation
4. Safe destructive-action handling
5. Progressive disclosure for advanced controls
6. Keyboard-efficient admin flows
7. Mobile practicality with prioritized information

---

## 5. Interface Recommendations

## 5.1 Data Listing Interfaces

Current component policy: use existing UI helpers only.

### Option A: `ui_table responsive: false` for dense operational lists

| Pros | Cons |
|------|------|
| Dense desktop readability | Mobile horizontal scroll is expected |
| Existing semantics and patterns | Less mobile-friendly than card stacking |

### Option B: `ui_table` (responsive, the default) for mobile-sensitive lists

| Pros | Cons |
|------|------|
| Better mobile adaptation | Less dense on smaller screens |
| Shares `ui_table` styling and supports stacked rows | May not fit wide operational datasets |

### Option C: Mixed strategy per page

| Pros | Cons |
|------|------|
| Flexible without introducing new components | Requires page-level choice discipline |
| Keeps implementation within current helper ecosystem | |

### Option D: Two-level drill-down for categorized records

A category index of `ui_drill_down_row` leading to a per-category `filter_bar` + `ui_table`
page. See **Pattern 6: Records Management** in `docs/DESIGN-GUIDE.md`.

| Pros | Cons |
|------|------|
| Each page answers one question; no scrolling past irrelevant categories | Two clicks to reach a record instead of one |
| Category counts and exception badges are visible before committing to a page | Needs a second route, action, and view |
| The category leaves the filter set and the table, so both get simpler | Wrong fit when the reader's question spans categories |

### Recommendation

Use **Option C** for the table itself, and **Option D** for the page structure whenever the
records fall into a small, stable set of categories:

1. Keep `ui_table`'s responsive default (since 2026-10-03), dense operational pages included:
   admin reports are read on a phone on playa too
2. Pass `responsive: false` only where the grid itself is the point (a matrix or a ledger read
   sideways) or the page is a print sheet, and say why at the call site
3. Structure a categorized management section as a drill-down (Option D) rather than one
   page of stacked per-category accordions — accordions put every category's table in one
   document and force the filter set to carry the category as a filter
4. Keep a flat single-page table when there is no natural category, when a category holds
   only a handful of records, or when the report deliberately reads across categories
5. Keep sorting/filtering/pagination implementation within existing components and controller logic for now.
   The one exception is Salesforce Query, whose POST results cannot be fetched again: it sorts in the
   browser (DESIGN-GUIDE > Client-Side Sortable Headings)
6. Put the page's CSV export in the filter bar's `actions:` rather than a button row of its own —
   the export is scoped by the filters, so it belongs on the control that sets them. A category
   index has no filter bar, so its export stays in the `button_row` beside New Record

**Reference implementations:** Asset Inventory (`asset-management/records`), Slots
(`scheduling/slots`). Assets Outstanding (`asset-management/assets-outstanding`) is the
counter-example: it reads across every type on purpose, so it stays flat.

## 5.2 Dashboard Interfaces

### Option A: Fixed sections

| Pros | Cons |
|------|------|
| Lowest complexity | Less customizable |
| Uses existing components directly | |

### Option B: Tabbed domain dashboards

| Pros | Cons |
|------|------|
| Handles large domains cleanly | More clicks to compare domains |
| Works with existing navigation helpers | |

### Option C: Role-aware hub dashboard

| Pros | Cons |
|------|------|
| Good admin landing pattern | Requires clear visibility rules |
| Keeps parity with existing page structure | |

### Recommendation

Use **Option C** as primary and **Option B** for complex domains.

### Multi-Dashboard Strategy

1. Admin Home dashboard
2. People dashboard
3. Events/Operations dashboard
4. Reports/Compliance dashboard

All dashboards use existing layout and section helpers.

## 5.3 Navigation Interfaces

### Option A: Expanded sidebar with collapsible sections

| Pros | Cons |
|------|------|
| Existing pattern and menu infrastructure | Sidebar length can grow |
| Role visibility already supported | |

### Option B: Sidebar + domain landing pages

| Pros | Cons |
|------|------|
| Better orientation for occasional admins | Adds one click for expert users |
| Uses existing page patterns | |

### Recommendation

Use **Option A** by default. Add **Option B** only in complex domains.

## 5.4 Form Interfaces

### Option A: Compact composition using existing form helpers

| Pros | Cons |
|------|------|
| No new components needed | Must enforce readability |
| Faster adoption | |

### Option B: Multi-column groups on desktop (`lg:` only)

| Pros | Cons |
|------|------|
| Improves throughput for short fields | Easy to over-compress if misused |
| Mobile stays stacked | |

### Option C: Sectioned tabs/accordion for long forms

| Pros | Cons |
|------|------|
| Reduces perceived complexity | Requires clear validation surfacing |
| Existing patterns can be reused | |

### Recommendation

Use all three with conservative defaults and no new component creation.

## 5.5 Self-Explanatory Page Patterns

### Option A: Intent header + action summary
### Option B: Context help section for risky pages
### Option C: First-use hints for uncommon flows

### Recommendation

Use Option A broadly. Use Option B for permissions, destructive actions, and compliance flows. Use Option C only when needed.

---

## 6. Existing UI Component Policy (Current)

Administration interfaces will use existing UI components.

Allowed current component set (non-exhaustive):
- `hero_panel`
- `ui_section`
- `ui_table`
- `tab_navigation`
- `ui_form` / existing `AppFormBuilder` patterns
- existing sidebar/menu rendering helpers
- existing button/link helpers

Current constraints:
1. No new admin-specific helper components in this stage
2. No new admin-specific color system in this stage
3. If a gap appears, document it first and defer component expansion to a later plan revision

---

## 7. Accessibility and Cognitive Policy for Admin

### Must keep

- WCAG AA contrast baseline
- Keyboard navigation and visible focus
- Semantic HTML and ARIA correctness
- Clear validation and error messaging
- Dark mode support parity
- Minimum 36px interactive targets

### Allowed reductions from end-user defaults

- Less ADHD-specific instructional scaffolding
- Shorter operational copy for trained users
- Less explanatory text on routine pages

### Not allowed

- Accessibility regressions
- Color-only status communication
- Hidden critical actions without explicit labeling

---

## 8. Backward Compatibility Guarantees

- End-user interfaces remain source baseline and cannot be regressed by admin changes
- Existing helper APIs remain stable and additive
- Admin route styling/configuration changes must not alter `/me` behavior
- Any future admin override must be opt-in and localized

---

## 9. Execution Phases (Plan Only)

### Phase 1: Categorization and governance
- Finalize end-user/admin guideline split
- Finalize end-user/admin skill split
- Document admin override governance

### Phase 2: IA and navigation
- Define admin domain map and role visibility matrix
- Expand `Menus::ADMIN` in phased increments

### Phase 3: Interface rollout with existing components
- Build list pages with `ui_table`
- Build dashboard pages with existing section/layout helpers
- Build forms with existing form helpers and denser composition where needed

### Phase 4: Validation and hardening
- Regression checks against key end-user routes
- Mobile/desktop and dark-mode checks
- Keyboard and screen-reader checks
- Performance checks on high-row-count admin lists

---

## Critical Path

1. Establish guideline and skill category split
2. Lock governance for admin overrides
3. Ship first admin interfaces with existing components only
4. Validate no regressions on end-user interfaces

---

## Risks and Mitigations

1. **Risk:** Admin pages diverge too quickly from baseline  
   **Mitigation:** Require explicit documented override before any admin-specific change
2. **Risk:** Existing components feel constrained in some admin flows  
   **Mitigation:** Capture concrete gaps and defer new components to planned revisions
3. **Risk:** Mobile usability degrades in dense pages  
   **Mitigation:** Keep `ui_table`'s responsive default; opt out only where the grid is the point
4. **Risk:** End-user regressions from shared helper updates  
   **Mitigation:** Additive-only updates and focused regression checks

---

## Open Questions / Assumptions

### Assumptions

- Admin users receive basic training
- Existing UI helpers can cover initial admin rollout
- End-user style language remains the visual baseline

### Open Questions

1. Which admin domains need dashboards first?
2. Which high-risk pages need self-explanatory context in initial rollout?
3. At what point should admin-specific helper proposals be reopened?

---

## Request Conformance Checklist

| Requested Update | Status | Location |
|---|---|---|
| Split design guidelines into end-user and administration categories | Met | Sections 1 and 2 |
| Split skills into end-user and administration categories | Met | Section 2 |
| Base admin guidelines on end-user guidelines and modify gradually | Met | Sections 1, 2, 9 |
| Admin interfaces use existing UI components | Met | Sections 5 and 6 |
