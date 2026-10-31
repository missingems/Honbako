#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Linux || "${EUID}" != 0 ]]; then
  printf '%s\n' 'Run only as root inside the dedicated review VM.' >&2
  exit 1
fi
task_repo_root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
export HONBAKO_REVIEW_RUNTIME=/var/lib/honbako-review-setup
export HONBAKO_REVIEW_CREDENTIALS_FILE=/etc/honbako-review/private-accounts.json
export HONBAKO_REVIEW_LIBRARY_ROOT=/srv/honbako-review
export HONBAKO_REVIEW_PROBE_OUTPUT=/var/lib/honbako-review-setup/provider-probes.json
for task_service in komga kavita suwayomi gateway; do
  systemctl is-active --quiet "honbako-$task_service"
done
# Fail closed if any provider or gateway listens outside localhost.
python3 - <<'CHECK'
import ipaddress,subprocess
for line in subprocess.check_output(['ss','-H','-lnt'],text=True).splitlines():
    fields=line.split();address=fields[3]
    if any(address.endswith(':'+str(port)) for port in range(39101,39105)):
        ip=ipaddress.ip_address(address.rsplit(':',1)[0].strip('[]'))
        assert ip.is_loopback or (getattr(ip,'ipv4_mapped',None) is not None and ip.ipv4_mapped.is_loopback), 'Fixture port must bind loopback only'
CHECK
# First boot includes scanning CBZs. Retry the full read-only probes, never
# replace fixture content/accounts or weaken a probe to hide a startup failure.
for task_attempt in $(seq 1 30); do
  if python3 "$task_repo_root/Tools/reviewer-fixtures/probe.py"; then
    python3 - <<'RESULT'
import json,os
from pathlib import Path
report=json.loads(Path(os.environ['HONBAKO_REVIEW_PROBE_OUTPUT']).read_text())
assert all(v['passed'] for v in report['providers'].values())
print(json.dumps({'private_provider_probes':'passed','providers':list(report['providers']),'public_activation':False,'credential_values_printed':False}))
RESULT
    systemctl show honbako-komga honbako-kavita honbako-suwayomi honbako-gateway --property=Id,ActiveState,MemoryCurrent,MemoryPeak
    exit 0
  fi
  printf '%s\n' "Original fixture scan not ready; private probe attempt $task_attempt/30."
  sleep 10
done
printf '%s\n' 'Private provider verification failed. Keep public activation disabled and inspect service logs privately.' >&2
exit 1
