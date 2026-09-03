REGION ?= ap-southeast-2

.PHONY: match up down clients status ip shell init fmt validate plan destroy dns keys

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
match: up
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

# Tear everything down. Safe to run even if the instance already terminated
# itself on the idle timer - Terraform reconciles either way. The Route 53
# hosted zone is not managed here and survives.
down:
	terraform destroy -auto-approve
	@if [ ! -f keys/server.key ]; then rm -rf clients; fi

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
