# راه‌اندازی سریع CHR + پنل ثنایی (3x-ui) با خروجی چندکشوری

این فایل همه دستورهای لازم برای ساختن یک سرور مشابه CHR فعلی است. کانفیگ CHR فعلی بعد از تست نهایی (2026-10-11) مبنای آن است.

- **کار اپراتور:** ساخت تونل‌ها، ست کردن IP روی آن‌ها و نصب پنل. این بخش‌ها با «اپراتور» مشخص شده‌اند.
- **کار ما:** بقیه دستورها، یعنی روتینگ.
- **ترتیب اجرا:** بخش‌ها را به ترتیب و در ترمینال RouterOS اجرا کنید.

> قبل از هر کاری: `/system backup save name=before-setup dont-encrypt=yes`

---

## ۰. مقادیر این سرور

قبل از اجرا، این مقادیر را با سرور جدید جایگزین کنید.

| متغیر | مقدار نمونه (CHR فعلی) |
|---|---|
| اینترفیس WAN | `ether1` |
| IP عمومی / gateway | `5.10.248.147/24` / `5.10.248.1` |
| پورت Winbox | `2020` |
| پورت پنل 3x-ui | `2096` |
| شبکه کانتینر | `172.17.0.0/24` (روتر `.1`، پنل `.2`) |
| مسیر پیش‌فرض (DNS و ترافیک خود پنل) | `de` |

### جدول مسیرها

هر ردیف یک کشور است. سه ستون آخر را اپراتور می‌دهد.

| نام | پورت inbound | IP کانتینر (sendThrough) | اینترفیس تونل | IP سمت ما | Gateway |
|---|---|---|---|---|---|
| de | 9001 | 172.17.0.3 | gre-to-DE | 10.20.36.2/30 | 10.20.36.1 |
| fl | 9002 | 172.17.0.4 | gre-to-FL | 10.20.31.2/30 | 10.20.31.1 |
| hl | 9003 | 172.17.0.5 | gre-to-HL | 10.20.30.2/30 | 10.20.30.1 |
| pl | 9004 | 172.17.0.6 | l2tp-to-PL | 10.20.32.2/30 | 10.20.32.1 |
| trk | 9005 | 172.17.0.7 | gre-to-TRK | 10.20.33.2/30 | 10.20.33.1 |
| us | 9006 | 172.17.0.8 | gre-to-USA | 10.20.34.2/30 | 10.20.34.1 |
| warp | 9007 | 172.17.0.9 | gre-to-warp | 10.20.35.2/30 | 10.20.35.1 |
| fl-ghorbani | 9009 | 172.17.0.11 | gre-ghorbani-FL | 10.20.37.2/30 | 10.20.37.1 |

---

## ۱. پایه سیستم

```
/system identity set name=CHR
/system clock set time-zone-name=Asia/Tehran

/ip address add address=5.10.248.147/24 interface=ether1
/ip route add dst-address=0.0.0.0/0 gateway=5.10.248.1

/ip service
set ftp disabled=yes
set ssh disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox port=2020

/ip neighbor discovery-settings set discover-interface-list=none
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=none
/tool mac-server ping set enabled=no
/tool bandwidth-server set enabled=no

# DNS روتر از WAN قابل دسترس نباشد
/ip firewall filter
add chain=input action=drop protocol=udp in-interface=ether1 dst-port=53
add chain=input action=drop protocol=tcp in-interface=ether1 dst-port=53
```

> **fasttrack اضافه نکنید.** fasttrack از mangle عبور نمی‌کند و policy routing را خراب می‌کند.

---

## ۲. تونل‌ها (اپراتور)

نمونه یک تونل. همین کار برای هر ردیف جدول تکرار می‌شود.

```
/interface gre add name=gre-to-DE remote-address=46.4.181.193
/ip address add address=10.20.36.2/30 interface=gre-to-DE
/ping 10.20.36.1 count=3
```

