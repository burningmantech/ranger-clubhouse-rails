// A preference kept in the browser. Reaching the store, reading it and writing
// it can all throw where site data is blocked, and a preference that cannot be
// kept is no error: a read answers null and a write does nothing. area is
// "localStorage" or "sessionStorage".
export function read(area, key) {
    try { return window[area].getItem(key) } catch { return null }
}

export function write(area, key, value) {
    try { window[area].setItem(key, value) } catch {}
}

export function remove(area, key) {
    try { window[area].removeItem(key) } catch {}
}
