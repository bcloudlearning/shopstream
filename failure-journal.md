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
