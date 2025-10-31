#!/bin/bash

# Proxmox VLAN-Aware Network Configuration Script
# This script configures a fresh Proxmox installation with VLAN support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Proxmox VLAN Configuration Script ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Backup existing configuration
BACKUP_FILE="/etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${YELLOW}Creating backup of current configuration...${NC}"
cp /etc/network/interfaces "$BACKUP_FILE"
echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}\n"

# Detect the primary network interface
echo -e "${YELLOW}Detecting primary network interface...${NC}"

# On Proxmox, we need to find the physical interface, not the bridge
# First, check if vmbr0 exists and get its bridge port
if [ -f /etc/network/interfaces ]; then
    BRIDGE_PORT=$(grep -A 10 "^iface vmbr0" /etc/network/interfaces | grep "bridge-ports" | awk '{print $2}' | head -n 1)
fi

# If we found a bridge port in the config, use that
if [ -n "$BRIDGE_PORT" ] && [ "$BRIDGE_PORT" != "none" ]; then
    PRIMARY_IFACE="$BRIDGE_PORT"
else
    # Otherwise, find physical interface (exclude bridges, loopback, and virtual interfaces)
    PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth|^enp|^eno|^ens' | head -n 1)
fi

if [ -z "$PRIMARY_IFACE" ]; then
    echo -e "${RED}Error: Could not detect primary network interface${NC}"
    echo "Available interfaces:"
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'
    exit 1
fi

echo -e "${GREEN}Detected physical interface: $PRIMARY_IFACE${NC}\n"

# Get current IP configuration (check both bridge and physical interface)
# First check for VLAN interfaces (vmbr0.X)
CURRENT_IP=$(ip -4 addr show | grep -A 2 "vmbr0\." | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | awk '{print $2}' | head -n 1)

# If no VLAN interface, check vmbr0
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(ip -4 addr show vmbr0 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | awk '{print $2}' | head -n 1)
fi

# If still nothing, check the physical interface
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(ip -4 addr show "$PRIMARY_IFACE" | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | awk '{print $2}' | head -n 1)
fi

CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)

# Detect current VLAN ID if configured
CURRENT_VLAN=""
if grep -q "bridge-vlan-aware yes" /etc/network/interfaces 2>/dev/null; then
    CURRENT_VLAN=$(grep -E "^auto vmbr0\.[0-9]+" /etc/network/interfaces | head -n 1 | sed 's/auto vmbr0\.//')
    if [ -z "$CURRENT_VLAN" ]; then
        CURRENT_VLAN="1"
    fi
fi

# Detect current VLAN range
CURRENT_VLAN_RANGE=$(grep "bridge-vids" /etc/network/interfaces 2>/dev/null | awk '{print $2}' | head -n 1)
if [ -z "$CURRENT_VLAN_RANGE" ]; then
    CURRENT_VLAN_RANGE="1-4094"
fi

echo -e "${YELLOW}Current network configuration:${NC}"
echo "  Interface: $PRIMARY_IFACE"
echo "  IP/Mask: $CURRENT_IP"
echo "  Gateway: $CURRENT_GATEWAY"
if [ -n "$CURRENT_VLAN" ]; then
    echo "  Management VLAN: $CURRENT_VLAN"
    echo "  VLAN Range: $CURRENT_VLAN_RANGE"
fi
echo

# Prompt for configuration with current values as defaults
read -p "Enter management VLAN ID (default: ${CURRENT_VLAN:-1}): " MGMT_VLAN
MGMT_VLAN=${MGMT_VLAN:-${CURRENT_VLAN:-1}}

read -p "Enter management IP/mask (default: $CURRENT_IP): " MGMT_IP
MGMT_IP=${MGMT_IP:-$CURRENT_IP}

read -p "Enter gateway IP (default: $CURRENT_GATEWAY): " GATEWAY_IP
GATEWAY_IP=${GATEWAY_IP:-$CURRENT_GATEWAY}

read -p "Enter VLAN range to allow (default: ${CURRENT_VLAN_RANGE:-1-4094}): " VLAN_RANGE
VLAN_RANGE=${VLAN_RANGE:-${CURRENT_VLAN_RANGE:-1-4094}}

echo
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  Physical Interface: $PRIMARY_IFACE"
echo "  Management VLAN: $MGMT_VLAN"
echo "  Management IP: $MGMT_IP"
echo "  Gateway: $GATEWAY_IP"
echo "  Allowed VLANs: $VLAN_RANGE"
echo

read -p "Apply this configuration? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Configuration cancelled${NC}"
    exit 0
fi

# Create new network configuration
echo -e "\n${YELLOW}Writing new network configuration...${NC}"

cat > /etc/network/interfaces << 'EOF'
# Loopback interface
auto lo
iface lo inet loopback

EOF

# Add physical interface configuration
cat >> /etc/network/interfaces << EOF
# Physical interface
auto $PRIMARY_IFACE
iface $PRIMARY_IFACE inet manual

# VLAN-aware bridge
auto vmbr0
iface vmbr0 inet manual
        bridge-ports $PRIMARY_IFACE
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids $VLAN_RANGE

# Management VLAN interface
auto vmbr0.$MGMT_VLAN
iface vmbr0.$MGMT_VLAN inet static
        address $MGMT_IP
        gateway $GATEWAY_IP

# Source additional interface configurations
source /etc/network/interfaces.d/*
EOF

echo -e "${GREEN}Configuration written successfully${NC}\n"

# Update /etc/hosts with new IP
echo -e "${YELLOW}Updating /etc/hosts with new IP...${NC}"
BANNER_IP=$(echo "$MGMT_IP" | cut -d'/' -f1)
HOSTNAME=$(hostname)

# Backup /etc/hosts
cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

# Update or add the hostname entry in /etc/hosts
if grep -q "^[0-9].*$HOSTNAME" /etc/hosts; then
    # Replace existing entry
    sed -i "s/^[0-9].*$HOSTNAME.*/$BANNER_IP $HOSTNAME.local $HOSTNAME pvelocalhost/" /etc/hosts
else
    # Add new entry if it doesn't exist
    echo "$BANNER_IP $HOSTNAME.local $HOSTNAME pvelocalhost" >> /etc/hosts
fi

echo -e "${GREEN}/etc/hosts updated${NC}\n"

# Ask about applying changes
echo -e "${YELLOW}The new configuration has been written but not yet applied.${NC}"
echo -e "${YELLOW}You can either:${NC}"
echo "  1) Reboot the system (safest option)"
echo "  2) Apply with 'ifreload -a' (may lose connection temporarily)"
echo

read -p "Would you like to reboot now? (yes/no): " REBOOT_NOW

if [ "$REBOOT_NOW" = "yes" ]; then
    echo -e "${GREEN}Rebooting system...${NC}"
    reboot
else
    echo -e "${YELLOW}Configuration complete but not applied.${NC}"
    echo -e "To apply the changes, run: ${GREEN}ifreload -a${NC} or reboot"
    echo -e "To restore the previous configuration: ${GREEN}cp $BACKUP_FILE /etc/network/interfaces${NC}"
fi