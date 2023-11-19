#!/bin/bash -ex
# https://docs.aws.amazon.com/efs/latest/ug/installing-amazon-efs-utils.html
yum install -y amazon-efs-utils

mkdir /efs
efs_id="${efs_id}"
mount -t efs "$efs_id":/ /efs
echo "$efs_id":/ /efs efs defaults,_netdev 0 0 >> /etc/fstab
