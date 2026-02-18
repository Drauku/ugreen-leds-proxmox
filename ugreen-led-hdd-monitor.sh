#!/bin/bash

# =================CONFIGURATION=================
# Options: "TRUENAS", "UNRAID", "OMV"
OS_MODE="TRUENAS"

# Target VM Settings
VMID="100"               # Proxmox VM ID (for Idle/IO check)
VM_IP="192.168.1.50"     # VM IP Address
SSH_KEY="/root/.ssh/id_rsa"

# SSH User Configuration
if [ "$OS_MODE" == "TRUENAS" ]; then
    SSH_USER="truenas_admin"
elif [ "$OS_MODE" == "UGOS" ]; then
    # UGOS usually creates a user named 'admin' or your custom username.
    # Root SSH is often disabled by default on stock UGOS.
    SSH_USER="your_ugos_username" 
else
    SSH_USER="root"
fi

# Thresholds
IDLE_MINUTES=15          # Minutes of 0 IO before showing "Sleep" state
BRIGHTNESS_FULL=255
BRIGHTNESS_DIM=20        # Brightness for "Healthy/Active"
BRIGHTNESS_SLEEP=5       # Brightness for "Spun Down" (Night Light)

# LED Paths (Adjust if needed)
LED_BASE="/sys/class/leds"
# ===============================================

# Global State Tracking
IO_IDLE_COUNTER=0
LAST_STATE="unknown"
PREV_IO=0

function set_drive_leds() {
    local color=$1    # white, red, off
    local bright=$2   # 0-255
    local i

    # Loop through disk slots (Adjust 1..6 for DXP6800)
    for i in {1..6}; do
        # Reset both colors first to ensure clean state
        echo 0 > "$LED_BASE/disk$i:white/brightness" 2>/dev/null
        echo 0 > "$LED_BASE/disk$i:red/brightness" 2>/dev/null
        
        if [ "$color" != "off" ]; then
            echo "$bright" > "$LED_BASE/disk$i:$color/brightness" 2>/dev/null
        fi
    done
}

function check_nas_health() {
    local status="UNKNOWN"
    local raw=""
    local errors=""
    
    # We use -o StrictHostKeyChecking=no to avoid script failure on first run or IP changes
    # We use -o ConnectTimeout=5 to prevent script hanging if VM is down
    
    case $OS_MODE in
        "OMV")
            # Check mdstat for degraded arrays (standard [U_] notation)
            raw=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$SSH_USER@$VM_IP" "cat /proc/mdstat")
            if [[ "$raw" == *"_U"* ]] || [[ "$raw" == *"U_"* ]]; then 
                status="DEGRADED"
            else 
                status="HEALTHY"
            fi
            ;;
        "TRUENAS")
            # "zpool status -x" returns "all pools are healthy" if good.
            # NOTE: Verify 'truenas_admin' has permissions to run zpool status (usually yes).
            raw=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "zpool status -x")
            
            if [[ "$raw" == *"all pools are healthy"* ]]; then 
                status="HEALTHY"
            else 
                status="DEGRADED"
            fi
            ;;
        "UGOS")
            # UGOS (Debian) can use ZFS or MDADM (Software RAID). We check both.
            
            # 1. Check ZFS (returns "all pools are healthy" or error)
            # 2. Check MDADM (returns [UU] for healthy, [_U] for degraded)
            # We concatenate both outputs to check them in one pass.
            
            raw=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "zpool status -x 2>/dev/null; cat /proc/mdstat 2>/dev/null")
            
            # Logic: If ZFS reports non-healthy OR MDADM shows a missing disk (_), flag as DEGRADED.
            if [[ "$raw" != *"all pools are healthy"* && "$raw" == *"pool:"* ]]; then
                status="DEGRADED"
            elif [[ "$raw" == *"_U"* ]] || [[ "$raw" == *"U_"* ]]; then 
                status="DEGRADED"
            else 
                status="HEALTHY"
            fi
            ;;
        "UNRAID")
            # Check Unraid array state from var.ini
            raw=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$SSH_USER@$VM_IP" "grep 'mdState' /var/local/emhttp/var.ini")
            if [[ "$raw" == *"STARTED"* ]]; then
                 errors=$(ssh -i "$SSH_KEY" "$SSH_USER@$VM_IP" "grep 'numErrors' /var/local/emhttp/var.ini | cut -d'=' -f2")
                 if [ "$errors" -eq "0" ]; then 
                    status="HEALTHY"
                 else 
                    status="DEGRADED"
                 fi
            else
                 status="STOPPED"
            fi
            ;;
    esac
    echo "$status"
}

function main() {
    echo "Starting Ugreen LED Monitor for VMID: $VMID (Mode: $OS_MODE | User: $SSH_USER)"
    
    while true; do
        # 1. Check if VM is running (Proxmox Local)
        local vm_status
        vm_status=$(qm status "$VMID" | awk '{print $2}')
        
        if [ "$vm_status" != "running" ]; then
            # VM Crashed/Stopped -> Flash RED once then wait
            set_drive_leds "red" $BRIGHTNESS_FULL
            sleep 1
            set_drive_leds "off" 0
            sleep 4
            continue
        fi

        # 2. Check Disk Activity (Proxmox Local - No Wakeup)
        # Using cgroup stats to detect IO without waking disks
        local curr_io
        curr_io=$(cat "/sys/fs/cgroup/qemu.slice/$VMID.scope/io.stat" 2>/dev/null | grep "rbytes\|wbytes" | awk '{s+=$2} END {print s}')
        
        # Handle empty/null case if VM is just starting
        if [ -z "$curr_io" ]; then curr_io=0; fi

        if [ "$curr_io" == "$PREV_IO" ]; then
            ((IO_IDLE_COUNTER++))
        else
            IO_IDLE_COUNTER=0
        fi
        PREV_IO=$curr_io

        # 3. Check Health (SSH)
        local health
        health=$(check_nas_health)

        # ================= LOGIC ENGINE =================
        if [ "$health" == "DEGRADED" ]; then
            if [ "$LAST_STATE" != "degraded" ]; then
                set_drive_leds "red" $BRIGHTNESS_FULL
                LAST_STATE="degraded"
            fi

        elif [ $IO_IDLE_COUNTER -gt $((IDLE_MINUTES * 6)) ]; then
            # Spun Down (Sleep Mode) - 6 loops per minute (sleep 10)
            if [ "$LAST_STATE" != "sleep" ]; then
                set_drive_leds "white" $BRIGHTNESS_SLEEP
                # Optional: Turn Power LED Blue if supported
                # echo 1 > /sys/class/leds/power:blue/brightness 2>/dev/null
                LAST_STATE="sleep"
            fi

        else
            # Active & Healthy
            if [ "$LAST_STATE" != "active" ]; then
                set_drive_leds "white" $BRIGHTNESS_DIM
                LAST_STATE="active"
            fi
        fi

        sleep 10
    done
}

# Run Main
main "$@"
