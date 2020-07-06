#!/usr/bin/env bash
#
# Bootstrap script to configure all nodes.
#
# This script is intended to be used by vagrant to provision nodes.
# To use it, set it as 'PROVISION_SCRIPT' inside your Vagrantfile.custom.
# You can use Vagrantfile.custom.example as a template for this.

VM=$1
MODE=$2
NUMBER_OF_COMPUTE_NODES=$3
NUMBER_OF_STORAGE_NODES=$4
NUMBER_OF_NETWORK_NODES=$5
NUMBER_OF_CONTROL_NODES=$6
NUMBER_OF_MONITOR_NODES=$7

export http_proxy=
export https_proxy=

if [ "$MODE" == 'aio' ]; then
    # Run registry on port 4000 since it may collide with keystone when doing AIO
    REGISTRY_PORT=4000
else
    REGISTRY_PORT=5000
fi
REGISTRY_URL="operator.local"
REGISTRY=${REGISTRY_URL}:${REGISTRY_PORT}
ADMIN_PROTOCOL="http"

function _ensure_lsb_release {
    if type lsb_release >/dev/null 2>&1; then
        return
    fi

    if type apt-get >/dev/null 2>&1; then
        apt-get -y install lsb-release
    elif type yum >/dev/null 2>&1; then
        yum -y install redhat-lsb-core
    fi
}

function _is_distro {
    if [[ -z "$DISTRO" ]]; then
        _ensure_lsb_release
        DISTRO=$(lsb_release -si)
    fi

    [[ "$DISTRO" == "$1" ]]
}

function is_ubuntu {
    _is_distro "Ubuntu"
}

function is_centos {
    _is_distro "CentOS"
}

# Install common packages and do some prepwork.
function prep_work {

    # This removes the fqdn from /etc/hosts's 127.0.0.1. This name.local will
    # resolve to the public IP instead of localhost.
    sed -i -r "s,^127\.0\.0\.1\s+.*,127\.0\.0\.1   localhost localhost.localdomain localhost4 localhost4.localdomain4," /etc/hosts

    if is_centos; then
        if [[ "$(systemctl is-enabled firewalld)" == "enabled" ]]; then
            systemctl stop firewalld
            systemctl disable firewalld
        fi
        yum -y install epel-release
        rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
        yum -y install MySQL-python vim-enhanced python-pip python-devel gcc openssl-devel libffi-devel libxml2-devel libxslt-devel
    elif is_ubuntu; then
        if [[ "$(systemctl is-enabled ufw)" == "enabled" ]]; then
            systemctl stop ufw
            systemctl disable ufw
        fi
        cat >/etc/apt/sources.list <<-EOF
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic main restricted 
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-updates main restricted
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic universe
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-updates universe
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic multiverse
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-updates multiverse
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-backports main restricted universe multiverse
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-security main restricted
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-security universe
deb http://192.168.7.237:8081/repository/ubuntu-bionic/ bionic-security multiverse
EOF
        apt-get update
        apt-get -y install python3-mysqldb python3-pip python3-dev build-essential libssl-dev libffi-dev libxml2-dev libxslt-dev
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi

    pip3 install --upgrade docker
}

# Do some cleanup after the installation of kolla
function cleanup {
    if is_centos; then
        yum clean all
    elif is_ubuntu; then
        apt-get clean
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi
}

# Install and configure a quick&dirty docker daemon.
function install_docker {
    if is_centos; then
        cat >/etc/yum.repos.d/docker.repo <<-EOF
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
        # Also upgrade device-mapper here because of:
        # https://github.com/docker/docker/issues/12108
        # Upgrade lvm2 to get device-mapper installed
        yum -y install docker-engine lvm2 device-mapper

        # Despite it shipping with /etc/sysconfig/docker, Docker is not configured to
        # load it from it's service file.
        sed -i -r "s|(ExecStart)=(.+)|\1=/usr/bin/docker daemon --insecure-registry ${REGISTRY} --registry-mirror=http://${REGISTRY}|" /usr/lib/systemd/system/docker.service
        sed -i 's|^MountFlags=.*|MountFlags=shared|' /usr/lib/systemd/system/docker.service

        usermod -aG docker vagrant
    elif is_ubuntu; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get -y install docker-ce docker-ce-cli containerd.io
        ##sed -i -r "s|(ExecStart)=(.+)|\1=/usr/bin/docker daemon --insecure-registry ${REGISTRY} --registry-mirror=http://${REGISTRY}|" /lib/systemd/system/docker.service
        echo "{ \"insecure-registries\" : [\"operator:4000\"], \"registry-mirrors\": [\"http://operator:4000\"] }" > /etc/docker/daemon.json
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi

    if [[ "${http_proxy}" != "" ]]; then
        mkdir -p /etc/systemd/system/docker.service.d
        cat >/etc/systemd/system/docker.service.d/http-proxy.conf <<-EOF
[Service]
Environment="HTTP_PROXY=${http_proxy}" "HTTPS_PROXY=${https_proxy}" "NO_PROXY=localhost,127.0.0.1,${REGISTRY_URL}"
EOF

        if [[ "$(grep http_ /etc/bashrc)" == "" ]]; then
            echo "export http_proxy=${http_proxy}" >> /etc/bashrc
            echo "export https_proxy=${https_proxy}" >> /etc/bashrc
        fi
    fi

    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
}


# Configure the operator node and install some additional packages.
function configure_operator {
    if is_centos; then
        yum -y install git mariadb
    elif is_ubuntu; then
        apt-get -y install git mariadb-client selinux-utils
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi

    pip install --upgrade "ansible>=2" python-openstackclient python-neutronclient tox


    # Set selinux to permissive
    if [[ "$(getenforce)" == "Enforcing" ]]; then
        sed -i -r "s,^SELINUX=.+$,SELINUX=permissive," /etc/selinux/config
        setenforce permissive
    fi


    # Make sure Ansible uses scp.
    cat > ~vagrant/.ansible.cfg <<EOF
[defaults]
forks=100
remote_user = root

[ssh_connection]
scp_if_ssh=True
EOF
    chown vagrant: ~vagrant/.ansible.cfg <<EOF
[libvirt]
virt_type = qemu
cpu_mode = none
EOF

    # Launch a local registry (and mirror) to speed up pulling images.
    if [[ ! $(docker ps -a -q -f name=registry) ]]; then
        docker run -d \
            --name registry \
            --restart=always \
            -p ${REGISTRY_PORT}:5000 \
            -e STANDALONE=True \
            -e MIRROR_SOURCE=https://registry-1.docker.io \
            -e MIRROR_SOURCE_INDEX=https://index.docker.io \
            -e STORAGE_PATH=/var/lib/registry \
            -v /data/host/registry-storage:/var/lib/registry \
            registry:2
    fi
}

prep_work

if [[ "$VM" == "operator" ]]; then
    configure_operator
    install_docker
fi

cleanup
