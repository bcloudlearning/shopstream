ShopStream architecture (Stage 1)

Everything runs in ap-south-2 (Hyderabad), except the CloudFront certificate, which must live in us-east-1.

Diagram
VPC shopstream-vpc 10.30.0.0/16
Global
DB subnets: 10.30.32.0/24 AZ a, 10.30.80.0/24 AZ b
App subnets: 10.30.16.0/24 AZ a, 10.30.64.0/24 AZ b
Public subnets: 10.30.0.0/24 AZ a, 10.30.48.0/24 AZ b
shopstream.in, www
api.shopstream.in
8080
5432 TLS
outbound only
via NAT, at startup
Visitor's browser
Route 53hosted zone shopstream.in
CloudFrontshopstream-frontend
S3 bucketprivate, OAC
Internet gateway
ALB shopstream-alb
NAT instanceshopstream-natAZ a only
API serversASG shopstream-api-asg, 2servers
RDS PostgreSQLshopstream-db, single-AZin a
Secrets Managershopstream/db/app

Solid arrows are customer traffic. Dotted arrows are traffic the servers start themselves (package installs, SSM, Secrets Manager), which always goes through the NAT.

Network
Subnets
Subnet	AZ	CIDR	Route table	What lives here	Why
shopstream-public-a	ap-south-2a	10.30.0.0/24	shopstream-rt-public	ALB node, NAT instance	Must be reachable from, or reach, the internet directly
shopstream-public-b	ap-south-2b	10.30.48.0/24	shopstream-rt-public	ALB node	The ALB needs a subnet in each AZ
shopstream-app-a	ap-south-2a	10.30.16.0/24	shopstream-rt-app	API server	Only the ALB should reach the API; outbound only via NAT
shopstream-app-b	ap-south-2b	10.30.64.0/24	shopstream-rt-app	API server	Second AZ, so the app survives losing one AZ
shopstream-db-a	ap-south-2a	10.30.32.0/24	shopstream-rt-db	RDS primary	No internet path at all
shopstream-db-b	ap-south-2b	10.30.80.0/24	shopstream-rt-db	Reserved for a Multi-AZ standby	RDS requires subnets in two AZs

The VPC range 10.30.0.0/16 avoids 172.31.0.0/16 (default VPCs) and 192.168.x.x (home and office networks), so it can be connected to other networks later. Each AZ's subnets are grouped together (AZ a: .0, .16, .32; AZ b: .48, .64, .80).

Route tables
Route table	Routes	Used by
shopstream-rt-public	10.30.0.0/16 → local, 0.0.0.0/0 → shopstream-igw	Public subnets
shopstream-rt-app	10.30.0.0/16 → local, 0.0.0.0/0 → shopstream-nat	App subnets
shopstream-rt-db	10.30.0.0/16 → local only	DB subnets
Main (unnamed)	10.30.0.0/16 → local only	Nothing explicitly. A forgotten new subnet falls back here and stays private (fails closed).

Route tables decide which path traffic takes. Who is allowed to talk to whom is decided by security groups.

Security groups
Security group	Attached to	Inbound	Why
shopstream-alb-sg	ALB	HTTP 80 and HTTPS 443 from 0.0.0.0/0	The public front door. Port 80 only redirects to HTTPS.
shopstream-app-sg	API servers	TCP 8080 from shopstream-alb-sg	Only the load balancer can reach the API
shopstream-db-sg	RDS	PostgreSQL 5432 from shopstream-app-sg	Only API servers can reach the database
shopstream-nat-sg	NAT instance	All traffic from shopstream-app-sg	Only API servers can use the NAT

Rules reference other security groups instead of IP ranges, so new Auto Scaling servers get access automatically. Security groups are stateful: replies are allowed without extra rules. There is no SSH rule anywhere; admin access uses SSM Session Manager.

NAT instance

shopstream-nat is a t4g.micro (Amazon Linux 2023, Arm) in shopstream-public-a, chosen over a managed NAT gateway to save cost. What makes it a NAT:

Layer	Setting	Purpose
AWS	Source/destination check off	Lets the instance forward traffic not addressed to itself
AWS	Public subnet + auto-assigned public IP	Its own path to the internet gateway
Linux	net.ipv4.ip_forward = 1 in /etc/sysctl.d/90-nat.conf	Kernel forwards packets between machines
Linux	iptables -t nat -A POSTROUTING -o ens5 -s 10.30.0.0/16 -j MASQUERADE	Rewrites the sender address to the NAT's own
Linux	iptables-services, rules saved to /etc/sysconfig/iptables	Rule survives a reboot

Accepted trade-off: one NAT in AZ a. If AZ a fails, servers in AZ b keep serving customers through the ALB but lose outbound access (SSM, package installs, Secrets Manager at startup). Production would use one NAT gateway per AZ, at higher cost.

