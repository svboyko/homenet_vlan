# -------------------------------------------------------------
# Configure Mikrotik router for home network with VLANs
# https://github.com/svboyko/homenet_vlan
#
# Copyright (c) 2024 Serge Boyko (https://github.com/svboyko)
# License: MIT
#
# This script configures VLANs, Wi-Fi, DHCP, firewall, and more
# for MikroTik routers using a JSON config file.
# RouterOS v7+ required; run after full reset with or without default configuration
# See repository for documentation and updates.
# -------------------------------------------------------------


# ---------- Logger function ----------
# $1 = mode, $2 = string
:local logAction do={

    :if ($1 = "error") do={
        :log error $2;
        :put ("Error:".$2);
    } else={
        :if ($1 = "warning") do={
            :log warning $2;
            :put ("Warning:".$2);
        } else={
            :log info $2;
            :put $2;
        }
    }

    # Save system logs to a file (overwrites each time!)
    /log print file=homenet_vlans_log
};

$logAction info "Script homenet_vlans started.";

# ---------- Load config ----------
:local configFile "homenet_vlans_config.json";
$logAction info ("Loading config from ".$configFile."...");
:if ([:len [/file find name=$configFile]] = 0) do={
    $logAction error ("Config file not found: " . $configFile);
    :error ("Config file not found: " . $configFile)
};

# Deserialize(parse) JSON config
$logAction info "Parsing config...";
:local cfg;
:onerror err in={
    :local cfgFileContent [/file get $configFile contents];
    :if ([:len $cfgFileContent] > 0) do={
        :set cfg [:deserialize $cfgFileContent from=json];
    } else={
        $logAction error ("Config file ".$configFile." is empty.");
        :error ("Config file ".$configFile." is empty.")
    }

    :if ([:len ($cfg->"vlans")] = 0) do={
        $logAction error ("Wrong config file: no VLANs defined");
        :error ("Wrong config file: no VLANs defined")
    };

    :if ([:len ($cfg->"bridgeName")] = 0) do={ :set ($cfg->"bridgeName") "bridge-main" };
} do={
    $logAction error ("Error parsing config: " . $err);
    :error ("Error parsing config: " . $err)
};

# ---------- Helper functions ----------
# Join array elements into a string with separator
# $1 = array, $2 = separator
# Returns string
:local stringJoin do={
    :local arr $1; :local sep $2; :local out "";
    :foreach i in=$arr do={
        :if ([:len $out] > 0) do={ :set out ($out . $sep) };
        :set out ($out . $i)
    }
    :return $out
};

# ---------- Remove default single-LAN settings (if exists) ----------
$logAction info "Removing default single-LAN settings...";
:onerror err in={
    /ip dhcp-server
    :local defDhcp [/ip dhcp-server find name="defconf"];
    :if ([:len $defDhcp] > 0) do={ remove $defDhcp }
    /ip dhcp-server network
    :local defNet [/ip dhcp-server network find address~"192.168.88.0/24"];
    :if ([:len $defNet] > 0) do={ remove $defNet }
    /ip pool
    :local defPool [/ip pool find name="default-dhcp"];
    :if ([:len $defPool] > 0) do={ remove $defPool }
    /ip address
    :local defAddr [/ip address find comment="defconf"];
    :if ([:len $defAddr] > 0) do={ remove $defAddr }
    /ip dhcp-client
    :local dhcpc [/ip dhcp-client find interface="ether1"];
    :if ([:len $dhcpc] > 0) do={ remove $dhcpc }
    /ip dns static
    :local defDns [/ip dns static find name="router.lan"];
    :if ([:len $defDns] > 0) do={ remove $defDns }
    /interface list member
    :foreach item in=[/interface list member find interface="bridge" list="LAN"] do={ remove $item }
    :foreach item in=[/interface list member find list="WAN"] do={ remove $item }
} do={
    $logAction error ("Error removing default settings: " . $err);
}

