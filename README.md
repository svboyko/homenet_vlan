# Home Network VLAN configuration for MikroTik routers

## Disclaimer

This project is an amateur home project. Use it at your own risk.

If you’re a professional in this area, I’d appreciate feedback/notes.

This project is tested on MikroTik L009UiGS-2HaxD-IN only. Unfortunately another MikroTik device died before I could test it.

## Overview

This script allows you to configure a MikroTik router to use VLANs based on a config file you create for it.

It can work in two modes:

- configure from scratch - MikroTik should be reset with no default configuration (blank config)
- configure from defaults - MikroTik should be reset with default configuration

## Requirements

- RouterOS v.7 (tested on v7.20)
- MikroTik router with [hardware offload feature for VLAN filtering](https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching#BridgingandSwitching-BridgeHardwareOffloading). It may work on routers without this feature, but network performance will probably suffer.

## Installing

Just copy *homenet_vlans.rsc* script on the router.

If you use Windows and WinBox:
- open File window in WinBox
- Drag-And-Drop *homenet_vlans.rsc* file from explorer to WinBox File window

## Configuration

Create *homenet_vlans_config.json* to define the network configuration for the script.

See *homenet_vlans_config_example.json* to understand the config file structure.

Copy the *homenet_vlans_config.json* to your router next to *homenet_vlans.rsc*.

### Configuration file structure notes

- The "pppoe" section in "wan" is optional; if omitted, the system won’t configure WAN and will just add ether1 to the WAN interface list. If the default config is used, the default DHCP client will be removed. Example:
    ```json
    "wan" : {
        "port": "ether1"
    },
    ```

- "wifi" section in "vlan" is optional, a VLAN might not have its own WiFi. See TV example in homenet_vlans_config_example.json
    ```json
    "tv": {
        "id": 40,
        "title": "TV VLAN",
        "ip": {
            "address": "192.168.40.1/24",
            "subnet": "192.168.40.0/24",
            "gateway": "192.168.40.1",
            "dhcpRange": "192.168.40.100-192.168.40.199"
        }
    }
    ```

*Be careful with:*
- JSON file structure - *homenet_vlans_config.json* should be a valid JSON file
- names of ports (ether1, ...) - use only names of ports that your router really has
- consistency of names/IPs/vlan IDs

## Running

### Configure from scratch

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) are copied to your router
- Reset your router configuration **without** default configuration
- Reconnect to the router (after reset) using a port that is not **WAN** or **TRUNK**.
- Run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- You might be logged out while the script runs because of reconfiguration.
- Reconnect to router and tune-up your configuration if you need

### Configure from defaults

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) are copied to your router
- Reset your router configuration **with** default configuration
- Reconnect to router ***by IP address (NOT by MAC address)***. Use a port that is not **WAN** or **TRUNK**.
- Run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- You will be logged out while the script runs because of reconfiguration.
- Reconnect to router and tune-up your configuration if you need

## Known issues / open questions

- If you log in via **MAC address** after a reset **with default settings**, and then run the script, the script fails mid-run. You will be kicked out and will no longer be able to reconnect to the router. Only a hardware reset helps after that. I tried allowing all MAC addresses and changing the command execution order, but nothing helped. The only reliable solution is to log in using an IP address before running the script. There is no such problem if you run the script after reset **without default settings**

- I know nothing about bridge **protocol-mode**. For now the script keeps it as is (I presume RSTP is default), but as I understand MikroTik recommends to use MSTP for VLANs. ChatGPT, Codex and Perplexity recommend to set **none** for home if you do not use other switches (simple home configuration), but I have another VLAN switch, so we will see...

- **MAC addresses** - MikroTik recommends explicitly setting MAC addresses for more stable operation. This script does not modify MAC addresses. If you run it from scratch, MAC addresses are assigned automatically by the router. If you run it after applying the default configuration, the router has already set MAC addresses (from default configuration), and the script preserves them. The exception is WiFi VAPs: the script creates them but does not assign MAC addresses. If you want fixed MAC addresses for VAPs, configure them manually after the script finishes.

- **IPv6** - I know nothing about IPv6, so it is disabled in this version. I added code from the default configuration, along with some additional changes, but I am not fully confident in this part.




