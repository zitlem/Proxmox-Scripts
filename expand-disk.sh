#!/bin/bash
set -e

echo "=== Auto Disk Expansion Script (ext4 only) ==="

#############################################
# Step 1: Detect root block device
#############################################
ROOT_DEV=$(findmnt -no SOURCE /)

echo "Root device: $ROOT_DEV"

# Check filesystem type
FSTYPE=$(findmnt -no FSTYPE /)
if [[ "$FSTYPE" != "ext4" ]]; then
    echo "ERROR: Root filesystem is not ext4. Detected: $FSTYPE"
    exit 1
fi


#############################################
# Step 2: Detect if LVM or not
#############################################
if [[ "$ROOT_DEV" == /dev/mapper/* ]]; then
    IS_LVM=1
else
    IS_LVM=0
fi

#############################################
# If LVM system
#############################################
if [[ $IS_LVM -eq 1 ]]; then
    echo "LVM detected."

    LV_PATH="$ROOT_DEV"
    VG=$(lvs --noheadings -o vg_name "$LV_PATH" | awk '{print $1}')
    LV=$(lvs --noheadings -o lv_name "$LV_PATH" | awk '{print $1}')
    PV=$(pvs --noheadings -o pv_name | awk '{print $1}')

    echo "  PV: $PV"
    echo "  VG: $VG"
    echo "  LV: $LV"

    # 1. Rescan disk (virt environments)
    echo "[1/3] Rescanning disk..."
    echo 1 | sudo tee /sys/class/block/sda/device/rescan >/dev/null || true

    # 2. Resize PV
    echo "[2/3] Resizing physical volume: $PV"
    sudo pvresize "$PV"

    # 3. Extend LV
    echo "[3/3] Extending logical volume: $LV_PATH"
    sudo lvextend -l +100%FREE "$LV_PATH"

    # Grow filesystem
    echo "Growing ext4 filesystem..."
    sudo resize2fs "$LV_PATH"

    echo "=== LVM expansion complete ==="
    df -h /
    exit 0
fi


#############################################
# If NON-LVM system
#############################################
echo "Non-LVM ext4 root detected."

DISK="/dev/$(lsblk -no pkname "$ROOT_DEV")"
PART="$ROOT_DEV"

echo "  Disk: $DISK"
echo "  Partition: $PART"

# 1. Grow the partition using growpart
echo "[1/2] Expanding partition..."
sudo growpart "$DISK" "${PART##*[^0-9]}"

# 2. Resize ext4 filesystem
echo "[2/2] Growing ext4 filesystem..."
sudo resize2fs "$PART"

echo "=== Non-LVM expansion complete ==="
df -h /
