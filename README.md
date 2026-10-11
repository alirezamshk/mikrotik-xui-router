# mikrotik-xui-router

<div dir="rtl">

مجموعه اسکریپت برای راه‌اندازی و مدیریت یک **MikroTik / CHR** که کاربران را از طریق **3x-ui (کانتینر)** و **OpenVPN + RADIUS** به چند تونل خروجی (هر کشور یک تونل) می‌فرستد.

ایده اصلی: **اپراتور فقط تونل را می‌سازد و IP ‎/30 را ست می‌کند؛ بقیه مسیر (جدول روتینگ، failover، mangle، IP کانتینر، پورت، OpenVPN) با یک دستور ساخته می‌شود.**

```
$arAdd name=uk iface=gre-to-UK backup=de dns=yes ovpn=1181
```

</div>

---

## ساختار ریپو

| مسیر | کاربرد |
|---|---|
| `scripts/chr-init.rsc` | مرحله ۱ — راه‌اندازی پایه روتر جدید |
| `scripts/chr-container.rsc` | مرحله ۲ — نصب کانتینر 3x-ui |
| `scripts/ar-lib.rsc` | مرحله ۳ — توابع `$arAdd` / `$arDel` / `$arList` |
| `migrate/ar-base.rsc` | مهاجرت یک CHR قدیمی به این ساختار (نمونه، باید با کانفیگ خودتان تطبیق داده شود) |
| `docs/architecture.md` | منطق کارکرد و جریان ترافیک |
| `docs/new-router.md` | راهنمای قدم‌به‌قدم روتر جدید |
| `docs/add-route.md` | اضافه/حذف کردن یک کشور |
| `docs/3x-ui.md` | تنظیمات لازم داخل پنل |
| `docs/operator.md` | چیزهایی که اپراتور تونل باید رعایت کند |
| `docs/troubleshooting.md` | عیب‌یابی (اینستاگرام، DNS، MTU، failover) |

## شروع سریع (روتر جدید)

<div dir="rtl">

۱. فایل‌های `scripts/` را در Files روتر آپلود کنید.
۲. پارامترهای بالای `chr-init.rsc` را ویرایش کنید (WAN، Winbox، RADIUS secret، پورت پنل).
۳. Safe Mode را روشن کنید (`Ctrl+X`) و:

</div>

```
/import chr-init.rsc
```

<div dir="rtl">

۴. اگر پکیج `container` نصب نیست نصب کنید؛ VM را **cold reboot** کنید (برای device-mode).
۵. کانتینر:

</div>

```
/import chr-container.rsc
```

<div dir="rtl">

۶. بعد از اتصال هر تونل توسط اپراتور:

</div>

```
/import ar-lib.rsc
$arAdd name=de iface=gre-to-DE dns=yes direct=yes fallback=yes
$arAdd name=fl iface=gre-to-FL backup=de dns=yes ovpn=1198
$arList
```

<div dir="rtl">

جزئیات کامل در [`docs/new-router.md`](docs/new-router.md).

## قوانین طلایی

- mangle را **دستی ویرایش نکنید**؛ فقط با `$arAdd` / `$arDel`.
- **fasttrack فعال نکنید** — mangle و policy routing را دور می‌زند.
- سمت مقابل هر تونل باید به **ping** جواب بدهد (برای `check-gateway`).
- همه آبجکت‌ها با کامنت `AR:<name>` یا `AR-BASE ...` برچسب دارند.
- `ar-lib` بعد از هر ریبوت باید دوباره `import` شود (توابع global ذخیره نمی‌شوند).

## سازگاری

- RouterOS 7.x (روی 7.24 نوشته شده)
- CHR یا هر دستگاهی که پکیج `container` دارد
- ایمیج 3x-ui: `bigbugcc/3x-ui` (قابل تغییر)

</div>
