# terraform-aws-wireguard-vpn

Reusable Terraform for an **ephemeral** WireGuard VPN server on AWS, defaulting
to **ap-southeast-2 (Sydney)**. Built for the "spin it up to watch a match,
throw it away afterwards" pattern: `make match` before kickoff, `make down`
after, and nothing bills in between.

With a hostname and a keyset configured, your client configs are generated once
and keep working forever — every rebuild reuses the same identity behind the
same DNS name. The instance also self-terminates when idle, so a stack you
forget about cleans itself up.

## Cost

The VPC, subnet, internet gateway, security group and IAM role are free to
leave in place. Only the running instance and the DNS zone cost anything.

| | Rate | Per 3-hour match |
|---|---|---|
| t4g.small compute | ~$0.0212/hr | ~$0.064 |
| Public IPv4 (while running) | $0.005/hr | ~$0.015 |
| 8 GiB gp3 root volume | ~$0.001/hr | ~$0.003 |
| Data transfer out (~9 GB at 1080p) | free under 100 GB/mo | $0 |
| Route 53 hosted zone | $0.50/month | — |

**Four matches a month: about $0.80**, nearly all of it the DNS zone. Skip the
hostname and it drops to ~$0.30, at the cost of re-importing configs every
time. AWS's 100 GB monthly free egress covers roughly eleven 3-hour 1080p
matches; past that it is $0.114/GB in Sydney, so ~$1 per extra match.

There is deliberately no Elastic IP: a reserved IPv4 is billed hourly whether
or not the instance runs, which would have cost more than everything else
combined. The address is assigned at launch, and Route 53 points the hostname
at whatever it happens to be.

## Layout

```
.
├── main.tf                  # root module -> ./modules/wireguard
├── variables.tf             # knobs you actually turn
├── outputs.tf
├── versions.tf              # provider pins, optional S3 backend
├── terraform.tfvars.example
├── Makefile                 # make dns / make keys / make match / make down
├── modules/wireguard/
│   ├── network.tf           # VPC, public subnet, IGW, security group
│   ├── iam.tf               # instance role: SSM Session Manager only
│   ├── dns.tf               # A record for the endpoint hostname
│   ├── main.tf              # instance, user_data rendering
│   └── templates/user_data.sh.tftpl
└── scripts/
    ├── setup-dns.sh         # one-time: create the Route 53 zone
    ├── gen-keys.sh          # one-time: permanent keyset + client configs
    ├── fetch-clients.sh     # collect throwaway configs (no-keyset mode)
    └── bootstrap-backend.sh # optional remote state bucket
```

## Prerequisites