# ---------- Bridge ----------
# note - there are differences in bridge settings from default script
# default settings has set: admin-mac=XX:XX:XX:XX:XX:XX auto-mac=no
# i have removed these settings to leave default behavior
# but Perplaxity says that mikrotik recommends to set admin-mac and auto-mac=no
# TODO: add admin-mac=[/interface ethernet get ether1 mac-address] auto-mac=no
# TODO: add mac-address to JSON config
# Codex and Perplexity also proposed to add "protocol-mode=none"
# I've read mikrotik docs and it recommend protocol-mode=mstp for vlans
# TODO: examine if we need to set protocol-mode
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring bridge...";
:local brName ($cfg->"bridgeName");
:onerror err in={
    /interface bridge
    :local br [/interface bridge find name=$brName];
    :if ([:len $br]=0) do={
        :local defaultBr [/interface bridge find name="bridge"];
        :if ([:len $defaultBr]=0) do={
            $logAction info "- did not found any bridge: adding it...";
            add name=$brName vlan-filtering=yes comment="Main VLAN bridge";
            :set br [/interface bridge find name=$brName]
        } else={
            $logAction info "- found default brige: configuring it...";
            set $defaultBr name=$brName vlan-filtering=yes comment="Main VLAN bridge";
            :set br $defaultBr
        }
    } else={
        $logAction info "- found our bridge: configuring it...";
        set $br vlan-filtering=yes comment="Main VLAN bridge"
    }
} do={
    $logAction error ("Error configuring bridge: " . $err);
}

# ---------- VLAN interfaces ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring VLAN interfaces...";
:onerror err in={
    /interface vlan
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local vid ($vlanData->"id");
        :local title ($vlanData->"title");
        :local vlanIName ("vlan-" . $vlanName);
        :local existing [/interface vlan find name=$vlanIName];
        :if ([:len $existing]=0) do={
            add name=$vlanIName vlan-id=$vid interface=$brName comment=$title
        } else={
            set $existing vlan-id=$vid interface=$brName comment=$title
        }
    }
} do={
    $logAction error ("Error VLAN interfaces: " . $err);
}

# ---------- WAN ----------
:delay 1; # wait a bit while previous changes applied
:local wanPort (($cfg->"wan")->"port");
:local wanInterface $wanPort;
:local pppName ""
:if ([:len ((($cfg->"wan")->"pppoe")->"name")]>0) do={
    # ---------- PPPoE ----------
    $logAction info "Configuring PPPoE client...";
    :set $pppName ((($cfg->"wan")->"pppoe")->"name");
    :onerror err in={
        /interface pppoe-client
        :local ppp [/interface pppoe-client find name=$pppName];
        :if ([:len $ppp]=0) do={
            :local anyPpp [/interface pppoe-client find];
            :if ([:len $anyPpp]>0) do={
                :set ppp [:pick $anyPpp 0];
                set $ppp add-default-route=yes disabled=no interface=$wanPort \
                    name=$pppName service-name=((($cfg->"wan")->"pppoe")->"serviceName") use-peer-dns=yes \
                    user=((($cfg->"wan")->"pppoe")->"username") password=((($cfg->"wan")->"pppoe")->"password")
            } else={
                add add-default-route=yes disabled=no interface=$wanPort name=$pppName \
                    service-name=((($cfg->"wan")->"pppoe")->"serviceName") use-peer-dns=yes \
                    user=((($cfg->"wan")->"pppoe")->"username") password=((($cfg->"wan")->"pppoe")->"password");
                :set ppp [/interface pppoe-client find name=$pppName]
            }
        } else={
            set $ppp add-default-route=yes disabled=no interface=$wanPort \
                service-name=((($cfg->"wan")->"pppoe")->"serviceName") use-peer-dns=yes \
                user=((($cfg->"wan")->"pppoe")->"username") password=((($cfg->"wan")->"pppoe")->"password")
        }
        :set $wanInterface $pppName
    } do={
        $logAction error ("Error configuring PPPoE client: " . $err);
    }
}

# ---------- Build tagged/untagged lists ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Building tagged/untagged lists...";
:local tagged [:deserialize "{}" from=json];
:local untagged [:deserialize "{}" from=json];
:onerror err in={
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :set ($tagged->$vlanName) {$brName};
        :set ($untagged->$vlanName) [:deserialize "[]" from=json]
    }
} do={
    $logAction error ("Error building tagged/untagged lists: " . $err);
}

