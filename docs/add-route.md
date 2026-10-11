# اضافه / حذف کردن یک مسیر (کشور)

<div dir="rtl">

## اضافه کردن

```
/import ar-lib.rsc
$arAdd name=uk iface=gre-to-UK backup=de
```

| پارامتر | اجباری | توضیح |
|---|---|---|
| `name` | ✔ | نام کوتاه (`uk`, `fl`, ...). جدول `to-<name>` و برچسب `AR:<name>` |
| `iface` | ✔ | اینترفیس تونل که اپراتور ساخته و IP دارد |
| `port` | | پورت inbound؛ پیش‌فرض اولین پورت آزاد از 9001 |
| `backup` | | جدول پشتیبان (`de`) یا `none` (پیش‌فرض) |
| `ovpn` | | پورت UDP برای OpenVPN این کشور (profile + لیست + mangle + firewall) |
| `dns` | | `yes` = DNS روتر از این تونل (اولی اصلی، بعدی‌ها پشتیبان) |
| `direct` | | `yes` = ترافیک خود 3x-ui از این تونل |
| `fallback` | | `yes` = کاربران PPP بدون لیست از این تونل |

اسکریپت خودکار:

- gateway را از ‎/30 پیدا می‌کند
- جدول، روت اصلی با `check-gateway=ping` و روت پشتیبان می‌سازد
- تونل را به لیست `TUNNELS` اضافه می‌کند (MSS، NAT، input)
- اولین IP آزاد `172.17.0.x` را روی `veth1` می‌گذارد
- mangle و dstnat را اضافه می‌کند
- در پایان دقیقاً می‌گوید در 3x-ui چه بسازید

نمونه خروجی:

```
route    : uk  table=to-uk  gw=10.20.38.1 via gre-to-UK
backup   : de
public   : tcp/9010  -> 172.17.0.2:9010
---- now in 3x-ui ----
1) Inbound : port 9010  (Sniffing ON + Route Only ON)
2) Outbound: freedom  tag=out-uk  sendThrough=172.17.0.12
3) Routing : inboundTag=inbound-9010  ->  outboundTag=out-uk
```

> اگر RouterOS اجازه تغییر veth در حال اجرای کانتینر را ندهد، اسکریپت دستور لازم را چاپ می‌کند: کانتینر را stop، دستور را اجرا، start.

## لیست

```
$arList
de      172.17.0.3   port 9001   UP
fl      172.17.0.4   port 9002   BACKUP
```

`BACKUP` یعنی روت اصلی down است و ترافیک از پشتیبان می‌رود.

## حذف

```
$arDel name=uk
```

همه آبجکت‌های `AR:uk` پاک می‌شوند. IP کانتینر آزاد می‌شود و در `$arAdd` بعدی دوباره استفاده می‌شود. inbound/outbound در 3x-ui را دستی پاک کنید.

اگر این مسیر `direct` یا `fallback` بوده، اول آن را به مسیر دیگری منتقل کنید (`$arAdd ... direct=yes` روی مسیر دیگر قانون موجود را به‌روزرسانی می‌کند).

## تغییر یک مسیر

`$arDel` و دوباره `$arAdd` با پارامترهای جدید (با `port=` همان پورت قبلی را نگه دارید تا کلاینت‌ها عوض نشوند).

</div>
