# Home Network VLAN configuration for Mikrotik router

## Disclaimer

This project is an amateur home project. Use it on your own risk.

If you are professional in this field, it will be very appreciated if you review it and send you feedback/notes.

This project tested on Mikrotik L009UiGS-2HaxD-IN only. Unfortunately other my Mikrotik device died before i was able to test script on it.

## Overview

This script allows you to configure Mikrotik router to use VLANs based on config file you create for it.

It can works in 2 modes

- configure from scratch - Mikrotik should be reset without default configuration, i.e it should be completely clear
- configure from defaults - Mikrotik should be reset with default configuration

## Requirements

- RouterOS v.7 (tested on v7.20)
- Mikrotik router with [hardware offload feature for VLAN filtering](https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching#BridgingandSwitching-BridgeHardwareOffloading). Possible it will work for routers without this feature, but network performance will not be great I presume.

## Installing

Just copy *homenet_vlans.rsc* script on the router.

If you uses Windows and WinBox:
- open File window in WinBox
- Drag-And-Drop *homenet_vlans.rsc* file from explorer to WinBox File window

## Configuration

You have to make a configuration file *homenet_vlans_config.json* to let script know what exactly network to configure.

See *homenet_vlans_config_example.json* to understand to config file structure.

Be careful with:
- JSON file structure - *homenet_vlans_config.json* should be a valid JSON file
- names of ports (ether1, ...) - use only names of ports that your router really has

Copy the *homenet_vlans_config.json* to your router nearby to *homenet_vlans.rsc*.

## Running

### Configure from scratch

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) copied to your router
- reset you router configuration **without** default configuration
- re-connect to router (after reset). Use not a **WAN** and not a **TRUNK** port.
- run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- you might be logged out during script working because of re-configuration.
- re-connect to router and tune-up your configuration if you need

### Configure from defaults

- Ensure that both files (*homenet_vlans.rsc* and *homenet_vlans_config.json*) copied to your router
- reset you router configuration **with** default configuration
- re-connect to router ***by IP address (NOT by MAC address)***. Use not a **WAN** and not a **TRUNK** port.
- run *homenet_vlans.rsc* script (*/import homenet_vlans.rsc*)
- you will be logged out during script working because of re-configuration.
- re-connect to router and tune-up your configuration if you need

## Known issues / questions to professions

- if connect to router by MAC-address after reset with default configuration, script crashes in the middle, you logs out and no more able to connect to router. Only hardware reset helps. I tried to all all MAC addresses, played with commands order - nothing helped. The only solution is us IP address to login before run the script.

- I know nothing about bridge protocol-mode. For now script keep it as is (i presume rstp is default), but as I understand Mikrotik recomends to use mstp for vlans. ChatGPT, Codex and Perplexity recomMend to set none for home if you do not use other switch (simple home configuration), but i have another VLAN switch, so... We will see

- MAC addresses - Mikrotik recommends to set MAC addresses for more stable work. Script does not touch MAC addresses, so, if you run it from scratch, MAC addresses will be set by router automatically, but if you run after default configuration, it set MAC addresses itself, so script keep them. Exception - WiFi VAPs - script creates them but not assign MAC addresses. If you want to set them hardly, configure them after the script.




