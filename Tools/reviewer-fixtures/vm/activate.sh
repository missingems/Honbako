#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Linux || "${EUID}" != 0 || "${1:-}" != --reviewed-public-activation || ( "$#" != 3 && "$#" != 4 ) ]]; then
  printf '%s\n' 'Usage on the dedicated VM only: sudo bash activate.sh --reviewed-public-activation VM_PUBLIC_IPV4 CERTIFICATE_CONTACT_EMAIL [--approved-lets-encrypt-v1.8]' >&2
  exit 1
fi
task_public_ip="$2"
task_certificate_email="$3"
task_vm_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
task_certbot_flags=()
if [[ "$#" == 4 ]]; then
  if [[ "$4" != --approved-lets-encrypt-v1.8 ]]; then
    printf '%s\n' 'Unknown certificate approval; refusing activation.' >&2
    exit 1
  fi
  # Owner explicitly approved this exact subscriber agreement. Block if ACME
  # advertises changed terms rather than silently accepting a newer version.
  python3 - <<'TERMS'
import json,urllib.request
expected='https://letsencrypt.org/documents/LE-SA-v1.8-July-06-2026.pdf'
with urllib.request.urlopen('https://acme-v02.api.letsencrypt.org/directory',timeout=30) as response:
    directory=json.load(response)
assert directory.get('meta',{}).get('termsOfService')==expected, 'Certificate terms changed; explicit owner approval is required'
TERMS
  task_certbot_flags=(--non-interactive --agree-tos --no-eff-email)
fi

python3 - "$task_public_ip" <<'PY'
import ipaddress,socket,sys
address=ipaddress.ip_address(sys.argv[1])
assert address.version==4 and address.is_global,'Use the dedicated VM publicIPv4, never this Mac or a private address'
for host in ['komga-review.honbako.xyz','kavita-review.honbako.xyz','suwayomi-review.honbako.xyz']:
    resolved={row[4][0] for row in socket.getaddrinfo(host,80,family=socket.AF_INET)}
    assert str(address) in resolved,'Point the reviewed DNS-only A record at this VM first: '+host
PY
mkdir -p /var/lib/letsencrypt
install -m 0644 "$task_vm_dir/nginx-http.conf" /etc/nginx/sites-available/honbako-review
ln -sf /etc/nginx/sites-available/honbako-review /etc/nginx/sites-enabled/honbako-review
if [[ -L /etc/nginx/sites-enabled/default ]]; then rm /etc/nginx/sites-enabled/default; fi
nginx -t
systemctl enable --now nginx
# Default is interactive; noninteractive terms require the explicit approved-version flag.
certbot certonly "${task_certbot_flags[@]}" --webroot -w /var/lib/letsencrypt --cert-name honbako-review \
  --email "$task_certificate_email" \
  -d komga-review.honbako.xyz -d kavita-review.honbako.xyz -d suwayomi-review.honbako.xyz
install -m 0644 "$task_vm_dir/nginx-https.conf" /etc/nginx/sites-available/honbako-review
nginx -t
systemctl reload nginx
printf '%s\n' 'HTTPS reviewer routes activated. Perform external TLS/account/page/security smoke tests before App Review submission.'
