# Ugreen NASync Proxmox LED Bridge (Universal)
**For Ugreen NASync DXP Series (DXP4800/6800/8800) running Proxmox VE with virtualized TrueNAS / Unraid / OMV.**

This project bridges the gap between virtualized NAS operating systems and the proprietary physical LEDs on Ugreen NASync hardware. It runs on the **Proxmox Host** and translates VM status into physical LED signals.

## Features
* **Universal Support:** Works with TrueNAS, Unraid, and OpenMediaVault via SSH.
* **Health Monitoring:** Turns Drive LEDs **Red** if the pool is Degraded/Faulted.
* **Smart Idle:** Detects disk spin-down by monitoring VM I/O from the Proxmox host (prevents accidental wake-ups).
* **Network Activity:** Enables hardware-level (zero-lag) blinking for the Network LED via kernel triggers.

## Prerequisites (Proxmox Host)

### 1. Drivers
You must have the community drivers installed on the Proxmox host to expose the LEDs.
* **LED Control Installation:** [miskcoo/ugreen_leds_controller](https://github.com/miskcoo/ugreen_leds_controller)

    ```bash
    # Install Build Tools
    apt update && apt install build-essential git dkms pve-headers-$(uname -r)
    ```

    ```bash
    # Install Driver
    git clone [https://github.com/miskcoo/ugreen_leds_controller.git](https://github.com/miskcoo/ugreen_leds_controller.git)
    ```

    ```bash
    cd ugreen_leds_controller && \
    make && make install && \
    modprobe led-ugreen
    ```

## Suggested network mods

### 1. Network Adapters
NOTE: The DXP6800 has shared PCIe lanes, therefore adding/removing NVMe drives can change your Ethernet interface names, dropping Proxmox off the LAN.

1. Get the current Ethernet interface names:

    ```bash
    nano /etc/systemd/network/10-persistent-net.link
    ```

2. Record the MAC of your adapter, and paste in the below TOML snippet:

    ```TOML
    [Match]
    MACAddress=xx:xx:xx:xx:xx:xx

    [Link]
    Name=eth_10g
    ```

3. Update the `initramfs` and then reboot.

    ```
    update-initramfs -u
    reboot
    ```

4. Repeat steps 1-3 for the second Ethernet adapter.

