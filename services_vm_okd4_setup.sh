#!/bin/bash

## This script is what starts turning all this crap into an OKD cluster
## This should be run from inside your Services VM

########## do not trust the links for the okd4 version used in this template, well, unless you want an older vesion

mkdir ./okd4
cd ./okd4
wget https://github.com/okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
wget https://github.com/okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-install-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
tar -xzvf openshift*
sudo mv kubectl oc openshift-install /usr/local/bin/
