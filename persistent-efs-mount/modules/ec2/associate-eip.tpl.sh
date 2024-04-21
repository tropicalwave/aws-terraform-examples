#!/bin/bash -ex
TOKEN="$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"
instance_id="$(curl -s "http://169.254.169.254/latest/meta-data/instance-id" -H "X-aws-ec2-metadata-token: $TOKEN")"
# shellcheck disable=SC2269
aws_region="${aws_region}"
# shellcheck disable=SC2269
allocation_id="${allocation_id}"
aws --region "$aws_region" ec2 associate-address --instance-id "$instance_id" --allocation-id "$allocation_id" --allow-reassociation
