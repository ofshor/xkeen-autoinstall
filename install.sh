#!/bin/sh
# ============================================================
# Автоустановка XKeen + Xray + SubKeen на встроенную память Keenetic
# Версия: 2.0 (с учётом всех ошибок UBIFS)
# ============================================================

set -e

echo "============================================"
echo "  Автоустановка XKeen + SubKeen"
echo "============================================"

# Проверка root
if [ "$(id -u)" != "0" ]; then
    echo "ОШИБКА: запускать от root"
    exit 1
fi

# Проверка Entware
if [ ! -f /opt/bin/opkg ]; then
    echo "ОШИБКА: Entware не установлен."
    echo "Сначала выполните: opkg disk storage:/"
    exit 1
fi

# ===== ШАГ 1: Смена пароля =====
echo ""
echo "[1/9] Пароль root: оставлен 'keenetic' (смените потом через 'passwd root')"

# ===== ШАГ 2: Установка пакетов по одному =====
echo ""
echo "[2/9] Обновление и установка пакетов (по одному, без зависаний)..."
opkg update >/dev/null 2>&1 || true

PACKAGES="bash python3-base python3-light python3-urllib python3-openssl python3-codecs python3-idna libpython3 curl tar unzip"
for pkg in $PACKAGES; do
    printf "  -> %-20s " "$pkg"
    if opkg list-installed | grep -q "^$pkg "; then
        echo "[уже установлен]"
    else
        if opkg install $pkg >/dev/null 2>&1; then
            echo "[OK]"
        else
            echo "[ошибка, продолжаем]"
        fi
    fi
done

# ===== ШАГ 3: Выбор и установка Xray =====
echo ""
echo "[3/9] Выбор версии Xray..."
echo ""
echo "  1) v26.9.30  - самая новая"
echo "  2) v26.9.9"
echo "  3) v26.9.8"
echo "  4) v26.7.28"
echo "  5) v26.7.11"
echo "  6) v26.6.27"
echo "  7) v26.6.22"
echo "  8) v26.6.1   - проверенная (рекомендуется)"
echo ""
printf "Введите номер [8]: "
read XRAY_CHOICE

case "$XRAY_CHOICE" in
    1) XRAY_VER="v26.9.30" ;;
    2) XRAY_VER="v26.9.9" ;;
    3) XRAY_VER="v26.9.8" ;;
    4) XRAY_VER="v26.7.28" ;;
    5) XRAY_VER="v26.7.11" ;;
    6) XRAY_VER="v26.6.27" ;;
    7) XRAY_VER="v26.6.22" ;;
    8|"") XRAY_VER="v26.6.1" ;;
    *) XRAY_VER="v26.6.1" ;;
esac

echo "  Устанавливаем: $XRAY_VER"
cd /tmp
curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/Xray-linux-arm64-v8a.zip" || {
    echo "  Ошибка скачивания $XRAY_VER, используем v26.6.1"
    curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.6.1/Xray-linux-arm64-v8a.zip"
    XRAY_VER="v26.6.1"
}

# Проверка, что скачался архив, а не "Not Found"
if [ ! -s xray.zip ] || file xray.zip 2>/dev/null | grep -q "ASCII\|HTML"; then
    echo "  Версия недоступна, используем v26.6.1"
    curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.6.1/Xray-linux-arm64-v8a.zip"
    XRAY_VER="v26.6.1"
fi

mkdir -p /opt/bin
unzip -o xray.zip xray -d /opt/bin/ >/dev/null
chmod +x /opt/bin/xray
rm -f xray.zip
echo "  Установлена: $(/opt/bin/xray version | head -1)"

# ===== ШАГ 4: Установка XKeen 2.1 =====
echo ""
echo "[4/9] Установка XKeen 2.1..."
cd /tmp
curl -fsSL -o xkeen.tar.gz "https://github.com/jameszeroX/XKeen/releases/download/2.1/xkeen.tar.gz"
tar -xzf xkeen.tar.gz -C /opt/ >/dev/null
rm -f xkeen.tar.gz
chmod +x /opt/xkeen
ln -sf /opt/xkeen /opt/bin/xkeen
cp -r /opt/_xkeen /opt/sbin/.xkeen
echo "  XKeen установлен: $(/opt/xkeen -version 2>/dev/null | head -1 || echo 'OK')"

