#!/bin/bash

## Intended as a second step to be used on one of your proxmox nodes after your OKD4 API server/Services VM is fully set up, this script will spin up an LXC container that runs a TFTP server to contain ignition files that provision Fedora CoreOS
## This script only exists because I ran into various types of errors and roadblocks when using other translation scripts that build an ignition file into a Proxmox cloud-init
# You might not even need this, plenty of people have had success provisioning ignition using the good wrapper here https://wiki.geco-it.net/public:pve_fcos
### You are probably considering this if you use btrfs for your VM storage, or use a legacy HBA like a Dell H700 that does not support IT mode.
# (At least those were the scenarios that the wrapper did not work on)

export node="node-name"
export LXC_NAME="ignition"
export hostname="ignition"
export password="potatopass"
export id="9001"
export vmstorage="local-btrfs"
#public ip, can be commented out if only using it within cluster network
export ip="10.1.0.210"
export mask="24"
export gw="10.1.0.1"
#cluster ip, only works properly if sending the ignition files over the cluster network on the API server
export cip="10.2.0.130"
export cmask="24"
export cgw="10.2.0.1"

# Download the latest Alpine Linux LXC template using pveam
pveam update
pveam download local alpine-3.17-default_20221129_amd64.tar.xz

# Create LXC
pct create vmid $id --ostemplate $vmstorage:alpine-3.17-default_20221129_amd64.tar.xz -n $hostname --cores 1 --memory 1024 -rootfs: $vmstorage:$id/vm-$id-disk-0.raw,size=32G --net0 name=eth0,bridge=vmbr0,firewall=1,gw=$gw,ip=$ip/$mask,type=veth --net1 name=eth1,bridge=vmbr2,firewall=1,gw=$cgw,ip=$cip/$cmask,type=veth --features nesting=0 --hostname $hostname --password $password --nameserver 9.9.9.9
pct start $id
sleep 30
#prep tftp server
pvesh create /nodes/$node/qemu/$id/status/current --command "apk update && apk add tftp-hpa && sed -i 's/TFTP_ADDRESS=":69"/TFTP_ADDRESS=":69"/' /etc/default/tftpd-hpa && sed -i 's/TFTP_OPTIONS="--secure --create --permissive"/TFTP_OPTIONS="--secure --create --permissive"/' /etc/default/tftpd-hpa && rc-update add tftpd-hpa && rc-service tftpd-hpa start"

# from this point, you are able to go back to your services VM, or whatever machine you will be running the openshift-installer from.
# the ignition files made can be sent to this tftpd server, and can be used as a coreos.install.url= source, eliminating the need for a custom cloud init wrapper that might not work with your host implementation.



