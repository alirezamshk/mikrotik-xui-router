# =====================================================================
#  xui-auto-config.rsc — settings for xui-auto (edit, then upload to router Files)
# =====================================================================
:global XAcfg {
  "panel"="http://172.17.0.2:2096/";
  "token"="";
  "sni"="www.speedtest.net";
  "portStart"=9001;
  "veth"="veth1";
  "types"="gre-tunnel,l2tp-ether,eoip-tunnel,ipip-tunnel,wg";
  "exclude"="";
  "backup"="";
  "dnsVia"="";
  "tplFile"="disk1/xui/xui-auto-template.json"
}
# panel     : panel URL from the router, INCLUDING the web base path and a trailing /
#             e.g. "http://172.17.0.2:2096/mypath/"
# token     : 3x-ui API token (Settings -> API Tokens). Empty = routing only, no panel changes
# sni       : Reality target / serverName for new inbounds
# portStart : first inbound port; the next free one is used for each new tunnel
# veth      : container veth interface (its addresses are the sendThrough pool)
# types     : interface types treated as exit tunnels
# exclude   : comma-separated interface names to ignore
# backup    : route name (e.g. "de") used as distance=10 backup for new routes; "" = none
# dnsVia    : route name for router DNS + 3x-ui own traffic; "" = first route
# tplFile   : where the dry run writes the generated Xray template
