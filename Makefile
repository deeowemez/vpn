REGION ?= ap-southeast-2
CONF   ?= clients/client1.conf

.PHONY: match up down clients status ip shell init fmt validate plan destroy dns keys dns-update dns-clear connect disconnect

# --- one-time setup ---------------------------------------------------------

# Create the Route 53 hosted zone for the VPN subdomain and print the NS
# records to add at your registrar. HOST must match vpn_hostname in tfvars.
dns:
	@test -n "$(HOST)" || { echo "usage: make dns HOST=vpn.example.com"; exit 1; }
	./scripts/setup-dns.sh $(HOST)

# Generate the permanent keyset and client configs. Run once; installing the
# resulting configs on your devices is the last time you have to touch them.
keys:
	@test -n "$(HOST)" || { echo "usage: make keys HOST=vpn.example.com [COUNT=3]"; exit 1; }
	./scripts/gen-keys.sh --host $(HOST) --count $(or $(COUNT),3)

# --- match-day workflow -----------------------------------------------------

# Build the server. With a keyset in keys/ there is nothing to collect
# afterwards - wait for it to finish booting and switch the VPN on.
match: up dns-update
	@if [ -f keys/server.key ]; then \
	  echo; echo "Server up at $$(terraform output -raw endpoint)."; \
	  echo "Give it ~60s to finish booting, then switch the VPN on."; \
	else \
	  $(MAKE) clients; \
	fi

up:
	terraform apply -auto-approve

# Only needed without a persistent keyset.
clients:
	./scripts/fetch-clients.sh $(REGION) $$(terraform output -raw instance_id)

# Connect only once the endpoint resolves to a real server, and roll back
# automatically if no traffic flows - a full-tunnel config pointed at a server
# that is not there takes the whole machine offline.
connect:
	./scripts/connect.sh $(CONF)

disconnect:
	@if [ -f $(CONF) ]; then ./scripts/disconnect.sh $(CONF); fi

# Tear everything down. Disconnects first: destroying the server you are
# routing through would drop you offline mid-command. Safe to run even if the
# instance already terminated itself on the idle timer.
down: disconnect dns-clear
	terraform destroy -auto-approve
	@if [ ! -f keys/server.key ]; then rm -rf clients; fi

# Repoint the DNS record at the instance just built. Skipped when no hostname
# is configured, or when Terraform already manages the record via Route 53.
dns-update:
	@host=$$(terraform output -raw endpoint 2>/dev/null || true); \
	ip=$$(terraform output -raw public_ip 2>/dev/null || true); \
	if [ -z "$$host" ] || [ "$$host" = "$$ip" ]; then \
	  echo "No hostname configured - clients dial $$ip directly."; \
	elif [ -f .env ] || [ -n "$$HOSTINGER_API_TOKEN" ]; then \
	  ./scripts/hostinger-dns.sh set "$$host" "$$ip"; \
	else \
	  echo; \
	  echo "  ==> Update the A record for $$host to  $$ip"; \
	  echo "      Hostinger hPanel -> Domains -> DNS -> edit the 'vpn' A record."; \
	  echo "      Edit the value; do not delete and recreate it."; \
	  echo; \
	fi

# Park the record on a non-routable address before tearing the server down, so
# the name never dangles at an AWS address that gets recycled to someone else.
dns-clear:
	@host=$$(terraform output -raw endpoint 2>/dev/null || true); \
	ip=$$(terraform output -raw public_ip 2>/dev/null || true); \
	if [ -n "$$host" ] && [ "$$host" != "$$ip" ] && { [ -f .env ] || [ -n "$$HOSTINGER_API_TOKEN" ]; }; then \
	  ./scripts/hostinger-dns.sh clear "$$host"; \
	fi

# --- inspection -------------------------------------------------------------

status:
	@id=$$(terraform output -raw instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "Nothing deployed."; else \
	  aws ec2 describe-instances --region $(REGION) --instance-ids $$id \
	    --query 'Reservations[0].Instances[0].{State:State.Name,IP:PublicIpAddress,Launched:LaunchTime}' \
	    --output table; \
	fi

ip:
	@terraform output -raw public_ip

shell:
	aws ssm start-session --region $(REGION) --target $$(terraform output -raw instance_id)

# --- terraform --------------------------------------------------------------

init:
	terraform init

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

plan:
	terraform plan

destroy: down
