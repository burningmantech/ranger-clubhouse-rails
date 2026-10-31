# Included by every location that proxies to Puma (conf.d/03-nginx.conf). Rails believes every
# one of these, so none may arrive from the client. Rack 3 reads "Forwarded" BEFORE
# X-Forwarded-*: "Forwarded: host=evil.example" alone changes request.host, and with it every
# *_url the app generates. TLS ends at Cloudflare and the load balancer, so the scheme is
# always https here ($scheme would say http); Rails assumes it anyway (assume_ssl).
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $remote_addr;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header Forwarded         "";
# A Client-IP that disagrees with X-Forwarded-For makes Rails raise IpSpoofAttackError.
proxy_set_header Client-IP         "";