L2TPv3 (مثل لهستان):

```
/interface l2tp-ether add name=l2tp-to-PL connect-to=<REMOTE-IP> local-address=<WAN-IP> \
    l2tp-proto-version=l2tpv3-ip unmanaged-mode=yes use-l2-specific-sublayer=no \
    local-tunnel-id=64 remote-tunnel-id=54 local-session-id=644 remote-session-id=544 cookie-length=0
/ip address add address=10.20.32.2/30 interface=l2tp-to-PL
```

**الزامات سمت سرور خارج:**

- masquerade برای همان /30
- جواب به ping روی `.1`
- MTU حداقل 1400
- هیچ DNAT یا REDIRECTی بدون شرط مقصد نداشته باشد. این همان مشکل پورت 8080 سرور قربانی بود.

---

## ۳. لیست تونل‌ها

```
/interface list add name=TUNNELS comment="exit tunnels"
:foreach i in={"gre-to-DE";"gre-to-FL";"gre-to-HL";"l2tp-to-PL";"gre-to-TRK";"gre-to-USA";"gre-to-warp";"gre-ghorbani-FL"} do={
  /interface list member add list=TUNNELS interface=$i
}
```

---

## ۴. جدول‌ها و روت‌ها

```
/routing table
add name=to-de fib
add name=to-fl fib
add name=to-hl fib
add name=to-pl fib
add name=to-trk fib
add name=to-us fib
add name=to-warp fib
add name=to-fl-ghorbani fib

/ip route
add dst-address=0.0.0.0/0 routing-table=to-de          gateway=10.20.36.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-fl          gateway=10.20.31.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-hl          gateway=10.20.30.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-pl          gateway=10.20.32.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-trk         gateway=10.20.33.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-us          gateway=10.20.34.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-warp        gateway=10.20.35.1 check-gateway=ping
add dst-address=0.0.0.0/0 routing-table=to-fl-ghorbani gateway=10.20.37.1 check-gateway=ping

# پشتیبان به آلمان. فقط وقتی روت اصلی با ping قطع شود فعال می‌شود.
:foreach t in={"to-fl";"to-hl";"to-pl";"to-trk";"to-us"} do={
  /ip route add dst-address=0.0.0.0/0 routing-table=$t gateway=10.20.36.1 distance=10 comment=Backup-to-DE
}
```

> یک مسیری که باید فقط از تونل خودش برود (مثل قربانی) روت Backup نمی‌گیرد.

---

## ۵. DNS از طریق تونل

DNS ایران دامنه‌های فیلترشده را به `10.10.34.x` برمی‌گرداند، حتی وقتی کوئری به 8.8.8.8 فرستاده شود. پس DNS باید از تونل برود.

```
/ip route
add dst-address=8.8.8.8/32 gateway=10.20.36.1 comment=DNS-via-DE
add dst-address=1.1.1.1/32 gateway=10.20.36.1 comment=DNS-via-DE

/ip dns set servers=8.8.8.8,1.1.1.1 allow-remote-requests=yes use-doh-server=https://8.8.8.8/dns-query verify-doh-cert=no
/ip dns cache flush
:put [:resolve instagram.com]
```

جواب باید `157.240.x.x` یا `31.13.x.x` باشد. اگر `10.10.34.x` بود، روت‌های DNS-via-DE را چک کنید.

---

## ۶. شبکه کانتینر و پنل (اپراتور / یک‌بار)

