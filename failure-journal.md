# ShopStream Failure Journal

## Template
- **Date:**
- **Stage / block:**
- **Symptom:** what I saw
- **Diagnosis:** commands I ran and what they showed
- **Root cause:** the actual reason
- **Fix:** what solved it
- **Prevention:** how to avoid or catch it next time

## 2026-10-02 — Script fails with "Permission denied"
- **Stage / block:** Stage 0, block 6 (Bash basics)
- **Symptom:** Running `./server-info.sh` returned
  `-bash: ./server-info.sh: Permission denied`.
- **Diagnosis:** Ran `ls -l server-info.sh` → permissions were
  `-rw-rw-r--`. No `x` (execute) bit for owner, group, or others.
- **Root cause:** New files are created without execute permission
  by default. Linux won't run a file as a program unless the
  execute bit is set.
- **Fix:** `chmod u+x server-info.sh` (execute for owner only;
  least privilege). Re-ran the script successfully.
- **Prevention:** After creating any script, run `chmod u+x` before
  executing it. In the rebuild script, set permissions explicitly
  instead of assuming them. Alternative: run as `bash server-info.sh`,
  which doesn't need the execute bit.


## 2026-10-03 - EC2 launched in wrong region
- **Date:**
- **Stage / block:** Stage 0, block 9 (EC2 launch)
- **Symptom:** EC2 spinned up in wrong region
- **Diagnosis:** noticed region selector on top right corner of AWS console
- **Root cause:** console launches to whichever region is currently selcted.
- **Fix:** deleted instance from North Virginia and spinned up another in Hyderabad
- **Prevention:** check region selector before creating any resource. Run EC2 Global view in the weekly cost check to catch resources in the other regions. Longterm: Terraform pins the region in code.
- **Cost Impact** None, terminated quickly; no leftover columes or IPs.

## 2026-10-05 - Host key verification failed after moving Elastic IP
- **Date:**
- **Stage / block:** Stage 0, block 11 (rebuild script)
- **Symptom:** Host key verification failed while SSHing to Elastic IP
- **Diagnosis:** Warning that the remote host identification had changed, pointing to a line in known_hosts.
- **Root cause:** a new instane generates a new host key at first boot. SSH saves one fingerprint per IP, so the same IP with different key looks like man-in-middle attack.
- **Fix:** ssh-keygen -R <Elastic IP>, which removes only that entry, not the whole file
- **Prevention:** include ssh-keygen -R in the runbook. verify the new fingerprint against the ec2 system log. Never bypass this warning for a server you didn't just rebuild.

## VM failed to start in Multipass
- **Date:** 2026-10-05
- **Stage / block:** stage 0, block 11
- **Symptom:** unable to start VM shopstream in Multipass due to insufficient memory
- **Diagnosis:** The error said "Not enough memory... ram size 1024 megabytes", and Task Manager showed browsers as the top memory users.
- **Root cause:** Hyper-V reserves the full 1 GB up front before booting.
- **Fix:** closing unused browser sessions and processes freedup memory
- **Prevention:** Check Available memory in Task Manager before starting the VM. Stop the VM when you're not using it. Stage 3 runs Kubernetes locally and needs more memory, so plan for it.

## Drill 1 - Ngninx down (stopped, crashed)
- **Date:** 2026-10-05
- **Stage / block:** stage 0, block 12
- **Symptom:** curl: (7) Failed to connect to shopstream.in:443 after 2231 ms: Could not connect to server
- **Diagnosis:** sudo ss -tlnp command showed nothing is listening on port 80,443,, nginx status check showed failed, Rsult showed after 29 secs it still is failed, and show nginx -P Restart shows restart=no
- **Root cause:** nginx stop is deliberate whereas next is a crash - but systemd coudn't restart nginx service beacuse nginx unit file restart was not on. even though ngninx service was enabled so that it gest started after boot.
- **Fix:** enabled restart on-failure, and not always because if we mention always then even whne we deliberately stop the service it would be started immediately.
- **Prevention:** This restart on failure fix has to go into server setup script

## Override seemed applied but it wasn't
- **Date:** 2026-10-05
- **Stage / block:** stage 0, block 12
- **Symptom:** after nginx crashed, it remained in failed state instaed of restarting, verified with nginx status check
- **Diagnosis:** verify the unit file of nginx to see whether changes had gone in
- **Root cause:** didnot type the chnages in the lines specified, therefore changes were ignored
- **Fix:** mentioned changes in designated space
- **Prevention:** always verify config before testing it. systemctl cat nginx, systemtctl show nginx -p Restart, status nginx

