#!/bin/bash

# sample series of scripts leading up to shorter deployment cycle of OKD4 nodes.

# Variables to set if you actually want to use this script as-is

# Change FCOS & RL8 image urls to desired versions
export FCOS="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz"
export RL8="https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
# proxmox node name must be set regardless if standalone or clustered

#proxmox variables
export NODE="pve"
export VMSTORAGE="local"
export SVC_VM="101"
export BOOTSTRAP_VM="500"
export CP_VM_START="501"
export CP_VM_END="503"
export WKR_VM_START="510"
export WKR_VM_END="511"
#services VM variables
export SVC_PUB_IP="10.10.1.100"
export SVC_CLU_IP="10.10.2.102"
export SVC_MASK="255.255.255.0"
export SVC_GW="10.10.1.1"
export CLU_GW="10.10.2.1"
#named subnet used for .local and db file
export NAMEDBSUB="10.10.2"
export CLU_SUBNET="10.10.2.0/24"
#nodes variables
##node IP ranges set number of nodes for each type, and should match number of VM IDs set above
export BOOTSTRAP_IP="10.10.2.101"
export CP_IP_START="10.10.2.103"
export CP_IP_END="10.10.2.105"
export WK_IP_START="10.10.2.120"
export WK_IP_END="10.10.2.121"

#global credentials variables
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
tput setaf 2
echo "Now creating services VM using ID $SVC_VM"
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
echo "Now creating bootstrap VM using ID $BOOTSTRAP_VM"
qm create $BOOTSTRAP_VM --name okd4-bootstrap --memory 2048 --cores 2
qm set $BOOTSTRAP_VM --net1 bridge=vmbr2,firewall=1
qm set $BOOTSTRAP_VM --ipconfig1 ip=$BOOTSTRAP_IP,netmask=$SVC_MASK
qm importdisk $BOOTSTRAP_VM fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz $VMSTORAGE
qm set $BOOTSTRAP_VM--scsi0 $VMSTORAGE:$BOOTSTRAP_VM/vm-$BOOTSTRAP_VM-disk-0.raw,discard=on,size=64G
qm set $BOOTSTRAP_VM --ide0 cloudinit,format=qcow2
qm set $BOOTSTRAP_VM --boot c --bootdisk scsi0
qm set $BOOTSTRAP_VM --ciuser $ciuser --cipassword $cipassword
qm set $BOOTSTRAP_VM --sshkey $sshkey

## Container VM provisioning - CoreOS VMs act as all nodes in the cluster, OKD minimum requirements are 3 control planes and at least 2 workers. Creating and adding to a cluster requires a bootstrap VM, which can be shutdown until needed

##   Each of the following segments require filling in a number of ID of the final node to be created
echo "Now creating control-planes using IDs between $CP_VM_START and $CP_VM_END"
for ((controlplane=$CP_VM_START; controlplane=<$CP_VM_END; controlplane++))
for ((cpname=okd-control-plane-1; okd-control-plane-<=3; cpname++))
for ((cpip=$CP_IP_START; cpip=<$CP_IP_END; cpip++))
qm create $controlplane --name $cpname --memory 4096 --cores 4
qm set $controlplane --net0 bridge=vmbr2,firewall=1
qm set $controlplane --ipconfig0 ip=$cpip,netmask=$SVC_MASK,gw=$CLU_GW
qm importdisk $controlplane fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz $VMSTORAGE
qm set $controlplane --scsi0 $VMSTORAGE:$controlplane/vm-$controlplane-disk-0.raw,discard=on,size=64G
qm set $controlplane --ide0 cloudinit,format=qcow2
qm set $controlplane --boot c --bootdisk scsi0
qm set $controlplane --ciuser $ciuser --cipassword $cipassword
qm set $controlplane --sshkey $sshkey
done
echo "Now creating workers using IDs between $WKR_VM_START and $WKR_VM_END"
for ((worker=$WKR_VM_START; worker=<$WKR_VM_END; worker++))
for ((wkname=okd-worker-1; okd-worker-<=3; wkname++))
for ((wkip=$WK_IP_START; wkip=<$WK_IP_END; wkip++))
qm create $worker --name $wkname --memory 4096 --cores 4
qm set $worker --net0 bridge=vmbr2,firewall=1
qm set $worker --ipconfig0 ip=$wkip,netmask=$SVC_MASK,gw=$CLU_GW
qm importdisk $worker fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz $VMSTORAGE
qm set $worker --scsi0 $VMSTORAGE:$controlplane/vm-$controlplane-disk-0.raw,discard=on,size=64G
qm set $worker --ide0 cloudinit,format=qcow2
qm set $worker --boot c --bootdisk scsi0
qm set $worker --ciuser $ciuser --cipassword $cipassword
qm set $worker --sshkey $sshkey
done

