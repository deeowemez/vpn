# terraform-aws-wireguard-vpn

Reusable Terraform for a single-instance WireGuard VPN server on AWS. Defaults
to **ap-southeast-2 (Sydney)**, but the region is just a variable — the same
module builds the same server anywhere.

The instance generates its own server and client keys on first boot, writes the
finished client configs into SSM Parameter Store as `SecureString`, and comes up
serving DNS from inside the region. No private key ever passes through Terraform
state.

## Layout

```
.
├── main.tf                  # root module -> ./modules/wireguard
├── variables.tf             # knobs you actually turn
├── outputs.tf               # IP, instance id, ready-to-run commands
├── versions.tf              # provider pins, optional S3 backend
├── terraform.tfvars.example
├── Makefile
├── modules/wireguard/       # the reusable module
│   ├── network.tf           # VPC, public subnet, IGW, security group
│   ├── iam.tf               # instance role: SSM + publish client configs
│   ├── main.tf              # EIP, instance, user_data rendering
│   └── templates/user_data.sh.tftpl
└── scripts/
    ├── fetch-clients.sh     # pull client configs out of SSM
    └── bootstrap-backend.sh # optional remote state bucket
```

## Prerequisites

- Terraform >= 1.5 (or OpenTofu)
- AWS credentials with permission to create VPC/EC2/IAM/SSM resources
- The [WireGuard client](https://www.wireguard.com/install/) on your devices

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # edit if you like
terraform init
terraform apply

# First boot installs packages; give it ~2 minutes, then:
make clients        # or: ./scripts/fetch-clients.sh ap-southeast-2 /vpn-syd/wireguard
```

You get `clients/client1.conf`, `client2.conf`, … Import one into the WireGuard
app per device (`fetch-clients.sh` prints a QR code for `client1` if `qrencode`
is installed), or on macOS/Linux:

```bash
sudo wg-quick up $PWD/clients/client1.conf
curl https://ifconfig.me      # should now be your Sydney Elastic IP
```

Useful commands:

```bash
make status        # did the bootstrap finish?
make shell         # SSM Session Manager onto the box, no SSH
make destroy
make clean-params  # remove the SSM client configs (Terraform doesn't own them)
```

## Reusing the module

```hcl
module "vpn_sydney" {
  source = "github.com/you/terraform-aws-wireguard-vpn//modules/wireguard"

  name              = "vpn-syd"
  region            = "ap-southeast-2"
  instance_type     = "t4g.small"
  client_count      = 5
  wg_port           = 51820
  allowed_vpn_cidrs = ["0.0.0.0/0"]
}
```

Stand up a second region by calling the module again with a different `name`,
`region`, and a non-overlapping `wg_subnet_cidr`. `name` namespaces every
resource and the SSM path, so parallel deployments don't collide.

## Design notes

- **WireGuard, not OpenVPN.** In-kernel, far lower CPU per gigabit, and it
  reconnects instantly when a laptop or phone changes networks — which matters
  when the tunnel is carrying a live stream.
- **Elastic IP allocated before the instance.** Its address is baked into the
  client configs at boot, so the configs never go stale after a reboot or
  replacement.
- **DNS resolves inside the region.** `dnsmasq` listens on the tunnel address
  and forwards to the VPC resolver (`.2` of the VPC CIDR). Without this, your
  device keeps using its local resolver and services see an Australian IP doing
  lookups that geolocate somewhere else — a common way to get flagged.
- **IPv6 is disabled on the server and blackholed by the client config**
  (`AllowedIPs` includes `::/0`). A working IPv6 path outside the tunnel is the
  single most common source of geo leaks.
- **No SSH by default.** The instance role includes
  `AmazonSSMManagedInstanceCore`; use `make shell`. `enable_ssh = true` requires
  a real CIDR list and refuses `0.0.0.0/0`.
- **`source_dest_check = false`** on the ENI, or AWS drops the NATed client
  traffic.
- **Keys stay off disk locally until you fetch them.** `.gitignore` excludes
  `clients/` and `*.conf`.

## Costs (ap-southeast-2, on-demand, indicative)

| Item | Rate | ~Monthly |
|---|---|---|
| t4g.small, 24/7 | ~$0.0212/hr | ~$15 |
| Elastic IP (in-use IPv4) | $0.005/hr | ~$3.60 |
| 8 GiB gp3 root | ~$0.10/GiB-mo | ~$1 |
| Data transfer out | ~$0.114/GB after 100 GB free/mo | see below |

Egress dominates once you stream. Rough consumption:

- 1080p video: ~3 GB/hr → ~$0.34/hr once past the free 100 GB
- 4K video: ~7 GB/hr → ~$0.80/hr
- Cloud gaming at 1080p60: ~10-14 GB/hr → ~$1.15-1.60/hr

So ~$20/month idle, and heavy use can add a lot more. Stop the instance when
you're not using it (`aws ec2 stop-instances`); the Elastic IP keeps the address
and the client configs keep working. Note that a *stopped* instance's Elastic IP
is still billed, and stopping doesn't reset your public IP — which is the point.

## Troubleshooting

- **`make clients` says the server hasn't bootstrapped.** `make shell`, then
  `sudo tail -f /var/log/wg-bootstrap.log`.
- **Handshake but no traffic.** Almost always MTU. Set `wg_mtu = 1380` and
  re-apply, or lower `MTU` in the client config.
- **Nothing connects at all.** Some networks block high UDP ports. Try
  `wg_port = 443`.
- **`terraform apply` replaces the instance.** `user_data_replace_on_change` is
  on, so changing any user_data input rebuilds the server and regenerates all
  keys. Re-run `make clients` afterwards.

## Read this before using it for geo-restricted streaming

This routes your traffic through a Sydney IP correctly and efficiently. Whether
a given service *accepts* that IP is a separate question, and not one this repo
can settle:

- **AWS publishes its IP ranges** (`ip-ranges.json`), and commercial
  geo-blocking vendors ingest them. An EC2 Elastic IP is identifiable as
  datacenter/hosting space, and most large streaming and cloud-gaming platforms
  block or degrade those ranges regardless of country. Success is per-service
  and can stop working after any blocklist refresh.
- **Cloud gaming is latency-sensitive.** The tunnel itself adds ~1-3 ms of
  processing, which is negligible; the real cost is the geographic detour. If
  you are outside Australia, your input latency becomes your RTT to Sydney plus
  Sydney-to-service, and 150-250 ms round trips make interactive game streaming
  unpleasant no matter how good the VPN is.
- **Egress is the real bill.** See the cost table — cloud gaming runs
  ~10-14 GB/hr, so a few hours a week meaningfully exceeds the instance cost.
- **Check the service's terms.** Circumventing regional restrictions usually
  violates them, and can put an account at risk. That is your call to make;
  this repo just moves packets.

Where this design is genuinely strong: a private exit node in Sydney that you
alone control, for accessing Australian services from a trip, reaching
AU-region game servers on a clean route, testing region-specific behaviour, or
avoiding a commercial VPN provider seeing your traffic. Where it is weakest is
exactly the case of a large platform actively working to detect datacenter
egress. If that is the goal, verify the specific service works from a
short-lived instance before committing to the setup.
