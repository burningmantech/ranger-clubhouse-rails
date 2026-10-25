import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme", on the navbar. Sets the theme on <html>
// -- the `.dark` class the `dark:` variant keys on, and data-theme for
// daisyUI's tokens -- from the saved preference or the system, and flips it
// from the toggle (application/_theme_toggle). The toggle's icon is drawn by
// CSS from that class, so nothing here paints it.
export default class extends Controller {
  connect() {
    const savedTheme = localStorage.getItem('theme')
    const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches

    if (savedTheme === 'dark' || (!savedTheme && systemPrefersDark)) {
      this.enableDarkMode()
    } else {
      this.enableLightMode()
    }
  }

  toggle() {
    if (document.documentElement.classList.contains('dark')) {
      this.enableLightMode()
    } else {
      this.enableDarkMode()
    }
  }

  enableDarkMode() {
    document.documentElement.classList.add('dark')
    document.documentElement.dataset.theme = 'dark'
    localStorage.setItem('theme', 'dark')
  }

  enableLightMode() {
    document.documentElement.classList.remove('dark')
    document.documentElement.dataset.theme = 'light'
    localStorage.setItem('theme', 'light')
  }
}