# start services vm and give time to provision cloud-init parameters
qm start $SVC_VM
sleep 60
echo "Please wait while VM creation completes its initial boot provisioning, software installation, and updates"

# schedule commands to services VM to install reprequisites and establish xrdp access
echo "Your system will reboot once after installation is complete, and the script will continue"
pvesh create /nodes/$NODE/qemu/$SVC_VM/status/current --command "sudo nmcli con mod ens18 ipv4.addresses $SVC_PUB_IP/$SVC_MASK ipv4.gateway $SVC_GW && sudo dnf update -y && sudo dnf install -y openssh-server && sudo systemctl enable --now sshd && sudo reboot"
tput setaf 3

ssh $sshuser@$SVC_PUB_IP << EOF
sudo dnf install -y epel-release
sudo dnf install -y xrdp tigervnc-server bind bind-utils named qemu-guest-agent.x86_64 httpd haproxy 
EOF

### configure config files for required services on Services VM and send to the appropriate locations
# Some performance and stability increases can be had from uncommenting "listen-on-v6" for the cluster, but can present a threat to security if done here
# If you want to use IPv6, wait until you enter the system and update /etc/named.conf for the cluster interface's ipv6 address
## !!! I have somwhat of an (read:no) idea if this will work as written in the shell script, so if I am just overestimating the power of bash, you can copypasta the templates and use scp to send them to your Services VM
## If you do have to copy the templates over manually, my attempts to automate the IP addresses and Subnet entries will need to be manually edited
namedconf:
"//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//
// See the BIND Administrator's Reference Manual (ARM) for details about the
// configuration located in /usr/share/doc/bind-{version}/Bv9ARM.html

