Lab step 1: Inventory Stage 1 (≈1.5 hrs)

Create a file docs/stage1-inventory.md in your ShopStream repo and record each resource below, mostly from the console. Keep it out of chat. And since your repo is on GitHub, leave out your account ID, full ARNs, and any passwords.

Network

VPC: name and CIDR.Shopstream-VPC, 10.30.0.0./16
Each subnet: name, AZ, CIDR, public or private. 
shopstream-public-a, ap-south-2a, 10.30.0.0/24, public
shopstream-public-b, ap-south-2b, 10.30.48.0/24, public
shopstream-app-a, ap-south-2a, 10.30.16.0/24, private
shopstream-app-b, ap-south-2b, 10.30.64.0/24, private
shopstream-db-a, ap-south-2a, 10.30.32.0/24, private
shopstream-db-b, ap-south-2b, 10.30.80.0/24, private


Internet Gateway, and whether you used a NAT Gateway or a NAT instance.
shopstream-igw, shopstream-nat  - EC2 instance

Each route table: its routes and which subnets it’s associated with.
shopstream-rt-public: 0.0.0.0/0 -> shopstream-igw
shopstream-rt-app: 0.0.0.0/0 -> shopstream-nat (NAT instance's endpoint)
shopstream-rt-db: there's no route except local



Security groups (the most important part)

For every SG: every inbound and outbound rule, with port, protocol and source. Note whether each source is a CIDR or another security group. Those SG-to-SG references are exactly what you’d forget.
shopstream-alb-sg, Traffic type: HTTP-80, HTTPS-443, Src: 0.0.0.0/0
shopstream-nat-sg, Traffic type: All, Ports: All, Src: shopstream-app-sg
shopstream-app-sg, Traffic type: Custom TCP, Ports: 8080, Src: shopstream-alb-sg
shopstream-db-sg, Traffic type: PostGRE SQL, Ports: 5432, Src:shopstream-app-sg

Compute

IAM role and instance profile for EC2, plus the policies attached.
shopstream-ec2-role - AmazonSSMManagedInstanceCore, shopstream-read-app-db-secret(secretsmanager:GetSecretValue)

Launch template: AMI, instance type, key pair, IAM profile, security group.
shopstream-api-lt: AMI: Amazon Linux 2023, arm64., instance type: t4g.micro, keypair: none, IAM Profile: shopstream-ec2-role, sg:shopstream-app-sg

Copy the full user data script into the repo as its own file. It’s the easiest thing to lose and the hardest to recreate.
#!/bin/bash
set -euxo pipefail
dnf install -y python3 python3-pip git
git clone https://github.com/bcloudlearning/shopstream.git /opt/shopstream
python3 -m venv /opt/shopstream/venv
/opt/shopstream/venv/bin/pip install -r /opt/shopstream/api/requirements.txt
id shopstream >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin shopstream
cp /opt/shopstream/deploy/shopstream-api.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now shopstream-api

ALB: listeners, target group port and protocol, health check path.
shopstream-alb: shopstream-api-tg, HTTPS-443, HTTP-80, https://api.shopstream/health

Auto Scaling group: min/max/desired, and which subnets.
shopstream-api-asg: 2/4/2, shopstream-app-a, shopstream-app-b

Database

RDS: engine and version, instance class, storage, DB subnet group, public access (should be “No”), backup retention, DB name and username (not the password).
shopstream-db: PostGRESQL 18.3, db.t4g.micro, 20GiB, shopstream-db-subnets, No, yes, Db name: shopstream, username: shopstream_admin

Frontend and DNS

S3 bucket: block public access settings, bucket policy, static hosting on or off.
shopstream-frontend-10312026: block public access -ON, CloudFront resource is allowed to getobject from this bucket, 

CloudFront: origin, origin access control, default root object, custom error pages, certificate.

shopstream-frontend (CloudFront): origin = shopstream-frontend-10312026 S3 bucket, OAC = oac-shopstream-frontend-10312026.s3.ap-south-2.amazo-mw0mhrilb5h, alternate domains = shopstream.in, www.shopstream.in, viewer protocol = redirect HTTP → HTTPS, default root object = index.html, error pages = 403/404 → /index.html (200), certificate = ACM in us-east-1 covering shopstream.in + www


Route 53: the records in your shopstream.in hosted zone.
shopstream.in