# ===== ШАГ 5: Конфиги (ЧИСТЫЕ, без geosite_v2fly.dat) =====
echo ""
echo "[5/9] Создание конфигов Xray..."
mkdir -p /opt/etc/xray/configs
cp -r /opt/_xkeen/02_install/08_install_configs/02_configs_xray/* /opt/etc/xray/configs/
touch /opt/etc/xray/geoip.dat /opt/etc/xray/geosite.dat

# ПЕРЕЗАПИСЫВАЕМ routing.json — убираем ext:geosite_v2fly.dat (Xray падает на пустом файле)
cat > /opt/etc/xray/configs/05_routing.json << 'ROUTING_EOF'
{
  "routing": {
    "rules": [
      {
        "inboundTag": ["redirect", "tproxy"],
        "outboundTag": "block",
        "type": "field",
        "network": "udp",
        "port": "135, 137, 138, 139"
      },
      {
        "inboundTag": ["redirect", "tproxy"],
        "outboundTag": "block",
        "type": "field",
        "domain": ["appcenter.ms"]
      },
      {
        "inboundTag": ["redirect", "tproxy"],
        "outboundTag": "direct",
        "type": "field",
        "domain": [
          "regexp:^([\\w\\-\\.]+\\.)ru$",
          "regexp:^([\\w\\-\\.]+\\.)su$",
          "regexp:^([\\w\\-\\.]+\\.)xn--p1ai$",
          "regexp:^([\\w\\-\\.]+\\.)xn--p1acf$",
          "regexp:^([\\w\\-\\.]+\\.)xn--80asehdb$",
          "regexp:^([\\w\\-\\.]+\\.)xn--c1avg$",
          "regexp:^([\\w\\-\\.]+\\.)xn--80aswg$",
          "regexp:^([\\w\\-\\.]+\\.)xn--80adxhks$",
          "regexp:^([\\w\\-\\.]+\\.)moscow$",
          "regexp:^([\\w\\-\\.]+\\.)xn--d1acj3b$"
        ]
      },
      {
        "inboundTag": ["redirect", "tproxy"],
        "outboundTag": "direct",
        "type": "field",
        "protocol": ["bittorrent"]
      },
      {
        "inboundTag": ["redirect", "tproxy"],
        "outboundTag": "vless-reality",
        "type": "field"
      }
    ]
  }
}
ROUTING_EOF

printf "  Проверка конфига: "
if /opt/bin/xray run -test -confdir /opt/etc/xray/configs 2>&1 | grep -q "Configuration OK"; then
    echo "OK"
else
    echo "ОШИБКА — проверьте конфиг вручную"
    exit 1
fi

# ===== ШАГ 6: Init-скрипты автозапуска =====
echo ""
echo "[6/9] Создание init-скриптов автозапуска..."

# S05xkeen — запуск Xray
cat > /opt/etc/init.d/S05xkeen << 'S05_EOF'
#!/bin/sh
XRAY=/opt/bin/xray
CONF=/opt/etc/xray/configs
PIDFILE=/var/run/xray.pid
case "$1" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then exit 0; fi
        $XRAY run -confdir $CONF >/dev/null 2>&1 &
        echo $! > $PIDFILE
        ;;
    stop)
        [ -f "$PIDFILE" ] && kill $(cat "$PIDFILE") 2>/dev/null && rm -f $PIDFILE
        killall xray 2>/dev/null
        ;;
    restart)
        $0 stop; sleep 2; $0 start
        ;;
esac
S05_EOF
chmod +x /opt/etc/init.d/S05xkeen

# S10crond — запуск cron (без дубликатов)
cat > /opt/etc/init.d/S10crond << 'S10_EOF'
#!/bin/sh
case "$1" in
    start)
        pgrep -x crond >/dev/null 2>&1 && exit 0
        crond -L /dev/null
        ;;
    stop) killall crond 2>/dev/null ;;
    restart) $0 stop; sleep 1; $0 start ;;
esac
S10_EOF
chmod +x /opt/etc/init.d/S10crond

# S90restore_cron — восстановление задачи после перезагрузки (crontab в tmpfs!)
cat > /opt/etc/init.d/S90restore_cron << 'S90_EOF'
#!/bin/sh
case "$1" in
    start)
        mkdir -p /var/spool/cron/crontabs
        cat > /var/spool/cron/crontabs/root << 'CRON'
# subkeen_cron
0 */3 * * * /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py -url 'ССЫЛКА_НА_ПОДПИСКУ'
CRON
        ;;
esac
S90_EOF
chmod +x /opt/etc/init.d/S90restore_cron

echo "  S05xkeen      - Xray"
echo "  S10crond      - cron"
echo "  S90restore_cron - восстановление cron"

# ===== ШАГ 7: Установка SubKeen + hardened скрипт =====
echo ""
echo "[7/9] Установка SubKeen..."
cd /opt
curl -fsSOfL https://raw.githubusercontent.com/V2as/SubKeen/main/install.sh
chmod +x ./install.sh
./install.sh >/dev/null 2>&1
rm -f install.sh