## none mode run on live EC2 removed HTTPS
- **Date:** 2026-10-05
- **Stage / block:** stage 0, block 12
- **Symptom:** Ngninx running, site not loading, curl error 7 to localjost:443
- **Diagnosis:** ss -tlnp showed only :80; nginx -T showed no listen 443 or ssl_certificate lines
- **Root cause:** ran setup-server.sh... none on EC2. Step3 cat > overwrote the config and none skipped certbot
- **Fix:** re-ran in production mode. certbot reused the certificate("not yet due for renewal") and reinstalled it. verified :443, the padlock and the http -> 301
- **Prevention:** the guard in the script refuses none when a certificate exists and the habit of never editing or testing on the server
"Underlying habit: edited and ran scripts on EC2 instead of the VM. This also caused a Git divergence."

## Drill 3: Port 443 blocked at security group
- **Date:** 2026-10-06
- **Stage / block:** stage 0, block 12 (break-it drills)
- **Symptom:** curl.exe -I https://shopstream.in > (28) failed to connect after 21103 ms. http://shopstream still returned 301 > https users get fast redirect, then browser hangs ~21secs and shows "site can't be reached"
- **Diagnosis:** ss -tlnp shows nginx listening on port 80 and 443. curl -I --resolve shopstream.in:443:127.0.0.1 https://shopstream.in returned 200 OK. server healthy from inside but unreachable from outside
- **Root cause:** HTTPS 443 inbound rule removed from security group. SG then drops the blcoked packets silently, so client gets no reply and times out (error 28), unlike drill 1's fast refusal (error 7).
- **Fix:** re-added inbound rule HTTPS.443.0.0.0.0/0, SG changes applied immediatelt and received 200 OK
- **Prevention:** monitor the path users actually take (HTTPS, oe curl -L to follow redirects). A check on http:// alone reports "up" during this outage. Long term: manaage SG rules in terraform stage 2. so manula console changes show up as drift
- **Key lesson:** Error 7 (fast) = reached the server, nothing listening.
  Error 28 (slow) = packet dropped on the way. Timing is evidence.

## Drill 4: DNS pointing to wrong IP
- **Date:** 2026-10-06
- **Stage / block:** stage 0, blcok 12 (drill 4)
- **Symptom:** curl command from server shows error 28, which means packets are dropping silently and connection timed out error occured after 20 secs, not a refusal. even server couldn't reach itself by name.
- **Diagnosis:** resolvectl query shopstream.in > 192.0.2.10 (wrong IP) and curl -I --resolve shopstream.in:443:127.0.0.1 https://shopstream.in > 200 OK. server healthy when DNs is bypassed. right server - wrong address - DNS layer
- **Root cause:** wrong ip given at DNS record
- **Fix:** set A record back to Elastic IP. Authoritative name server returned the correct IP immediately; cache resolvers updated on their won ttl schedule.
- **Prevention:** use elastic IP so rebuilds never require DNS changes, keep TTL low before planed DNS changes. when DNS looks wrong query authoritative servers first (nslookup -type=NS)
- **Key Lessons:** Outage length = time to notice+ time to fix + up to one TTL. A DNS timeout is not the same as wrong answer, retry before concluding anything. Timeout duration differs by OS.

## CLI on laptop pointed to other AWS account
- **Date:** 2026-10-12
- **Stage / block** Stage 1, block 1
- **Symptom:** CLI showed wrong accoutn while tried using AWS CLI 
- **RootCause:** the default profile held another AWS account's static keys
- **Fix:** backup, clear, add a named profile with no default
- **Prevention:** always use --profile.

## Drill 2A, ALB → API security group rule removed
- **Change** Removed shopstream-app-sg inbound rule Custom TCP port 8080 from shopstream-alb-sg
- **Date:** 2026-11-4
- **Stage / block:** stage 1, block 7
- **Symptom:** 504s for about 2–3 minutes; both targets unhealthy (“Request timed out”); the ASG replaced an instance.
- **Diagnosis:** The responses were HTTP codes, so the client reached the ALB. The internet, DNS, the ALB and its security group are all fine.
504 means the ALB couldn’t get an answer from a target, so the problem is between the ALB and the servers.
Both targets, in both AZs, failed at the same moment. A cause affecting one server wouldn’t do that, so it must be something they share: their security group, routing, or the app port.
No requests appeared in the app logs, so traffic never reached the servers. This is a network block, not an application failure.
The ASG’s replacement didn’t help, which confirms the problem isn’t in any particular server: new servers inherit the same configuration.
Therefore: check the shared network control in front of the servers, shopstream-app-sg’s inbound rules. The rule allowing 8080 from the ALB is missing.
- **Root cause:** the ALB couldn’t open connections to the targets. Because all targets were unhealthy, the ALB failed open and returned 504 instead of 503.
- **Fix:** restored the rule
- **Prevention:** 504 from an ALB with no app logs points to a network block between the ALB and the targets. And the ASG can’t fix configuration problems; it just recycles servers.


