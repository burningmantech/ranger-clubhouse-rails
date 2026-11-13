Opinions, not findings. None of these is a departure from a written rule.

1. **Fix the shared layer first.** Ninety departures sit in helpers, stylesheets and controllers, and they are the only ones a single change removes from every page. In order of reach: the required marker and tooltip help in `AppFormBuilder`; keyboard access in `tabs_controller`; an accessible name on `modal`; `delete_button`'s missing default confirmation; `ui_label_value`'s `text-sm` default.

2. **The guide documents about half of the component layer.** Of 125 shared helper methods, 46 have no entry in the guide, including some of the most used (`modal_dialog` in 47 files, `export_csv_link` in 84, `person_display_link` in 84). If `docs/UI-COMPONENTS.md` is where those live, the guide should say so per component, because "a component not documented in this design guide" is the trigger for the approval workflow (PROC-01) and today that test fails for helpers nobody would call unapproved.

3. **Several of the guide's examples are not rules, and readers will take them as rules.** My own first pass did: five rule IDs I wrote from examples had to be withdrawn (BTN-07, LAYOUT-02, SPACE-01, FORM-08, and HERO-01 outside the app shell), which moved 204 findings from DIVERGENT to UNCOVERED. Where the guide means "must", it should say so; where it means "for instance", a marker would help. Assigning IDs in the guide itself, with the CRITICAL/PREFERRED/AVOID marker on each, would settle this and make future audits diffable by rule.

4. **The guide contradicts itself in a few places.** Section titles are `font-semibold` under Heading Levels (line 533) and `font-medium` in the Typography Quick Reference (line 4033). The sticky button row is described as "using the `sticky: true` option" (line 2846) above an example that does not pass it, and the helper is not sticky unless asked (`button_helper.rb:56`). `inline-flex-center` is listed as a custom utility (line 652) and no stylesheet defines it. The radius table gives buttons and inputs 12px while the theme sets `--radius-field` to 8px.

5. **"One primary action per view" needs a definition of view.** Thirty-five BTN-04 findings are mostly list pages with a primary button per card or row (one per trainee, one per application stage) and HQ screens with several live actions. Those may be the right design. The rule would be more useful if it said whether a card, a dialog and a table row each count as a view.

6. **The schedule and timesheet screens chose a tablet tier on purpose.** The `md:` findings in `common/schedule` and `common/timesheet` come from a sticky action rail that appears at 768px. That is a design decision at odds with BP-01 rather than an accident; either sanction it as a third use of `md` or rebuild the rail on the `lg` fold.

7. **Print sheets are a second design system.** Nine sheets, five stylesheet families that repeat one skeleton, raw tables, hex literals and their own chips and callouts. They account for a large share of the TABLE-01, COLOR-01, STYLE-01 and BADGE-01 findings. One shared print stylesheet and a paragraph in the guide would retire most of them.

8. **Dense log tables want their own sanction.** Admin logs set cells in `text-sm leading-snug` deliberately, through one constant (`Admin::LogStylesHelper::LOG_TEXT`, 8 findings). TYPE-03 forbids `text-sm` table content without exception; I would add one for logs rather than enlarge them.

9. **Empty values are the cheapest consistency win.** Sixty-four places print "-", "None" or italics where `value_or_dash` exists and is already used in 65 files. It is a mechanical replacement.

10. **Severity is conservative.** Only 52 findings are `high` because reviewers were told to reserve it for what a reader can see or cannot use. The copy findings (163) are all `low` and could be cleared in one sitting.
