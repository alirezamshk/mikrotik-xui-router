# معماری و منطق کارکرد

<div dir="rtl">

## اجزا

- **WAN** (`ether1`): IP عمومی ایران. ترافیکی که mark نخورده از جدول `main` مستقیم از ایران خارج می‌شود.
- **تونل‌ها**: هر کشور یک تونل (GRE یا L2TPv3) با یک ‎/30 جدا. معمولاً سمت ما `.2` و سمت مقابل `.1` (اسکریپت هر دو حالت را تشخیص می‌دهد).
- **جدول روتینگ** برای هر کشور: `to-<name>` با روت اصلی (`check-gateway=ping`) و در صورت نیاز روت پشتیبان (`distance=10`).
- **3x-ui** در کانتینر روی `veth1`:
  - `172.17.0.2` آدرس اصلی؛ همه inboundها روی آن هستند (dstnat پورت‌ها از WAN).
  - `172.17.0.3` به بعد: هر کشور یک IP که در outbound با `sendThrough` استفاده می‌شود.
- **OpenVPN + RADIUS**: هر کشور یک ovpn-server روی پورت جدا، با profile‌ای که IP کاربر را به `users-<name>` اضافه می‌کند.

## جریان ترافیک — کاربر 3x-ui

```
Client ──► WAN:9002 ──dstnat──► 172.17.0.2:9002 (inbound)
                                     │ xray routing: inbound-9002 → out-fl
                                     ▼
                      outbound freedom, sendThrough=172.17.0.4
                                     │
              mangle: src=172.17.0.4 → routing-mark=to-fl
                                     ▼
              table to-fl: 0.0.0.0/0 → 10.20.31.1 (gre-to-FL)
                                     ▼
                     masquerade (TUNNELS) → Finland
```

## جریان ترافیک — کاربر OpenVPN

```
Client ──► ovpn-server "fl" (udp/1198) ──► profile-fl ──► address-list users-fl
        mangle: src-address-list=users-fl → to-fl → gre-to-FL
```

کاربر PPP که در هیچ لیستی نیست → قانون `AR-BASE ppp-fallback`.

## ترتیب mangle

| ترتیب | قانون | چرا |
|---|---|---|
| 1 | MSS (forward) | جلوگیری از گیر کردن پکت بزرگ در تونل (مشکل کلاسیک اینستاگرام) |
| 2 | accept `dst-address-type=local` | ترافیک به خود روتر وارد تونل نشود |
| 3 | accept `connection-nat-state=dstnat` | جواب پنل و inboundها از WAN برگردد نه تونل |
| 4 | accept `dst-address=172.17.0.0/24` | ترافیک به کانتینر |
| 5 | xui-direct | ترافیک خود 3x-ui (DNS / outbound direct) |
| 6 | `AR:<name>` src=172.17.0.x | خروجی‌های 3x-ui |
| 7 | `AR:<name>` users-<name> | کاربران OpenVPN (همیشه قبل از fallback) |
| 8 | ppp-fallback | آخرین قانون |

## DNS

DNS ایران (حتی پورت 53 به‌سمت 8.8.8.8) دستکاری می‌شود و دامنه‌های فیلتر را به `10.10.34.x` برمی‌گرداند. بنابراین:

- روت `8.8.8.8/32` و `1.1.1.1/32` در جدول main از تونل (`dns=yes`) + DoH روی روتر.
- 3x-ui با DNS سیستمی از `172.17.0.2` resolve می‌کند → با `direct=yes` از تونل می‌رود.
- برای اینکه DNS هر کاربر از تونل کشور خودش برود: در inbound‌ها **Sniffing + Route Only** روشن؛ Remote DNS کلاینت داخل پروکسی و با sendThrough همان کشور می‌رود.
- کاربران PPP: DNS عمومی (8.8.8.8) از profile داده می‌شود تا کوئری‌شان همراه بقیه ترافیک mark بخورد.

## NAT

- `masquerade out-interface=ether1` و `masquerade out-interface-list=TUNNELS`.
- **هرگز** masquerade بدون out-interface نگذارید: ترافیک به کانتینر هم NAT می‌شود و 3x-ui همه را `172.17.0.1` می‌بیند (IP Limit / Fail2ban از کار می‌افتد).

## Failover

GRE stateless است؛ اینترفیس همیشه running می‌ماند. پس failover فقط با `check-gateway=ping` روی روت اصلی کار می‌کند. سمت مقابل تونل باید ping را جواب بدهد.

</div>
