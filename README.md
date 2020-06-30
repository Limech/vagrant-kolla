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
# Go in operator and manually install Kolla
vagrant ssh operator

sudo apt-get update
sudo apt-get install -y python-dev libffi-dev gcc libssl-dev python-selinux python-setuptools

sudo apt-get install -y python-virtualenv
mkdir kolla-ansible-venv
virtualenv ~/kolla-ansible-venv/
source ~/kolla-ansible-venv/bin/activate

pip install -U pip
pip install 'ansible<2.10'
pip install kolla-ansible

sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
git clone https://github.com/Limech/docker-kolla-ansible.git
cp docker-kolla-ansible/kolla/* /etc/kolla/
cp docker-kolla-ansible/inventory/multinode .

sudo mkdir /etc/ansible
sudo vi /etc/ansible/ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100

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
ansible -i multinode all -m ping

kolla-genpwd

## Populate private registry with all images.
kolla-ansible -i ./multinode bootstrap-servers

## Ensure docker_registry is not set in /etc/kolla/globals.yaml
kolla-ansible pull
docker images | grep kolla | grep -v local | awk '{print $1,$2}' | while read -r image tag; do
    docker tag ${image}:${tag} operator:5000/${image}:${tag}
    docker push operator:5000/${image}:${tag}
done
## Ensure to set the docker_registry back to operator:5000
## before running next commands.


kolla-ansible -i ./multinode prechecks
kolla-ansible -i ./multinode deploy

# Possible MariaDB sync issue across multiple controllers.
# Run mariadb-recovery and deploy again.
kolla-ansible -i ./multinode mariadb-recovery

```

# Use OpenStack
```bash
## Command line has issues
pip install python-openstackclient
kolla-ansible -i ./multinode post-deploy
. /etc/kolla/admin-openrc.sh

# Get admin password
cat /etc/kolla/passwords.yml | grep keystone_admin
# Open Horizon UI, username 'admin', password above.
http://{control01-ip}
```