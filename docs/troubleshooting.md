# عیب‌یابی

<div dir="rtl">

## اینستاگرام (یا سایت‌های فیلتر) باز نمی‌شود

**۱. DNS مسموم** — شایع‌ترین علت.

```
:put [:resolve instagram.com]
```

اگر `10.10.34.x` بود: DNS روتر از ایران می‌رود.

```
/ip route print where dst-address=8.8.8.8/32
/ip dns print
/ip dns cache flush
```

باید روت 8.8.8.8 از یک تونل active باشد (`$arAdd ... dns=yes`). بعد کانتینر را restart کنید تا کش xray خالی شود.

**۲. MTU / MSS** — سایت‌های سبک باز می‌شوند ولی اینستاگرام نه.

```
/ping 157.240.0.174 size=1400 do-not-fragment routing-table=to-<name>
/ip firewall mangle print where action=change-mss
```

**۳. QUIC** — اپ اینستاگرام روی UDP/443. برای تست:

```
/ip firewall filter add chain=forward protocol=udp dst-port=443 src-address=172.17.0.0/24 action=reject comment="test-quic"
```

**۴. ترافیک از مسیر اشتباه**

```
/ip firewall connection print where dst-address~"157.240|31.13"
```

`reply-dst-address` باید IP تونل (`10.20.x.2`) باشد نه IP WAN.

## مسیر DOWN در `$arList`

```
/ping 10.20.<n>.1 count=5
/interface gre print
```

- ping جواب نمی‌دهد → سمت اپراتور (تونل یا ping بسته).
- ping جواب می‌دهد ولی روت inactive → `check-gateway` را چک کنید.

## 3x-ui همه کاربرها را 172.17.0.1 می‌بیند

masquerade بدون `out-interface` وجود دارد:

```
/ip firewall nat print where action=masquerade
```

باید فقط `out-interface=ether1` و `out-interface-list=TUNNELS` باشد.

## پنل 3x-ui از بیرون باز نمی‌شود

- dstnat پنل: `/ip firewall nat print where comment~"panel"`
- قانون `AR-BASE exc port-forward replies` در mangle باید قبل از قوانین mark باشد.

## `$arAdd` خطا داد

| خطا | علت |
|---|---|
| `already exists` | جدول `to-<name>` وجود دارد → `$arDel` |
| `interface not found` | نام اینترفیس اشتباه |
| `no IP address on` | اپراتور IP ‎/30 را ست نکرده |
| `port in use` | پورت در dstnat هست |
| `could not set veth1 address` | کانتینر را stop کنید و دستور چاپ‌شده را بزنید |

## pull کانتینر خطا می‌دهد

Docker Hub آی‌پی ایران را بلاک می‌کند. در `chr-container.rsc` مقدار `REGISTRY` را به یک mirror در دسترس بدهید یا ایمیج را به‌صورت `.tar` آپلود کنید (`FILE`).

</div>