options {
	listen-on port 53 { 127.0.0.1; $SVC_CLU_IP; };
#	listen-on-v6 port 53 { ::1; };
	directory 	"/var/named";
	dump-file 	"/var/named/data/cache_dump.db";
	statistics-file "/var/named/data/named_stats.txt";
	memstatistics-file "/var/named/data/named_mem_stats.txt";
	recursing-file  "/var/named/data/named.recursing";
	secroots-file   "/var/named/data/named.secroots";
	allow-query     { localhost; $SVC_CLU_SUBNET; };

	/* 
	 - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
	 - If you are building a RECURSIVE (caching) DNS server, you need to enable 
	   recursion. 
	 - If your recursive DNS server has a public IP address, you MUST enable access 
	   control to limit queries to your legitimate users. Failing to do so will
	   cause your server to become part of large scale DNS amplification 
	   attacks. Implementing BCP38 within your network would greatly
	   reduce such attack surface 
	*/
	recursion yes;
	
	forwarders {
                9.9.9.11;
                1.1.1.1;
        };

	dnssec-enable yes;
	dnssec-validation yes;

	/* Path to ISC DLV key */
	bindkeys-file "/etc/named.root.key";

	managed-keys-directory "/var/named/dynamic";

	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
	type hint;
	file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
include "/etc/named/named.conf.local";
" 
cat namedconf > /tmp/named.conf

scp /tmp/named.conf $ciuser@$SVC_VM:/etc/named.conf

namedconflocal:


zone "okd.local" {
    type master;
    file "/etc/named/zones/db.okd.local"; # zone file path
};

zone "$NAMEDBSUB.in-addr.arpa" {
    type master;
    file "/etc/named/zones/db.$NAMEDBSUB";  ## $CLU_SUBNET subnet
};

cat namedconf > /tmp/named.conf.local
scp /tmp/named.conf.local $ciuser@$SVC_PUB_IP:/etc/named.conf.local
ssh $ciuser@$SVC_PUB_IP -t mkdir /etc/named/zones

db.$NAMEDBSUB:

$TTL    604800
@       IN      SOA     okd4-services.okd.local. admin.okd.local. (
                  6     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800     ; Negative Cache TTL
)

; name servers - NS records
    IN      NS      okd4-services.okd.local.

; name servers - PTR records
$(echo $SVC_CLU_IP | cut -c -3)    IN    PTR    okd4-services.okd.local.
# use variables to set domain PTR
; OpenShift Container Platform Cluster - PTR records
$(echo $BOOTSTRAP_IP | cut -c -3)    IN    PTR    okd4-bootstrap.lab.okd.local.
$(echo $cpip | cut -d "," -f 1 | cut -c -3)    IN    PTR    okd4-control-plane-1.lab.okd.local.
$(echo $cpip | cut -d "," -f 2 | cut -c -3)    IN    PTR    okd4-control-plane-2.lab.okd.local.
$(echo $cpip | cut -d "," -f 3 | cut -c -3)    IN    PTR    okd4-control-plane-3.lab.okd.local.
$(echo $wkip | cut -d "," -f 1 | cut -c -3)    IN    PTR    okd4-compute-1.lab.okd.local.
$(echo $wkip | cut -d "," -f 2 | cut -c -3)    IN    PTR    okd4-compute-2.lab.okd.local.
$(echo $SVC_CLU_IP | cut -c -3)    IN    PTR    api.lab.okd.local.
$(echo $SVC_CLU_IP | cut -c -3)    IN    PTR    api-int.lab.okd.local.
cat db.$NAMEDBSUB > /tmp/db.$NAMEDBSUB
scp /tmp/db* $ciuser@$SVC_PUB_IP:/etc/named/zones

haproxy.cfg:

# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          300s
    timeout server          300s
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 20000

listen stats
    bind :9000
    mode http
    stats enable
    stats uri /

frontend okd4_k8s_api_fe
    bind :6443
    default_backend okd4_k8s_api_be
    mode tcp
    option tcplog

backend okd4_k8s_api_be
    balance source
    mode tcp
    server      okd4-bootstrap $BOOTSTRAP_IP:6443 check
    server      okd4-control-plane-1 $(echo $cpip | cut -d "," -f 1):6443 check
    server      okd4-control-plane-2 $(echo $cpip | cut -d "," -f 2):6443 check
    server      okd4-control-plane-3 $(echo $cpip | cut -d "," -f 3):6443 check

frontend okd4_machine_config_server_fe
    bind :22623
    default_backend okd4_machine_config_server_be
    mode tcp
    option tcplog

backend okd4_machine_config_server_be
    balance source
    mode tcp
    server      okd4-bootstrap $BOOTSTRAP_IP check
    server      okd4-control-plane-1 $(echo $cpip | cut -d "," -f 1):22623 check
    server      okd4-control-plane-2 $(echo $cpip | cut -d "," -f 2):22623 check
    server      okd4-control-plane-3 $(echo $cpip | cut -d "," -f 3):22623 check

frontend okd4_http_ingress_traffic_fe
    bind :80
    default_backend okd4_http_ingress_traffic_be
    mode tcp
    option tcplog

backend okd4_http_ingress_traffic_be
    balance sourcelittle
    option tcplog

backend okd4_https_ingress_traffic_be
    balance source
    mode tcp
    server      okd4-compute-1 $(echo $wkip | cut -d "," -f 1):443 check
    server      okd4-compute-2 $(echo $wkip | cut -d "," -f 2):443 check

cat haproxy.cfg > /tmp/haproxy.cfg
scp /tmp/haproxy.cfg $ciuser@$SVC_PUB_IP:/etc/haproxy/haproxy.cfg

ssh $sshuser@$SVC_PUB_IP << EOF
sudo systemctl enable firewalld
sudo firewall-cmd --zone=public --add-port=53/tcp --permanent --interface=eth1
sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent --interface=eth1
sudo firewall-cmd --zone=public --add-port=6443/tcp --permanent --interface=eth1
sudo firewall-cmd --zone=public --add-port=22623/tcp --permanent --interface=eth1
sudo firewall-cmd --reload
sudo sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf
sudo setsebool -P httpd_read_user_content 1
sudo systemctl enable httpd
sudo systemctl start httpd
EOF

echo "test your web server function by running curl on your service VM IP address (remember to use port 8080) and enter yes, or anything else to wait and try again"
read answer
if [ "$answer" != "yes" ]; then
    start_line=361
    while true; do
        <run script from line $start_line>
    done
fi
tput sgr0
done


echo "Once the services VM completes the install and reboot of prerequisites, use xrdp to enter the system and configure the necessary services for the cluster to function."

##sections where scripting is nearly done
# build  named zones, enable firewall, allow ports 53,8080,6443/tcp,22623/tcp, service http and https, and reload firewall,

#next sections to script
#Set the DNS server on the interface that has access to the internet to 127.0.0.1 
#Once DNS resolution tests good, enable haproxy and httpd (use 'sudo sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf' 'sudo setsebool -P httpd_read_user_content 1' to configure httpd) then start httpd and haproxy


echo "If by this stage you get http code for Red Hat Apache, your services VM is prepared for cluster creation, and this is the end of the provisioning script /n /n
there will be a separate script written soon for cluster buildout"

