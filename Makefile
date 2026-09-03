REGION ?= ap-southeast-2
NAME   ?= vpn-syd

.PHONY: init plan apply clients destroy fmt validate shell status clean-params

init:
	terraform init

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

plan:
	terraform plan

apply:
	terraform apply

# Pull the generated client configs once the instance has booted.
clients:
	./scripts/fetch-clients.sh $(REGION) /$(NAME)/wireguard

status:
	aws ssm get-parameter --region $(REGION) --name /$(NAME)/wireguard/status \
		--query 'Parameter.Value' --output text

shell:
	aws ssm start-session --region $(REGION) --target $$(terraform output -raw instance_id)

destroy:
	terraform destroy

# The instance publishes client configs itself, so Terraform does not own them
# and destroy leaves them behind. Remove them explicitly.
clean-params:
	aws ssm get-parameters-by-path --region $(REGION) --path /$(NAME)/wireguard --recursive \
		--query 'Parameters[].Name' --output text \
	| tr '\t' '\n' | grep . \
	| xargs -r -n10 aws ssm delete-parameters --region $(REGION) --names