```
# حالت کانتینر. بعد از این دستور VM را کامل خاموش و روشن کنید.
/system device-mode update container=yes

/interface bridge add name=dockers
/ip address add address=172.17.0.1/24 interface=dockers

# veth: .2 آدرس اصلی پنل است، .3 به بعد یکی برای هر مسیر
/interface veth add name=veth1 gateway=172.17.0.1 \
    address=172.17.0.2/24,172.17.0.3/24,172.17.0.4/24,172.17.0.5/24,172.17.0.6/24,172.17.0.7/24,172.17.0.8/24,172.17.0.9/24,172.17.0.10/24,172.17.0.11/24
/interface bridge port add bridge=dockers interface=veth1

/container config set registry-url=https://registry-1.docker.io tmpdir=disk1/pull
# دیتابیس پنل در /etc/x-ui است و باید mount شود، وگرنه با pull دوباره از بین می‌رود
/container mounts add list=MOUNT_XUI src=/disk1/xui dst=/etc/x-ui
/container envs add list=ENV_XUI key=TZ value=Asia/Tehran
/container add name=xui remote-image=bigbugcc/3x-ui:latest interface=veth1 \
    root-dir=disk1/containers/3x-ui dns=8.8.8.8,1.1.1.1 workdir=/app \
    mountlists=MOUNT_XUI envlists=ENV_XUI ignore-remote-image-change=yes \
    start-on-boot=yes logging=yes
/container start [find name=xui]
```

> Docker Hub آی‌پی‌های ایران را بلاک می‌کند. اگر pull خطا داد، در `registry-url` یک mirror در دسترس بگذارید یا ایمیج را به‌صورت `.tar` آپلود کنید و با `file=` اضافه کنید.

---

## ۷. NAT

```
/ip firewall nat
add chain=srcnat action=masquerade out-interface=ether1 comment="SRCNAT: WAN"
add chain=srcnat action=masquerade out-interface-list=TUNNELS comment="SRCNAT: tunnels"
```

پورت پنل و inboundها. شرط `dst-address-type=local` **ضروری است**. بدون آن، ترافیک کاربرها به همین پورت‌ها روی هر سایتی به پنل خودمان منحرف می‌شود.

```
/ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-address-type=local dst-port=2096 to-addresses=172.17.0.2 to-ports=2096 comment=PANEL
:foreach p,c in={"9001"="GERMANY";"9002"="FINLAND";"9003"="NETHERLANDS";"9004"="POLAND";"9005"="TURKEY";"9006"="USA";"9007"="WARP";"9009"="FINLAND-Ghorbani"} do={
  /ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-address-type=local dst-port=$p to-addresses=172.17.0.2 to-ports=$p comment=$c
}
```

> **هرگز** masquerade بدون `out-interface` نگذارید. در آن حالت 3x-ui همه کاربرها را با آدرس `172.17.0.1` می‌بیند و IP Limit و Fail2ban از کار می‌افتند.

---

## ۸. Mangle

```
/ip firewall mangle

# ترافیک خود پنل (DoH، outbound direct) از مسیر پیش‌فرض برود
add chain=prerouting action=mark-connection src-address=172.17.0.2 connection-state=new dst-address-type=!local new-connection-mark=xui-direct passthrough=yes comment=XUI-DIRECT
add chain=prerouting action=mark-routing src-address=172.17.0.2 connection-mark=xui-direct new-routing-mark=to-de passthrough=no comment=XUI-DIRECT

# هر مسیر: IP مبدأ کانتینر تعیین می‌کند ترافیک به کدام جدول برود
add chain=prerouting action=mark-routing src-address=172.17.0.3  dst-address-type=!local new-routing-mark=to-de          passthrough=no comment=GERMANY-9001
add chain=prerouting action=mark-routing src-address=172.17.0.4  dst-address-type=!local new-routing-mark=to-fl          passthrough=no comment=FINLAND-9002
add chain=prerouting action=mark-routing src-address=172.17.0.5  dst-address-type=!local new-routing-mark=to-hl          passthrough=no comment=NETHERLANDS-9003
add chain=prerouting action=mark-routing src-address=172.17.0.6  dst-address-type=!local new-routing-mark=to-pl          passthrough=no comment=POLAND-9004
add chain=prerouting action=mark-routing src-address=172.17.0.7  dst-address-type=!local new-routing-mark=to-trk         passthrough=no comment=TURKEY-9005
add chain=prerouting action=mark-routing src-address=172.17.0.8  dst-address-type=!local new-routing-mark=to-us          passthrough=no comment=USA-9006
add chain=prerouting action=mark-routing src-address=172.17.0.9  dst-address-type=!local new-routing-mark=to-warp        passthrough=no comment=WARP-9007
add chain=prerouting action=mark-routing src-address=172.17.0.11 dst-address-type=!local new-routing-mark=to-fl-ghorbani passthrough=no comment=Finland-Ghorbani

# MSS
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1261-65535 dst-address=172.17.0.0/24 new-mss=1260 passthrough=yes comment="MSS: clients -> 3x-ui"
add chain=forward action=change-mss protocol=tcp tcp-flags=syn tcp-mss=1281-65535 src-address=172.17.0.0/24 new-mss=1280 passthrough=yes comment="MSS: 3x-ui -> tunnels"
```

