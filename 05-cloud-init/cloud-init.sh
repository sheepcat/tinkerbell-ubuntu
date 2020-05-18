#!/bin/bash

source functions.sh && init
set -o nounset


target="/mnt/target"
BASEURL='http://192.168.1.2/misc/osie/current'

mkdir -p $target
mount -t ext4 /dev/sda3 $target

ephemeral=/workflow/data.json
OS=$(jq -r .os "$ephemeral")


echo -e "${GREEN}#### Configuring cloud-init for Packet${NC}"
if [ -f $target/etc/cloud/cloud.cfg ]; then
	case ${OS} in
	centos* | rhel* | scientific*) repo_module=yum-add-repo ;;
	debian* | ubuntu*) repo_module=apt-configure ;;
	esac

	cat <<-EOF >$target/etc/cloud/cloud.cfg
		apt:
		  preserve_sources_list: true
		disable_root: 0
		package_reboot_if_required: false
		package_update: false
		package_upgrade: false
		hostname: kw-tf-worker
		bootcmd:
		 - echo 192.168.1.1 kw-tf-provisioner > /etc/hosts
		runcmd:
		 - touch /etc/cloud/cloud-init.disabled
		ssh_genkeytypes: ['rsa', 'dsa', 'ecdsa', 'ed25519']
		ssh_pwauth: True
		ssh_authorized_keys:
		 - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCiKZts/sKvjhuVC7iod0zSgYlfnH822HqFwkUzsObnKDZcbmv3+gnVHplLlBesK5USVCdOK2Qb4SkjCAeDcsj10ijJfkJlTo8HVKUx4OBXIfOAZyAIhoCgzXTwXReVPeg9uvhRhctiKM2DqXGCAA4ZrwRoXaZy3WntqUhr805XB3waTWXlkbgZEKc9I0G8mN7pI0afJYIjylhRvHad0fCR+zSHogJ/JUVm4+pcfAdP7UfckpBU74lIavm/lbyRBbN0d341GCRWjlO0RKnz9guxqywctuUI6UvOhBU301tckhXsOSfeyWPuzhPOc1xUpXOpPyY/izPpyIIBMSztPr0F root@kw-tf-provisioner
		cloud_init_modules:
		 - migrator
		 - bootcmd
		 - write-files
		 - growpart
		 - resizefs
		 - update_hostname
		 - update_etc_hosts
		 - users-groups
		 - rsyslog
		 - ssh
		cloud_config_modules:
		 - mounts
		 - locale
		 - set-passwords
		 ${repo_module:+- $repo_module}
		 - package-update-upgrade-install
		 - timezone
		 - puppet
		 - chef
		 - salt-minion
		 - mcollective
		 - runcmd
		cloud_final_modules:
		 - phone-home
		 - scripts-per-once
		 - scripts-per-boot
		 - scripts-per-instance
		 - scripts-user
		 - ssh-authkey-fingerprints
		 - keys-to-console
		 - final-message
	EOF
	echo "Disabling cloud-init based network config via cloud.cfg.d include"
	echo "network: {config: disabled}" >$target/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
	echo "WARNING: Removing /var/lib/cloud/*"
	rm -rf $target/var/lib/cloud/*
else
	echo "Cloud-init post-install -  default cloud.cfg does not exist!"
fi

if [ -f $target/etc/init/cloud-init-nonet.conf ]; then
	sed -i 's/dowait 120/dowait 1/g' $target/etc/init/cloud-init-nonet.conf
		sed -i 's/dowait 10/dowait 1/g' $target/etc/init/cloud-init-nonet.conf
else
	echo "Cloud-init post-install - cloud-init-nonet does not exist. skipping edit"
fi

cat <<EOF >$target/etc/cloud/cloud.cfg.d/90_dpkg.cfg
datasource_list: [ NoCloud ]
EOF

cat <<EOF >$target/etc/network/interfaces
auto lo
iface lo inet loopback
#
auto eno2
iface eno2 inet dhcp
EOF

