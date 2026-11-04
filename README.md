ShopStream

ShopStream is a small e-commerce app built to learn cloud engineering on AWS, one stage at a time. This repository holds the application code, the server setup scripts and the operational docs.

Live site: https://shopstream.in
API: https://api.shopstream.in
Region: ap-south-2 (Hyderabad)
Current stage: Stage 1 — core cloud, 3-tier app built through the AWS console

Architecture at a glance
Browser
  ├── https://shopstream.in ──► Route 53 ──► CloudFront ──► S3 bucket (private)   website files
  └── https://api.shopstream.in ──► Route 53 ──► ALB ──► API servers (ASG) ──► RDS PostgreSQL
Frontend: a React app built with Vite. The built files live in a private S3 bucket and are served worldwide by CloudFront over HTTPS.
API: a Python Flask app run by Gunicorn on EC2. Two servers in an Auto Scaling group, one per Availability Zone, behind an Application Load Balancer.
Database: PostgreSQL on RDS in private subnets. The API's password lives in Secrets Manager.
Network: a custom VPC across two AZs with public, app and database subnets. App servers reach the internet only through a NAT instance.

Full details, with the reasoning behind each subnet and security group: docs/architecture.md.

How a page load works
The browser downloads the website files (index.html plus the built JavaScript) from CloudFront. These contain no products.
The JavaScript calls https://api.shopstream.in/products.
The ALB forwards the request to a healthy API server, which reads the products from RDS and returns JSON.
The browser checks the API's CORS header and shows the products.

The website and the API are deployed separately. Changing one does not update the other.

Repository layout
Path	What it is
api/app.py	The Flask API: /health and /products
api/requirements.txt	Every Python dependency, pinned (lock file from pip freeze)
deploy/userdata-api.sh	EC2 user data: builds an API server from scratch at first boot
deploy/shopstream-api.service	systemd unit that runs and supervises the API
frontend/	The React app (Vite). src/App.jsx holds the page and the API address
docs/	Architecture, runbook, teardown and rebuild checklist
The API
Endpoint	Returns	Notes
GET /health	{"status": "ok", "host": "<hostname>"}	Used by the ALB health check. Deliberately does not touch the database (shallow check).
GET /products	JSON list of products	Opens a new database connection per request, so it recovers on its own after a database blip.

Configuration comes from environment variables, with defaults in the code:

Variable	Default	Purpose
AWS_REGION	ap-south-2	Region for Secrets Manager
DB_SECRET_ID	shopstream/db/app	Secret holding the database credentials
DB_NAME	shopstream	Database name
ALLOWED_ORIGINS	https://shopstream.in,https://www.shopstream.in	CORS allow-list

At startup the API fetches its database credentials from Secrets Manager using the server's IAM role. No password is stored on the server or in this repository.

Deploying

API change: commit and push, check the commit is on GitHub, then run an Auto Scaling instance refresh with Skip matching off. New servers clone the latest main at boot. Step by step: docs/runbook.md.

Frontend change: npm run build, copy dist/ out of the VM, aws s3 sync --delete, then invalidate /index.html in CloudFront. Step by step: docs/runbook.md.

Running and costs

The API servers, NAT instance and database bill by the hour, so they are shut down between work sessions. Start and stop order, and what each resource costs: docs/runbook.md.

Security notes
No long-lived credentials on any server: servers use an IAM role with temporary credentials, and IMDSv2 is required.
App servers and the database have no public IPs. Admin access is through SSM Session Manager; no SSH.
Security groups chain ALB → API (8080) → database (5432).
The database has no route to the internet.
The website bucket is private; only the CloudFront distribution can read it.
The API runs as a dedicated shopstream user with no login shell, and cannot modify its own code.

Known gaps, planned for later stages: the CLI uses an IAM user access key (Stage 6), one NAT instance in AZ a is a single point of failure for outbound traffic (accepted for cost), the database is single-AZ (Multi-AZ drill in Stage 8), and there is no disk or memory monitoring yet (Stage 4).