- Terraform >= 1.5 (or OpenTofu)
- AWS credentials able to create VPC/EC2/IAM/Route 53 resources
- `brew install wireguard-tools` for the `wg` key generator
- The [WireGuard client](https://www.wireguard.com/install/) on your devices
- Optional: `brew install qrencode` for phone setup by QR code

## One-time setup

### 1. Create the DNS record

Add one A record at whoever hosts your DNS, pointing the VPN subdomain at a
placeholder:

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `vpn` | `192.0.2.1` | lowest offered (300s at Hostinger) |

`192.0.2.1` is a reserved documentation address that goes nowhere. It is there
so the name always resolves to *something*.

**Edit this record's value before each match; never delete it.** Zones
typically cache a "no such host" answer for ten minutes, so a deleted record
would keep failing to resolve well after you rebuilt the server.

Two ways to skip the manual edit:

- **DNS on Route 53** — set `route53_zone_name` in `terraform.tfvars` and
  Terraform manages the record itself. `scripts/setup-dns.sh` creates a
  delegated zone if your registrar can add NS records (Hostinger's editor
  cannot).
- **DNS at Hostinger** — `scripts/hostinger-dns.sh` updates the record through
  Hostinger's API, and `make match` calls it automatically once
  `HOSTINGER_API_TOKEN` is set (hPanel → Account → API), optionally via a
  `.env` file. **This script is written against Hostinger's documented API but
  has not been run against a live token** — try `./scripts/hostinger-dns.sh get
  <fqdn>` first, and `--dry-run` to see the exact request.

### 2. Generate the permanent keyset

```bash
brew install wireguard-tools        # provides the `wg` key generator
make keys HOST=vpn.example.com COUNT=3
```

This writes `keys/` (consumed by Terraform on every build) and `clients/`
(your configs). Install those configs on your devices **once** — they stay
valid for every future match, because both the hostname and the keys are now
stable.

### 3. Point Terraform at it

```bash
cp terraform.tfvars.example terraform.tfvars
# set: vpn_hostname = "vpn.example.com"
terraform init
```

## Match-day workflow

```bash
make match      # ~30s to apply, ~60s more for the server to finish booting
```

It prints the new IP. Paste that into your `vpn` A record and wait out the TTL.
Then connect:

```bash
make connect        # or: make connect CONF=clients/client3.conf
make disconnect
```

Prefer these over `wg-quick up` directly. The configs are full tunnels
(`AllowedIPs = 0.0.0.0/0, ::/0`), so every packet goes into `wg0` — pointing
one at a server that is not running takes the machine offline until you notice
and run `wg-quick down`. `make connect` refuses to start when the endpoint
still resolves to the placeholder, and tears the tunnel back down by itself if
traffic does not flow once it is up.

On a phone, just use the toggle in the WireGuard app.

Afterwards:

```bash
make down       # destroy the instance; the DNS zone and your keys survive
```

Other targets: `make status` (is anything running), `make ip` (this session's
address), `make shell` (Session Manager, no SSH).

### If you forget `make down`

The instance checks every 5 minutes and powers off once no client has completed
a handshake for `idle_shutdown_minutes` (default 30). Shutdown behaviour is set
to *terminate*, so it genuinely goes away and billing stops.

One catch: `PersistentKeepalive` means a device left connected keeps
handshaking. **Switch the VPN off on your device when the match ends** — that
starts the idle clock. Run `make down` afterwards to tidy the Terraform state;
a later `terraform apply` recreates everything cleanly either way.

## Running without a hostname

Both one-time steps are optional. With no `vpn_hostname` and no `keys/`
directory, the server generates throwaway keys at boot and `make match` collects
the resulting configs over SSM into `clients/`. Cheaper by $0.50/month, but
every rebuild invalidates the configs, which means re-importing on every device
each time. Fine if you only ever watch on a laptop.

## Reusing the module

```hcl
module "vpn_sydney" {
  source = "github.com/you/terraform-aws-wireguard-vpn//modules/wireguard"

  name                  = "vpn-syd"
  instance_type         = "t4g.small"
  vpn_hostname          = "vpn.example.com"
  server_private_key    = file("keys/server.key")
  peer_stanzas          = file("keys/peers.conf")
  idle_shutdown_minutes = 30
}
```

Set `idle_shutdown_minutes = 0` for a conventional always-on server; shutdown
behaviour reverts to *stop*. Call the module twice with different `name` and
`wg_subnet_cidr` values to run two regions at once.

## Design notes

- **WireGuard, not OpenVPN.** In-kernel, far lower CPU per gigabit, and it
  reconnects instantly across network changes.
- **The hosted zone is not managed by Terraform.** Destroying and recreating it
  would issue new nameservers and break the registrar delegation on every
  match, so `setup-dns.sh` creates it once and `terraform destroy` only removes
  the A record.
- **A-record TTL is 60 seconds**, because the address changes on every rebuild.
  If you tear down and rebuild back to back, give DNS a minute before
  connecting.
- **The server private key reaches the instance through user_data**, which
  means it is stored in your Terraform state file. That is the price of configs
  that survive rebuilds. State is gitignored and lives on your machine; if that
  tradeoff bothers you, drop `keys/` and use throwaway mode, where no key ever
  leaves the instance.
- **No AWS CLI on the instance.** Boot time is the main cost of a disposable
  stack, so it installs only `wireguard-tools`, `dnsmasq` and `iptables`.
- **DNS resolves inside the region.** `dnsmasq` listens on the tunnel address
  and forwards to the VPC resolver (`.2` of the VPC CIDR). Without this your
  device keeps using its local resolver, and services see an Australian IP doing
  lookups that geolocate somewhere else — a common way to get flagged.
- **IPv6 is disabled server-side and blackholed by the client config**
  (`AllowedIPs` includes `::/0`). A working IPv6 path outside the tunnel is the
  most common source of geo leaks.
- **No SSH by default.** The instance role carries only
  `AmazonSSMManagedInstanceCore`; use `make shell`. `enable_ssh = true` requires
  a real CIDR list and refuses `0.0.0.0/0`.
- **`source_dest_check = false`**, or AWS drops the NATed client traffic.
- **`.gitignore` excludes `keys/`, `clients/` and `*.conf`** — those hold
  private keys.

## Troubleshooting

- **Client can't resolve the hostname.** Check the delegation with
  `dig +short NS vpn.example.com`, and that the instance is actually up
  (`make status`). Right after `make down`, the record is gone by design.
- **`make match` times out.** `make shell`, then
  `sudo tail -50 /var/log/wg-bootstrap.log`.
- **Handshake succeeds but no traffic flows.** Almost always MTU. Set
  `wg_mtu = 1380` in `terraform.tfvars`, and regenerate configs with
  `./scripts/gen-keys.sh --host ... --mtu 1380 --force`.
- **Nothing connects at all.** Some networks block high UDP ports. Try
  `wg_port = 443` and regenerate configs with `--port 443`.
- **The stream says you're using a VPN.** `make down && make match` draws a new
  address from the AWS pool. See below.
- **Terraform reports a peer-subnet mismatch.** Your `keys/peers.conf` was
  generated for a different tunnel subnet than `wg_subnet_cidr`. Regenerate
  with `--subnet-prefix` matching.

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
- **Rebuilding gives you a fresh IP**, a genuine advantage of the disposable
  design: if the address you're handed is flagged, `make down && make match`
  costs eight cents and draws again from the pool. The hostname stays the same,
  so your configs don't change.
- **Latency doesn't matter here.** For a buffered video stream the detour
  through Sydney is absorbed entirely. (This would not hold for interactive
  cloud gaming, where the round trip becomes input lag.)
- **Check the service's terms.** Circumventing regional restrictions usually
  violates them and can put an account at risk. That is your call to make; this
  repo just moves packets.

If unblocking is the whole point, the honest alternatives are a commercial VPN
(~$3/month, and fighting blocklists is their job) or an exit node on a real
Australian residential connection via something like Tailscale — a residential
IP is the one thing datacenter hosting cannot give you.
