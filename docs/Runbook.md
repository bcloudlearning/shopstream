ShopStream runbook (Stage 1)

How to start, stop, deploy and troubleshoot ShopStream. All CLI commands run from the laptop in PowerShell with --profile shopstream, unless they say "on a server" (run those in an SSM Session Manager session).

Start and stop

Hourly-billed resources are shut down between work sessions.

Start (in this order)
CloudFront shopstream-frontend: make sure it is Enabled (it should normally stay enabled; it costs nothing when idle).
Start shopstream-nat and wait for Running. The API servers need it to fetch their secret at boot.
Start shopstream-db and wait for Available (about 5 minutes).
ASG shopstream-api-asg → desired 2 / min 2 / max 4. Only after the database is Available.
Start shopstream-api-1 only if you need psql.

Verify: target group shopstream-api-tg shows 2 healthy targets (one per AZ), and https://shopstream.in lists products.

Stop (in this order)
ASG → 0 / 0 / 0. Never stop ASG instances by hand: the ASG treats them as unhealthy and launches replacements.
Stop shopstream-api-1 if running.
Stop shopstream-db (Actions → Stop temporarily). It restarts by itself after 7 days, so stop it again or plan around it.
Stop shopstream-nat.

Verify: EC2 → Instances shows nothing from ShopStream running; RDS shows Stopped.

What keeps costing money
Resource	Cost while idle	Note
ALB	About US$0.75/day	Kept running: deleting it changes its DNS name
RDS storage (stopped)	A few dollars a month	Plus automatic restart after 7 days
Route 53 hosted zone	US$0.50/month	
Secrets Manager	US$0.40 per secret per month	Two secrets
CloudFront, S3	Cents	No hourly charge

Check Billing → Bills at the start of every session.

Deploy an API change
Commit and push to main.
Check the commit is on GitHub before going further. Servers clone whatever is on main when they boot.
Start a health loop (see Tools) to watch the rollout.
EC2 → Auto Scaling groups → shopstream-api-asg → Instance refresh → Start:
Skip matching: off. The launch template hasn't changed, so with skip matching on, the ASG replaces nothing and still reports success.
Minimum healthy percentage: 50
Instance warmup: 120 seconds
Wait for the refresh to show Successful. The loop should show no errors: the ASG deregisters each old server, drains it for 30 seconds, then terminates it.
Verify on a new server:
bash
   sudo git -C /opt/shopstream log --oneline -1

If you change requirements.txt, refresh the lock file first: install on a test server, run /opt/shopstream/venv/bin/pip freeze, and commit the output.

Deploy a frontend change
In the VM, in frontend/:
bash
   npm run build
On Windows (PowerShell), copy the build out and upload it:
   multipass transfer --recursive shopstream:/home/ubuntu/shopstream/frontend/dist $HOME\shopstream-dist
   aws s3 sync $HOME\shopstream-dist s3://<bucket-name> --delete --profile shopstream
Clear the cached page so visitors get the new version:
   aws cloudfront create-invalidation --distribution-id <distribution-id> --paths "/index.html" --profile shopstream

JavaScript and CSS files have hashed names, so new builds get new URLs and don't need invalidating. 4. Hard-refresh https://shopstream.in (Ctrl+Shift+R) and check it.

The API address is baked into the JavaScript at build time (const API in src/App.jsx). Changing it means rebuilding and re-uploading.

For local development: npm run dev -- --host in the VM (note the -- before --host), then open http://<vm-ip>:5173. The production API's CORS list does not include the VM address; add it temporarily with the ALLOWED_ORIGINS environment variable if needed.

Database admin

From shopstream-api-1 (start the NAT, the database, then the instance):

Get the admin password: RDS → shopstream-db → Configuration → Master credentials ARN → Retrieve secret value.
Connect:
bash
   psql "host=<rds-endpoint> port=5432 dbname=shopstream user=shopstream_admin sslmode=require"
Run backslash commands (\dt, \du, \q) on a line of their own. To set a password, use \password <user> so it never lands in ~/.psql_history.
Troubleshooting

Start with the object the error names, and capture evidence before changing anything.