##Drill 2A: ALB → API security group rule removed

- **Date:** 4 Nov 2026
- **Change:** deleted the inbound rule TCP 8080 from shopstream-alb-sg on shopstream-app-sg.

- **Symptoms:**
Repeated 504 Gateway Timeout from https://api.shopstream.in/health, each taking about 10 seconds.
About 2–3 minutes of complete outage (14 consecutive errors).
Both targets Unhealthy.
ASG Activity: “an instance was taken out of service in response to an ELB system health check failure”. Server 16-159 was replaced by 16-164.

- **Diagnosis:**

HTTP codes came back, so the client reached the ALB. DNS and the ALB were fine.
A 504 means the ALB couldn’t get an answer from a target, so the problem was between the ALB and the servers.
Both targets, in both AZs, failed at the same moment, so the cause was something shared: security group, routing or port.
Nothing reached the app logs, so traffic never arrived: a network block, not an application failure.
The ASG’s replacement didn’t help, which confirmed the problem was configuration, not a particular server.
Checked shopstream-app-sg inbound: the 8080 rule from the ALB was missing.

- **Root cause:** the ALB’s connections to port 8080 were silently dropped. Health checks timed out, so every target went unhealthy. The ALB failed open and sent traffic to the unhealthy targets anyway, which also timed out, giving 504 rather than 503.

- **Fix:** restored TCP 8080 from shopstream-alb-sg. The targets became healthy, and the loop recovered.

- **Prevention:**
Record each security group rule before changing it; change one rule at a time.
Manage security groups in Terraform (Stage 2), so changes are reviewed and drift is detected.
Alarm on ALB 5xx and unhealthy host count (Stage 4).

- **Lessons:**
An ALB 504 with silent app logs points to a network block between the ALB and its targets.
When all targets are unhealthy, the ALB fails open, so expect 504, not 503.
Auto Scaling can’t fix configuration problems; it recycles servers that inherit the same fault.
Read the target health reason before fixing. I missed it this time.


##Drill 2B: API → database security group rule removed

- **Date:** 4 Nov 2026
- **Change:** deleted the inbound rule PostgreSQL 5432 from shopstream-app-sg on shopstream-db-sg.
- **Symptoms:**
/products returned HTTP 500 after about 5 seconds. The website showed “Could not load products: HTTP 500”.
/health returned OK at first.
Then the targets went Unhealthy (reason: timeout), and the ASG replaced servers (new host 64-191).
App logs: (add the exact database error line from journalctl -u shopstream-api)

- **Diagnosis:**
A 500 means the request reached the app and its code failed, so the problem was after the server, not in front of it.
The app logs showed the database connection failing, which pointed at the API → database path.
The targets going unhealthy contradicted the prediction, so I tested a hypothesis of worker exhaustion.
Test: fired 3 /products requests at once, then timed /health, which took 5.02 seconds (normally instant). It had waited in line behind the blocked requests.
The ALB’s health check timeout is 5 seconds, so the checks failed and healthy servers were marked dead.
Checked shopstream-db-sg inbound: the 5432 rule from shopstream-app-sg was missing.

- **Root cause:** the database was unreachable (missing rule), so each /products request held a Gunicorn worker for about 5 seconds (the connection timeout). With only 2 sync workers, /health couldn’t get a worker in time. The health checks timed out, and the ALB and ASG treated healthy servers as failed: a cascading failure.
- **Fix:** restored PostgreSQL 5432 from shopstream-app-sg. Products loaded, and the targets became healthy.

- **Prevention:**
Fail fast: a shorter database connection timeout (about 1 second).
More capacity: more workers, or a threaded worker type.
A circuit breaker: stop calling the database for a while after repeated failures.
Alarm on /products 5xx and database connection errors (Stage 4), not just target health.
Don’t just raise the health check timeout; that hides the symptom.

