ShopStream teardown and rebuild checklist (Stage 1)

Stage 2 deletes the console-built environment and rebuilds it with Terraform. This checklist records the exact order, the settings that matter, and the traps. Each section maps to a Terraform module.

Estimated time by hand: about 5–7 hours of hands-on work, realistically 8–10 with mistakes. With Terraform: about 15–20 minutes, mostly waiting for RDS and CloudFront.

What to keep (foundations)

These survive a teardown and are reused by the rebuild:

 Root user (MFA, no keys) and bharath-admin with MFA
 CLI profile shopstream (no default profile)
 Domain shopstream.in at GoDaddy, with nameservers pointing to Route 53
 Route 53 hosted zone shopstream.in (deleting it would change the nameservers and need a GoDaddy update)
 ACM certificates: api.shopstream.in (ap-south-2) and shopstream.in + www (us-east-1), plus their validation CNAMEs in Route 53
 GitHub repository
Rebuild order

Dependencies run top to bottom: each step needs the ones above it.

1. Network (Terraform module: network)
 VPC shopstream-vpc, 10.30.0.0/16, DNS hostnames on
 Six subnets: public, app, db × ap-south-2a / 2b (CIDRs in architecture.md)
 Internet gateway shopstream-igw, attached
 Route tables rt-public (0.0.0.0/0 → IGW), rt-app (route added after the NAT exists), rt-db (local only), each associated with its two subnets
 Security groups, in reference order: alb-sg → app-sg (8080 from alb-sg) → db-sg (5432 from app-sg) → nat-sg (all from app-sg)
 NAT instance in public-a: t4g.micro, public IP, shopstream-nat-sg, role shopstream-ec2-role, source/destination check off, IP forwarding plus a persistent MASQUERADE rule
 Add 0.0.0.0/0 → NAT instance to rt-app

Traps: Use "VPC only", not the "VPC and more" wizard, which can create hourly-billed NAT gateways. Check the instance type is Free tier eligible.

2. Identity (Terraform module: iam)
 Role shopstream-ec2-role trusting ec2.amazonaws.com, with its instance profile
 AmazonSSMManagedInstanceCore attached
 Inline policy shopstream-read-app-db-secret (needs the secret ARN from step 3, so attach it after the secret exists)
3. Database (Terraform module: database)
 DB subnet group shopstream-db-subnets (db-a, db-b only)
 RDS shopstream-db: PostgreSQL, db.t4g.micro, single-AZ in 2a, gp3 20 GB, autoscaling off, public access no, db-sg only, encrypted, backups 1 day, tags copied to snapshots, initial database shopstream, master shopstream_admin managed in Secrets Manager
 App user and schema: create products, create shopstream_app with \password, grant CONNECT, schema USAGE, table DML, sequence USAGE/SELECT
 Secret shopstream/db/app (shopstream_app credentials, host, port), rotation off
 Attach the inline secret-read policy to the role (step 2)

Traps: "Don't connect to an EC2 compute resource" (that option creates extra security groups). Remove the default security group.

4. Compute (Terraform module: compute)
 Launch template shopstream-api-lt: AL2023 Arm, t4g.micro, app-sg, role, no public IP, IMDSv2 required, user data deploy/userdata-api.sh, no subnet
 Target group shopstream-api-tg: HTTP 8080, /health, interval 10, timeout 5, thresholds 2 / 2, code 200, deregistration delay 30
 ALB shopstream-alb: internet-facing, public subnets in both AZs, alb-sg; listener 443 → target group with the api.shopstream.in certificate; listener 80 → 301 redirect to 443
 ASG shopstream-api-asg: app subnets in both AZs, target group attached, ELB health checks on, grace period 120, desired 2 / min 2 / max 4

Traps: Pick subnets by CIDR, not by name in a hurry (launching into a public subnet without a public IP was a real incident). Start the NAT and database before the ASG.

5. Frontend (Terraform module: frontend)
 S3 bucket shopstream-frontend-<suffix>: Block Public Access on, SSE-S3
 Upload the build with aws s3 sync --delete
 CloudFront shopstream-frontend: OAC to the bucket, HTTPS redirect, CachingOptimized, alternate names shopstream.in and www.shopstream.in, us-east-1 certificate, default root object index.html
 Bucket policy: s3:GetObject only from the distribution's ARN

Traps: The default root object is easy to miss (/ returns AccessDenied). The alternate domain names must be set, or Route 53 won't offer the distribution as an alias target.

6. DNS (Terraform module: dns)
 api.shopstream.in → A Alias to the ALB
 shopstream.in and www.shopstream.in → A + AAAA Alias to CloudFront
 Keep the ACM validation CNAMEs and _dmarc TXT
7. Verify
 Two healthy targets, one per AZ
 https://api.shopstream.in/health alternates between two hostnames
 https://shopstream.in lists products, with no CORS errors in the browser console
 http:// redirects to https:// for both names
 From an app server: reading shopstream/db/app works; reading the admin secret returns AccessDenied
Teardown order

Reverse of the rebuild. Each step removes something the next one depends on.

 DNS records: delete the Alias records for api, the apex and www (keep validation CNAMEs and _dmarc if keeping the hosted zone)
 CloudFront: disable, wait for deployment, then delete
 S3 bucket: empty it, then delete it
 ASG: delete (it terminates its own instances), then the launch template
 ALB, then the target group
 shopstream-api-1: terminate
 RDS: delete. Choose whether to keep a final snapshot. Manual and final snapshots keep billing until deleted.
 Secrets: delete shopstream/db/app (deletion is scheduled after a 7–30 day recovery window). The RDS-managed admin secret is removed with the database.
 DB subnet group
 NAT instance: terminate
 Security groups: delete in reverse reference order (nat-sg, db-sg, app-sg, alb-sg). A group can't be deleted while another group's rule references it.
 Route tables: remove associations and delete the three custom tables
 Internet gateway: detach, then delete
 Subnets, then the VPC
 IAM: remove the inline policy, then the role and instance profile (only if not rebuilding straight away)
Leftover-cost check
 EC2 → Volumes: none in the "available" state
 EC2 → Elastic IPs: none unattached
 RDS → Snapshots: only the ones you mean to keep
 EC2 → Load balancers and Target groups: none left
 Billing → Bills: daily spend drops back to the Route 53 hosted zone and certificates
