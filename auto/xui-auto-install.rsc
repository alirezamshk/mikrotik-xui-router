# =====================================================================
#  xui-auto-install.rsc — one-time install of the automation (safe to re-run)
#  Needs: xui-auto.rsc and xui-auto-config.rsc uploaded to the router root (Files)
#  Assumes: container "veth1" + bridge "dockers" 172.17.0.1/24, panel container at 172.17.0.2
# =====================================================================
{
# ---- interface list + srcnat ----
:if ([:len [/interface list find where name=TUNNELS]] = 0) do={ /interface list add name=TUNNELS comment="exit tunnels" }
:if ([:len [/ip firewall nat find where action=masquerade out-interface-list=TUNNELS]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface-list=TUNNELS comment="SRCNAT: tunnels" place-before=0
}
:if ([:len [/ip firewall nat find where action=masquerade out-interface=ether1]] = 0) do={
  /ip firewall nat add chain=srcnat action=masquerade out-interface=ether1 comment="SRCNAT: WAN" place-before=0
}

# ---- MSS ----
:if ([:len [/ip firewall mangle find where action=change-mss dst-address=172.17.0.0/24]] = 0) do={
  /ip firewall mangle add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1261-65535 dst-address=172.17.0.0/24 new-mss=1260 passthrough=yes comment="MSS: clients -> 3x-ui"
}
:if ([:len [/ip firewall mangle find where action=change-mss src-address=172.17.0.0/24]] = 0) do={
  /ip firewall mangle add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1281-65535 src-address=172.17.0.0/24 new-mss=1280 passthrough=yes comment="MSS: 3x-ui -> tunnels"
}

# ---- sendThrough pool: 172.17.0.2 .. 172.17.0.60 on veth1 (one-time container restart) ----
:local want ""
:for x from=2 to=60 do={ :set want ($want . "172.17.0." . $x . "/24,") }
:set want [:pick $want 0 ([:len $want] - 1)]
:if ([:len [/interface veth get [find where name=veth1] address]] < 59) do={
  :local c [/container find where interface=veth1]
  :do { /interface veth set [find where name=veth1] address=$want } on-error={
    :put "container must be stopped to change veth; restarting it once"
    /container stop $c
    :delay 8s
    /interface veth set [find where name=veth1] address=$want
    /container start $c
  }
  :put "veth1 pool = 172.17.0.2-60"
}

# ---- scheduler ----
:if ([:len [/system scheduler find where name=xui-auto]] = 0) do={
  /system scheduler add name=xui-auto interval=1m start-time=startup policy=read,write,policy,test \
    on-event="/import file-name=xui-auto-config.rsc verbose=no; /import file-name=xui-auto.rsc verbose=no"
}
:put "xui-auto installed. Fill token/panel in xui-auto-config.rsc. Dry run: :global XAdry true; /import xui-auto-config.rsc; /import xui-auto.rsc"
}
