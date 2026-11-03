import { Controller } from "@hotwired/stimulus"
import { local } from "controllers/storage"

// Connects to data-controller="theme", on the navbar. Sets the theme on <html>
// -- the `.dark` class the `dark:` variant keys on, and data-theme for
// daisyUI's tokens -- from the saved preference or the system, and flips it
// from the toggle (application/_theme_toggle). The toggle's icon is drawn by
// CSS from that class, so nothing here paints it.
export default class extends Controller {
  connect() {
    const savedTheme = local.read("theme")
    const systemPrefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches

    this.apply(savedTheme === "dark" || (!savedTheme && systemPrefersDark))
  }

  toggle() {
    this.apply(!document.documentElement.classList.contains("dark"))
  }

  // Dark or light, on the page and on file.
  apply(dark) {
    const theme = dark ? "dark" : "light"
    document.documentElement.classList.toggle("dark", dark)
    document.documentElement.dataset.theme = theme
    local.write("theme", theme)
  }
}