# Фикс бага интервала
sed -i 's/update_interval = int(headers.get("profile-update-interval"))/update_interval = int(headers.get("profile-update-interval") or 2)/' /opt/sbin/SubKeen-current/subkeen.py

# Hardened subkeen_multi.py с мультибалансером
cat > /opt/sbin/SubKeen-current/subkeen_multi.py << 'PYEOF'
#!/usr/bin/env python3
import urllib.request, ssl, base64, json, subprocess, argparse, sys, shutil, re, os, time
from urllib.parse import urlparse, parse_qs

OB = "/opt/etc/xray/configs/04_outbounds.json"
RT = "/opt/etc/xray/configs/05_routing.json"
OBS = "/opt/etc/xray/configs/07_observatory.json"
CONF_DIR = "/opt/etc/xray/configs"
EXCLUDE_FILE = "/opt/etc/xray/subkeen_exclude.txt"
CRON_TAG = "# subkeen_cron"
BAK_SUFFIX = ".bak-subkeen-multi"

def shell_quote(s): return "'" + s.replace("'", "'\\''") + "'"

def remove_json_comments(text):
    text = re.sub(r'//.*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return text

def load_jsonc(fp):
    with open(fp, 'r', encoding='utf-8') as f: return json.loads(remove_json_comments(f.read()))

def atomic_write_json(fp, d):
    tmp = fp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, fp)

def make_backups():
    for f in (OB, RT, OBS):
        if os.path.exists(f): shutil.copy2(f, f + BAK_SUFFIX)

def restore_backups():
    for f in (OB, RT, OBS):
        bak = f + BAK_SUFFIX
        if os.path.exists(bak): shutil.copy2(bak, f)

def load_exclude():
    pats = []
    if os.path.exists(EXCLUDE_FILE):
        with open(EXCLUDE_FILE, encoding="utf-8") as f:
            for l in f:
                l = l.strip().lower()
                if l and not l.startswith("#"): pats.append(l)
    return pats

def get_sub(url):
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    last_err = None
    for a in range(1, 4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url), context=ctx, timeout=30) as r:
                hdr = {k.lower(): v for k, v in r.getheaders()}
                body = r.read().decode(errors="replace")
            interval = int(hdr.get("profile-update-interval") or 2)
            try: decoded = base64.b64decode(body.strip().replace("\n","")).decode(errors="replace")
            except Exception as e: sys.exit("Ошибка: не Base64: %s" % e)
            lines = [l.strip() for l in decoded.split("\n") if l.strip().startswith("vless://")]
            return lines, interval
        except Exception as e:
            last_err = e
            print("Попытка %d/3: %s" % (a, e))
            if a < 3: time.sleep(3)
    sys.exit("Не удалось скачать: %s" % last_err)

def parse(u, i):
    d = urlparse(u.replace("vless://", "http://", 1)); q = parse_qs(d.query)
    sec = q.get("security", ["none"])[0]; net = q.get("type", ["tcp"])[0]
    ss = {}; ssn = None
    if sec == "reality":
        ssn = "realitySettings"
        ss = {"fingerprint": q.get("fp", ["chrome"])[0], "publicKey": q.get("pbk", [""])[0],
              "serverName": q.get("sni", q.get("serverName", [""]))[0], "shortId": q.get("sid", [""])[0]}
        if q.get("spx"): ss["spiderX"] = q["spx"][0]
    elif sec == "tls":
        ssn = "tlsSettings"
        sni = q.get("sni", q.get("serverName", [""]))[0]
        if sni: ss["serverName"] = sni
        if "alpn" in q: ss["alpn"] = q["alpn"][0].split(",")
    ts = {}; tsn = "tcpSettings"
    if net == "ws":
        tsn = "wsSettings"; ts = {"path": q.get("path", ["/"])[0]}
        if q.get("host"): ts["host"] = q["host"][0]
    elif net == "grpc":
        tsn = "grpcSettings"; ts = {"serviceName": q.get("serviceName", [""])[0]}
    user = {"id": d.username, "encryption": "none"}
    if "flow" in q: user["flow"] = q["flow"][0]
    cfg = {"protocol": "vless",
           "settings": {"vnext": [{"address": d.hostname, "port": int(d.port), "users": [user]}]},
           "streamSettings": {"network": net, "security": sec},
           "tag": "proxy-%02d" % i}
    if ssn: cfg["streamSettings"][ssn] = ss
    if ts: cfg["streamSettings"][tsn] = ts
    return cfg