---

## ۹. پنل ثنایی (Xray)

### inboundها

برای هر مسیر یک inbound بسازید:

- **پورت:** همان پورت جدول، مثلاً 9001.
- **Tag:** `in-9001-tcp` و به همین الگو برای بقیه.
- **Sniffing:** روشن، با `http` و `tls` و `quic`. Route Only خاموش.
- **امنیت:** **Reality** را به‌جای `security: none` توصیه می‌کنم. بدون رمزنگاری، DPI ترافیک را تشخیص می‌دهد.

### Xray Configs → Advanced

این متن را جایگزین کنید. برای هر مسیر جدید، یک outbound و یک قانون routing به همین الگو اضافه می‌شود.

```json
{
  "inbounds": [
    { "listen": "127.0.0.1", "port": 62789, "protocol": "tunnel", "settings": { "rewriteAddress": "127.0.0.1" }, "tag": "api" }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom",
      "settings": { "finalRules": [ { "action": "block", "ip": ["geoip:private"] }, { "action": "allow" } ] },
      "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9001", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.3",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9002", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.4",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9003", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.5",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9004", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.6",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9005", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.7",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9006", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.8",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9007", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.9",  "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "out-9009", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.11", "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } },
    { "tag": "dns-out", "protocol": "dns", "settings": {} },
    { "tag": "blocked", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" },
      { "type": "field", "port": "53", "network": "tcp,udp", "outboundTag": "dns-out" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked" },
      { "type": "field", "inboundTag": ["in-9001-tcp"], "outboundTag": "out-9001" },
      { "type": "field", "inboundTag": ["in-9002-tcp"], "outboundTag": "out-9002" },
      { "type": "field", "inboundTag": ["in-9003-tcp"], "outboundTag": "out-9003" },
      { "type": "field", "inboundTag": ["in-9004-tcp"], "outboundTag": "out-9004" },
      { "type": "field", "inboundTag": ["in-9005-tcp"], "outboundTag": "out-9005" },
      { "type": "field", "inboundTag": ["in-9006-tcp"], "outboundTag": "out-9006" },
      { "type": "field", "inboundTag": ["in-9007-tcp"], "outboundTag": "out-9007" },
      { "type": "field", "inboundTag": ["in-9009-tcp"], "outboundTag": "out-9009" }
    ]
  },
  "dns": {
    "tag": "dns_inbound",
    "servers": ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"],
    "queryStrategy": "UseIPv4"
  },
  "log": { "access": "none", "error": "", "loglevel": "warning", "dnsLog": false, "maskAddress": "" },
  "policy": {
    "system": { "statsInboundDownlink": true, "statsInboundUplink": true, "statsOutboundDownlink": false, "statsOutboundUplink": false },
    "levels": { "0": { "statsUserDownlink": true, "statsUserUplink": true } }
  },
  "api": { "services": ["HandlerService", "LoggerService", "StatsService", "RoutingService"], "tag": "api" },
  "metrics": { "listen": "127.0.0.1:11111", "tag": "metrics_out" },
  "stats": {}
}
```

