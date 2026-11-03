import { Turbo } from "@hotwired/turbo-rails"

// The JSON a @rails/request.js call answered with. A redirect is the sign-in
// page a session that has run out answers with: the page goes there and the
// caller gets null. An error answer throws, with the server's message or the
// caller's. A good answer that is not JSON (a proxy's page, a captive portal)
// rejects with request.js's own message, which the caller shows. The redirect
// is read first: response.json is a getter that rejects on a page.
export async function readJson(response, fallback) {
    if (response.redirected) {
        Turbo.visit(response.response.url)
        return null
    }
    if (!response.ok) {
        const data = await response.json.catch(() => ({}))
        throw new Error(data.error || fallback)
    }
    return response.json
}