def xray_test():
    bin_path = shutil.which("xray") or "/opt/bin/xray"
    p = subprocess.run([bin_path, "run", "-test", "-confdir", CONF_DIR], capture_output=True, text=True)
    if p.returncode == 0:
        print("  xray -test: OK"); return True
    print("  xray -test FAIL:\n" + (p.stderr or p.stdout)[-1500:]); return False

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("-url", required=True); a = ap.parse_args()
    urls, interval = get_sub(a.url)
    print("Серверов в подписке:", len(urls))
    if not urls: sys.exit("Нет vless-серверов")
    exclude = load_exclude()
    make_backups()
    ob = load_jsonc(OB)
    ob["outbounds"] = [o for o in ob["outbounds"] if not str(o.get("tag","")).startswith(("proxy-","excl-"))]
    n_excl = 0
    for i, u in enumerate(urls):
        c = parse(u, i)
        host = (urlparse(u.replace("vless://","http://",1)).hostname or "").lower()
        if any(p in host for p in exclude):
            c["tag"] = "excl-%02d" % i; n_excl += 1
            print("  -", c["tag"], host, "(исключён)")
        else:
            c["tag"] = "proxy-%02d" % i
            print("  +", c["tag"], host)
        ob["outbounds"].append(c)
    if len(urls) - n_excl == 0:
        restore_backups(); sys.exit("Все серверы исключены")
    atomic_write_json(OB, ob)
    atomic_write_json(OBS, {"observatory": {"subjectSelector": ["proxy-"],
             "probeUrl": "http://cp.cloudflare.com/generate_204", "probeInterval": "60s"}})
    rt = load_jsonc(RT); r = rt.get("routing", rt)
    r["balancers"] = [b for b in r.get("balancers", []) if b.get("tag") != "auto-balancer"]
    r["balancers"].append({"tag": "auto-balancer", "selector": ["proxy-"], "strategy": {"type": "leastPing"}})
    known = {"vless-reality", "proxy", "proxy-00", "main", "vpn"}
    changed = 0
    for rule in r.get("rules", []):
        if rule.get("outboundTag") in known:
            rule["balancerTag"] = "auto-balancer"; del rule["outboundTag"]; changed += 1
    atomic_write_json(RT, rt)
    print("Routing: правил на balancer:", changed)
    print("Исключено:", n_excl, "из", len(urls))
    if not xray_test():
        restore_backups(); sys.exit("Отмена: конфиг не прошёл тест")
    subprocess.run(["/opt/etc/init.d/S05xkeen", "restart"], check=True)
    p = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    lines = [l for l in (p.stdout.splitlines() if p.returncode == 0 else []) if CRON_TAG not in l]
    lines.append("0 */%d * * * /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py -url %s %s" % (interval, shell_quote(a.url), CRON_TAG))
    with open("/tmp/cron_subkeen.txt", "w") as f: f.write("\n".join(lines) + "\n")
    subprocess.run(["crontab", "/tmp/cron_subkeen.txt"], check=True)
    print("Готово. Cron каждые %d ч." % interval)

if __name__ == "__main__":
    main()
PYEOF
chmod +x /opt/sbin/SubKeen-current/subkeen_multi.py
echo "  SubKeen установлен"

# ===== ШАГ 8: Файл исключений =====
echo ""
echo "[8/9] Создание файла исключений российских серверов..."
cat > /opt/etc/xray/subkeen_exclude.txt << 'EXCLUDE_EOF'
# Подстроки hostname — серверы с этими паттернами не попадут в балансировку
ru
msk
moscow
russia
cashgruz
EXCLUDE_EOF
echo "  Файл создан: /opt/etc/xray/subkeen_exclude.txt"

# ===== ШАГ 9: Первый запуск с подпиской =====
echo ""
echo "[9/9] Первый запуск..."
echo ""
echo "Введите ссылку на вашу подписку (vless:// формат):"
read SUB_URL

if [ -z "$SUB_URL" ]; then
    echo "ОШИБКА: ссылка не указана"
    exit 1
fi

# Обновляем S90restore_cron с реальной ссылкой
sed -i "s|ССЫЛКА_НА_ПОДПИСКУ|$SUB_URL|g" /opt/etc/init.d/S90restore_cron

# Запускаем subkeen_multi.py
/opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py -url "$SUB_URL"

echo ""
echo "============================================"
echo "  Установка завершена!"
echo "============================================"
echo ""
echo "Финальная проверка:"
echo "  Xray:  $(ps | grep -v grep | grep -c xray) процесс(ов)"
echo "  Cron:  $(ps | grep -v grep | grep -c crond) процесс(ов)"
echo "  IP:    $(curl -s ifconfig.me)"
echo "  Место: $(df -h /opt | tail -1 | awk '{print $3 "/" $1 " (" $4 " свободно)"}')"
echo ""
echo "Перезагрузите роутер командой 'reboot' для проверки автозапуска."