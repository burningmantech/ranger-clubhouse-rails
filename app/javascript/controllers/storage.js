// A preference kept in the browser: local for localStorage, session for
// sessionStorage. Reaching the store, reading it and writing it can all throw
// where site data is blocked, and a preference that cannot be kept is no
// error: a read answers null and a write does nothing.
function storage(area) {
    return {
        read(key) {
            try { return window[area].getItem(key) } catch { return null }
        },
        write(key, value) {
            try { window[area].setItem(key, value) } catch {}
        },
        remove(key) {
            try { window[area].removeItem(key) } catch {}
        }
    }
}

export const local = storage("localStorage")
export const session = storage("sessionStorage")
