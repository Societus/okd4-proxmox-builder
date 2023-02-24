#!/bin/bash

# sample series of scripts leading up to shorter deployment cycle of OKD4 nodes.

# Variables to set if you actually want to use this script as-is

# Change FCOS & RL8 image urls to desired versions
export FCOS="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz"
export RL8="https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
# proxmox node name must be set regardless if standalone or clustered
export NODE="pve"
export VMSTORAGE="local"
export SVC_VM="101"
export BOOTSTRAP_VM="500"
export CP_VM_START="501"
export WKR_VM_START="510"
export SVC_PUB_IP="10.10.1.100"
export SVC_MASK="255.255.255.0"
export SVC_GW="10.10.1.1"
export CLU_GW="10.10.2.1"
export BOOTSTRAP_IP="10.10.2.101"
export SVC_CLU_IP="10.10.2.102"
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
# Assumptions - Services VM will have 2 network interfaces, one for access to the internet, and one for access to a dedicated network containing $VMSTORAGE nodes used for egress

qm create $SVC_VM --name okd4-services --memory 4096 --cores 4
qm set $SVC_VM --net0 bridge=vmbr0,firewall=1
qm set $SVC_VM --ipconfig0 ip=$SVC_PUB_IP,netmask=$SVC_MASK,gw=$SVC_GW
qm set $SVC_VM --net1 bridge=vmbr2,firewall=1
qm set $SVC_VM --ipconfig1 ip=$SVC_CLU_IP,netmask=$SVC_MASK
qm importdisk $SVC_VM Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 $VMSTORAGE
qm set $SVC_VM --scsi0 $VMSTORAGE:$SVC_VM/vm-$SVC_VM-disk-0.raw,discard=on,size=64G
qm set $SVC_VM --ide0 cloudinit,format=qcow2
qm set $SVC_VM --boot c --bootdisk scsi0
qm set $SVC_VM --ciuser $ciuser --cipassword $cipassword
qm set $SVC_VM --sshkey $sshkey

## Bootstrap provisioning - CoreOS bootstrap is where ignition for the cluster will be hosted will be hosted for bringing nodes into consensus and fulfilling any prerequisites
#### Bootstrap requires ignition, which can be loaded as a json to a TFTP server, which will have a section added here soon
qm create $BOOTSTRAP_VM --name okd4-bootstrap --memory 2048 --cores 2
qm set $BOOTSTRAP_VM --net1 bridge=vmbr2,firewall=1
qm set $BOOTSTRAP_VM --ipconfig1 ip=$BOOTSTRAP_IP,netmask=$SVC_MASK
qm importdisk $BOOTSTRAP_VM Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 $VMSTORAGE
qm set $BOOTSTRAP_VM--scsi0 $VMSTORAGE:$BOOTSTRAP_VM/vm-$BOOTSTRAP_VM-disk-0.raw,discard=on,size=64G
qm set $BOOTSTRAP_VM --ide0 cloudinit,format=qcow2
qm set $BOOTSTRAP_VM --boot c --bootdisk scsi0
qm set $BOOTSTRAP_VM --ciuser $ciuser --cipassword $cipassword
qm set $BOOTSTRAP_VM --sshkey $sshkey

## Container VM provisioning - CoreOS VMs act as all nodes in the cluster, OKD minimum requirements are 3 control planes and at least 2 workers. Creating and adding to a cluster requires a bootstrap VM, which can be shutdown until needed

##   Each of the following segments require filling in a number of ID of the final node to be created
for ((controlplane=$CP_VM_START; controlplane=<503; controlplane++))
for ((cpname=okd-control-plane-1; okd-control-plane<=3; cpname++))
for ((cpip=10.10.2.103; cpip=<10.10.2.105; cpip++))
qm create $controlplane --name $cpname --memory 4096 --cores 4
qm set $controlplane --net0 bridge=vmbr2,firewall=1
qm set $controlplane --ipconfig0 ip=$cpip,netmask=$SVC_MASK,gw=$CLU_GW
qm importdisk $controlplane Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 $VMSTORAGE
qm set $controlplane --scsi0 $VMSTORAGE:$controlplane/vm-$controlplane-disk-0.raw,discard=on,size=64G
qm set $controlplane --ide0 cloudinit,format=qcow2
qm set $controlplane --boot c --bootdisk scsi0
qm set $controlplane --ciuser $ciuser --cipassword $cipassword
qm set $controlplane --sshkey $sshkey
done

# start services vm and give time to provision cloud-init parameters
qm start $SVC_VM
sleep 60
echo "Please wait while VM creation completes its initial boot provisioning"

# schedule commands to services VM to install reprequisites and establish xrdp access
pvesh create /nodes/$NODE/qemu/101/status/current --command "sudo dnf update -y && sudo dnf install -y epel-release && sudo dnf install -y xrdp tigervnc-server bind bind-utils named qemu-guest-agent.x86_64 httpd haproxy & sudo reboot"

# network portion follows, will probably make separate script for this eventually

tput setaf 3
echo "Once the services VM completes the install and reboot of prerequisites, use xrdp to enter the system and configure the necessary services for the cluster to function.

This includes modifying the named.conf to listen from your cluster interface's IP as well as $VMSTORAGE host (and changing the name servers the hell away from Google),

build zones (great templates for this section found at https://github.com/cragr/okd4_files), enable firewall, allow ports 53,8080,6443/tcp,22623/tcp, service http and https, and reload firewall,

Then set the DNS server on the interface that has access to the internet to 127.0.0.1 

Once DNS resolution tests good, enable haproxy and httpd (use 'sudo sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf' 'sudo setsebool -P httpd_read_user_content 1' to configure httpd) then start httpd and haproxy

If by this stage you get http code for Red Hat Apache, your services VM is prepared for cluster creation, and you can continue by typing entering 'yes', any other answers will end the script and the rest can be done by hand. (yes/no)"
read answer
if [ "$answer" = "yes" ]
then
fi
tput sgr0
