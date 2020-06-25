# -*- mode: ruby -*-
# vi: set ft=ruby :

require "ipaddr"

# Check for required plugin(s)
['vagrant-hostmanager'].each do |plugin|
  unless Vagrant.has_plugin?(plugin)
    raise "#{plugin} plugin not found. Please install it via 'vagrant plugin install #{plugin}'"
  end
end

class VagrantConfigMissing < StandardError
end

vagrant_dir = File.expand_path(File.dirname(__FILE__))

# Vagrantfile.custom contains user customization for the Vagrantfile
# You shouldn't have to edit the Vagrantfile, ever.
if File.exists?(File.join(vagrant_dir, 'Vagrantfile.custom'))
  eval(IO.read(File.join(vagrant_dir, 'Vagrantfile.custom')), binding)
end

# Either libvirt or virtualbox
PROVIDER ||= "virtualbox"
# Either centos or ubuntu
DISTRO ||= "ubuntu"

# Provisioning other boxes than the default ones may therefore
# require changes to bootstrap.sh.
PROVISION_SCRIPT ||= "bootstrap.sh"

# The bootstrap.sh provisioning script requires CentOS or Ubuntu; see below
# for the supported versions for each provider.

PROVIDER_DEFAULTS ||= {
  libvirt: {
    centos: {
      base_image: "centos/7",
      bridge_interface: "virbr0",
      sync_method: "nfs",
      username: "vagrant"
    }
  },
  virtualbox: {
    centos: {
      base_image: "centos/7",
      bridge_interface: "wlp3s0b1",
      sync_method: "virtualbox",
      username: "vagrant"
    },
    ubuntu: {
      base_image: "ubuntu/bionic64",
      bridge_interface: "wlp3s0b1",
      sync_method: "virtualbox",
      username: "ubuntu"
    }
  }
}

# Whether to do Multi-node or All-in-One deployment
#MULTINODE = false unless self.class.const_defined?(:MULTINODE)
MULTINODE = true

# The following is only used when deploying in Multi-nodes
NUMBER_OF_CONTROL_NODES ||= 3
NUMBER_OF_COMPUTE_NODES ||= 1
NUMBER_OF_STORAGE_NODES ||= 3
NUMBER_OF_NETWORK_NODES ||= 1
NUMBER_OF_MONITOR_NODES ||= 1

NODE_SETTINGS ||= {
  aio: {
    cpus: 4,
    memory: 4096
  },
  operator: {
    cpus: 1,
    memory: 1024
  },
  control: {
    cpus: 1,
    memory: 2048
  },
  compute: {
    cpus: 1,
    memory: 1024
  },
  storage: {
    cpus: 1,
    memory: 1024
  },
  network: {
    cpus: 1,
    memory: 1024
  },
  monitor: {
    cpus: 1,
    memory: 1024
  }
}

# Configure a new SSH key and config so the operator is able to connect with
# the other cluster nodes.
unless File.file?(File.join(vagrant_dir, 'vagrantkey'))
  system("ssh-keygen -f #{File.join(vagrant_dir, 'vagrantkey')} -N '' -C this-is-vagrant")
end

def get_default(setting)
  PROVIDER_DEFAULTS[PROVIDER.to_sym][DISTRO.to_sym][setting]
rescue
  raise VagrantConfigMissing,
    "Missing configuration for PROVIDER_DEFAULTS[#{PROVIDER}][#{DISTRO}][#{setting}]"
end

def get_setting(node, setting)
  NODE_SETTINGS[node][setting]
rescue
  raise VagrantConfigMissing,
    "Missing configuration for NODE_SETTINGS[#{node}][#{setting}]"
end

def configure_wifi_vbox_networking(vm)
  # Even if adapters 1 & 2 don't need to be modified, if the order is to be
  # maintained, some modification has to be done to them. This will maintain
  # the association inside the guest OS: NIC1 -> eth0, NIC2 -> eth1, NIC3 ->
  # eht2. The modifications for adapters 1 & 2 only change optional properties.
  # Adapter 3 is enabled and connected to the NAT-Network named "OSNetwork",
  # while also changing its optional properties. Since adapter 3 is used by
  # Neutron for the external network, promiscuous mode is set to "allow-all".
  # Also, use virtio as the adapter type, for better performance.
  vm.customize ["modifyvm", :id, "--nictype1", "virtio"]
  vm.customize ["modifyvm", :id, "--cableconnected1", "on"]
  vm.customize ["modifyvm", :id, "--nicpromisc2", "deny"]
  vm.customize ["modifyvm", :id, "--nictype2", "virtio"]
  vm.customize ["modifyvm", :id, "--cableconnected2", "on"]
  vm.customize ["modifyvm", :id, "--nic3", "natnetwork"]
  vm.customize ["modifyvm", :id, "--nat-network3", "OSNetwork"]
  vm.customize ["modifyvm", :id, "--nicpromisc3", "allow-all"]
  vm.customize ["modifyvm", :id, "--nictype3", "virtio"]
  vm.customize ["modifyvm", :id, "--cableconnected3", "on"]
