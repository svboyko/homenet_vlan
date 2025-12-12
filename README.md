# Home Network VLAN configuration for MikroTik router

## Disclaimer

This project is an amateur home project. Use it at your own risk.

If you’re a professional in this area, I’d appreciate feedback/notes.

This project is tested on MikroTik L009UiGS-2HaxD-IN only. Unfortunately another MikroTik device died before I could test it.

## Overview

This script allows you to configure a MikroTik router to use VLANs based on config file you create for it.

It can work in two modes:

- configure from scratch - MikroTik should be reset with no default configuration (blank config)
- configure from defaults - MikroTik should be reset with default configuration

## Requirements

- RouterOS v.7 (tested on v7.20)
- MikroTik router with [hardware offload feature for VLAN filtering](https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching#BridgingandSwitching-BridgeHardwareOffloading). Possible it will work for routers without this feature, but network performance will not be great I presume.

## Installing

Just copy *homenet_vlans.rsc* script on the router.

If you use Windows and WinBox:
- open File window in WinBox
- Drag-And-Drop *homenet_vlans.rsc* file from explorer to WinBox File window

## Configuration

You have to make a configuration file *homenet_vlans_config.json* to let the script know what exactly network to configure.

See *homenet_vlans_config_example.json* to understand to config file structure.

Copy the *homenet_vlans_config.json* to your router nearby to *homenet_vlans.rsc*.

### Configuration file structure notes

- "pppoe" section in "wan" is optional, you can omit it. In this case system will not configure any WAN, but just add ether1 into WAN interface list. In case of default configuration, default DHCP client will be deleted. Example:
    ```json
    "wan" : {
        "port": "ether1"
    },
    ```

- "wifi" section in vlan is optional, vlan might not have own WiFi. See TV example in homenet_vlans_config_example.json
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

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) copied to your router
- reset you router configuration **without** default configuration
- re-connect to router (after reset). Use not a **WAN** and not a **TRUNK** port.
- run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- you might be logged out while the script runs because of re-configuration.
- re-connect to router and tune-up your configuration if you need

### Configure from defaults

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) copied to your router
- reset your router configuration **with** default configuration
- reconnect to router ***by IP address (NOT by MAC address)***. Use not a **WAN** and not a **TRUNK** port.
- run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- you will be logged out during script working because of re-configuration.
- reconnect to router and tune-up your configuration if you need

## Known issues / open questions

- If you log in by MAC after a default reset, the script fails mid-run; you logs out and no more able to connect to router. Only hardware reset helps. I tried to allow all MAC addresses, played with commands order - nothing helped. The only solution is to use IP address to login before run the script.

- I know nothing about bridge protocol-mode. For now script keep it as is (i presume rstp is default), but as I understand MikroTik recommends to use mstp for vlans. ChatGPT, Codex and Perplexity recomMend to set none for home if you do not use other switch (simple home configuration), but i have another VLAN switch, so... We will see

- MAC addresses - MikroTik recommends to set MAC addresses for more stable work. Script does not touch MAC addresses, so, if you run it from scratch, MAC addresses will be set by router automatically, but if you run after default configuration, it set MAC addresses itself, so script keep them. Exception - WiFi VAPs - script creates them but not assign MAC addresses. If you want to set them hardly, configure them after the script.




