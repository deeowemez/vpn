# terraform-aws-wireguard-vpn

Reusable Terraform for an **ephemeral** WireGuard VPN server on AWS, defaulting
to **ap-southeast-2 (Sydney)**. Built for the "spin it up to watch a match, throw
it away afterwards" pattern: `make match` before kickoff, `make down` after, and
nothing bills in between.

The instance generates its own keys on first boot and self-terminates once no
client has used it for a while, so a stack you forget about cleans itself up.

## Cost

Nothing persists between matches. The VPC, subnet, internet gateway, security
group and IAM role are all free to leave in place; only the running instance
costs anything.

| | Rate | Per 3-hour match |
|---|---|---|
| t4g.small compute | ~$0.0212/hr | ~$0.064 |
| Public IPv4 (while running) | $0.005/hr | ~$0.015 |
| 8 GiB gp3 root volume | ~$0.001/hr | ~$0.003 |
| Data transfer out (~9 GB at 1080p) | free under 100 GB/mo | $0 |
| **Total** | | **~$0.08** |

**At rest: $0.00.** Four matches a month is roughly **30 cents**. AWS's 100 GB
monthly free egress allowance covers about eleven 3-hour 1080p matches; past
that it is $0.114/GB in Sydney, so ~$1 per extra match.

Because the whole stack is disposable, there is no Elastic IP — a reserved IPv4
is billed by the hour whether or not the instance is running, which would have
cost more than everything else combined. The address is assigned at launch and
the server reads it from instance metadata.

## Layout

```
.
├── main.tf                  # root module -> ./modules/wireguard
├── variables.tf             # knobs you actually turn
├── outputs.tf
├── versions.tf              # provider pins, optional S3 backend
├── terraform.tfvars.example
├── Makefile                 # make match / make down
├── modules/wireguard/       # the reusable module
│   ├── network.tf           # VPC, public subnet, IGW, security group
│   ├── iam.tf               # instance role: SSM Session Manager only
│   ├── main.tf              # instance, user_data rendering
│   └── templates/user_data.sh.tftpl
└── scripts/
    ├── fetch-clients.sh     # pull client configs off the box over SSM
    └── bootstrap-backend.sh # optional remote state bucket
```

## Prerequisites