# ---------- Bridge ports ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring bridge ports...";
:onerror err in={
    /interface bridge port
    :foreach portName,portData in=(($cfg->"vlans")->"ports") do={
        :local existing [/interface bridge port find interface=$portName];

        :if ([:typeof ($portData->"trunk")]="array") do={
            :if ([:len $existing]=0) do={
                add bridge=$brName interface=$portName ingress-filtering=yes \
                    frame-types=admit-only-vlan-tagged comment=($portData->"comment")
            } else={
                set $existing bridge=$brName interface=$portName pvid=1 ingress-filtering=yes \
                    frame-types=admit-only-vlan-tagged comment=($portData->"comment")
            }
            :foreach v in=($portData->"trunk") do={ :set ($tagged->$v) (($tagged->$v), $portName) }
        } else={
            :if ([:typeof ($portData->"vlan")]="str") do={
                :local vlanName ($portData->"vlan");
                :local vid (((($cfg->"vlans")->"list")->$vlanName)->"id");
                :if ([:len $existing]=0) do={
                    add bridge=$brName interface=$portName pvid=$vid ingress-filtering=yes \
                        frame-types=admit-only-untagged-and-priority-tagged comment=($portData->"comment")
                } else={
                    set $existing bridge=$brName interface=$portName pvid=$vid ingress-filtering=yes \
                        frame-types=admit-only-untagged-and-priority-tagged comment=($portData->"comment")
                }
                :set ($untagged->$vlanName) (($untagged->$vlanName), $portName)
            } else={
                :error ("Invalid port VLAN config for port: " . $portName . " (" . [:typeof ($portData->"vlan")] . ")")
            }
        }
    }
} do={
    $logAction error ("Error configuring bridge ports: " . $err);
}

# ---------- Wi-Fi ----------
# Simple per-AP settings with inline datapath VLANs; adjust SSIDs/PSKs
# default script also set a mac-address for guest AP, but here we skip it
# TODO: when we add mac-address to bridge/JSON config, add it here too
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring Wi-Fi interfaces...";
/interface wifi
:onerror err in={
    # set main interfaces first
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local wifi ($vlanData->"wifi");
        :if ([:len $wifi]>0) do={
            :local radio ($wifi->"radio");
            :local vid ($vlanData->"id");
            :if (($wifi->"main")=true) do={
                :local base [/interface wifi find default-name=$radio];
                :if ([:len $base]=0) do={ :set base [/interface wifi find name=$radio] };
                :if ([:len $base]=0) do={ :error ("Radio not found: " . $radio) };
                set $base channel.skip-dfs-channels=10min-cac configuration.country=($cfg->"countryCode") \
                    configuration.mode=ap configuration.ssid=($wifi->"ssid") disabled=no \
                    security.authentication-types=($wifi->"encryption") .ft=yes .ft-over-ds=yes \
                    security.passphrase=($wifi->"password") \
                    datapath.bridge=$brName datapath.vlan-id=$vid;
                :set ($tagged->$vlanName) (($tagged->$vlanName), $radio)
            }
        }
    }
} do={
    $logAction error ("Error configuring main Wi-Fi interfaces: " . $err);
}

:onerror err in={
    # then set VAPs
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local wifi ($vlanData->"wifi");
        :if ([:len $wifi]>0) do={
            :local radio ($wifi->"radio");
            :local vid ($vlanData->"id");
            :if (($wifi->"main")=false) do={
                :local vapName ($radio . "-" . $vlanName);
                :local vap [/interface wifi find name=$vapName];
                :if ([:len $vap]=0) do={
                    add name=$vapName master-interface=$radio configuration.ssid=($wifi->"ssid") \
                        security.authentication-types=($wifi->"encryption") .ft=yes .ft-over-ds=yes \
                        security.passphrase=($wifi->"password") \
                        datapath.bridge=$brName datapath.vlan-id=$vid disabled=no
                } else={
                    set $vap master-interface=$radio configuration.ssid=($wifi->"ssid") \
                        security.authentication-types=($wifi->"encryption") .ft=yes .ft-over-ds=yes \
                        security.passphrase=($wifi->"password") \
                        datapath.bridge=$brName datapath.vlan-id=$vid disabled=no
                }
                :set ($tagged->$vlanName) (($tagged->$vlanName), $vapName)
            }
        }
    }
} do={
    $logAction error ("Error configuring Wi-Fi VAP interfaces: " . $err);
}

# ---------- Bridge VLAN table ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring bridge VLAN table...";
:onerror err in={
    /interface bridge vlan
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local vid ($vlanData->"id");
        :local taggedList [$stringJoin ($tagged->$vlanName) ","];
        :local untagList [$stringJoin ($untagged->$vlanName) ","];
        :local existing [/interface bridge vlan find bridge=$brName vlan-ids=$vid dynamic=no];
        :if ([:len $existing]=0) do={
            add bridge=$brName vlan-ids=$vid tagged=$taggedList untagged=$untagList
        } else={
            set $existing tagged=$taggedList untagged=$untagList
        }
    }
} do={
    $logAction error ("Error configuring bridge VLAN table: " . $err);
}

