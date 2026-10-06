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
