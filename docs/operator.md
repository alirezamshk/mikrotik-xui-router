# الزامات سمت اپراتور تونل

<div dir="rtl">

اپراتور فقط تونل را می‌سازد. برای اینکه `$arAdd` درست کار کند:

1. **یک ‎/30 مستقل برای هر تونل** (پیشنهاد: `10.20.<n>.0/30`، سمت ایران `.2`، سمت خارج `.1`).
2. IP سمت ایران **روی اینترفیس تونل** در روتر ایران ست شده باشد.
3. سمت خارج **NAT/masquerade** برای همان ‎/30 به اینترنت (روتر ایران همه ترافیک را با IP تونل خودش می‌فرستد).
4. سمت خارج به **ping** روی IP تونل جواب بدهد (`check-gateway`).
5. MTU تونل حداقل 1400 (MSS روی 1360 clamp می‌شود).
6. برای نام اینترفیس از الگوی ثابت استفاده شود: `gre-to-<COUNTRY>` / `l2tp-to-<COUNTRY>`.

## نمونه سمت خارج (MikroTik)

```
/interface gre add name=gre-to-IR remote-address=<IRAN-WAN-IP>
/ip address add address=10.20.38.1/30 interface=gre-to-IR
/ip firewall nat add chain=srcnat src-address=10.20.38.0/30 out-interface=ether1 action=masquerade
/ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss new-mss=clamp-to-pmtu
```

## نمونه سمت خارج (Linux)

```bash
ip tunnel add gre-to-IR mode gre remote <IRAN-WAN-IP> local <SERVER-IP> ttl 255
ip addr add 10.20.38.1/30 dev gre-to-IR
ip link set gre-to-IR up mtu 1476
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.20.38.0/30 -o eth0 -j MASQUERADE
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

## سمت ایران (قبل از `$arAdd`)

```
/interface gre add name=gre-to-UK remote-address=<SERVER-IP>
/ip address add address=10.20.38.2/30 interface=gre-to-UK
/ping 10.20.38.1 count=3
```

</div>
