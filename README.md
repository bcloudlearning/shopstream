# ShopStream — Stage 0: Foundations

## What this is
ShopStream's static landing page, served by Nginx on a single Ubuntu 24.04
EC2 instance in AWS `ap-south-2` (Hyderabad), at https://shopstream.in with
a trusted Let's Encrypt certificate. The server is rebuilt from scratch with
one script.

## Architecture
```
Browser → DNS (GoDaddy A record) → Elastic IP → EC2 (Ubuntu 24.04)
        → Nginx → /var/www/shopstream (site/index.html)
```

- **Elastic IP:** fixed public IP. DNS points to it once; on a rebuild the
  IP is moved to the new instance, so there's no DNS change or TTL wait.
- **Security group `shopstream-web-sg`:**
  | Port | Source | Why |
  |---|---|---|
  | 22 (SSH) | My IP only | Admin access; limits attack surface |
  | 80 (HTTP) | Anywhere | Let's Encrypt HTTP-01 challenge + redirect to HTTPS |
  | 443 (HTTPS) | Anywhere | Serves the site |
- **TLS:** Let's Encrypt via Certbot (Nginx plugin). 90-day certificates,
  renewed automatically by `certbot.timer`. HTTP redirects to HTTPS (301).

## Rebuild runbook
Measured rebuild time: **4:12** (target: under 15 minutes).

1. **Launch:** EC2 → select the current instance → Actions → Image and
   templates → *Launch more like this*. Rename (e.g. `shopstream-web-dev-N`),
   check tags (`owner`, `stage=0`), key pair `shopstream-key`, security group
   `shopstream-web-sg`, free-tier instance type.
2. **Move the Elastic IP:** EC2 → Elastic IPs → `shopstream-eip` → Associate
   → new instance → tick *Allow reassociation*.
3. **Clear the old host key and SSH in** (the new server has a new host key):
```bash
   ssh-keygen -R <ELASTIC-IP>
   ssh -i ~/.ssh/shopstream-key.pem ubuntu@<ELASTIC-IP>
```
4. **Clone and run the setup script:**
```bash
   git clone https://github.com/bcloudlearning/shopstream.git
   cd shopstream
   sudo ./scripts/setup-server.sh shopstream.in <email> <mode>
```
   | Mode | Use for | Notes |
   |---|---|---|
   | `staging` (default) | Practice rebuilds | Untrusted cert; no rate-limit risk |
   | `production` | Real rebuilds | Trusted cert; Let's Encrypt limits ~5/week per domain |
   | `none` | Local VM testing | Skips HTTPS |
5. **Verify:**
```bash
   sudo certbot certificates      # VALID (production) or TEST_CERT (staging)
   curl -I http://shopstream.in   # expect 301 → https://shopstream.in/
```
   Then open https://shopstream.in in a private window and check the padlock.
6. **Clean up:** terminate the old instance (terminate, not stop) and confirm
   EC2 → Volumes shows no leftover volumes.

## What the setup script does
`scripts/setup-server.sh` is idempotent (safe to re-run) and stops on the
first error (`set -euo pipefail`):
1. Installs `nginx`, `certbot`, `python3-certbot-nginx`
2. Copies `site/` to `/var/www/shopstream`
3. Writes the Nginx server block for the domain and removes the default site
4. Runs `nginx -t`, then enables and reloads Nginx
5. Gets the certificate (per mode), adds the HTTPS redirect, and runs
   `certbot renew --dry-run` to prove renewal works

## Repo layout
- `site/` — the static landing page
- `scripts/setup-server.sh` — builds the server from scratch
- `scripts/server-info.sh` — prints user, IP, disk, and memory
- `failure-journal.md` — every failure: symptom, diagnosis, root cause, fix, prevention

## Cost notes
- One free-tier instance and one Elastic IP while the site is live.
- An Elastic IP that isn't attached to a running instance is billed:
  release it when Stage 0 ends unless it's still in use.
- Budget alerts are set at US$10 and US$50.
