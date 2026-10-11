# =====================================================================
#  ar-lib.rsc  v2  -  add / remove an exit route for 3x-ui (+ optional OpenVPN)
#  Load (after each reboot):  /import ar-lib.rsc
#
#  Precondition: operator has created the tunnel and its /30 IP is set
#  on the tunnel interface (e.g. gre-to-UK = 10.20.38.2/30).
#
#  $arAdd name=<n> iface=<if> [port=9010] [ovpn=1181] [backup=de|none]
#         [dns=yes] [direct=yes] [fallback=yes]
#     dns=yes      router DNS (8.8.8.8/1.1.1.1 + DoH) goes via this tunnel
#                  (first one = primary, next ones = backup)
#     direct=yes   3x-ui own traffic (172.17.0.2: direct outbound, DNS) uses this tunnel
#     fallback=yes PPP users without a country list use this tunnel
#  $arDel name=<n>
#  $arList
#
#  Typical first tunnel on a new router:
#     $arAdd name=de iface=gre-to-DE dns=yes direct=yes fallback=yes
#  Next ones:
#     $arAdd name=fl iface=gre-to-FL backup=de dns=yes ovpn=1198
# =====================================================================

:global arAdd do={
  :if ([:typeof $name] = "nothing" || [:typeof $iface] = "nothing") do={
    :error "usage: \$arAdd name=uk iface=gre-to-UK [port=] [ovpn=] [backup=de|none] [dns=yes] [direct=yes] [fallback=yes]"
  }
  :local tag ("AR:" . $name)
  :local tbl ("to-" . $name)

  # ---- checks ----
  :if ([:len [/routing table find where name=$tbl]] > 0) do={ :error ("already exists: " . $tbl . "  (use \$arDel first)") }
  :if ([:len [/interface find where name=$iface]] = 0) do={ :error ("interface not found: " . $iface) }
  :local aid [/ip address find where interface=$iface]
  :if ([:len $aid] = 0) do={ :error ("no IP address on " . $iface) }

  # ---- gateway = other side of the /30 ----
  :local a [/ip address get ($aid->0) address]
  :local lip [:toip [:pick $a 0 [:find $a "/"]]]
  :local net [:toip [/ip address get ($aid->0) network]]
  :local gw ($net + 1)
  :if ($gw = $lip) do={ :set gw ($net + 2) }

  # ---- free 172.17.0.x (not used by any mangle rule) ----
  :local used ","
  :foreach r in=[/ip firewall mangle find where action=mark-routing] do={
    :set used ($used . [:tostr [/ip firewall mangle get $r src-address]] . ",")
  }
  :local cip ""
  :for i from=3 to=250 do={
    :if ($cip = "") do={
      :local c ("172.17.0." . $i)
      :if ([:typeof [:find $used ("," . $c . ",")]] = "nil") do={ :set cip $c }
    }
  }
  :if ($cip = "") do={ :error "no free 172.17.0.x" }

  # ---- free port ----
  :local p 0
  :if ([:typeof $port] != "nothing") do={
    :set p [:tonum $port]
    :if ([:len [/ip firewall nat find where chain=dstnat dst-port=[:tostr $p]]] > 0) do={ :error ("port in use: " . $p) }
  } else={
    :for i from=9001 to=9999 do={
      :if ($p = 0) do={
        :if ([:len [/ip firewall nat find where chain=dstnat dst-port=[:tostr $i]]] = 0) do={ :set p $i }
      }
    }
  }

  # ---- routing table + routes ----
  /routing table add name=$tbl fib comment=$tag
  /ip route add dst-address=0.0.0.0/0 gateway=$gw routing-table=$tbl check-gateway=ping comment=$tag
  :local bk "none"
  :if ([:typeof $backup] != "nothing") do={ :set bk $backup }
  :if ($bk != "none" && $bk != $name) do={
    :local br [/ip route find where routing-table=("to-" . $bk) dst-address=0.0.0.0/0 distance=1]
    :if ([:len $br] > 0) do={
      :local bgw [/ip route get ($br->0) gateway]
      /ip route add dst-address=0.0.0.0/0 gateway=$bgw routing-table=$tbl distance=10 comment=$tag
    } else={ :put ("WARN: backup table to-" . $bk . " not found, no backup route") }
  }

  # ---- TUNNELS list (MSS + NAT + input) ----
  :if ([:len [/interface list member find where list=TUNNELS interface=$iface]] = 0) do={
    /interface list member add list=TUNNELS interface=$iface comment=$tag
  }

  # ---- container IP on veth1 ----
  :local vstr ""
  :foreach v in=[:toarray [/interface veth get [find name=veth1] address]] do={ :set vstr ($vstr . "," . [:tostr $v]) }
  :if ([:typeof [:find ($vstr . ",") ("," . $cip . "/")]] = "nil") do={
    :local nstr ([:pick $vstr 1 [:len $vstr]] . "," . $cip . "/24")
    :do { /interface veth set [find name=veth1] address=$nstr } on-error={
      :put ("WARN: could not set veth1 address. Stop the container, run:")
      :put ("  /interface veth set veth1 address=\"" . $nstr . "\"")
      :put "  then start the container again."
    }
  }

  # ---- mangle + dstnat ----
  /ip firewall mangle add chain=prerouting action=mark-routing src-address=$cip new-routing-mark=$tbl passthrough=no comment=$tag
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-port=$p to-addresses=172.17.0.2 to-ports=$p comment=$tag

  # ---- dns=yes : router DNS via this tunnel ----
  :if ($dns = "yes") do={
    :local cnt [:len [/ip route find where dst-address=8.8.8.8/32 routing-table=main]]
    :local d 1
    :if ($cnt > 0) do={ :set d (10 + $cnt) }
    /ip route add dst-address=8.8.8.8/32 gateway=$gw distance=$d check-gateway=ping comment=$tag
    /ip route add dst-address=1.1.1.1/32 gateway=$gw distance=$d check-gateway=ping comment=$tag
    :if ($d = 1) do={
      /ip dns set use-doh-server=https://1.1.1.1/dns-query verify-doh-cert=no
      /ip dns cache flush
    }
  }

  # ---- direct=yes : 3x-ui own traffic ----
  :if ($direct = "yes") do={
    :local mr [/ip firewall mangle find where comment="AR-BASE xui-direct" action=mark-routing]
    :if ([:len $mr] > 0) do={
      /ip firewall mangle set $mr new-routing-mark=$tbl
    } else={
      /ip firewall mangle add chain=prerouting action=mark-connection src-address=172.17.0.2 connection-state=new new-connection-mark=xui-direct passthrough=yes comment="AR-BASE xui-direct"
      /ip firewall mangle add chain=prerouting action=mark-routing src-address=172.17.0.2 connection-mark=xui-direct new-routing-mark=$tbl passthrough=no comment="AR-BASE xui-direct"
    }
  }

  # ---- fallback=yes : PPP users without list ----
  :if ($fallback = "yes") do={
    :local fr [/ip firewall mangle find where comment="AR-BASE ppp-fallback"]
    :if ([:len $fr] > 0) do={
      /ip firewall mangle set $fr new-routing-mark=$tbl
    } else={
      /ip firewall mangle add chain=prerouting action=mark-routing in-interface=all-ppp new-routing-mark=$tbl passthrough=no comment="AR-BASE ppp-fallback"
    }
  }

  # ---- ovpn=<port> : OpenVPN entry for this country ----
  :if ([:typeof $ovpn] != "nothing") do={
    :local prof ("profile-" . $name)
    :local al ("users-" . $name)
    :if ([:len [/ppp profile find where name=$prof]] = 0) do={
      /ppp profile add name=$prof address-list=$al dns-server=8.8.8.8,1.1.1.1 local-address=10.50.0.1 remote-address=Global-VPN-Pool
    }
    /interface ovpn-server server add name=$name port=[:tonum $ovpn] protocol=udp certificate=server auth=sha1,sha256 cipher=aes128-gcm,aes256-gcm,aes128-cbc,aes256-cbc default-profile=$prof disabled=no
    :local fb [/ip firewall mangle find where comment="AR-BASE ppp-fallback"]
    :if ([:len $fb] > 0) do={
      /ip firewall mangle add chain=prerouting action=mark-routing src-address-list=$al new-routing-mark=$tbl passthrough=no comment=$tag place-before=($fb->0)
    } else={
      /ip firewall mangle add chain=prerouting action=mark-routing src-address-list=$al new-routing-mark=$tbl passthrough=no comment=$tag
    }
    :local dw [/ip firewall filter find where comment="AR-BASE drop wan"]
    :if ([:len $dw] > 0) do={
      /ip firewall filter add chain=input action=accept protocol=udp dst-port=[:tonum $ovpn] comment=$tag place-before=($dw->0)
    }
  }

  # ---- summary ----
  :put "=============================================="
  :put ("route    : " . $name . "  table=" . $tbl . "  gw=" . $gw . " via " . $iface)
  :put ("backup   : " . $bk)
  :put ("public   : tcp/" . $p . "  -> 172.17.0.2:" . $p)
  :if ([:typeof $ovpn] != "nothing") do={ :put ("openvpn  : udp/" . $ovpn . "  profile-" . $name) }
  :if ($dns = "yes") do={ :put "dns      : router DNS via this tunnel" }
  :if ($direct = "yes") do={ :put "direct   : 3x-ui own traffic via this tunnel" }
  :if ($fallback = "yes") do={ :put "fallback : PPP users without list via this tunnel" }
  :put "---- now in 3x-ui ----"
  :put ("1) Inbound : port " . $p . "  (Sniffing ON + Route Only ON)")
  :put ("2) Outbound: freedom  tag=out-" . $name . "  sendThrough=" . $cip)
  :put ("3) Routing : inboundTag=inbound-" . $p . "  ->  outboundTag=out-" . $name)
  :put "=============================================="
}