# ---------- Addresses ----------
# note: mikrotik default script also adds network=A.B.C.D option,
# but it looks like it's not needed
# https://www.reddit.com/r/mikrotik/comments/1fyi2jr/routeros_ipv4_addressing_network_parameter_what/
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring IP addresses...";
:onerror err in={
    /ip address
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local ipInfo ($vlanData->"ip");
        :local vlanIName ("vlan-" . $vlanName);
        :local existing [/ip address find interface=$vlanIName];
        :if ([:len $existing]=0) do={
            add address=($ipInfo->"address") interface=$vlanIName comment=(($vlanData->"title") . " GW")
        } else={
            set $existing address=($ipInfo->"address") comment=(($vlanData->"title") . " GW")
        }
    }
} do={
    $logAction error ("Error configuring IP addresses: " . $err);
}

# ---------- DHCP ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring DHCP servers pools...";
:onerror err in={
    /ip pool
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local poolName ("pool-" . $vlanName);
        :local existing [/ip pool find name=$poolName];
        :if ([:len $existing]=0) do={
            add name=$poolName ranges=((($vlanData->"ip")->"dhcpRange"))
        } else={
            set $existing ranges=((($vlanData->"ip")->"dhcpRange"))
        }
    }
} do={
    $logAction error ("Error configuring DHCP server pools: " . $err);
}

:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring DHCP servers...";
:onerror err in={
    /ip dhcp-server
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local srvName ("dhcp-" . $vlanName);
        :local poolName ("pool-" . $vlanName);
        :local vlanIName ("vlan-" . $vlanName);
        :local existing [/ip dhcp-server find name=$srvName];
        :if ([:len $existing]=0) do={
            add name=$srvName interface=$vlanIName address-pool=$poolName lease-time=1d disabled=no
        } else={
            set $existing interface=$vlanIName address-pool=$poolName lease-time=1d disabled=no
        }
    }
} do={
    $logAction error ("Error configuring DHCP servers: " . $err);
}

:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring DHCP server networks...";
:onerror err in={
    /ip dhcp-server network
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local ipInfo ($vlanData->"ip");
        :local existing [/ip dhcp-server network find address=($ipInfo->"subnet")];
        :if ([:len $existing]=0) do={
            add address=($ipInfo->"subnet") gateway=($ipInfo->"gateway") dns-server=($ipInfo->"gateway")
        } else={
            set $existing gateway=($ipInfo->"gateway") dns-server=($ipInfo->"gateway")
        }
    }
} do={
    $logAction error ("Error configuring DHCP server networks: " . $err);
}

# ---------- DNS ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring DNS...";
:onerror err in={
    # note: default script do not set custom DNS servers, not sure if we should do it here
    # TODO: verify if $cfg->"dnsServers" is not-empty before setting
    /ip dns
    set allow-remote-requests=yes servers=($cfg->"dnsServers")
} do={
    $logAction error ("Error configuring DNS: " . $err);
}

# ---------- Interface lists ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Updating interface lists...";
:onerror err in={
    /interface list
    :if ([:len [/interface list find name="WAN"]] = 0) do={ add name="WAN" comment="Uplink" }
    :if ([:len [/interface list find name="LAN"]] = 0) do={ add name="LAN" comment="All local VLAN SVIs" }
} do={
    $logAction error ("Error configuring interface lists: " . $err);
}

:onerror err in={
    /interface list member
    # in case of PPPoE:
    # default script has ether1 in WAN list also here, we use pppoe-uplink only instead
    # chatGPT confirms this is correct,
    # old mikrotik settings uses pppoe in Firewall, so also correct to use pppoe here
    # i do not know how is better if both or just pppoe
    # may be it's better to keep only pppoe to have all rules linked to pppoe
    # but also may be a good idea to add more protection on ether1
    # the rule 
    # - add chain=input action=drop in-interface-list=!LAN comment="INPUT drop others (WAN)"
    # protect for input chain
    # but may be a good idea to add also
    # - add chain=forward in-interface=ether1 action=drop comment="FWD drop all from ether1"
    :if ([:len [/interface list member find interface=$wanInterface list="WAN"]] = 0) do={
        add list="WAN" interface=$wanInterface
    }
    :foreach vlanName,vlanData in=(($cfg->"vlans")->"list") do={
        :local vlanIName ("vlan-" . $vlanName);
        :if ([:len [/interface list member find interface=$vlanIName list="LAN"]] = 0) do={
            add list="LAN" interface=$vlanIName
        }
    }
} do={
    $logAction error ("Error updating interface lists: " . $err);
}

