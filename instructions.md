## Installation

### Step 0: Network Interface Pinning (CRITICAL)

- **DO NOT SKIP THIS**. The DXP6800 has shared PCIe lanes. Adding/removing NVMe drives or passing through PCIe devices can change your Ethernet interface names (e.g., enp4s0 -> enp5s0), locking you out of Proxmox.

#### Run on Proxmox Host:

- Get your 10GbE MAC address: 

    ```bash
    ## Installation & Configuration

    ### Network Interface Pinning (CRITICAL)

    - **DO NOT SKIP.** The DXP6800 shares PCIe lanes. Adding/removing NVMe drives or passing through PCIe devices can change Ethernet interface names (for example, `enp4s0` -> `enp5s0`) and may lock you out of Proxmox.

    Run these on the Proxmox host:

    1. Get your 10GbE MAC address:

    ```bash
    ip link
    ```

    2. Create a persistent link file:

    ```bash
    nano /etc/systemd/network/10-persistent-net.link
    ```

    Paste the following into that file (replace the `xx` values with the device MAC you want pinned):

    ```toml
    [Match]
    MACAddress=xx:xx:xx:xx:xx:xx

    [Link]
    Name=eth_10g
    ```

    3. Update initramfs and reboot:

    ```bash
    update-initramfs -u && reboot
    ```

    ### Install Scripts

    Copy the repository files to these locations on the Proxmox host:

    - `ugreen-led-monitor.sh` -> `/usr/local/bin/` (then `chmod +x /usr/local/bin/ugreen-led-monitor.sh`)
    - `ugreen-leds.service` -> `/etc/systemd/system/`
    - `ugreen-net-led.service` -> `/etc/systemd/system/`

    ### Configure

    Edit `/usr/local/bin/ugreen-led-monitor.sh` and set the following variables to match your environment:

    - `OS_MODE` — one of `TRUENAS`, `UNRAID`, `OMV`, or `UGOS`.
    - `VM_IP` — the IP of the NAS/VM to monitor.
    - `VMID` — (if required) the VM ID on the host.
    - `SSH_USER` — defaults: TrueNAS -> `truenas_admin`; others -> `root`. Change if your setup uses a different user.

    ### Enable Services

    Reload systemd and enable the services:

    ```bash
    systemctl daemon-reload
    systemctl enable --now ugreen-leds.service
    systemctl enable --now ugreen-net-led.service
    ```

    ## SSH Access (The Bridge)

    The Proxmox host requires password-less SSH access to the NAS VM to check health status. Steps:

    1. Generate an SSH key on the Proxmox host (skip if you already have one):

    ```bash
    ssh-keygen -t rsa -b 4096
    ```

    2. Copy the public key to the NAS VM (replace `user` and `<YOUR_NAS_IP>` appropriately):

    ```bash
    # TrueNAS: truenas_admin | Unraid/OMV: root | UGOS: your_admin_user
    ssh-copy-id user@<YOUR_NAS_IP>
    ```

    Ensure `SSH_USER` in `ugreen-led-monitor.sh` matches the account you used.

    ### Special Note: Virtualized UGOS & SSH Persistence

    If UGOS runs in a VM, its root filesystem is often read-only or reset on reboot which can erase `/root/.ssh/authorized_keys`. To keep SSH keys persistent:

    - Use a non-root admin user created during UGOS setup (for example, `alex`).
    - User keys are stored in `/home/<user>/.ssh/authorized_keys` on the persistent partition.
    - Example:

    ```bash
    ssh-copy-id alex@<UGOS_IP>
    ```

    Update `SSH_USER` in the monitor script to that user.

    ## Hardware Notes

    - DXP6800: Drive LEDs are White/Red only. Requests for "Blue" map to dim white (night mode).
    - Interface pinning (above) is essential on the DXP6800 to avoid interface renaming and potential network loss.
