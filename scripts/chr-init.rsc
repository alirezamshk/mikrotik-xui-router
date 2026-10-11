# =====================================================================
#  chr-init.rsc  -  bootstrap a NEW MikroTik/CHR for the 3x-ui + tunnels layout
#  RouterOS 7.x   |   run on a clean router:  /import chr-init.rsc
#  Phase 1 of 3:
#     1) chr-init.rsc        (this file)  -> base system, firewall, NAT, mangle, PPP/RADIUS
#     2) chr-container.rsc   (after device-mode reboot) -> 3x-ui container
#     3) ar-lib.rsc + $arAdd (per tunnel, after operator connects it)
# =====================================================================

# ------------------------- PARAMETERS (edit) -------------------------
:local IDENTITY   "CHR-NEW"
:local WAN        "ether1"
# WAN addressing: set WANIP="" to use DHCP client
:local WANIP      "203.0.113.10/24"
:local WANGW      "203.0.113.1"
:local WINBOX     2020
:local RADIUS     "198.51.100.20"
:local RADSECRET  "CHANGE-ME"
:local PANELPORT  2096
:local OVPN       "yes"
:local CONTAINER  "yes"
# ---------------------------------------------------------------------

# ---------- system ----------
/system identity set name=$IDENTITY
/system clock set time-zone-name=Asia/Tehran
/system ntp client set enabled=yes servers=pool.ntp.org

# ---------- WAN ----------
:if ($WANIP = "") do={
  /ip dhcp-client add interface=$WAN disabled=no
} else={
  /ip address add address=$WANIP interface=$WAN
  /ip route add dst-address=0.0.0.0/0 gateway=$WANGW comment="AR-BASE wan-default"
}

# ---------- services / hardening ----------
/ip service set ftp disabled=yes
/ip service set ssh disabled=yes
/ip service set telnet disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set winbox port=$WINBOX
/ip neighbor discovery-settings set discover-interface-list=none
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=none
/tool mac-server ping set enabled=no
/tool bandwidth-server set enabled=no

# ---------- DNS (plain until a tunnel is added with dns=yes) ----------
/ip dns set allow-remote-requests=yes servers=8.8.8.8,1.1.1.1

# ---------- interface lists ----------
/interface list add name=TUNNELS

# ---------- container network (bridge + veth) ----------
:if ($CONTAINER = "yes") do={
  /interface bridge add name=dockers
  /ip address add address=172.17.0.1/24 interface=dockers
  /interface veth add name=veth1 address=172.17.0.2/24 gateway=172.17.0.1
  /interface bridge port add bridge=dockers interface=veth1
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-port=$PANELPORT \
      to-addresses=172.17.0.2 to-ports=$PANELPORT comment="AR-BASE 3x-ui panel"
}

# ---------- firewall filter ----------
/ip firewall filter
add chain=input action=accept connection-state=established,related,untracked comment="AR-BASE in est"
add chain=input action=drop connection-state=invalid comment="AR-BASE in invalid"
add chain=input action=accept protocol=icmp comment="AR-BASE in icmp"
add chain=input action=accept protocol=gre comment="AR-BASE in gre"
add chain=input action=accept protocol=115 comment="AR-BASE in l2tpv3"
add chain=input action=accept protocol=tcp dst-port=$WINBOX comment="AR-BASE in winbox"
add chain=input action=accept protocol=udp dst-port=3799 src-address=$RADIUS comment="AR-BASE in radius-coa"
add chain=input action=accept in-interface=dockers comment="AR-BASE in containers"
add chain=input action=accept in-interface=all-ppp comment="AR-BASE in ppp"
add chain=input action=accept in-interface-list=TUNNELS comment="AR-BASE in tunnels"
add chain=input action=drop in-interface=$WAN comment="AR-BASE drop wan"
add chain=forward action=accept connection-state=established,related,untracked comment="AR-BASE fw est"
add chain=forward action=drop connection-state=invalid comment="AR-BASE fw invalid"
# NOTE: no fasttrack on purpose - fasttrack bypasses mangle/policy routing

# ---------- NAT ----------
/ip firewall nat
add chain=srcnat action=masquerade out-interface=$WAN comment="AR-BASE wan"
add chain=srcnat action=masquerade out-interface-list=TUNNELS comment="AR-BASE tunnels"

# ---------- mangle (base; routes are added by $arAdd) ----------
/ip firewall mangle
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1261-65535 dst-address=172.17.0.0/24 new-mss=1260 passthrough=yes comment="AR-BASE mss clients->xui"
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1361-65535 out-interface-list=TUNNELS new-mss=1360 passthrough=yes comment="AR-BASE mss ->tunnels"
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1361-65535 in-interface-list=TUNNELS new-mss=1360 passthrough=yes comment="AR-BASE mss <-tunnels"
add chain=prerouting action=accept dst-address-type=local comment="AR-BASE exc to-router"
add chain=prerouting action=accept connection-nat-state=dstnat comment="AR-BASE exc port-forward replies"
add chain=prerouting action=accept dst-address=172.17.0.0/24 comment="AR-BASE exc to-containers"

# ---------- PPP / RADIUS / OpenVPN ----------
:if ($OVPN = "yes") do={
  /ip pool add name=Global-VPN-Pool ranges=10.50.0.2-10.50.255.254
  /ppp profile add name=Base-VPN-Profile local-address=10.50.0.1 remote-address=Global-VPN-Pool dns-server=8.8.8.8,1.1.1.1
  /ppp aaa set use-radius=yes interim-update=59s use-circuit-id-in-nas-port-id=yes
  /radius add address=$RADIUS secret=$RADSECRET service=ppp,login,ipsec
  /radius incoming set accept=yes

  # self-signed CA + server certificate for ovpn-server
  /certificate add name=ca-tpl common-name=AR-CA key-usage=key-cert-sign,crl-sign days-valid=3650
  /certificate sign ca-tpl name=AR-CA
  :delay 3s
  /certificate add name=srv-tpl common-name=AR-SERVER key-usage=digital-signature,key-encipherment,tls-server days-valid=3650
  /certificate sign srv-tpl ca=AR-CA name=server
  :delay 3s
}

# ---------- container mode ----------
:if ($CONTAINER = "yes") do={
  :if ([:len [/system package find name=container]] = 0) do={
    :put "!! container package is NOT installed: upload container-<ver>.npk, reboot, then continue"
  }
  :if ([/system device-mode get container] != true) do={
    :put "!! device-mode: requesting container=yes -> COLD REBOOT the VM (power off/on) within 5 min"
    /system device-mode update container=yes
  }
}

:put "chr-init: done.  Next: chr-container.rsc  then  /import ar-lib.rsc + \$arAdd"
