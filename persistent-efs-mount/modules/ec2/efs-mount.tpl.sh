#!/bin/bash -ex
# https://docs.aws.amazon.com/efs/latest/ug/installing-amazon-efs-utils.html

# shellcheck disable=SC2269
efs_id="${efs_id}"
yum install -y amazon-efs-utils
mkdir /efs
mount -t efs "$efs_id":/ /efs
echo "$efs_id":/ /efs efs defaults,_netdev 0 0 >> /etc/fstab