# ---------- NAT ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Configuring NAT...";
:onerror err in={
    /ip firewall nat
    :local natRule [/ip firewall nat find comment~"masquerade"];
    :if ([:len $natRule]=0) do={ :set natRule [/ip firewall nat find comment="LAN -> Internet (auto)"] }
    :if ([:len $natRule]=0) do={
        add chain=srcnat out-interface-list=WAN action=masquerade ipsec-policy=out,none \
            comment="LAN -> Internet (auto)"
    } else={
        set $natRule chain=srcnat out-interface-list=WAN action=masquerade ipsec-policy=out,none \
            comment="LAN -> Internet (auto)"
    }
} do={
    $logAction error ("Error configuring NAT: " . $err);
}

# ---------- Firewall (basic) ----------
$logAction info "Configuring firewall (basic) filters...";
:onerror err in={
    /ip firewall filter
    :if ([:len [/ip/firewall/filter/find]] = 0) do={
        $logAction info "No firewall filter rules found. Setup from scratch.";

        # INPUT (protect router)
        :if ([:len [/ip firewall filter find comment="INPUT allow established/related"]] = 0) do={
            add chain=input action=accept connection-state=established,related,untracked comment="INPUT allow established/related"
        }
        :if ([:len [/ip firewall filter find comment="INPUT drop invalid"]] = 0) do={
            add chain=input action=drop connection-state=invalid comment="INPUT drop invalid"
        }
        :if ([:len [/ip firewall filter find comment="INPUT allow ICMP"]] = 0) do={
            add chain=input action=accept protocol=icmp comment="INPUT allow ICMP"
        }
        :if ([:len [/ip firewall filter find comment="INPUT allow loopback"]] = 0) do={
            add chain=input action=accept dst-address=127.0.0.1 comment="INPUT allow loopback"
        }
        # this rule does not exists in default script
        # ChatGPT said it's ok, The rule simply allows LAN -> Router access.
        # Default script just drops everything not from LAN, so this rule is implicit there.
        :if ([:len [/ip firewall filter find comment="INPUT allow LAN to router"]] = 0) do={
            add chain=input in-interface-list=LAN action=accept comment="INPUT allow LAN to router"
        }
        :if ([:len [/ip firewall filter find comment="INPUT drop others (WAN)"]] = 0) do={
            add chain=input action=drop in-interface-list=!LAN comment="INPUT drop others (WAN)"
        }

        # FORWARD (traffic through router, VLANs isolated)
        :if ([:len [/ip firewall filter find comment="FWD accept in ipsec policy"]] = 0) do={
            add chain=forward action=accept ipsec-policy=in,ipsec comment="FWD accept in ipsec policy"
        }
        :if ([:len [/ip firewall filter find comment="FWD accept out ipsec policy"]] = 0) do={
            add chain=forward action=accept ipsec-policy=out,ipsec comment="FWD accept out ipsec policy"
        }
        # this rule is different then in default script - it limits fasttrack to LAN->WAN only
        # according to ChatGPT it made to use fasttrack only for internet traffic, but not for inter-VLAN
        :if ([:len [/ip firewall filter find comment="FWD fasttrack LAN->WAN"]] = 0) do={
            add chain=forward action=fasttrack-connection connection-state=established,related \
                hw-offload=yes in-interface-list=LAN out-interface-list=WAN comment="FWD fasttrack LAN->WAN"
        }
        :if ([:len [/ip firewall filter find comment="FWD allow established/related"]] = 0) do={
            add chain=forward action=accept connection-state=established,related,untracked \
                comment="FWD allow established/related"
        }
        :if ([:len [/ip firewall filter find comment="FWD drop invalid"]] = 0) do={
            add chain=forward action=drop connection-state=invalid comment="FWD drop invalid"
        }
        # this rule does not exists in default script because there is no VLANs there
        :if ([:len [/ip firewall filter find comment="FWD drop inter-VLAN"]] = 0) do={
            add chain=forward in-interface-list=LAN out-interface-list=LAN action=drop \
                comment="FWD drop inter-VLAN"
        }
        # this rule does not exists in default script 
        :if ([:len [/ip firewall filter find comment="FWD LAN to WAN"]] = 0) do={
            add chain=forward in-interface-list=LAN out-interface-list=WAN action=accept comment="FWD LAN to WAN"
        }
        :if ([:len [/ip firewall filter find comment="FWD drop WAN not dstnat"]] = 0) do={
            add chain=forward connection-nat-state=!dstnat connection-state=new in-interface-list=WAN action=drop \
                comment="FWD drop WAN not dstnat"
        }
    } else={
        # some default settings exist, adjust them
        $logAction info "Firewall filter rules exist. Adjusting them.";
        :local ff [/ip firewall filter find comment~"fasttrack" dynamic=no];
        :if ([:len $ff]=0) do={
            add chain=forward action=fasttrack-connection connection-state=established,related \
                in-interface-list=LAN out-interface-list=WAN hw-offload=yes comment="FWD fasttrack LAN->WAN"
        } else={
            set $ff chain=forward action=fasttrack-connection connection-state=established,related \
                in-interface-list=LAN out-interface-list=WAN hw-offload=yes
        }
        :if ([:len [/ip firewall filter find comment="FWD drop inter-VLAN"]] = 0) do={
            add chain=forward in-interface-list=LAN out-interface-list=LAN action=drop \
                comment="FWD drop inter-VLAN"
        }
    }

    # in case of PPPoE we are adding also this rule to further protect router on physical port
    :if ([:len $pppName]>0) do={
        :if ([:len [/ip firewall filter find comment="FWD drop all from $wanPort"]] = 0) do={
            add chain=forward in-interface=$wanPort action=drop comment="FWD drop all from $wanPort"
        }
    }

} do={
    $logAction error ("Error configuring firewall (basic) filters: " . $err);
}