**ترتیب‌هایی که نباید عوض شوند:**

- `direct` باید **اولین outbound** باشد. Xray کوئری‌های DoH خودش را از outbound اول می‌فرستد، که از آدرس 172.17.0.2 و با قانون XUI-DIRECT از تونل آلمان می‌رود.
- قانون پورت 53 و قانون‌های private و bittorrent باید **قبل از** قانون‌های inbound باشند. اگر بعد از آن‌ها باشند هیچ‌وقت اجرا نمی‌شوند.

بعد از ذخیره: **Save** و بعد **Restart Xray**.

---

## ۱۰. تست

روی روتر:

```
/ip route print where routing-table~"^to-" dst-address=0.0.0.0/0
:put [:resolve instagram.com]
/container shell [find name=xui]
```

داخل کانتینر. همه مسیرها باید `ig=200` بدهند، IP خروجی هر کدام باید مال همان کشور باشد، و سرعت دانلود قابل قبول باشد:

```
for i in 2 3 4 5 6 7 8 9 11; do a=172.17.0.$i; echo "$a ip=$(curl --interface $a -m 8 -s https://ifconfig.me) ig=$(curl --interface $a -m 8 -s -o /dev/null -w '%{http_code}' https://www.instagram.com) http=$(curl --interface $a -m 8 -s -o /dev/null -w '%{http_code}' http://example.com) dl=$(curl --interface $a -m 15 -s -o /dev/null -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=10000000')"; done
```

تست پورت‌ها روی یک مسیر. اگر speedtest خطا داد، باید پورت 8080 جواب بدهد:

```
for p in 80 443 5222 8080 8443 2053; do echo "$p $(curl --interface 172.17.0.11 -m 6 -s -o /dev/null -w '%{http_code}' http://portquiz.net:$p/)"; done
exit
```

---

## ۱۱. بکاپ نهایی

```
/system backup save name=after-setup dont-encrypt=yes
/export file=after-setup
```

---

## افزودن یک مسیر جدید

مثال: انگلیس روی پورت 9010 با IP آزاد 172.17.0.10. فرض این است که اپراتور تونل `gre-to-UK` را با آدرس `10.20.38.2/30` ساخته است.

```
/routing table add name=to-uk fib
/ip route add dst-address=0.0.0.0/0 routing-table=to-uk gateway=10.20.38.1 check-gateway=ping
/ip route add dst-address=0.0.0.0/0 routing-table=to-uk gateway=10.20.36.1 distance=10 comment=Backup-to-DE
/interface list member add list=TUNNELS interface=gre-to-UK
/ip firewall mangle add chain=prerouting action=mark-routing src-address=172.17.0.10 dst-address-type=!local new-routing-mark=to-uk passthrough=no comment=UK-9010 place-before=[find comment="MSS: clients -> 3x-ui"]
/ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-address-type=local dst-port=9010 to-addresses=172.17.0.2 to-ports=9010 comment=UK
```

اگر IP جدید روی `veth1` نیست، کانتینر را stop کنید، آدرس را به لیست `address` در `veth1` اضافه کنید و دوباره start کنید.

در پنل:

1. inbound پورت 9010 با tag `in-9010-tcp` و Sniffing روشن.
2. outbound زیر:
   ```json
   { "tag": "out-9010", "protocol": "freedom", "settings": {}, "sendThrough": "172.17.0.10", "streamSettings": { "sockopt": { "domainStrategy": "UseIPv4" } } }
   ```
3. قانون routing زیر، بعد از قانون‌های block:
   ```json
   { "type": "field", "inboundTag": ["in-9010-tcp"], "outboundTag": "out-9010" }
   ```

در آخر تست: `curl --interface 172.17.0.10 https://ifconfig.me` از داخل کانتینر.
