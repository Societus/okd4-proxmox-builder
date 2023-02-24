#!/bin/bash

# sample series of scripts leading up to shorter deployment cycle of OKD4 nodes.

# Variables to set if you actually want to use this script as-is

# Change FCOS & RL8 image urls to desired versions
export FCOS="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz"
export RL8="https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
# proxmox node name must be set regardless if standalone or clustered
export NODE="pve"
export SVC_VM="101"
export SVC_PUB_IP="1.2.3.4"
export SVC_MASK="255.255.255.0"
export SVC_GW="1.2.3.1"
export SVC_CLU_IP="2.3.4.5"
export ciuser="cloudinitusername"
export cipassword="cloudinitpassword"
export sshkey="ssh-pubkey"

# First, provision a new VM in proxmox to act as the services machine, used to provide DNS, load balancing, nfs origins, and internet to the cluster. 
# Ideally a minimal install of RHEL 8 or an upstream comparison, I used a cloud image of Rocky Linux 8, resized to 64GB

# Download Cloud Images for services and cluster nodes 
wget $RL8
qemu-img resize Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 64G
wget $FCOS

# VM provisioning - Services VM will act as a bastion host, using cloud init for simple user management
# Assumptions - Services VM will have 2 network interfaces, one for access to the internet, and one for access to a dedicated network containing local nodes used for egress

qm create $SVC_VM --name okd4-services --memory 4096 --cores 4
qm set $SVC_VM --net0 bridge=vmbr0,firewall=1
qm set $SVC_VM --ipconfig0 ip=$SVC_PUB_IP,netmask=$SVC_MASK,gw=$SVC_GW
qm set $SVC_VM --net1 bridge=vmbr2,firewall=1
qm set $SVC_VM --ipconfig1 ip=$SVC_CLU_IP,netmask=$SVC_MASK
qm importdisk $SVC_VM Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 local
qm set $SVC_VM --scsi0 local:$SVC_VM/vm-$SVC_VM-disk-0.raw,discard=on,size=64G
qm set $SVC_VM --ide0 cloudinit,format=qcow2
qm set $SVC_VM --boot c --bootdisk scsi0
qm set $SVC_VM --ciuser $ciuser --cipassword $cipassword
qm set $SVC_VM --sshkey <ssh-key>

# start services vm and give time to provision cloud-init parameters
qm start $SVC_VM
sleep 60
echo "Please wait while VM creation completes its initial boot provisioning"

# schedule commands to services VM to install reprequisites and establish xrdp access
pvesh create /nodes/$NODE/qemu/101/status/current --command "sudo dnf update -y && sudo dnf install -y epel-release && sudo dnf install -y xrdp tigervnc-server bind bind-utils named qemu-guest-agent.x86_64 httpd haproxy & sudo reboot"

# network portion follows, will probably make separate script for this eventually

tput setaf 3
echo "Once the services VM completes the install and reboot of prerequisites, use xrdp to enter the system and configure the necessary services for the cluster to function.

This includes modifying the named.conf to listen from your cluster interface's IP as well as local host (and changing the name servers the hell away from Google),

build zones (great templates for this section found at https://github.com/cragr/okd4_files), enable firewall, allow ports 53,8080,6443/tcp,22623/tcp, service http and https, and reload firewall,

Then set the DNS server on the interface that has access to the internet to 127.0.0.1 

Once DNS resolution tests good, enable haproxy and httpd (use 'sudo sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf' 'sudo setsebool -P httpd_read_user_content 1' to configure httpd) then start httpd and haproxy

If by this stage you get http code for Red Hat Apache, your services VM is prepared for cluster creation, and you can continue by typing entering 'yes', any other answers will end the script and the rest can be done by hand. (yes/no)"
read answer
if [ "$answer" = "yes" ]
then
fi
tput sgr0