# ---------- IPv6 firewall ----------
$logAction info "Configuring firewall (IPv6) filters...";
# I know nothing about IPv6, so for now just disable it
:local ipv6Mode 0; # default to disabled
:onerror err in={
    :if ($ipv6Mode=0) do={
        # Disable IPv6 becasue we do not use it with VLANs yet
        $logAction info "This version does not support IPv6: Disable IPv6...";
        /ipv6 settings set disable-ipv6=yes
    } else={
        # I added code (below) from the default configuration, along with some additional changes,
        # but I am not fully confident in this part.

        # Fill addresses from default template
        /ipv6 firewall address-list
        :local badIPv6List { \
            "::/128":            "defconf: unspecified address"; \
            "::1/128":           "defconf: lo"; \
            "fec0::/10":         "defconf: site-local"; \
            "::ffff:0.0.0.0/96": "defconf: ipv4-mapped"; \
            "::/96":             "defconf: ipv4 compat"; \
            "100::/64":          "defconf: discard only "; \
            "2001:db8::/32":     "defconf: documentation"; \
            "2001:10::/28":      "defconf: ORCHID"; \
            "3ffe::/16":         "defconf: 6bone" \
        }

        :foreach ipv6Addr,ipv6Comment in=($badIPv6List) do={
            :if ([:len [/ipv6 firewall address-list find address=$ipv6Addr list=bad_ipv6]] = 0) do={
                add address=$ipv6Addr comment=$ipv6Comment list=bad_ipv6
            }
        }

        # Fill firewall rules from default template
        /ipv6 firewall filter
        :if ([:len [/ipv6/firewall/filter/find]] = 0) do={
            $logAction info "No IPv6 firewall filter rules found. Setup from scratch the defaults.";
            add action=accept chain=input connection-state=established,related,untracked \
                comment="defconf: accept established,related,untracked"
            add action=drop chain=input connection-state=invalid comment="defconf: drop invalid"
            add action=accept chain=input protocol=icmpv6 comment="defconf: accept ICMPv6"
            add action=accept chain=input dst-port=33434-33534 protocol=udp \
                comment="defconf: accept UDP traceroute"
            add action=accept chain=input dst-port=546 protocol=udp src-address=fe80::/10 \
                comment="defconf: accept DHCPv6-Client prefix delegation."
            add action=accept chain=input dst-port=500,4500 protocol=udp comment="defconf: accept IKE"
            add action=accept chain=input protocol=ipsec-ah comment="defconf: accept ipsec AH"
            add action=accept chain=input protocol=ipsec-esp comment="defconf: accept ipsec ESP"
            add action=accept chain=input ipsec-policy=in,ipsec \
                comment="defconf: accept all that matches ipsec policy"
            add action=drop chain=input in-interface-list=!LAN \
                comment="defconf: drop everything else not coming from LAN"
            #this rule is different then in default script - it limits fasttrack to LAN->WAN only
            add action=fasttrack-connection chain=forward connection-state=established,related \
                in-interface-list=LAN out-interface-list=WAN comment="defconf: fasttrack6"
            add action=accept chain=forward connection-state=established,related,untracked \
                comment="defconf: accept established,related,untracked"
            add action=drop chain=forward connection-state=invalid comment="defconf: drop invalid"
            add action=drop chain=forward src-address-list=bad_ipv6 comment="defconf: drop packets with bad src ipv6"
            add action=drop chain=forward dst-address-list=bad_ipv6 comment="defconf: drop packets with bad dst ipv6"
            add action=drop chain=forward hop-limit=equal:1 protocol=icmpv6 comment="defconf: rfc4890 drop hop-limit=1"
            add action=accept chain=forward protocol=icmpv6 comment="defconf: accept ICMPv6"
            add action=accept chain=forward protocol=139 comment="defconf: accept HIP"
            add action=accept chain=forward dst-port=500,4500 protocol=udp comment="defconf: accept IKE"
            add action=accept chain=forward protocol=ipsec-ah comment="defconf: accept ipsec AH"
            add action=accept chain=forward protocol=ipsec-esp comment="defconf: accept ipsec ESP"
            add action=accept chain=forward ipsec-policy=in,ipsec comment="defconf: accept all that matches ipsec policy"
            add action=drop chain=forward in-interface-list=!LAN comment="defconf: drop everything else not coming from LAN"
            # this rule does not exists in default script because there is no VLANs there
            add chain=forward in-interface-list=LAN out-interface-list=LAN action=drop comment="FWD drop inter-VLAN"
        } else={
            $logAction info "IPv6 firewall filter rules exist. Adjusting them.";

            #this rule is different then in default script - it limits fasttrack to LAN->WAN only
            :local ff [/ipv6 firewall filter find comment="defconf: fasttrack6"];
            :if ([:len $ff]=0) do={
                add action=fasttrack-connection chain=forward connection-state=established,related \
                    in-interface-list=LAN out-interface-list=WAN comment="defconf: fasttrack6"
            } else={
                # adjust existing rule
                set $ff action=fasttrack-connection chain=forward connection-state=established,related \
                    in-interface-list=LAN out-interface-list=WAN
            }

            # this rule does not exists in default script because there is no VLANs there
            :if ([:len [/ipv6 firewall filter find comment="FWD drop inter-VLAN"]] = 0) do={
                add chain=forward in-interface-list=LAN out-interface-list=LAN action=drop comment="FWD drop inter-VLAN"
            }
        } 
    }
} do={
    $logAction error ("Error configuring firewall (IPv6) filters: " . $err);
}

