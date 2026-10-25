# Pin npm packages by running ./bin/importmap
#
# `preload: true` is importmap-rails' default, and it emits a modulepreload for
# every pin on every page. Everything below that a page does not always need is
# therefore pinned `preload: false`: it stays available to `import`, but it is
# fetched when something asks for it rather than up front.

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
# Controllers are lazy-loaded (see controllers/index.js): Stimulus fetches one
# the first time an element asks for it by name. Preloading defeats that — it
# pulled all 53 down on every page load, 61KB gzipped across 53 requests, for
# the two or three a given page actually uses.
pin_all_from "app/javascript/controllers", under: "controllers", preload: false

# Stimulus cannot start without controllers/index.js and controllers/application.js,
# so those two are preloaded from the layouts instead. Pinning them here with
# preload: true would not work: importmap-rails expands pin_all_from over the
# package pins, so the directory's preload setting always wins for a name inside it.


# curl -o app/javascript/vendor/cropper-VERSION.js https://cdnjs.cloudflare.com/ajax/libs/cropperjs/VERSION/cropper.esm.min.js
# The file must land in vendor/: importmap-rails silently drops a pin whose file
# it cannot find, and the browser then reports "Failed to resolve module specifier".
pin "cropperjs", to: "vendor/cropper-2.3.0.js", preload: false

# driver.js - the first-sign-in tour (controllers/onboarding_controller.js).
# https://github.com/nilbuild/driver.js, which npm's driver.js names as its
# repository since 1.10 (it moved there from kamranahmedse/driver.js).
# curl -o app/javascript/vendor/driver-VERSION.js https://unpkg.com/driver.js@VERSION/dist/driver.js.mjs
# Its stylesheet, dist/driver.css, is app/assets/stylesheets/driver.css; the
# re-theme is components/driver.css.
pin "driver.js", to: "vendor/driver-1.10.1.js", preload: false

# Vanilla Calendar Pro - https://vanilla-calendar.pro/
# Downloaded from: https://www.npmjs.com/package/vanilla-calendar-pro
pin "vanilla-calendar-pro", to: "vendor/vanilla-calendar-pro-3.0.5.js", preload: false

# Lexxy rich text editor - https://github.com/basecamp/lexxy
# Copied from the lexxy 1.0.0 gem (`gem fetch lexxy -v 1.0.0`, then `gem unpack`):
#   app/assets/javascript/lexxy.min.js
# Matching stylesheets, same gem: app/assets/stylesheets/lexxy-{variables,content,editor}.css
# Delete line 1 of lexxy-content.css and lexxy-editor.css (`@import url("lexxy-variables.css")`):
# Tailwind does not inline a url() import, and application.css imports the variables itself.
# @rails/activestorage is deliberately not pinned. Lexxy imports it only when an
# upload starts, and rich_text_area turns uploads off (attachments="false").
pin "lexxy", to: "vendor/lexxy-1.0.0.js", preload: false

# Drag and drop - https://www.stimulus-components.com/docs/stimulus-sortable/
# Downloaded from https://ga.jspm.io/npm:@stimulus-components/sortable@5.0.3/dist/stimulus-sortable.mjs
# and its two dependencies:
#   https://ga.jspm.io/npm:sortablejs@1.15.7/modular/sortable.esm.js
#   https://ga.jspm.io/npm:@rails/request.js@0.0.13/src/index.js
#
# Under app/javascript/vendor rather than the vendor/javascript directory
# `bin/importmap pin` downloads to: /vendor is gitignored here, so a pin
# pointing there resolves on the machine that ran the command and 404s
# everywhere else.
pin "@stimulus-components/sortable", to: "vendor/stimulus-sortable-5.0.3.js", preload: false
pin "sortablejs", to: "vendor/sortablejs-1.15.7.js", preload: false
pin "@rails/request.js", to: "vendor/rails-request-0.0.13.js", preload: false