- Terraform >= 1.5 (or OpenTofu)
- AWS credentials able to create VPC/EC2/IAM resources
- The [WireGuard client](https://www.wireguard.com/install/) on your devices
- Optional: `brew install qrencode` for phone setup by QR code

## Match-day workflow

```bash
cp terraform.tfvars.example terraform.tfvars   # first time only
terraform init                                 # first time only

make match      # build + fetch configs, ~2 minutes
```

`make match` applies the stack, waits for the SSM agent, polls until the
bootstrap finishes, and drops `clients/client1.conf`, `client2.conf`, … into the
working directory. Then:

```bash
sudo wg-quick up $PWD/clients/client1.conf
curl https://ifconfig.me      # should be your Sydney address
# ... watch the match ...
sudo wg-quick down $PWD/clients/client1.conf

make down       # destroy everything
```

On a phone, scan the QR code `make match` prints, or AirDrop/import the `.conf`.

Other targets:

```bash
make status     # is anything running, and since when
make ip         # public IP of the current server
make shell      # SSM Session Manager onto the box, no SSH
```

### If you forget `make down`

The instance runs an idle check every 5 minutes and powers off once no client
has completed a WireGuard handshake for `idle_shutdown_minutes` (default 30).
Shutdown behaviour is set to *terminate*, so the instance genuinely goes away
and billing stops.

One catch worth knowing: `PersistentKeepalive` means a device left connected
keeps handshaking even while you sleep. **Switch the VPN off on your device when
the match ends** — that starts the idle clock. Run `make down` afterwards to
clear the Terraform state; a later `terraform apply` recreates the instance
cleanly either way.

## Reusing the module

```hcl
module "vpn_sydney" {
  source = "github.com/you/terraform-aws-wireguard-vpn//modules/wireguard"

  name                  = "vpn-syd"
  instance_type         = "t4g.small"
  client_count          = 3
  wg_port               = 51820
  idle_shutdown_minutes = 30
}
```

Set `idle_shutdown_minutes = 0` for a conventional always-on server; shutdown
behaviour reverts to *stop* and the instance stays put. Call the module twice
with different `name` and `wg_subnet_cidr` values to run two regions at once.

## Design notes

- **WireGuard, not OpenVPN.** In-kernel, far lower CPU per gigabit, and it
  reconnects instantly across network changes.
- **Keys never touch Terraform state.** The instance generates them at boot;
  `fetch-clients.sh` reads the finished configs over SSM Session Manager. The
  private keys are deleted from the server's disk once written into the configs.
- **No AWS CLI on the instance.** Boot time is the main cost of a disposable
  stack, so the instance installs only `wireguard-tools`, `dnsmasq` and
  `iptables`. Anything the operator needs is pulled over SSM instead.
- **DNS resolves inside the region.** `dnsmasq` listens on the tunnel address
  and forwards to the VPC resolver (`.2` of the VPC CIDR). Without this, your
  device keeps using its local resolver and services see an Australian IP doing
  lookups that geolocate somewhere else — a common way to get flagged.
- **IPv6 is disabled server-side and blackholed by the client config**
  (`AllowedIPs` includes `::/0`). A working IPv6 path outside the tunnel is the
  most common source of geo leaks.
- **No SSH by default.** The instance role carries only
  `AmazonSSMManagedInstanceCore`; use `make shell`. Setting `enable_ssh = true`
  requires a real CIDR list and refuses `0.0.0.0/0`.
- **`source_dest_check = false`**, or AWS drops the NATed client traffic.
- **`.gitignore` excludes `clients/` and `*.conf`** — those hold private keys.

## Troubleshooting

- **`make match` times out waiting for bootstrap.** `make shell`, then
  `sudo tail -50 /var/log/wg-bootstrap.log`.
- **Handshake succeeds but no traffic flows.** Almost always MTU. Set
  `wg_mtu = 1380` in `terraform.tfvars` and rebuild.
- **Nothing connects at all.** Some networks block high UDP ports. Try
  `wg_port = 443`.
- **The stream says you're using a VPN.** Rebuild — `make down && make match`
  gets you a different IP from the AWS pool. See below for why this happens.
- **Configs stopped working.** Every rebuild generates fresh keys and gets a new
  address, so configs from a previous match are dead. Re-run `make clients`.

## Read this before using it for geo-restricted streaming

This routes your traffic through a Sydney IP correctly and efficiently. Whether
a given service *accepts* that IP is a separate question, and not one this repo
can settle:

- **AWS publishes its IP ranges** (`ip-ranges.json`), and commercial
  geo-blocking vendors ingest them. An EC2 address is identifiable as
  datacenter/hosting space, and large streaming platforms — Australian sports
  broadcasters among the more aggressive — block those ranges regardless of
  country. Success is per-service and can stop working after any blocklist
  refresh.
- **Rebuilding gives you a fresh IP**, which is a genuine advantage of the
  disposable design: if the address you're handed is flagged, `make down &&
  make match` costs eight cents and draws again from the pool.
- **Latency doesn't matter here.** For a buffered video stream, the detour
  through Sydney is absorbed entirely. (This would not hold for interactive
  cloud gaming, where the round trip becomes input lag.)
- **Check the service's terms.** Circumventing regional restrictions usually
  violates them and can put an account at risk. That is your call to make; this
  repo just moves packets.

If unblocking is the whole point, the honest alternatives are a commercial VPN
(~$3/month, and fighting blocklists is their job) or an exit node on a real
Australian residential connection via something like Tailscale — a residential
IP is the one thing datacenter hosting cannot give you.
