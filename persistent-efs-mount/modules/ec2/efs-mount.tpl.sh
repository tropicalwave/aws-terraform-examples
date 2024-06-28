#!/bin/bash -ex
# https://docs.aws.amazon.com/efs/latest/ug/installing-amazon-efs-utils.html

# shellcheck disable=SC2269
efs_id="${efs_id}"
yum install -y amazon-efs-utils
mkdir /efs

if ! grep -q /efs /etc/fstab; then
    echo "$efs_id":/ /efs efs _netdev,noresvport,tls,iam 0 0 >>/etc/fstab
fi

while true; do
    mount -t efs "$efs_id":/ /efs && break
    sleep 10
done
