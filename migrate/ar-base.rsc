# =====================================================================
# NOTE: example from a real CHR (tunnel names, tables, 172.17.0.x, ports 9001-9009).
#       Adapt names/IPs/ports to YOUR router before running. Not for new routers.
#  ar-base.rsc  -  ONE-TIME migration of current CHR to the standard layout
#  RouterOS 7.x
#  Before: /export file=backup-before-ar   and enable Safe Mode (Ctrl+X)
#  Run:    /import ar-base.rsc
# =====================================================================

# ---------- 1) TUNNELS interface list (all GRE + L2TPv3) ----------
:if ([:len [/interface list find name=TUNNELS]] = 0) do={ /interface list add name=TUNNELS }
:foreach i in=[/interface gre find] do={
  :local n [/interface gre get $i name]
  :if ([:len [/interface list member find list=TUNNELS interface=$n]] = 0) do={
    /interface list member add list=TUNNELS interface=$n
  }
}
:foreach i in=[/interface l2tp-ether find] do={
  :local n [/interface l2tp-ether get $i name]
  :if ([:len [/interface list member find list=TUNNELS interface=$n]] = 0) do={
    /interface list member add list=TUNNELS interface=$n
  }
}

# ---------- 2) NAT: masquerade only on WAN + tunnels ----------
# (old masquerade without out-interface hid real client IPs from 3x-ui)
/ip firewall nat remove [find where action=masquerade]
/ip firewall nat add chain=srcnat action=masquerade out-interface=ether1 comment="AR-BASE wan"
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=TUNNELS comment="AR-BASE tunnels"

# tag existing 3x-ui port-forwards
:local ports {"de"=9001;"fl"=9002;"hl"=9003;"pl"=9004;"trk"=9005;"us"=9006;"warp"=9007;"fl-ghorbani"=9009}
:foreach k,v in=$ports do={
  /ip firewall nat set [find where chain=dstnat dst-port=[:tostr $v]] comment=("AR:" . $k)
}

# ---------- 3) Mangle: full rebuild ----------
/ip firewall mangle remove [find dynamic=no]
/ip firewall mangle
# MSS
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1261-65535 dst-address=172.17.0.0/24 new-mss=1260 passthrough=yes comment="AR-BASE mss clients->xui"
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1361-65535 out-interface-list=TUNNELS new-mss=1360 passthrough=yes comment="AR-BASE mss ->tunnels"
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1361-65535 in-interface-list=TUNNELS new-mss=1360 passthrough=yes comment="AR-BASE mss <-tunnels"
# exceptions (stay on main)
add chain=prerouting action=accept dst-address-type=local comment="AR-BASE exc to-router"
add chain=prerouting action=accept connection-nat-state=dstnat comment="AR-BASE exc port-forward replies"
add chain=prerouting action=accept dst-address=172.17.0.0/24 comment="AR-BASE exc to-containers"
# 3x-ui own traffic (direct outbound / DNS) -> DE
add chain=prerouting action=mark-connection src-address=172.17.0.2 connection-state=new new-connection-mark=xui-direct passthrough=yes comment="AR-BASE xui-direct"
add chain=prerouting action=mark-routing src-address=172.17.0.2 connection-mark=xui-direct new-routing-mark=to-de passthrough=no comment="AR-BASE xui-direct"
# 3x-ui outbounds (sendThrough)
add chain=prerouting action=mark-routing src-address=172.17.0.3  new-routing-mark=to-de          passthrough=no comment="AR:de"
add chain=prerouting action=mark-routing src-address=172.17.0.4  new-routing-mark=to-fl          passthrough=no comment="AR:fl"
add chain=prerouting action=mark-routing src-address=172.17.0.5  new-routing-mark=to-hl          passthrough=no comment="AR:hl"
add chain=prerouting action=mark-routing src-address=172.17.0.6  new-routing-mark=to-pl          passthrough=no comment="AR:pl"
add chain=prerouting action=mark-routing src-address=172.17.0.7  new-routing-mark=to-trk         passthrough=no comment="AR:trk"
add chain=prerouting action=mark-routing src-address=172.17.0.8  new-routing-mark=to-us          passthrough=no comment="AR:us"
add chain=prerouting action=mark-routing src-address=172.17.0.9  new-routing-mark=to-warp        passthrough=no comment="AR:warp"
add chain=prerouting action=mark-routing src-address=172.17.0.11 new-routing-mark=to-fl-ghorbani passthrough=no comment="AR:fl-ghorbani"
# OpenVPN users (address-list from PPP profile)
add chain=prerouting action=mark-routing src-address-list=users-hl  new-routing-mark=to-hl  passthrough=no comment="AR:hl"
add chain=prerouting action=mark-routing src-address-list=users-trk new-routing-mark=to-trk passthrough=no comment="AR:trk"
add chain=prerouting action=mark-routing src-address-list=users-fl  new-routing-mark=to-fl  passthrough=no comment="AR:fl"
add chain=prerouting action=mark-routing src-address-list=users-pl  new-routing-mark=to-pl  passthrough=no comment="AR:pl"
add chain=prerouting action=mark-routing src-address-list=users-us  new-routing-mark=to-us  passthrough=no comment="AR:us"
add chain=prerouting action=mark-routing in-interface=all-ppp new-routing-mark=to-de passthrough=no comment="AR-BASE ppp-fallback"

# ---------- 4) Routes: real failover ----------
# GRE is stateless -> without check-gateway the Backup-to-DE routes never activate
/ip route set [find where routing-table~"^to-" dst-address=0.0.0.0/0 distance=1] check-gateway=ping
:foreach t in={"de";"fl";"hl";"pl";"trk";"us";"warp";"fl-ghorbani"} do={
  /ip route set [find where routing-table=("to-" . $t)] comment=("AR:" . $t)
}
# remove old disabled leftovers
/ip route remove [find where disabled=yes]

# DNS of router / unmarked traffic: DE, backup FL
/ip route set [find where comment="DNS-via-DE"] check-gateway=ping
:if ([:len [/ip route find where comment="DNS-backup-FL"]] = 0) do={
  /ip route add dst-address=8.8.8.8/32 gateway=10.20.31.1 distance=10 comment="DNS-backup-FL"
  /ip route add dst-address=1.1.1.1/32 gateway=10.20.31.1 distance=10 comment="DNS-backup-FL"
}

:put "ar-base: done"
