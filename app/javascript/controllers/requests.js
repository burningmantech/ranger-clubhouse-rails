import { Turbo } from "@hotwired/turbo-rails"

// The JSON a @rails/request.js call answered with. A redirect is the sign-in
// page a session that has run out answers with: the page goes there and the
// caller gets null. An error answer throws, with the server's message or the
// caller's. The redirect is read first: response.json is a getter that rejects
// on a page that is not JSON.
export async function readJson(response, fallback) {
    if (response.redirected) {
        Turbo.visit(response.response.url)
        return null
    }
    const data = await response.json.catch(() => ({}))
    if (!response.ok) throw new Error(data.error || fallback)
    return data
}
