#!/bin/bash

## This script is what starts turning all this crap into an OKD cluster
## This should be run from inside your Services VM

########## do not trust the links for the okd4 version used in this template, well, unless you want an older vesion

## These are in the main script now, keep commented out to prevent double work. If you used the main script, all the template files are 
# mkdir ./okd4
# cd ./okd4
# wget https://github.com/okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
# wget https://github.com/okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-install-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
# tar -xzvf openshift*
# sudo mv kubectl oc openshift-install /usr/local/bin/

cp ~/install_dir/install-config.yaml ~/install_dir/install-config.yaml.bak
openshift-install create manifests --dir=install_dir/
sed -i 's/mastersSchedulable: true/mastersSchedulable: False/' install_dir/manifests/cluster-scheduler-02-config.yml
openshift-install create ignition-configs --dir=install_dir/
# only do this once per install_dir, this creates hidden files and super-hidden files that are used by the installer, and don't usually go away unless the whole folder is deleted.

# send ignition files to proper web server =  2 methods. I had problems getting the Services VM to properly host the files for this, so you can also upload the files to a TFTP server
# there is a script labeled proxmox_ignition_script_bypass that will work for this purpose if you use tftp instead

echo "Enter 1 to send ignition files to Services VM HTTP server, or 2 to upload files to a TFTP server created with the proxmox ignition bypass script"
read CHOICE

if [ $CHOICE == 1 ]
then 
    echo "You chose 1. Running command series 1..."
    sudo mkdir /var/www/html/okd4
    sudo cp -R install_dir/* /var/www/html/okd4/
        wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz
    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz.sig
    mv fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz /var/www/html/okd4/fcos.qcow2.xz
    mv fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz /var/www/html/okd4/fcos.qcow2.xz.sig
    sudo chown -R apache: /var/www/html/
    sudo chmod -R 755 /var/www/html/
    echo "Your ignition image and profiles are prepared on your Services VM HTTP server, now you can boot your bootstrap VM, and give it the following boot commands (press TAB on boot menu) /n /n 
    coreos.inst.install_dev=/dev/sda /n
    coreos.inst.image_url=http://$SVC_CLU_IP:8080/okd4/fcos.raw.xz /n
    coreos.inst.ignition_url=http://$SVC_CLU_IP:8080/okd4/bootstrap.ign"
elif [ $CHOICE == 2 ]
then
    echo "You chose 2. Please enter the IP address you want to upload to:"
    read TFTP
    echo "Adding IP address to tftp server..."
    #add IP address to tftp server
    echo "Uploading files to $TFTP..."
    tftp put ~/install_dir/*   $TFTP
    echo "Now downloading and preparing FCOS images to send to TFTP server"
    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz
    wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230205.3.0/x86_64/fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz.sig
    mv fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz fcos.qcow2.xz
    mv fedora-coreos-37.20230205.3.0-qemu.x86_64.qcow2.xz fcos.qcow2.xz.sig
    tftp put fcos.qcow2* $TFTP
        echo "Your ignition image and profiles are prepared on your cluster network's TFTP server, now you can boot your bootstrap VM, and give it the following boot commands (press TAB on boot menu) /n /n 
    coreos.inst.install_dev=/dev/sda /n
    coreos.inst.image_url=tftp://$TFTP/fcos.raw.xz /n
    coreos.inst.ignition_url=tftp://$TFTP/bootstrap.ign"
else
    echo "Invalid choice."
fi

echo "Don't forget to add 'export KUBECONFIG=~/install_dir/auth/kubeconfig' to your path to run commands from the API server. At this stage, the scriptable portion of the OKD4 install is complete. Once your bootstrap VM is detected by the API server, you can start the control plane and worker nodes one at a time, /n /n
Similar to the bootstrap VM, enter the bootloader commands except changing the ignition file from boostrap.ign to master.ign and worker.ign respectively. /n
You can monitor the API server bootstrapping with the command 'openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info' which can take up to 30 minutes and will tell you when it is safe to remove your bootstrap resources by editing the services VM haproxy.cfg and commenting out the bootstrap node and reloading haproxy"