# ---------- MAC-server, clock ----------
:delay 1; # wait a bit while previous changes applied
$logAction info "Adjusting clock and miscellaneous settings...";
:onerror err in={
    /tool mac-server
    set allowed-interface-list=LAN
    /tool mac-server mac-winbox
    set allowed-interface-list=LAN

    /system clock
    :if ([:len ($cfg->"timeZoneName")] > 0) do={ set time-zone-name=($cfg->"timeZoneName") }

    # ============================================
    # Miscellaneous settings from default script
    /system routerboard settings
    set enter-setup-on=delete-key

    # limit mikrotik discovery to LAN interfaces only
    # to avoid sending discovery packets to WAN
    /ip neighbor discovery-settings
    set discover-interface-list=LAN

    # i do not know if this settings are needed, ChatGPT says they are not needed
    # it says that this model even does not have serial port
    #/port
    #set 0 name=serial0

    # i do not know if this settings are needed, ChatGPT says it's better to remove it
    # this settings is about sharing flash disk content over network, which is not so secure
    #/disk settings
    #set auto-media-interface=bridge auto-media-sharing=yes auto-smb-sharing=yes
} do={
    $logAction error ("Error adjusting clock/misc settings: " . $err);
}

# ---------- Finish ----------
$logAction info "Script homenet_vlans finished.";
