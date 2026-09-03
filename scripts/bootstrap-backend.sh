#!/usr/bin/env bash
# Optional: creates a versioned, encrypted S3 bucket for remote Terraform state,
# then prints the backend block to paste into versions.tf.
set -euo pipefail

BUCKET="${1:?usage: bootstrap-backend.sh <bucket-name> [region]}"
REGION="${2:-ap-southeast-2}"

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration "LocationConstraint=$REGION"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

cat <<BACKEND

Add to versions.tf inside the terraform block:

  backend "s3" {
    bucket       = "$BUCKET"
    key          = "vpn/sydney/terraform.tfstate"
    region       = "$REGION"
    encrypt      = true
    use_lockfile = true
  }

Then run: terraform init -migrate-state
BACKEND
