# =====================================================================
#  xui-auto.rsc  —  automatic routing + 3x-ui provisioning (RouterOS 7.24+, 3x-ui 3.9)
#
#  Runs every minute from the scheduler (see xui-auto-install.rsc).
#  For every tunnel interface (GRE / L2TP-ether / EoIP / IPIP / WireGuard)
#  that has a /30 or /31 address and is not yet managed, it:
#    1. creates routing table to-<name> + default route via the far end (check-gateway=ping)
#    2. adds the tunnel to interface-list TUNNELS (srcnat)
#    3. picks a free container IP 172.17.0.x and a free port (from portStart)
#    4. adds mangle (src 172.17.0.x -> to-<name>) and dstnat (port -> 172.17.0.2)
#    5. creates a VLESS + Reality inbound in 3x-ui through the panel API
#    6. rebuilds the Xray template (one outbound per route, sendThrough 172.17.0.x)
#
#  Registry = mangle comment:  XUI|<name>|<iface>|<table>|<port>|<ip>|<inbound-tag or ->
#  Config   = xui-auto-config.rsc  (global XAcfg)
#  Dry run  = :global XAdry true   -> nothing is changed, template written to <tplFile>
# =====================================================================
{
:global XAcfg
:global XAlastTpl
:global XAbusy
:global XAdry

:if ([:typeof $XAcfg] != "array") do={ :log error "xui-auto: XAcfg missing (import xui-auto-config.rsc)"; :error "no config" }
:if ($XAbusy = true) do={ :log warning "xui-auto: previous run still busy"; :error "busy" }
:set XAbusy true
:do {
:local cfg $XAcfg
:local dry ($XAdry = true)
:local panel ($cfg->"panel")
:local token ($cfg->"token")
:local sni ($cfg->"sni")
:local portStart [:tonum ($cfg->"portStart")]
:local types [:toarray ($cfg->"types")]
:local exclude [:toarray ($cfg->"exclude")]
:local veth ($cfg->"veth")
:local changed false

# ---------- helpers ----------
:local lower do={
  :local u "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; :local l "abcdefghijklmnopqrstuvwxyz"; :local o ""
  :for i from=0 to=([:len $1] - 1) do={
    :local c [:pick $1 $i]; :local p [:find $u $c]
    :if ([:typeof $p] = "num") do={ :set o ($o . [:pick $l $p]) } else={ :set o ($o . $c) }
  }
  :return $o
}
:local esc do={
  :local o ""
  :for i from=0 to=([:len $1] - 1) do={
    :local c [:pick $1 $i]
    :if ($c = "\"" || $c = "\\") do={ :set o ($o . "\\" . $c) } else={ :set o ($o . $c) }
  }
  :return $o
}
:local split do={
  :local out [:toarray ""]; :local s $1; :local p [:find $s "|"]
  :while ([:typeof $p] = "num") do={ :set out ($out, [:pick $s 0 $p]); :set s [:pick $s ($p + 1) [:len $s]]; :set p [:find $s "|"] }
  :set out ($out, $s)
  :return $out
}
:local api do={
  :local h ("Authorization: Bearer " . $tok)
  :local r
  :if ($method = "post") do={
    :if ([:len $ct] > 0) do={ :set h ($h . ",Content-Type: " . $ct) }
    :set r [/tool fetch url=($base . $path) http-method=post http-header-field=$h http-data=$body output=user as-value]
  } else={
    :set r [/tool fetch url=($base . $path) http-header-field=$h output=user as-value]
  }
  :return ($r->"data")
}

# ---------- read registry ----------
:local regIfaces ","
:local regIps ","
:local regPorts ","
:foreach m in=[/ip firewall mangle find where comment~"^XUI\\|"] do={
  :local f [$split [/ip firewall mangle get $m comment]]
  :set regIfaces ($regIfaces . ($f->2) . ",")
  :set regPorts ($regPorts . ($f->4) . ",")
  :set regIps ($regIps . ($f->5) . ",")
}

# ---------- 1) discover new tunnels ----------
:local prefixes {"gre-to-";"gre-";"l2tp-to-";"l2tp-";"eoip-to-";"eoip-";"ipip-to-";"ipip-";"wg-to-";"wg-"}
:foreach a in=[/ip address find where disabled=no] do={
  :local ifn [/ip address get $a interface]
  :local it ""
  :do { :set it [/interface get [find where name=$ifn] type] } on-error={}
  :local isTun ([:typeof [:find $types $it]] = "num")
  :local isEx ([:typeof [:find $exclude $ifn]] = "num")
  :local known ([:typeof [:find $regIfaces ("," . $ifn . ",")]] = "num")
  :if ($isTun && !$isEx && !$known) do={
    # name from interface
    :local n [$lower $ifn]
    :local done false
    :foreach p in=$prefixes do={
      :if (!$done && [:pick $n 0 [:len $p]] = $p) do={ :set n [:pick $n [:len $p] [:len $n]]; :set done true }
    }
    :local tbl ("to-" . $n)
    # gateway = far end of /30 or /31
    :local addr [/ip address get $a address]
    :local sl [:find $addr "/"]
    :local lip [:toip [:pick $addr 0 $sl]]
    :local pfx [:tonum [:pick $addr ($sl + 1) [:len $addr]]]
    :local net [:toip [/ip address get $a network]]
    :local gw ""
    :if ($pfx = 30) do={ :set gw ($net + 1); :if ($gw = $lip) do={ :set gw ($net + 2) } }
    :if ($pfx = 31) do={ :set gw $net; :if ($gw = $lip) do={ :set gw ($net + 1) } }
    :if ($gw = "") do={
      :log warning ("xui-auto: " . $ifn . " has /" . $pfx . " (need /30 or /31), skipped")
    } else={
      :if ([:len [/routing table find where name=$tbl]] > 0) do={
        :log warning ("xui-auto: table " . $tbl . " already exists but is not in registry; adopt it manually. skipped " . $ifn)
      } else={
        # free container IP (must already be on veth)
        :local vstr ","
        :foreach v in=[/interface veth get [find where name=$veth] address] do={ :set vstr ($vstr . [:pick $v 0 [:find $v "/"]] . ",") }
        :local used $regIps
        :foreach r in=[/ip firewall mangle find where action=mark-routing] do={ :set used ($used . [/ip firewall mangle get $r src-address] . ",") }
        :local cip ""
        :for x from=3 to=250 do={
          :local c ("172.17.0." . $x)
          :if ($cip = "" && [:typeof [:find $used ("," . $c . ",")]] = "nil" && [:typeof [:find $vstr ("," . $c . ",")]] = "num") do={ :set cip $c }
        }
        # free port
        :local port 0
        :for x from=$portStart to=($portStart + 500) do={
          :if ($port = 0 && [:len [/ip firewall nat find where chain=dstnat dst-port=[:tostr $x]]] = 0 && [:typeof [:find $regPorts ("," . $x . ",")]] = "nil") do={ :set port $x }
        }
        :if ($cip = "") do={
          :log error ("xui-auto: no free 172.17.0.x on " . $veth . " for " . $ifn . " (add addresses to veth)")
        } else={
          :local c ("XUI|" . $n)
          :log info ("xui-auto: new route " . $n . " iface=" . $ifn . " gw=" . $gw . " ip=" . $cip . " port=" . $port)
          :if (!$dry) do={
            /routing table add name=$tbl fib comment=$c
            /ip route add dst-address=0.0.0.0/0 gateway=$gw routing-table=$tbl check-gateway=ping comment=$c
            :local bk ($cfg->"backup")
            :if ([:len $bk] > 0 && $bk != $n) do={
              :local br [/ip route find where routing-table=("to-" . $bk) dst-address=0.0.0.0/0 distance=1]
              :if ([:len $br] > 0) do={ /ip route add dst-address=0.0.0.0/0 gateway=[/ip route get ($br->0) gateway] routing-table=$tbl distance=10 comment=$c }
            }
            :if ([:len [/interface list member find where list=TUNNELS interface=$ifn]] = 0) do={ /interface list member add list=TUNNELS interface=$ifn comment=$c }
            /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-address-type=local dst-port=$port to-addresses=172.17.0.2 to-ports=$port comment=$c
            /ip firewall mangle add chain=prerouting action=mark-routing src-address=$cip dst-address-type=!local new-routing-mark=$tbl passthrough=no comment=("XUI|" . $n . "|" . $ifn . "|" . $tbl . "|" . $port . "|" . $cip . "|-")
          }
          :set regIfaces ($regIfaces . $ifn . ","); :set regIps ($regIps . $cip . ","); :set regPorts ($regPorts . $port . ",")
          :set changed true
        }
      }
    }
  }
}

# ---------- 2) DNS + 3x-ui own traffic via the first (or dnsVia) route ----------
:local entries [/ip firewall mangle find where comment~"^XUI\\|"]
:if (!$dry && [:len $entries] > 0) do={
  :local dv ($cfg->"dnsVia")
  :local dtbl ""
  :if ([:len $dv] > 0) do={ :set dtbl ("to-" . $dv) } else={ :set dtbl ([$split [/ip firewall mangle get ($entries->0) comment]]->3) }
  :local dr [/ip route find where routing-table=$dtbl dst-address=0.0.0.0/0 distance=1]
  :if ([:len [/ip route find where dst-address=8.8.8.8/32 routing-table=main]] = 0 && [:len $dr] > 0) do={
    :local dgw [/ip route get ($dr->0) gateway]
    /ip route add dst-address=8.8.8.8/32 gateway=$dgw check-gateway=ping comment="XUI-DNS"
    /ip route add dst-address=1.1.1.1/32 gateway=$dgw check-gateway=ping comment="XUI-DNS"
    /ip dns set servers=8.8.8.8,1.1.1.1 use-doh-server=https://1.1.1.1/dns-query verify-doh-cert=no
    /ip dns cache flush
    :log info ("xui-auto: router DNS via " . $dtbl)
  }
  :if ([:len [/ip firewall mangle find where new-connection-mark=xui-direct]] = 0) do={
    /ip firewall mangle add chain=prerouting action=mark-connection src-address=172.17.0.2 connection-state=new dst-address-type=!local new-connection-mark=xui-direct passthrough=yes comment="XUI-DIRECT"
    /ip firewall mangle add chain=prerouting action=mark-routing src-address=172.17.0.2 connection-mark=xui-direct new-routing-mark=$dtbl passthrough=no comment="XUI-DIRECT"
    :log info ("xui-auto: 3x-ui direct traffic via " . $dtbl)
  }
}

# ---------- 3) create missing inbounds (VLESS + Reality) ----------
:if (!$dry && [:len $token] > 0) do={
  :foreach m in=[/ip firewall mangle find where comment~"^XUI\\|.*\\|-\$"] do={
    :local f [$split [/ip firewall mangle get $m comment]]
    :local n ($f->1); :local port ($f->4)
    :do {
      :local k ([:deserialize from=json value=[$api base=$panel tok=$token path="panel/api/server/getNewX25519Cert" method="get"]]->"obj")
      :local u1 ([:deserialize from=json value=[$api base=$panel tok=$token path="panel/api/server/getNewUUID" method="get"]]->"obj"->"uuid")
      :local u2 ([:deserialize from=json value=[$api base=$panel tok=$token path="panel/api/server/getNewUUID" method="get"]]->"obj"->"uuid")
      :local sid ([:pick $u2 0 8] . [:pick $u2 9 13])
      :local se ("{\"clients\":[{\"id\":\"" . $u1 . "\",\"flow\":\"xtls-rprx-vision\",\"email\":\"" . $n . "-" . $port . "\",\"enable\":true}],\"decryption\":\"none\",\"fallbacks\":[]}")
      :local st ("{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"xver\":0,\"target\":\"" . $sni . ":443\",\"serverNames\":[\"" . $sni . "\"],\"privateKey\":\"" . ($k->"privateKey") . "\",\"shortIds\":[\"" . $sid . "\"],\"settings\":{\"publicKey\":\"" . ($k->"publicKey") . "\",\"fingerprint\":\"chrome\",\"spiderX\":\"/\"}},\"tcpSettings\":{\"header\":{\"type\":\"none\"}}}")
      :local sn "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"routeOnly\":false}"
      :local body ("{\"up\":0,\"down\":0,\"total\":0,\"remark\":\"" . $n . "\",\"enable\":true,\"expiryTime\":0,\"listen\":\"\",\"port\":" . $port . ",\"protocol\":\"vless\",\"settings\":\"" . [$esc $se] . "\",\"streamSettings\":\"" . [$esc $st] . "\",\"sniffing\":\"" . [$esc $sn] . "\"}")
      :local res [:deserialize from=json value=[$api base=$panel tok=$token path="panel/api/inbounds/add" method="post" ct="application/json" body=$body]]
      :if (($res->"success") = true) do={
        :local tag ($res->"obj"->"tag")
        /ip firewall mangle set $m comment=("XUI|" . ($f->1) . "|" . ($f->2) . "|" . ($f->3) . "|" . ($f->4) . "|" . ($f->5) . "|" . $tag)
        :log info ("xui-auto: inbound " . $tag . " created for " . $n)
        :set changed true
      } else={
        :log error ("xui-auto: inbound for " . $n . " failed: " . ($res->"msg"))
      }
    } on-error={ :log error ("xui-auto: panel API error while creating inbound for " . $n) }
  }
}

# ---------- 4) Xray template from registry ----------
:local outs ""
:local rules ""
:foreach m in=[/ip firewall mangle find where comment~"^XUI\\|"] do={
  :local f [$split [/ip firewall mangle get $m comment]]
  :if (($f->6) != "-") do={
    :set outs ($outs . ",{\"tag\":\"out-" . ($f->1) . "\",\"protocol\":\"freedom\",\"settings\":{},\"sendThrough\":\"" . ($f->5) . "\",\"streamSettings\":{\"sockopt\":{\"domainStrategy\":\"UseIPv4\"}}}")
    :set rules ($rules . ",{\"type\":\"field\",\"inboundTag\":[\"" . ($f->6) . "\"],\"outboundTag\":\"out-" . ($f->1) . "\"}")
  }
}
:local tpl ("{\"api\":{\"services\":[\"HandlerService\",\"LoggerService\",\"StatsService\",\"RoutingService\"],\"tag\":\"api\"}," \
  . "\"dns\":{\"servers\":[\"https://1.1.1.1/dns-query\",\"https://8.8.8.8/dns-query\"],\"queryStrategy\":\"UseIPv4\",\"tag\":\"dns_inbound\"}," \
  . "\"inbounds\":[{\"listen\":\"127.0.0.1\",\"port\":62789,\"protocol\":\"tunnel\",\"settings\":{\"rewriteAddress\":\"127.0.0.1\"},\"tag\":\"api\"}]," \
  . "\"log\":{\"access\":\"none\",\"dnsLog\":false,\"error\":\"\",\"loglevel\":\"warning\",\"maskAddress\":\"\"}," \
  . "\"metrics\":{\"listen\":\"127.0.0.1:11111\",\"tag\":\"metrics_out\"}," \
  . "\"outbounds\":[{\"tag\":\"direct\",\"protocol\":\"freedom\",\"settings\":{\"finalRules\":[{\"action\":\"block\",\"ip\":[\"geoip:private\"]},{\"action\":\"allow\"}]},\"streamSettings\":{\"sockopt\":{\"domainStrategy\":\"UseIPv4\"}}}" \
  . $outs . ",{\"tag\":\"dns-out\",\"protocol\":\"dns\",\"settings\":{}},{\"tag\":\"blocked\",\"protocol\":\"blackhole\",\"settings\":{}}]," \
  . "\"policy\":{\"levels\":{\"0\":{\"statsUserDownlink\":true,\"statsUserUplink\":true}},\"system\":{\"statsInboundDownlink\":true,\"statsInboundUplink\":true,\"statsOutboundDownlink\":false,\"statsOutboundUplink\":false}}," \
  . "\"routing\":{\"domainStrategy\":\"AsIs\",\"rules\":[{\"type\":\"field\",\"inboundTag\":[\"api\"],\"outboundTag\":\"api\"},{\"type\":\"field\",\"port\":\"53\",\"network\":\"tcp,udp\",\"outboundTag\":\"dns-out\"},{\"type\":\"field\",\"ip\":[\"geoip:private\"],\"outboundTag\":\"blocked\"},{\"type\":\"field\",\"protocol\":[\"bittorrent\"],\"outboundTag\":\"blocked\"}" \
  . $rules . "]},\"stats\":{}}")

:if ($dry) do={
  :local tf ($cfg->"tplFile")
  :if ([:len [/file find where name=$tf]] = 0) do={ /file add name=$tf contents=$tpl } else={ /file set [find where name=$tf] contents=$tpl }
  :log info ("xui-auto: DRY RUN - template written to " . $tf)
} else={
  :if ([:len $token] > 0 && $tpl != $XAlastTpl) do={
    :do {
      :local res [:deserialize from=json value=[$api base=$panel tok=$token path="panel/api/xray/update" method="post" ct="application/x-www-form-urlencoded" body=("xraySetting=" . [:convert $tpl to=url])]]
      :if (($res->"success") = true) do={
        :local rr [$api base=$panel tok=$token path="panel/api/server/restartXrayService" method="post" ct="application/x-www-form-urlencoded" body="a=1"]
        :set XAlastTpl $tpl
        :log info "xui-auto: xray template updated and xray restarted"
      } else={ :log error ("xui-auto: xray template rejected: " . ($res->"msg")) }
    } on-error={ :log error "xui-auto: panel API error while updating xray template" }
  }
}

:put "xui-auto: done"
} on-error={ :log error "xui-auto: run aborted with an error" }
:set XAbusy false
}