- **Lessons:**
A 500 means the code failed (look after the server); a 404 means the path doesn’t exist; a 504 means nothing answered in time (look in front of the server).
A shallow health check isn’t isolated if it shares workers with slow requests.
Slow dependencies cause cascading failures. Measure with a timed test, rather than assuming.

- **Symptoms -> App logs: **
ERROR in app: Exception on /products [GET]
app.py line 44: psycopg.connect(**DB_CONFIG)
psycopg.errors.ConnectionTimeout: connection timeout expired

##Drill 3 (full disk)
- **Date:** 11/5/2026
- **Stage/Drill:** Stage 1, Drill 3
- **Change:** filled the root volume to 100% with fallocate (8 GB volume, 164 KB free).
- **Symptoms:**
Customers unaffected (/health ok, /products 200)
Target healthy
Writes and dnf failed with “No space left on device” (ENOSPC, Errno 28)
No new log lines
No disk metric in default EC2 monitoring
A new SSM session failed to connect
- **Root cause:** disk space exhausted. Nothing in the default setup measures disk space, so nothing noticed.
Fix: deleted the fill file; disk back to 26%. (Alternative: terminate the instance and let the ASG replace it.)
- **Prevention:**
CloudWatch agent on every server for disk and memory metrics, with an alarm at about 80% disk usage (Stage 4)
Ship logs off the server to CloudWatch Logs
Limit log growth (log rotation, journald size limits)
Keep servers stateless, so replacing one is always safe
- **Lessons:**
Health checks and default metrics don’t cover everything; a “healthy” server can be broken.
Disk-full failures are silent until something writes, and can block your own access to fix them.


##Drill 4: Database outage (reboot, single-AZ)

- **Date:** 5 Nov 2026, 00:57 IST
- **Change:** rebooted shopstream-db (RDS → Actions → Reboot). A single-AZ database, so no standby to fail over to. Multi-AZ isn’t available on the current Free plan; the failover drill is planned for Stage 8.

- **Prediction**

First attempt: no errors seen, so I hypothesised that products were served from memory.
Missed: the first loop wasn’t running during that reboot (00:49 IST), so it never covered the outage window.

- **Symptoms:**

The timestamped loop (saved to db-reboot-drill.txt) showed 4 × HTTP 500 between 00:57:15 and 00:57:21, each taking only 14–16 ms.
Fully recovered at 00:57:23 (the first request took 97 ms, against a normal 30–40 ms), with no restart.
RDS events: DB instance shutdown at 00:57:08.9 IST; DB instance restarted at 00:57:28.2 IST.
- **App logs:**
  app.py line 44: psycopg.connect(**DB_CONFIG)
  psycopg.OperationalError: connection failed: connection to server at
  "10.30.32.103", port 5432 failed: server closed the connection unexpectedly

- **Diagnosis:**

A 500 means requests reached the app, and its code failed, so the problem was after the server.
The app logs show the database connection failing at 10.30.32.103:5432 (in shopstream-db-a), at the same time as RDS’s shutdown event.
“Server closed the connection unexpectedly” means the database’s address was reachable, but PostgreSQL was shutting down, so it actively closed the connection.
Each failure took about 15 ms, not 5 seconds like the ConnectionTimeout in Drill 2B. The workers weren’t blocked, so /health kept working.
The “served from memory” hypothesis was rejected: the code queries the database on every request, and the re-run, with saved evidence, showed the errors clearly.

- **Root cause:** a planned database reboot, with no standby instance. PostgreSQL was unavailable for a few seconds, and every /products request during that window failed.

- **Fix:** none needed. The database came back, and the API recovered by itself, because it opens a new connection on every request.

- **Customer impact:** about 8 seconds of failed product loads (4 requests). The website itself stayed up.

- **Prevention:**

Multi-AZ for production databases: a standby in another AZ for instance and AZ failures (Stage 8).
Retry once on database connection errors in the API, to smooth over short blips like this.
Schedule planned reboots and maintenance in the maintenance window, at a low-traffic time.
Alarm on API 5xx rates and database connection errors (Stage 4).

- **Lessons:**

Measure from the customer’s side, and save evidence to a file. Screen output gets lost, and RDS’s events don’t match exactly what customers experience.
Fast failures are far less harmful than slow ones. Compare the 15 ms failures here with the 5-second hangs and worker exhaustion in Drill 2B.
Connecting per request lets the app heal itself after the database returns.
Test hypotheses against the evidence. My first conclusion was wrong, and the timestamps proved it.
