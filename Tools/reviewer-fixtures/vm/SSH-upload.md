# Direct private SSH deployment — only after approval

This is an operator runbook, not a cloud launch script. The new AWS account is in Sydney (`ap-southeast-2`); the launch draft uses official Ubuntu 24.04 AMD64 AMI `ami-0c4c0d31978150116`, one `c7i-flex.large`, and 30 GB gp3. Confirm those values in the console; the AMI ID is regional and not a general installer dependency. The security group currently permits owner-IP SSH only; HTTP/HTTPS stay off until approved activation. No public bundle hosting is needed.

## Approval and prerequisites

The parent operator must have approval to generate/store a dedicated private SSH key, launch this credit-funded Free Plan VM, and later publish only the three original-sample review hosts. Store the private key under an owner-only directory outside the repository; mode0600. Never paste it into source, chat or review notes. Register only its public key with AWS. Keep Free account plan, credit balance and expiry visible; do not upgrade.

For public activation, permission must also cover DNS-only records for the three proposed hostnames, public80/443, and accepting Let's Encrypt subscriber terms using the owner's approved certificate-contact email. The installer itself does not perform those actions. The certificate subscriber prompt is intentional; the operator must supply the approved answer interactively. It is separate from App Store review submission approval.

## Upload and private install

Set operator-local variables to the approved VM IPv4 and key path. These example commands are for the operator's terminal. Quoted variable expansion preserves spaces; values must come from the actual approved VM, not copied placeholders.

```sh
task_vm_ip='ACTUAL_APPROVED_VM_IPV4'
task_ssh_key='/absolute/private/path/to/reviewer-key'
task_bundle='/Users/jun/Documents/Codex/Honbako/AppStore/review/build73/honbako-review-vm-bundle.tar.gz'
```

Verify the SSH host fingerprint against the instance's trusted console/system log, then make the initial SSH connection with its normal host-key prompt. Preserve that host binding; the remaining commands require it rather than silently replacing an existing key.

```sh
ssh -i "$task_ssh_key" -o IdentitiesOnly=yes "ubuntu@$task_vm_ip" 'true'
scp -i "$task_ssh_key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes "$task_bundle" "ubuntu@$task_vm_ip:honbako-review-vm-bundle.tar.gz"
scp -i "$task_ssh_key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes "$task_bundle.json" "ubuntu@$task_vm_ip:honbako-review-vm-bundle.tar.gz.json"
ssh -i "$task_ssh_key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes "ubuntu@$task_vm_ip"
```

Inside the VM, verify the actual archive hash against the trusted local manifest/hash before extraction. The copied JSON is a convenience, not an independent signature. The current hash is available in the local build73 manifest; do not hard-code it into this runbook, because including the runbook changes the bundle itself.

```sh
python3 - <<'CHECK'
import hashlib,json
from pathlib import Path
archive=Path('honbako-review-vm-bundle.tar.gz')
manifest=json.loads(Path('honbako-review-vm-bundle.tar.gz.json').read_text())
assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['sha256']
print('Archive matches copied manifest; compare this manifest hash with the trusted Mac value before extraction.')
CHECK
sudo mkdir -p /opt/honbako-review
sudo tar -xzf honbako-review-vm-bundle.tar.gz --strip-components=1 -C /opt/honbako-review
sudo bash /opt/honbako-review/Tools/reviewer-fixtures/vm/install.sh
sudo bash /opt/honbako-review/Tools/reviewer-fixtures/vm/verify-private.sh
```

Private credentials are generated on the VM at `/etc/honbako-review/private-accounts.json`, readable by root only. Do not print the whole file. Gateway service receives only its own Suwayomi account subset. The private verification report lives under `/var/lib/honbako-review-setup/provider-probes.json` and contains no credential values. Check memory peaks, OOM events, free disk and service stability; perform a clean reboot and repeat verification before enabling public access. If4 GiB is insufficient, stop and report instead of silently resizing or upgrading.

## Public activation after approval

Create the three DNS-only A records pointing at this VM, enable only approved80/443 ingress, and run the prepared activation helper interactively:

```sh
sudo bash /opt/honbako-review/Tools/reviewer-fixtures/vm/activate.sh --reviewed-public-activation ACTUAL_APPROVED_VM_IPV4 APPROVED_CERTIFICATE_EMAIL
```

Then run external strict TLS/wrong-password/authenticated cover/chapter/page/gateway-denial tests, and fresh iPhone-cellular checks. Service port39103 and administrative credentials must never be public. Retrieve only the dedicated reader credentials through the approved private route for private Apple review notes; never put passwords into a public URL or committed file. Authenticated MCP reviewer proof still needs a separate real Apple-verified reviewer workspace and OAuth consent.

For this specific approved deployment, the owner has accepted the exact Let’s Encrypt v1.8 agreement dated 6 July 2026 and contact `missingems@gmail.com`. The operator may append `--approved-lets-encrypt-v1.8` to activation. That flag checks the ACME-advertised agreement URL exactly before using noninteractive agreement acceptance; changed terms block activation. It does not enroll the contact in EFF marketing.
