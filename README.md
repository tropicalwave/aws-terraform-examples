# Collection of AWS examples using Terraform

[![GitHub Super-Linter](https://github.com/tropicalwave/aws-terraform-examples/workflows/Lint%20Code%20Base/badge.svg)](https://github.com/marketplace/actions/super-linter)

## General

Generally, it should be sufficient to switch into the
subdirectories and execute the following commands to
start deployments:

```bash
terraform init
terraform apply
```

The deployments can later be destroyed by the
execution of `terraform destroy`.

## List of projects

* [Cloudfront deployment with static content](static-website/README.md)
* [Highly available EC2 instance with EFS backend](persistent-efs-mount/README.md)
* [Route53 DNS service deployment from CSV file with DNSSEC](route53/README.md)
