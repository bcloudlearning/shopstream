#!/usr/bin/env bash
# setup-server.sh: builds the ShopStream web server from scratch.
# Usage: sudo ./scripts/setup-server.sh <domain> <email> [staging|production|none]
set -euo pipefail

DOMAIN="${1:?Usage: sudo $0 <domain> <email> [staging|production|none]}"
EMAIL="${2:?Usage: sudo $0 <domain> <email> [staging|production|none]}"
CERT_MODE="${3:-staging}"
WEB_ROOT="/var/www/shopstream"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0 $*" >&2
  exit 1
fi

case "$CERT_MODE" in
  staging|production|none) ;;
  *) echo "CERT_MODE must be staging, production or none (got: $CERT_MODE)" >&2; exit 1 ;;
esac

echo "==> [1/5] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx

echo "==> [2/5] Deploying site to $WEB_ROOT"
mkdir -p "$WEB_ROOT"
cp -r "$REPO_DIR/site/." "$WEB_ROOT/"

if [[ "$CERT_MODE" == "none" && -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
  echo "Refusing: a certificate for $DOMAIN exists here. 'none' would remove HTTPS." >&2
  echo "Use 'production' (or 'staging') on servers that already have HTTPS." >&2
  exit 1
fi

echo "==> [3/5] Writing Nginx config for $DOMAIN"
cat > /etc/nginx/sites-available/shopstream <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
ln -sf /etc/nginx/sites-available/shopstream /etc/nginx/sites-enabled/shopstream
rm -f /etc/nginx/sites-enabled/default

echo "==> Configuring Nginx to restart on crash"
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf <<EOF
[Service]
Restart=on-failure
RestartSec=5s
EOF
systemctl daemon-reload

echo "==> [4/5] Testing config and starting Nginx"
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "==> [5/5] HTTPS certificate (mode: $CERT_MODE)"
if [[ "$CERT_MODE" == "none" ]]; then
  echo "Skipping HTTPS."
else
  CERTBOT_ARGS=(--nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect)
  if [[ "$CERT_MODE" == "staging" ]]; then
    CERTBOT_ARGS+=(--staging)
  fi
  certbot "${CERTBOT_ARGS[@]}"
  certbot renew --dry-run
fi

echo "==> Done. Check: curl -I http://$DOMAIN"
