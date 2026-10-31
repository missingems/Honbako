# AWS Free Plan reviewer host — prepared, not provisioned

## Confirm before launch

- Verify the account is newly eligible and explicitly says **Free account plan**. Do not choose or upgrade to Paid. Record the actual remaining credits and account end date; $200 is not guaranteed upfront.
- Select a region where the console confirms the instance is Free Plan eligible. The prepared minimum candidate is **c7i-flex.large, 2 vCPU, 4 GiB, x86_64**. Choose official Canonical **Ubuntu Server 24.04 LTS AMD64**, not a paid Marketplace image.
- Use one **30 GB gp3** root volume, baseline IOPS/throughput, and one public IPv4 only if needed for the approved public HTTPS route. Check the console's complete estimate; storage, public IPv4, transfer and other services can consume credits in addition to compute.
- Do not add NAT Gateway, load balancer, RDS, paid monitoring, extra disks, snapshots or additional addresses by default. Do not activate paid support or an automatic plan upgrade.
- Use an owner-approved SSH key and restrict port22 to the operator's IP. Require IMDSv2. No instance IAM role is needed by this fixture installer. Do not put private keys or personal manga/source data in the bundle or cloud-init.
- Keep provider ports39101–39104 private. Open80/443 only for the separately approved activation step. The prepared Suwayomi public route goes to restricted gateway39104, never admin backend39103.

## Capacity and credit runway

The current configuration caps Komga at900 MiB, Suwayomi at900 MiB, Kavita at1,100 MiB and the gateway at128 MiB. The two Java heaps are each512 MiB. The summed service caps are3,028 MiB; 4 GiB leaves limited OS/reverse-proxy headroom. This is suitable only as a minimum candidate for small original fixtures, subject to Linux validation. The 8 GiB m7i-flex.large is eligible too, but selecting it requires confirming the larger credit consumption. Micro/small candidates with1–2 GiB do not fit this combined deployment.

Official current Linux compute prices were read from AWS's public regional price feed on2026-10-30:

| Region | c7i-flex.large hourly | 30-day compute only | $100 compute-only upper bound |
|---|---:|---:|---:|
| US East (N. Virginia) | $0.08479 | $61.05 | 49.1 days |
| Asia Pacific (Singapore) | $0.09778 | $70.40 | 42.6 days |

These are **credit-consumption illustrations**, not money charged to a Free Plan account. They assume24/7 operation, no other AWS usage and no applicable allowance. They exclude disk, IP, transfer, tax and other services, so actual credit runway may be shorter. Twice the remaining credit would at most double this compute-only runway; it does not extend the six-month account limit. The dated machine-readable source URLs/rate codes and8 GiB comparison are in `AWS-pricing-example.json`. Confirm the actual account/region estimate in the console immediately before provisioning.

## Install and prove before public activation

1. Verify and upload the secret-free bundle. Do not copy Mac runtime credentials. Follow `README.md`; VM credentials are generated privately on the VM.
2. Run the Ubuntu installer, then local provider probes. Confirm all three real catalog/chapter/page paths, restricted review accounts, original-content hashes and gateway denial cases.
3. Check startup/scanning memory and OOM/service logs, available disk, idle steady state, and persistence after a clean reboot. If4 GiB fails, do not silently resize or upgrade the plan.
4. Only after activation approval, create the three proposed DNS names, obtain free certificates and validate HTTPS/auth from outside the VM and from an iPhone on cellular. No public access is ready until those checks pass.
5. Keep the server available throughout review. Watch the actual credit balance; retain the original sample bundle/provenance elsewhere before account expiry. Free Plan ends on credit exhaustion or after six months, whichever comes first. A permanent production host needs a separate future decision.

MCP continues to use the existing separate Cloudflare service. No AWS reviewer host credential, owner's MCP grant or entitlement bypass is included; authenticated reviewer MCP testing still requires the reviewer's own verified test purchase/workspace and OAuth consent.

Sources:
- Eligible instance types: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/LaunchingAndUsingInstances.html
- Free Plan credits and end conditions: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html
- Instance specifications: https://docs.aws.amazon.com/ec2/latest/instancetypes/co.html
- Public IPv4 pricing: https://aws.amazon.com/vpc/pricing/
- EBS pricing: https://aws.amazon.com/ebs/pricing/