Is it the network or the app?
You got an HTTP status code: the network up to that point worked. Look at the application or its configuration.
You got a timeout or no response: look at the network: routes, security groups, NAT.
ALB status codes
Code	Meaning	First check
503	No targets registered	Target group → Targets; is the ASG at 0?
502	A target closed or refused the connection (app stopped, server still up)	App logs; is Gunicorn listening on 8080?
504	A target didn't answer in time. Also what you get when all targets are unhealthy: the ALB fails open and sends traffic to them anyway	shopstream-app-sg rule from the ALB; target health reason
500	The app ran and its code failed	App logs (journalctl)
404	The app answered but has no such path	Health check path vs routes in app.py
Target health reasons
Reason	Meaning
Request timed out	Health check packets dropped (security group) or the app is too slow (blocked workers)
Health checks failed with these codes: [404]	Reached the app; wrong health check path
Connection refused	Server up, nothing listening on 8080
Database errors in the app logs
Error	Meaning	First check
ConnectionTimeout: connection timeout expired	No answer: packets dropped	shopstream-db-sg rule from shopstream-app-sg
server closed the connection unexpectedly	Database reachable but shutting down or restarting	RDS status and events
Connection refused	Address reachable, nothing listening	Database stopped?
password authentication failed	Login rejected	Secret value vs database user
permission denied for table	Logged in, not allowed	Database grants
Other common problems
Symptom	Likely cause	Fix
Browser console: blocked by CORS policy, no Access-Control-Allow-Origin	Page origin not in the API's allow-list, or servers running old code	Check the origin; check the server's commit
New server missing from Session Manager	No path out (NAT stopped, or launched in a public subnet without a public IP) or no role	Instance subnet and route table; EC2 → Actions → Monitor and troubleshoot → Get system log
Instance refresh replaced 0 instances	Skip matching on, launch template unchanged	Restart the refresh with skip matching off
CloudFront / gives AccessDenied but /index.html works	No default root object	Set it to index.html
CloudFront not offered as a Route 53 alias target	Distribution lacks the alternate domain name	Add shopstream.in / www.shopstream.in with the us-east-1 certificate
S3 AccessDenied for a file	Private bucket reports missing files as AccessDenied	Check the object key exists
"No space left on device" (Errno 28)	Disk full. Invisible to health checks and default metrics; may block SSM	Delete the file, or terminate the instance and let the ASG replace it
Git: "detected dubious ownership" on a server	Repo owned by root, you are ssm-user	sudo git -C /opt/shopstream …
Node: libatomic.so.1: cannot open shared object file	Minimal Ubuntu image missing an OS library	sudo apt install libatomic1
Tools

Health loop with timing, saved to a file (laptop):

$log = "$HOME\shopstream-loop.txt"
1..300 | ForEach-Object {
  $t = Get-Date
  try {
    $r = Invoke-RestMethod https://api.shopstream.in/products -TimeoutSec 30
    $ms = [int]((Get-Date) - $t).TotalMilliseconds
    "$($t.ToString('HH:mm:ss')) OK $($r.Count) products ${ms}ms"
  } catch {
    $ms = [int]((Get-Date) - $t).TotalMilliseconds
    "$($t.ToString('HH:mm:ss')) ERROR ${ms}ms $($_.Exception.Message)"
  }
  Start-Sleep 2
} | Tee-Object -FilePath $log

On a server:

bash
systemctl status shopstream-api --no-pager
sudo journalctl -u shopstream-api -n 50 --no-pager
sudo journalctl -u shopstream-api -b --no-pager          # since this boot
systemctl show shopstream-api -p NRestarts
sudo tail -n 30 /var/log/cloud-init-output.log            # first-boot build log
curl -s localhost:8080/health
sudo ss -tlnp | grep 8080
df -h /
getent hosts <rds-endpoint>
timeout 3 bash -c '</dev/tcp/<rds-endpoint>/5432' && echo open || echo blocked

From the laptop:

aws sts get-caller-identity --profile shopstream
aws elbv2 describe-target-health --target-group-arn <arn> --profile shopstream
aws autoscaling describe-scaling-activities --auto-scaling-group-name shopstream-api-asg --profile shopstream
aws rds describe-events --source-type db-instance --source-identifier shopstream-db --duration 60 --profile shopstream --query "Events[].[Date,Message]" --output table
Resolve-DnsName api.shopstream.in

RDS events are in UTC; India is UTC + 5:30.

Drill results (Block 7)
Drill	Result
Terminate a server under load	3 failed requests (502, then 504) over about 25 s; ASG replaced the server
Planned rolling refresh	0 errors
Remove ALB → API rule	504s for 2–3 minutes (ALB failed open); ASG replaced a healthy server; app logs silent
Remove API → DB rule	/products 500 after 5 s; workers blocked, so /health took 5.02 s and targets went unhealthy (cascading failure)
Fill a server's disk	Customers and target health unaffected; writes, dnf and new SSM sessions failed; no default metric showed it
Reboot the database	About 8 s of 500s at about 15 ms each; recovered with no restart

Full write-ups are in the failure journal.
