terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Local state is fine for a single-operator VPN. To share the stack,
  # uncomment and create the bucket first with scripts/bootstrap-backend.sh.
  #
  # backend "s3" {
  #   bucket       = "my-tfstate-bucket"
  #   key          = "vpn/sydney/terraform.tfstate"
  #   region       = "ap-southeast-2"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
