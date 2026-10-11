# تنظیمات 3x-ui

<div dir="rtl">

برای هر مسیری که با `$arAdd` ساخته می‌شود سه چیز در پنل لازم است (مقادیر را از خروجی `$arAdd` بردارید):

## ۱. Inbound

- Port: همان پورت (`9010`)
- Listen IP: خالی یا `172.17.0.2`
- **Sniffing: ON** و **Route Only: ON**
  (بدون Route Only، xray دامنه را دوباره خودش از `172.17.0.2` resolve می‌کند و DNS از تونل کشور کاربر نمی‌رود)

## ۲. Outbound

Xray Configs → Outbounds → Add:

```json
{
  "tag": "out-uk",
  "protocol": "freedom",
  "sendThrough": "172.17.0.12",
  "settings": { "domainStrategy": "AsIs" }
}
```

## ۳. Routing rule

```json
{
  "type": "field",
  "inboundTag": ["inbound-9010"],
  "outboundTag": "out-uk"
}
```

> نام tag inbound در 3x-ui معمولاً `inbound-<port>` است؛ در لیست inboundها چک کنید.

## outbound پیش‌فرض (direct)

هر ترافیکی که به هیچ rule نخورد از outbound `direct` با آدرس `172.17.0.2` خارج می‌شود → قانون `xui-direct` آن را به تونل `direct=yes` می‌فرستد. اگر می‌خواهید سایت‌های ایرانی مستقیم باز شوند، برای `geoip:ir` / `geosite:category-ir` یک outbound با `sendThrough` آدرسی بگذارید که mark نمی‌خورد (یا یک قانون accept در mangle برای آن اضافه کنید).

## IP Limit / Fail2ban

با NAT استاندارد این ریپو، 3x-ui IP واقعی کاربر را می‌بیند و IP Limit واقعاً اعمال می‌شود.

</div>