Compute: API tier
Component	Name	Key settings
Launch template	shopstream-api-lt	Amazon Linux 2023 Arm, t4g.micro, shopstream-app-sg, shopstream-ec2-role, no public IP, IMDSv2 required, user data deploy/userdata-api.sh, no subnet (the ASG chooses)
Target group	shopstream-api-tg	HTTP 8080, health check /health, interval 10 s, timeout 5 s, healthy 2, unhealthy 2, success code 200, deregistration delay 30 s
Load balancer	shopstream-alb	Internet-facing, public subnets in both AZs. Listener 80 → 301 redirect to 443. Listener 443 → target group, ACM certificate api.shopstream.in (ap-south-2).
Auto Scaling group	shopstream-api-asg	App subnets in both AZs, desired 2 / min 2 / max 4, ELB health checks on, grace period 120 s
Admin box	shopstream-api-1	Standalone server in shopstream-app-a with the psql client. Not in the ASG; kept stopped.

Each server builds itself in about 54 seconds at first boot, well inside the 120-second grace period.

Data tier
Item	Setting
Instance	shopstream-db, PostgreSQL, db.t4g.micro, single-AZ in ap-south-2a
Subnet group	shopstream-db-subnets (db-a, db-b only)
Storage	gp3, 20 GB, storage autoscaling off, encrypted (AWS managed key)
Access	Public access no, security group shopstream-db-sg only
Backups	Automated, 1-day retention, tags copied to snapshots
Deletion protection	Off (lab). Would be on in production.
Database users	shopstream_admin (master, password managed by RDS in Secrets Manager, humans only); shopstream_app (CONNECT, schema USAGE, SELECT/INSERT/UPDATE/DELETE on tables, sequence USAGE/SELECT; cannot create or drop tables or users)
Schema	products (id SERIAL PRIMARY KEY, name TEXT NOT NULL, price INTEGER NOT NULL)
Identity and secrets
Item	Purpose
Root user	MFA on, no access keys, locked away
bharath-admin (in group Admins, AdministratorAccess)	Daily console and CLI work, MFA on
CLI profile shopstream	Region ap-south-2. There is no default profile, so a command without --profile fails instead of hitting the wrong account.
shopstream-ec2-role	Trusts ec2.amazonaws.com. Policies: AmazonSSMManagedInstanceCore, plus inline shopstream-read-app-db-secret (secretsmanager:GetSecretValue on the shopstream/db/app ARN only). Proven: reading the admin secret returns AccessDenied.
Secret shopstream/db/app	shopstream_app credentials plus host and port. Rotation off for now (Stage 6).
Frontend and DNS
Component	Settings
S3 bucket shopstream-frontend-<suffix>	ap-south-2, Block Public Access on, SSE-S3. Bucket policy allows s3:GetObject only from the CloudFront distribution's ARN.
CloudFront shopstream-frontend	Origin Access Control to the bucket, HTTP → HTTPS redirect, GET/HEAD, CachingOptimized, price class excluding the most expensive regions, alternate names shopstream.in and www.shopstream.in, ACM certificate in us-east-1, default root object index.html, no WAF yet
Route 53 hosted zone shopstream.in	Domain registered at GoDaddy; GoDaddy's nameservers point to Route 53

Route 53 records:

Name	Type	Target
shopstream.in	A + AAAA (Alias)	CloudFront distribution
www.shopstream.in	A + AAAA (Alias)	CloudFront distribution
api.shopstream.in	A (Alias)	shopstream-alb
Three _… CNAMEs	CNAME	ACM validation (needed for automatic certificate renewal)
_dmarc	TXT	Email anti-spoofing policy (domain sends no email)

The bare domain needs an Alias record: DNS does not allow a CNAME at the zone apex, and CloudFront has no fixed IPs.

Request path, end to end
Route 53 resolves api.shopstream.in to the ALB's current IPs (one per AZ).
The browser opens a TLS connection to the ALB on 443; the ALB presents the ACM certificate. TLS ends at the ALB.
The ALB picks a healthy target and opens a separate connection to its private IP on 8080 (local route; shopstream-app-sg allows it).
Gunicorn passes the request to a worker; Flask runs products().
The app connects to RDS on 5432 over TLS (local route; shopstream-db-sg allows it) and queries the products table.
The JSON response returns the same way; Flask adds the CORS header; the ALB re-encrypts to the browser.
Known limits (accepted in Stage 1)
Limit	Impact	Planned fix
Single NAT instance	AZ b loses outbound access if AZ a fails	NAT per AZ or VPC endpoints
Single-AZ database	An instance or AZ failure takes products offline	Multi-AZ (Stage 8)
Servers clone the latest main at boot	Servers launched at different times can run different code	Versioned releases via AMIs or launch template versions (Stage 3)
2 sync Gunicorn workers, 5 s DB connect timeout	A slow database can block health checks (cascading failure, Drill 2B)	Shorter timeout, more or threaded workers, circuit breaker
No disk or memory metrics	A full disk is invisible (Drill 3)	CloudWatch agent and alarms (Stage 4)
IAM user access key for the CLI	Long-lived credential on the laptop	Temporary credentials (Stage 6)
TLS ends at the ALB	ALB-to-server traffic is plain HTTP inside the VPC	End-to-end TLS if a client requires it (Stage 6)