end

Vagrant.configure(2) do |config|


  config.vm.box = get_default(:base_image)

  # these may change depending on the image
  username = get_default(:username)
  user_home = "/home/#{username}"
  vagrant_shared_folder = "#{user_home}/sync"

  # Next to the hostonly NAT-network there is a host-only network with all
  # nodes attached. Plus, each node receives a 3rd adapter connected to the
  # outside public network.
  config.vm.network "private_network", type: "dhcp"

  my_privatekey = File.read(File.join(vagrant_dir, "vagrantkey"))
  my_publickey = File.read(File.join(vagrant_dir, "vagrantkey.pub"))

  config.vm.provision :shell, inline: <<-EOS
    mkdir -p /root/.ssh
    echo '#{my_privatekey}' > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    echo '#{my_publickey}' > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo '#{my_publickey}' > /root/.ssh/id_rsa.pub
    chmod 644 /root/.ssh/id_rsa.pub
    mkdir -p #{user_home}/.ssh
    echo '#{my_privatekey}' >> #{user_home}/.ssh/id_rsa
    chmod 600 #{user_home}/.ssh/*
    echo 'Host *' > #{user_home}/.ssh/config
    echo StrictHostKeyChecking no >> #{user_home}/.ssh/config
    chown -R #{username} #{user_home}/.ssh
  EOS

  config.hostmanager.enabled = true
  # Make sure hostmanager picks IP address of eth1
  config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
    case PROVIDER
    when "libvirt"
      if vm.name
        `python newest_dhcp_lease.py #{vm.name}`.chop
      end
    when "virtualbox"
      if vm.id
        `VBoxManage guestproperty get #{vm.id} "/VirtualBox/GuestInfo/Net/1/V4/IP"`.split()[1]
      end
    end
  end

  # The operator controls the deployment
  config.vm.define "operator", primary: true do |admin|
    admin.vm.hostname = "operator.local"
    admin.vm.provision :shell, path: PROVISION_SCRIPT, args: "operator #{MULTINODE ? 'multinode' : 'aio'} #{NUMBER_OF_COMPUTE_NODES} #{NUMBER_OF_STORAGE_NODES} #{NUMBER_OF_NETWORK_NODES} #{NUMBER_OF_CONTROL_NODES} #{NUMBER_OF_MONITOR_NODES}"
    admin.vm.synced_folder File.join(vagrant_dir, 'storage', 'operator'), "/data/host", create:"True", type: get_default(:sync_method)
    admin.vm.synced_folder File.join(vagrant_dir, 'storage', 'shared'), "/data/shared", create:"True", type: get_default(:sync_method)
    admin.vm.synced_folder ".", vagrant_shared_folder, disabled: true
    admin.vm.provider PROVIDER do |vm|
      vm.memory = MULTINODE ? get_setting(:operator, :memory) : get_setting(:aio, :memory)
      vm.cpus = MULTINODE ? get_setting(:operator, :cpus) : get_setting(:aio, :cpus)
      if PROVIDER == "libvirt"
        vm.graphics_ip = GRAPHICSIP
      end
      
    end
    admin.hostmanager.aliases = "operator"
  end

  if MULTINODE
    ['compute', 'storage', 'network', 'control'].each do |node_type|
      (1..self.class.const_get("NUMBER_OF_#{node_type.upcase}_NODES")).each do |i|
        hostname = "#{node_type}0#{i}"
        config.vm.define hostname do |node|
          node.vm.hostname = "#{hostname}.local"
          node.vm.provision :shell, path: PROVISION_SCRIPT, args: "#{hostname} multinode #{NUMBER_OF_COMPUTE_NODES} #{NUMBER_OF_STORAGE_NODES} #{NUMBER_OF_NETWORK_NODES} #{NUMBER_OF_CONTROL_NODES} #{NUMBER_OF_MONITOR_NODES}"
          node.vm.synced_folder File.join(vagrant_dir, 'storage', node_type), "/data/host", create:"True", type: get_default(:sync_method)
          node.vm.synced_folder File.join(vagrant_dir, 'storage', 'shared'), "/data/shared", create:"True", type: get_default(:sync_method)
          node.vm.synced_folder ".", vagrant_shared_folder, disabled: true
          node.vm.provider PROVIDER do |vm|
            vm.memory = get_setting(node_type.to_sym, :memory)
            vm.cpus = get_setting(node_type.to_sym, :cpus)
            if PROVIDER == "libvirt"
              vm.graphics_ip = GRAPHICSIP
            end
            
          end
          node.hostmanager.aliases = hostname
        end
      end
    end
  end

end
