# =====================================================================
#  adopt-current-chr.rsc — register the routes that already exist on the
#  current CHR (5.10.248.147) so xui-auto manages them and does not recreate them.
#  Format: XUI|<name>|<iface>|<table>|<port>|<container ip>|<inbound tag>
# =====================================================================
/ip firewall mangle
set [find where comment="GERMANY-9001"]      comment="XUI|de|gre-to-DE|to-de|9001|172.17.0.3|in-9001-tcp"
set [find where comment="FINLAND-9002"]      comment="XUI|fl|gre-to-FL|to-fl|9002|172.17.0.4|in-9002-tcp"
set [find where comment="NETHERLANDS-9003"]  comment="XUI|hl|gre-to-HL|to-hl|9003|172.17.0.5|in-9003-tcp"
set [find where comment="POLAND-9004"]       comment="XUI|pl|l2tp-to-PL|to-pl|9004|172.17.0.6|in-9004-tcp"
set [find where comment="TURKEY-9005"]       comment="XUI|trk|gre-to-TRK|to-trk|9005|172.17.0.7|in-9005-tcp"
set [find where comment="USA-9006"]          comment="XUI|us|gre-to-USA|to-us|9006|172.17.0.8|in-9006-tcp"
set [find where comment="WARP-9007"]         comment="XUI|warp|gre-to-warp|to-warp|9007|172.17.0.9|in-9007-tcp"
set [find where comment="Finland-Ghorbani"]  comment="XUI|fl-ghorbani|gre-ghorbani-FL|to-fl-ghorbani|9009|172.17.0.11|in-9009-tcp"
:put [:len [find where comment~"^XUI\\|"]]
