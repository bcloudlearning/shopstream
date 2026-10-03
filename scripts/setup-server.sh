#!/usr/bin/env bash
# setup-server.sh: builds the ShopStream web server from scratch.
# Usage: sudo ./scripts/setup-server.sh <domain>
set -euo pipefail

DOMAIN="${1:?Usage: sudo $0 <domain>}"
WEB_ROOT="/var/www/shopstream"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0 $DOMAIN" >&2
  exit 1
fi

echo "==> [1/4] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx

echo "==> [2/4] Deploying site to $WEB_ROOT"
mkdir -p "$WEB_ROOT"
cp -r "$REPO_DIR/site/." "$WEB_ROOT/"

echo "==> [3/4] Writing Nginx config for $DOMAIN"
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

echo "==> [4/4] Testing config and starting Nginx"
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "==> Done. Check: curl -I http://localhost"
