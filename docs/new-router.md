# راه‌اندازی روتر جدید

<div dir="rtl">

## پیش‌نیاز

- CHR / MikroTik با RouterOS 7.x
- دیسک برای کانتینر (پیش‌فرض `disk1`)
- پکیج `container` (از Extra packages هم‌نسخه RouterOS)
- secret سرور RADIUS

## مرحله ۱ — `chr-init.rsc`

پارامترهای بالای فایل:

| پارامتر | توضیح |
|---|---|
| `IDENTITY` | نام روتر |
| `WAN` | اینترفیس WAN (پیش‌فرض `ether1`) |
| `WANIP` / `WANGW` | IP ثابت؛ `WANIP=""` یعنی DHCP |
| `WINBOX` | پورت Winbox (تنها سرویس مدیریتی باز) |
| `RADIUS` / `RADSECRET` | سرور RADIUS |
| `PANELPORT` | پورت پنل 3x-ui که از WAN باز می‌شود |
| `OVPN` | `yes` = pool، PPP، RADIUS و گواهی OpenVPN |
| `CONTAINER` | `yes` = bridge/veth و درخواست device-mode |

```
/import chr-init.rsc
```

> ⚠️ firewall input همه چیز از WAN را جز Winbox/GRE/L2TPv3/ICMP/CoA می‌بندد. قبل از اجرا مطمئن شوید با همان پورت `WINBOX` وصل می‌شوید و Safe Mode روشن است.

بعد از اجرا:

1. اگر پیام `container package is NOT installed` آمد: `container-7.x.npk` را آپلود و ریبوت کنید.
2. `device-mode`: ظرف ۵ دقیقه VM را از hypervisor **خاموش/روشن** کنید (ریبوت نرم کافی نیست).
3. بررسی: `/system device-mode print` → `container: yes`

## مرحله ۲ — `chr-container.rsc`

| پارامتر | توضیح |
|---|---|
| `DISK` | دیسک کانتینر |
| `IMAGE` | ایمیج 3x-ui |
| `REGISTRY` | Docker Hub از ایران بلاک است → mirror داخلی |
| `FILE` | اگر ایمیج را به‌صورت `.tar` آپلود کرده‌اید |

```
/import chr-container.rsc
```

بعد وارد پنل شوید، پورت پنل را روی `PANELPORT` بگذارید و رمز پیش‌فرض را عوض کنید.

## مرحله ۳ — تونل‌ها

وقتی اپراتور تونل را وصل کرد و IP ‎/30 روی اینترفیس است ([`operator.md`](operator.md)):

```
/import ar-lib.rsc
$arAdd name=de iface=gre-to-DE dns=yes direct=yes fallback=yes
```

اولین تونل معمولاً «تونل اصلی» است: DNS روتر، ترافیک مستقیم 3x-ui و fallback کاربران PPP. بقیه: [`add-route.md`](add-route.md).

## چک‌لیست نهایی

```
:put [:resolve instagram.com]          # نباید 10.10.34.x باشد
$arList                                 # همه UP
/ip route print where routing-table~"^to-"
/ip firewall nat print where action=masquerade   # فقط 2 قانون
/container print
```

</div>
