## Introduction

This repo contains the files needed to deploy VMs using the VirtualBox hypervisor to help with the development of a Kolla-Ansible based solution.

It creates the "Operator" VM from which Kolla-Ansible (and any custom wrapper solution) is run along with additional VMs that can then be used to deploy OpenStack to them using Kolla-Ansible.

Vagrant is used to make it easier to setup and configure the VMs in Virtualbox, including any networking needs to mimic advanced multiple network configurations for OpenStack.

Each VM is setup with the following:

* SSH setup such that the Operator VM can access the other VMs over SSH, enabling the Ansible scripts to operate on the other VMs.
* Docker is installed and started on each node ready to be used to run the Kolla based OpenStack control plane containers.

## Installation

### Install Virtualbox

```
sudo vi /etc/apt/sources.list
deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian bionic contrib

wget https://www.virtualbox.org/download/oracle_vbox_2016.asc
sudo apt-key add oracle_vbox_2016.asc

sudo apt-get update
sudo apt-get install -y virtualbox-6.1
```
### Install Vagrant

Download deb package from: [https://releases.hashicorp.com/vagrant/2.2.9/](https://releases.hashicorp.com/vagrant/2.2.9/)

Open with software manager to install.

Verify Vagrant is in path with:
```
   vagrant --version
```

#### Install Vagrant plugins

```
vagrant plugin install vagrant-hostmanager
```
This plugin is used to ensure every VM's /etc/hosts file contains entries for the other machines and thus can address each other when needed.
