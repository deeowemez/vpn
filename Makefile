REGION ?= ap-southeast-2

.PHONY: match down up clients status ip shell init fmt validate plan destroy

# --- match-day workflow -----------------------------------------------------

# Build the server and pull the client configs. Takes ~2 minutes end to end,
# so start it before kickoff.
match: up clients

up:
	terraform apply -auto-approve

clients:
	./scripts/fetch-clients.sh $(REGION) $$(terraform output -raw instance_id)

# Tear everything down. Safe to run even if the instance already terminated
# itself on the idle timer - Terraform reconciles either way.
down:
	terraform destroy -auto-approve
	rm -rf clients

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
