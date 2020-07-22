# Introduction

This repo contains the files needed to deploy VMs using the VirtualBox hypervisor to help with the development of a Kolla-Ansible based solution.

It creates the "Operator" VM from which Kolla-Ansible (and any custom wrapper solution) is run along with additional VMs that can then be used to deploy OpenStack to them using Kolla-Ansible.

Vagrant is used to make it easier to setup and configure the VMs in Virtualbox, including any networking needs to mimic advanced multiple network configurations for OpenStack.

Each VM is setup with the following:

* SSH setup such that the Operator VM can access the other VMs over SSH, enabling the Ansible scripts to operate on the other VMs.
* Docker is installed and started on each node ready to be used to run the Kolla based OpenStack control plane containers.

# Installation

## Install Virtualbox

```
sudo vi /etc/apt/sources.list
deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian bionic contrib

wget https://www.virtualbox.org/download/oracle_vbox_2016.asc
sudo apt-key add oracle_vbox_2016.asc

sudo apt-get update
sudo apt-get install -y virtualbox-6.1
```
## Install Vagrant

Download deb package from: [https://releases.hashicorp.com/vagrant/2.2.9/](https://releases.hashicorp.com/vagrant/2.2.9/)

Open with software manager to install.

Verify Vagrant is in path with:
```bash
   vagrant --version
```

### Install Vagrant plugins

```bash
vagrant plugin install vagrant-hostmanager
```
This plugin is used to ensure every VM's /etc/hosts file contains entries for the other machines and thus can address each other when needed.

## Clone this repo

```bash
git clone https://github.com/Limech/vagrant-kolla.git
cd vagrant-kolla
```

# Running VMs

```bash
vagrant up
```

# Install Kolla in operator node

```bash
vagrant ssh operator


git clone https://github.com/Limech/docker-kolla-ansible.git
cd docker-kolla-ansible
git checkout test
## colla on purpose due to registry populating that searches
## for all images 'kolla'
sudo docker build --rm -t kolla:latest .

# Ensure all nodes can be reached from operator.
sudo cp /home/ubuntu/.ssh/id_rsa /home/vagrant/.ssh
sudo chown vagrant:vagrant ~/.ssh/id_rsa
ssh root@control01  # Log in to each and accept the host key..
# for some reason ansible hangs on it even if the .cfg says to ignore.

## For each node
# Verify /etc/hosts entries to other VMs are ok.
# Ensure no entry for VM points to 127.0.0.1
# Otherwise, RabbitMQ will fail prechecks

# This should successfully ping localhost and control01 node
sudo ./kolla-ansible.sh "ansible -i multinode all -m ping"

cp kolla/passwords-empty.yml kolla/passwords.yml
sudo ./kolla-ansible.sh kolla-genpwd

sudo ./start-registry.sh

# Optional, create VM snapshots.
exit
## Turn on nested hypervisor in compute node(s)
vagrant snapshot push
vagrant ssh operator
cd docker-kolla-ansible

# This will ensure docker is setup on nodes with private registry set.
sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode bootstrap-servers"

## Install ceph??
## Copy files for OpenStack
exit
vagrant ssh storage01
sudo mkdir /data/shared/ceph/
sudo cp -r /etc/ceph/* /data/shared/ceph/
exit
vagrant ssh operator
cp /data/shared/ceph/ceph.conf kolla/config/glance/
cp /data/shared/ceph/ceph.client.glance.keyring kolla/config/glance/
mkdir kolla/config/cinder/cinder-backup
mkdir kolla/config/cinder/cinder-volume
cp /data/shared/ceph/ceph.conf kolla/config/cinder/
cp /data/shared/ceph/ceph.client.cinder.keyring kolla/config/cinder/cinder-backup/
cp /data/shared/ceph/ceph.client.cinder-backup.keyring kolla/config/cinder/cinder-backup/
cp /data/shared/ceph/ceph.client.cinder.keyring kolla/config/cinder/cinder-volume/
mkdir kolla/config/nova
cp /data/shared/ceph/ceph.conf kolla/config/nova/
cp /data/shared/ceph/ceph.client.cinder.keyring kolla/config/nova/
cp kolla/config/nova/ceph.client.cinder.keyring kolla/config/nova/ceph.client.nova.keyring

## Force pull all images to nodes using local registry.
sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode pull"

sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode prechecks"
sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode deploy"

# Possible MariaDB sync issue across multiple controllers.
# Run mariadb-recovery and deploy again.
sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode mariadb_recovery"

sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode post-deploy"
sudo ./kolla-ansible.sh "kolla-ansible -i ./multinode check"
```

# Use OpenStack
```bash
sudo apt install -y python3 python3-pip python3-venv
mkdir ~/ostack
python3 -m venv ~/ostack
source ~/ostack/bin/activate
python3 -m pip install python-openstackclient
openstack --version

. kolla/admin-openrc.sh
openstack user list

# Get admin password
cat kolla/passwords.yml | grep keystone_admin
# Open Horizon UI, username 'admin', password above.
http://{control01-ip}

# Get image
wget https://cloud-images.ubuntu.com/bionic/20200702/bionic-server-cloudimg-amd64.img
wget http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img

openstack image create \
    --container-format bare \
    --disk-format qcow2 \
    --file bionic-server-cloudimg-amd64.img \
    Ubuntu-18.04-x86_64

openstack image create \
    --container-format bare \
    --disk-format qcow2 \
    --file cirros-0.5.1-x86_64-disk.img\
    cirros

openstack image set --public 2a28debc-3b63-48f4-bffe-2e63834862a6
openstack image set --protected 2a28debc-3b63-48f4-bffe-2e63834862a6

# Create flavor - 2GB RAM, 8GB HDD for Ubuntu bionic.
# Create security group enable SSH / ICMP
# Create external network
# Create external router
# Create floating-ip range
# Connect router to external network
# Create VM
# Allocate floating IP to VM
# SSH into VM using floating IP
```