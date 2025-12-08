# Proxmox Scripts


## One-Line Installation VLAN Script )
```bash
bash <(curl -s https://raw.githubusercontent.com/zitlem/Proxmox-Scripts/master/proxmox_vlan.sh)
```

## One-Line Linux Set Static IP)
```bash
bash <(curl -s https://raw.githubusercontent.com/zitlem/Proxmox-Scripts/master/linux-set-static-ip.shsh)

## proxmenux
bash -c "$(wget -qLO - https://raw.githubusercontent.com/MacRimi/ProxMenux/main/install_proxmenux.sh)"
```

## PVE No Boot
nomodeset

## Rename PVE host
Rename a standalone PVE host, you need to edit the following files: /etc/hosts /etc/hostname

## location of..
location of storage config cat /etc/pve/storage.cfg
location of disk img files cd /dev/pve
location of iso/templates /var/lib/vz

## Remove PVE from cluster
Stop Cluster Services systemctl stop pve-cluster corosync
Force Local Mode pmxcfs -l
Remove Cluster Configuration rm -r /etc/corosync/*
Remove the Proxmox cluster configuration file: rm /etc/pve/corosync.conf
Kill Cluster File System Process killall pmxcfs
Restart Services systemctl start pve-cluster
(remove unused nodes from here) cd /etc/pve/nodes (use rm -f pve1)
(remove unused nodes from here too?) nano /etc/pve/corosync.conf

##Fix Date Time

nano /etc/chrony/chrony.conf 
add
server 10.1.10.10 iburst

remove others

timedatectl set-timezone America/New_York