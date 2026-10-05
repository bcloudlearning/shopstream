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
