#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Linux || "${EUID}" != 0 ]]; then
  printf '%s\n' 'Run only as root inside the dedicated Ubuntu24.04 review VM.' >&2
  exit 1
fi
if ! /usr/bin/python3 -c 'import platform; assert platform.freedesktop_os_release().get("ID")=="ubuntu" and platform.freedesktop_os_release().get("VERSION_ID")=="24.04"'; then
  printf '%s\n' 'Only Ubuntu24.04 is validated by this preparation bundle.' >&2
  exit 1
fi
task_repo_root="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless python3 nginx certbot python3-certbot-nginx libicu74 libfontconfig1 libfreetype6 fonts-dejavu-core
systemctl disable --now nginx
python3 "$task_repo_root/Tools/reviewer-fixtures/vm/install.py" "$task_repo_root"
printf '%s\n' 'Private local services installed. Public proxy, DNS and TLS remain inactive.'