:global arDel do={
  :if ([:typeof $name] = "nothing") do={ :error "usage: \$arDel name=uk" }
  :local tag ("AR:" . $name)
  :local tbl ("to-" . $name)
  :if ([:len [/ip firewall mangle find where comment="AR-BASE xui-direct" new-routing-mark=$tbl]] > 0) do={
    :put ("WARN: 3x-ui direct traffic uses " . $tbl . " - move it first: \$arAdd ... direct=yes on another route, or edit the rule")
  }
  :if ([:len [/ip firewall mangle find where comment="AR-BASE ppp-fallback" new-routing-mark=$tbl]] > 0) do={
    :put ("WARN: PPP fallback uses " . $tbl . " - move it first")
  }
  /ip firewall mangle remove [find where comment=$tag]
  /ip firewall nat remove [find where comment=$tag]
  /ip firewall filter remove [find where comment=$tag]
  /ip route remove [find where routing-table=$tbl]
  /ip route remove [find where comment=$tag]
  /interface list member remove [find where comment=$tag]
  /interface ovpn-server server remove [find where name=$name]
  /ppp profile remove [find where name=("profile-" . $name)]
  :do { /routing table remove [find where name=$tbl] } on-error={ :put ("WARN: table " . $tbl . " still referenced, not removed") }
  :put ("removed: " . $name . "  (container IP is freed for reuse; remove inbound/outbound in 3x-ui)")
}

:global arList do={
  :foreach r in=[/ip firewall mangle find where comment~"^AR:" action=mark-routing src-address-list=""] do={
    :local c [/ip firewall mangle get $r comment]
    :local n [:pick $c 3 [:len $c]]
    :local s [/ip firewall mangle get $r src-address]
    :local pt ""
    :foreach x in=[/ip firewall nat find where comment=$c] do={ :set pt [/ip firewall nat get $x dst-port] }
    :local st "DOWN"
    :foreach x in=[/ip route find where routing-table=("to-" . $n) active=yes] do={
      :if ([/ip route get $x distance] = 1) do={ :set st "UP" } else={ :if ($st != "UP") do={ :set st "BACKUP" } }
    }
    :put ($n . "\t" . $s . "\tport " . $pt . "\t" . $st)
  }
}

:put "ar-lib v2 loaded: \$arAdd  \$arDel  \$arList"
