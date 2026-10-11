# راه‌اندازی خودکار (xui-auto)

<div dir="rtl">

**اپراتور فقط تونل را می‌سازد و IP ‎/30 را روی آن می‌گذارد.** حداکثر یک دقیقه بعد، xui-auto بقیه کارها را خودش انجام می‌دهد:

1. جدول `to-<name>` و روت پیش‌فرض با `check-gateway=ping`
2. اضافه کردن تونل به لیست `TUNNELS` (srcnat)
3. انتخاب یک IP آزاد کانتینر (`172.17.0.x`) و یک پورت آزاد (از 9001 به بعد)
4. mangle (`src 172.17.0.x → to-<name>`) و dstnat پورت با `dst-address-type=local`
5. ساخت inbound از نوع **VLESS + Reality** در پنل 3x-ui (از طریق API)
6. بازسازی کامل کانفیگ Xray: برای هر مسیر یک outbound با `sendThrough`، به‌اضافه DoH و `dns-out`
7. اولین مسیر (یا مسیر `dnsVia`) DNS روتر و ترافیک خود پنل را حمل می‌کند

اسم مسیر از اسم اینترفیس می‌آید: `gre-to-UK` → `uk`، `l2tp-to-PL` → `pl`.

## فایل‌ها

| فایل | کار |
|---|---|
| `auto/xui-auto.rsc` | منطق اصلی؛ هر دقیقه با scheduler اجرا می‌شود |
| `auto/xui-auto-config.rsc` | تنظیمات (آدرس پنل، توکن API، SNI و ...) |
| `auto/xui-auto-install.rsc` | نصب یک‌باره: TUNNELS، NAT، MSS، استخر IP روی veth، scheduler |
| `auto/adopt-current-chr.rsc` | ثبت مسیرهای موجود CHR فعلی در رجیستری |

## رجیستری

هر مسیر یک قانون mangle با کامنت زیر است:

```
XUI|<name>|<iface>|<table>|<port>|<container-ip>|<inbound-tag>
```

`-` در آخر یعنی inbound هنوز ساخته نشده است. اسکریپت در اجرای بعدی دوباره تلاش می‌کند.

## نصب

1. در پنل: Settings → **API Tokens** → یک توکن بسازید.
2. در `xui-auto-config.rsc` این دو مقدار را پر کنید:
   - `panel`: آدرس پنل از دید روتر، **همراه با web base path** و `/` در آخر. مثال: `http://172.17.0.2:2096/xyz/`
   - `token`: توکن API
3. هر چهار فایل را در Files روتر آپلود کنید.
4. فقط روی CHRای که از قبل مسیر دارد: `/import adopt-current-chr.rsc` (برای هر سرور جدا بنویسید).
5. تست بدون تغییر:
   ```
   :global XAdry true; /import xui-auto-config.rsc; /import xui-auto.rsc
   /log print where message~"xui-auto"
   ```
   کانفیگ Xray تولیدشده در `disk1/xui/xui-auto-template.json` نوشته می‌شود. داخل کانتینر تستش کنید:
   ```
   /container shell 0
   /app/bin/xray-linux-amd64 run -test -c /etc/x-ui/xui-auto-template.json
   ```
6. نصب واقعی:
   ```
   :global XAdry false
   /import xui-auto-install.rsc
   ```
   veth یک‌بار با IPهای ‎172.17.0.2 تا 60 پر می‌شود. اگر RouterOS اجازه تغییر در حال اجرا ندهد، کانتینر یک‌بار ری‌استارت می‌شود.

## نکته‌ها

- **کانفیگ Xray کاملاً در اختیار xui-auto است.** تغییر دستی در تب Advanced پنل، در اولین تغییر بعدی مسیرها بازنویسی می‌شود. تغییرات دائمی را در `xui-auto.rsc` بدهید.
- inboundهایی که از قبل وجود دارند (مثل VLESS TCP روی CHR فعلی) دست نمی‌خورند و فقط به outbound درست وصل می‌شوند.
- حذف تونل، مسیر را خودکار پاک **نمی‌کند**. این کار عمداً دستی است تا کاربران یک مسیر به‌خاطر قطعی موقت از بین نروند.
- لاگ‌ها: `/log print where message~"xui-auto"`
- تست‌شده با RouterOS 7.24.5، پنل 3x-ui 3.9.0 و Xray 26.9.30.

</div>
