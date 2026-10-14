#!/bin/sh
# ============================================================
# Автоустановка XKeen + Xray + SubKeen на Keenetic (Online)
# Версия 5.1: Исправлена ошибка KeyError в subkeen_multi.py
# ============================================================
set -e

# АВТОЛЕЧЕНИЕ: Убираем Windows-окончания строк
sed -i 's/\r$//' "$0" 2>/dev/null || true

echo "============================================"
echo "  XKeen + SubKeen Auto-Install v5.1"
echo "============================================"

# ===== БАЗОВЫЕ ПРОВЕРКИ =====
if [ "$(id -u)" != "0" ]; then echo "ОШИБКА: запускать от root"; exit 1; fi
if [ ! -f /opt/bin/opkg ]; then echo "ОШИБКА: Entware не установлен"; exit 1; fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ОШИБКА: curl не установлен!"
    echo "Выполните: opkg update && opkg install curl"
    exit 1
fi

FREE_MB=$(df /opt | tail -1 | awk '{print int($4/1024)}')
if [ "$FREE_MB" -lt 20 ]; then
    echo "ОШИБКА: мало памяти (нужно 20MB, есть ${FREE_MB}MB)"; exit 1
fi
echo "  Свободно памяти: ${FREE_MB}MB"

# ===== [1/13] ПРОВЕРКА GITHUB =====
echo ""
echo "[1/13] Проверка доступности GitHub..."
if ! curl -sI --max-time 10 https://github.com >/dev/null 2>&1; then
    echo "ОШИБКА: GitHub недоступен"; exit 1
fi
echo "  GitHub доступен"

# ===== [2/13] АРХИТЕКТУРА =====
echo ""
echo "[2/13] Архитектура процессора:"
echo "  1) aarch64 (Peak, Ultra 1811, Giga 1012, Hopper 3811/3812)"
echo "  2) mipsel  (Giga 1010/1011, Ultra 1810, Viva, Hero 4G, Giant, Hopper 3810)"
echo "  3) mips    (Giga SE, Ultra SE, DSL, Duo, Skipper DSL, Hopper DSL)"
printf "Введите номер [1]: "
read ARCH_CHOICE
case "$ARCH_CHOICE" in
    2) XRAY_ARCH="mips32le" ;;
    3) XRAY_ARCH="mips32" ;;
    *) XRAY_ARCH="arm64-v8a" ;;
esac
echo "  Выбрано: $XRAY_ARCH"

# ===== [3/13] ПАКЕТЫ =====
echo ""
echo "[3/13] Установка пакетов..."
opkg update >/dev/null 2>&1 || true
for pkg in python3 curl iptables; do
    printf "  -> %-10s " "$pkg"
    if opkg list-installed 2>/dev/null | grep -q "^$pkg "; then
        echo "[уже установлен]"
    elif opkg install $pkg >/dev/null 2>&1; then
        echo "[OK]"
    else
        echo "[ОШИБКА]"; exit 1
    fi
done

# ===== [4/13] XRAY =====
echo ""
echo "[4/13] Установка Xray..."
cd /tmp
XRAY_VER="v26.9.30"
if ! curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/Xray-linux-$XRAY_ARCH.zip"; then
    echo "  $XRAY_VER недоступна, беру v26.6.1..."
    XRAY_VER="v26.6.1"
    curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/Xray-linux-$XRAY_ARCH.zip" || { echo "ОШИБКА скачивания Xray"; exit 1; }
fi
mkdir -p /opt/bin
unzip -o xray.zip xray -d /opt/bin/ >/dev/null
chmod +x /opt/bin/xray
rm -f xray.zip
echo "  Установлена: $(/opt/bin/xray version | head -1)"

# ===== [5/13] XKEEN =====
echo ""
echo "[5/13] Установка XKeen 2.1..."
cd /tmp
curl -fsSL -o xkeen.tar.gz "https://github.com/jameszeroX/XKeen/releases/download/2.1/xkeen.tar.gz" || { echo "ОШИБКА скачивания XKeen"; exit 1; }
tar -xzf xkeen.tar.gz -C /opt/ >/dev/null
rm -f xkeen.tar.gz
chmod +x /opt/xkeen
ln -sf /opt/xkeen /opt/bin/xkeen
ln -sfn /opt/_xkeen /opt/bin/.xkeen
echo "  XKeen установлен"

# ===== [6/13] КОНФИГИ XRAY (оригинальные от XKeen) =====
echo ""
echo "[6/13] Копирование оригинальных конфигов Xray..."
mkdir -p /opt/etc/xray/configs
cp -r /opt/_xkeen/02_install/08_install_configs/02_configs_xray/* /opt/etc/xray/configs/
touch /opt/etc/xray/geoip.dat /opt/etc/xray/geosite.dat

printf "  Проверка конфига: "
if /opt/bin/xray run -test -confdir /opt/etc/xray/configs 2>&1 | grep -q "Configuration OK"; then
    echo "OK"
else
    echo "ОШИБКА"; exit 1
fi

# ===== [7/13] subkeen.conf.json =====
echo ""
echo "[7/13] Создание subkeen.conf.json..."
cat > /opt/etc/xray/subkeen.conf.json << 'CONF_EOF'
{
  "subscription": {"url": "", "update_interval_hours": 1},
  "observatory": {"probe_url": "http://cp.cloudflare.com/generate_204", "probe_interval": "60s"},
  "balancer": {"strategy": "leastLoad", "expected_servers": 3, "max_rtt": "2000ms", "tolerance_percent": 50},
  "priority": {"patterns": []},
  "exclusions": {"by_flag": ["🇷🇺"], "by_name": ["россия", "russia", "ru"], "by_hostname": ["msk", "moscow", "cashgruz"], "manual_ip_blacklist": []},
  "system": {"log_level": "warning", "auto_restart_on_fail": true, "keep_backups": 3}
}
CONF_EOF
echo "  Создан"

# ===== [8/13] subkeen_multi.py (ИСПРАВЛЕНА ОШИБКА KeyError) =====
echo ""
echo "[8/13] Создание subkeen_multi.py..."
mkdir -p /opt/sbin/SubKeen-current
cat > /opt/sbin/SubKeen-current/subkeen_multi.py << 'PYEOF'
#!/usr/bin/env python3
import urllib.request, ssl, base64, json, subprocess, sys, shutil, re, os, time, socket
from urllib.parse import urlparse, parse_qs, unquote

CONF_FILE = "/opt/etc/xray/subkeen.conf.json"
OB = "/opt/etc/xray/configs/04_outbounds.json"
RT = "/opt/etc/xray/configs/05_routing.json"
OBS = "/opt/etc/xray/configs/07_observatory.json"
CONF_DIR = "/opt/etc/xray/configs"
CACHE_TTL = 7 * 24 * 60 * 60

def load_config():
    if not os.path.exists(CONF_FILE): sys.exit("Конфиг не найден: %s" % CONF_FILE)
    with open(CONF_FILE, encoding='utf-8') as f: return json.load(f)

def save_config(config):
    tmp = CONF_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, CONF_FILE)

def remove_json_comments(text):
    text = re.sub(r'//.*$', '', text, flags=re.MULTILINE)
    return re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)

def load_jsonc(fp):
    with open(fp, 'r', encoding='utf-8') as f: return json.loads(remove_json_comments(f.read()))

def atomic_write_json(fp, d):
    tmp = fp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, fp)

def get_sub(url):
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    for a in range(1, 4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url), context=ctx, timeout=30) as r:
                body = r.read().decode(errors="replace")
            try: decoded = base64.b64decode(body.strip().replace("\n","")).decode(errors="replace")
            except Exception as e: sys.exit("Ошибка: не Base64: %s" % e)
            return [l.strip() for l in decoded.split("\n") if l.strip().startswith("vless://")]
        except Exception as e:
            print("Попытка %d/3: %s" % (a, e))
            if a < 3: time.sleep(3)
    sys.exit("Не удалось скачать подписку")

def get_smart_geo_data(urls, config):
    cache = config.get("geo_cache", {})
    current_time = int(time.time())
    resolved_data = {}; hostnames_to_api = []; results = {}
    for u in urls:
        try:
            hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
            if not hostname: continue
            ip = socket.gethostbyname(hostname)
            resolved_data[hostname] = ip
            if hostname in cache:
                cached = cache[hostname]
                if cached.get("ip") == ip and (current_time - cached.get("timestamp", 0)) < CACHE_TTL:
                    results[hostname] = cached["country"]
                else:
                    hostnames_to_api.append(hostname)
            else:
                hostnames_to_api.append(hostname)
        except socket.gaierror:
            resolved_data[hostname] = None
    if hostnames_to_api:
        ips_to_query = list(set([resolved_data[h] for h in hostnames_to_api if resolved_data[h]]))
        if ips_to_query:
            try:
                data = json.dumps(ips_to_query).encode('utf-8')
                req = urllib.request.Request('http://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r:
                    api_results = json.loads(r.read().decode())
                ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]
                    country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}
                    results[hostname] = country
            except Exception as e:
                print("  Warning API (%s), беру из кэша" % e)
                for hostname in hostnames_to_api:
                    results[hostname] = cache.get(hostname, {}).get("country", "??")
    config["geo_cache"] = cache
    save_config(config)
    return results, resolved_data

def parse_vless(u, idx, cfg, geo_data, resolved_data):
    d = urlparse(u.replace("vless://", "http://", 1)); q = parse_qs(d.query)
    friendly_name = ""
    if "#" in u:
        try: friendly_name = unquote(u.split("#", 1)[1]).lower()
        except: friendly_name = ""
    hostname = (d.hostname or "").lower()
    excluded = False; excl_cfg = cfg.get("exclusions", {})
    for flag in excl_cfg.get("by_flag", []):
        if flag in friendly_name: excluded = True; break
    if not excluded:
        for name in excl_cfg.get("by_name", []):
            if name.lower() in friendly_name: excluded = True; break
    if not excluded:
        for hp in excl_cfg.get("by_hostname", []):
            if hp.lower() in hostname: excluded = True; break
    is_priority = False
    for pat in cfg.get("priority", {}).get("patterns", []):
        if pat.lower() in friendly_name or pat.lower() in hostname:
            is_priority = True; break
    if not excluded and not is_priority:
        ip_blacklist = excl_cfg.get("manual_ip_blacklist", [])
        current_ip = resolved_data.get(hostname)
        if ip_blacklist and current_ip and current_ip in ip_blacklist:
            excluded = True
        if not excluded and current_ip:
            if geo_data.get(hostname, '??') == 'RU':
                excluded = True
                print("  [!] %s авто-исключён (Россия по IP: %s)" % (hostname, current_ip))
    tag = "excl-%02d" % idx if excluded else ("priority-%02d" % idx if is_priority else "proxy-%02d" % idx)
    sec = q.get("security", ["none"])[0]; net = q.get("type", ["tcp"])[0]
    ss = {}; ssn = None
    if sec == "reality":
        ssn = "realitySettings"
        ss = {"fingerprint": q.get("fp", ["chrome"])[0], "publicKey": q.get("pbk", [""])[0],
              "serverName": q.get("sni", q.get("serverName", [""]))[0], "shortId": q.get("sid", [""])[0]}
        if q.get("spx"): ss["spiderX"] = q["spx"][0]
    elif sec == "tls":
        ssn = "tlsSettings"; sni = q.get("sni", q.get("serverName", [""]))[0]
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
    out = {"protocol": "vless", "settings": {"vnext": [{"address": d.hostname, "port": int(d.port), "users": [user]}]},
           "streamSettings": {"network": net, "security": sec}, "tag": tag}
    if ssn: out["streamSettings"][ssn] = ss
    if ts: out["streamSettings"][tsn] = ts
    return out, excluded, is_priority

def xray_test():
    bin_path = shutil.which("xray") or "/opt/bin/xray"
    p = subprocess.run([bin_path, "run", "-test", "-confdir", CONF_DIR], capture_output=True, text=True)
    if p.returncode == 0: print("  xray -test: OK"); return True
    print("  xray -test FAIL:\n" + (p.stderr or p.stdout)); return False

def main():
    cfg = load_config(); sub_url = cfg["subscription"]["url"]
    if not sub_url: sys.exit("URL подписки пуст")
    print("Скачиваем подписку..."); urls = get_sub(sub_url)
    print("Серверов в подписке:", len(urls))
    if not urls: sys.exit("Нет vless-серверов")
    print("Smart Geo-Caching...")
    geo_data, resolved_data = get_smart_geo_data(urls, cfg)
    keep = cfg.get("system", {}).get("keep_backups", 3)
    for f in [OB, RT, OBS]:
        if os.path.exists(f):
            for i in range(keep, 0, -1):
                src = f if i == 1 else "%s.%d" % (f, i-1)
                dst = "%s.%d" % (f, i)
                if os.path.exists(src): shutil.copy2(src, dst)
    
    # ИСПРАВЛЕНИЕ: Защита от KeyError, если в файле нет ключа "outbounds"
    ob = load_jsonc(OB)
    if isinstance(ob, list):
        ob = {"outbounds": ob}
    if "outbounds" not in ob:
        ob["outbounds"] = []
        
    ob["outbounds"] = [o for o in ob["outbounds"] if not str(o.get("tag","")).startswith(("proxy-","excl-","priority-"))]
    n_excl = n_pri = n_proxy = 0
    for i, u in enumerate(urls):
        out, ex, pri = parse_vless(u, i, cfg, geo_data, resolved_data)
        if ex: n_excl += 1; print("  -", out["tag"], "(исключён)")
        elif pri: n_pri += 1; print("  *", out["tag"], "(приоритет)")
        else: n_proxy += 1; print("  +", out["tag"])
        ob["outbounds"].append(out)
    if n_pri + n_proxy == 0: sys.exit("Все серверы исключены!")
    atomic_write_json(OB, ob)
    obs_cfg = cfg.get("observatory", {})
    atomic_write_json(OBS, {
        "observatory": {
            "subjectSelector": ["proxy-", "priority-"],
            "probeUrl": obs_cfg.get("probe_url", "http://cp.cloudflare.com/generate_204"),
            "probeInterval": obs_cfg.get("probe_interval", "60s")
        }
    })
    rt = load_jsonc(RT); r = rt.get("routing", rt)
    r["balancers"] = [b for b in r.get("balancers", []) if b.get("tag") != "auto-balancer"]
    bal_cfg = cfg.get("balancer", {})
    r["balancers"].append({
        "tag": "auto-balancer", "selector": ["priority-", "proxy-"],
        "strategy": {
            "type": bal_cfg.get("strategy", "leastLoad"),
            "settings": {
                "expectedServers": bal_cfg.get("expected_servers", 3),
                "maxRTT": bal_cfg.get("max_rtt", "2000ms"),
                "tolerance": bal_cfg.get("tolerance_percent", 50) / 100.0
            }
        }
    })
    known = {"vless-reality", "proxy", "proxy-00", "main", "vpn"}
    changed = 0
    for rule in r.get("rules", []):
        if rule.get("outboundTag") in known:
            rule["balancerTag"] = "auto-balancer"
            if "outboundTag" in rule: del rule["outboundTag"]
            changed += 1
    atomic_write_json(RT, rt)
    print("Результат: приоритетных %d, обычных %d, исключено %d из %d" % (n_pri, n_proxy, n_excl, len(urls)))
    if not xray_test():
        if cfg.get("system", {}).get("auto_restart_on_fail", True):
            print("Откат на бэкапы...")
            for f in [OB, RT, OBS]:
                bak = f + ".1"
                if os.path.exists(bak): shutil.copy2(bak, f)
        sys.exit("Конфиг не прошёл тест")
    
    subprocess.run(["xkeen", "-restart"], check=False)
    
    interval = cfg["subscription"].get("update_interval_hours", 1)
    p = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    lines = [l for l in (p.stdout.splitlines() if p.returncode == 0 else []) if "# subkeen_cron" not in l]
    lines.append("0 */%d * * * /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py # subkeen_cron" % interval)
    with open("/tmp/cron_subkeen.txt", "w") as f: f.write("\n".join(lines) + "\n")
    subprocess.run(["crontab", "/tmp/cron_subkeen.txt"], check=True)
    print("Готово. Cron каждые %d ч." % interval)

if __name__ == "__main__": main()
PYEOF
chmod +x /opt/sbin/SubKeen-current/subkeen_multi.py
echo "  Создан"

# ===== [9/13] choose =====
echo ""
echo "[9/13] Создание команды choose..."
cat > /opt/sbin/choose-servers.py << 'CHOOSE_EOF'
#!/usr/bin/env python3
import urllib.request, ssl, base64, json, socket, time
from urllib.parse import urlparse, unquote

COUNTRY_NAMES = {
    'RU': 'Россия', 'US': 'США', 'DE': 'Германия', 'NL': 'Нидерланды',
    'FR': 'Франция', 'GB': 'Великобритания', 'JP': 'Япония', 'SE': 'Швеция',
    'FI': 'Финляндия', 'PL': 'Польша', 'CZ': 'Чехия', 'RO': 'Румыния',
    'BG': 'Болгария', 'IT': 'Италия', 'AT': 'Австрия', 'LV': 'Латвия',
    'LT': 'Литва', 'EE': 'Эстония', 'UA': 'Украина', 'BY': 'Беларусь',
    'KZ': 'Казахстан', 'CN': 'Китай', 'SG': 'Сингапур', 'HK': 'Гонконг',
    'CA': 'Канада', 'AU': 'Австралия', 'BR': 'Бразилия', 'IN': 'Индия',
    'TR': 'Турция', 'ES': 'Испания', 'PT': 'Португалия', 'CH': 'Швейцария',
}
CACHE_TTL = 7 * 24 * 60 * 60

def get_smart_geo_data(urls, config):
    cache = config.get("geo_cache", {})
    current_time = int(time.time())
    hostnames_to_api = []; results = {}; resolved_data = {}
    for u in urls:
        try:
            hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
            if not hostname: continue
            ip = socket.gethostbyname(hostname)
            resolved_data[hostname] = ip
            if hostname in cache:
                cached = cache[hostname]
                if cached.get("ip") == ip and (current_time - cached.get("timestamp", 0)) < CACHE_TTL:
                    results[hostname] = cached["country"]
                else:
                    hostnames_to_api.append(hostname)
            else:
                hostnames_to_api.append(hostname)
        except socket.gaierror:
            resolved_data[hostname] = None
    if hostnames_to_api:
        ips_to_query = list(set([resolved_data[h] for h in hostnames_to_api if resolved_data[h]]))
        if ips_to_query:
            try:
                data = json.dumps(ips_to_query).encode('utf-8')
                req = urllib.request.Request('http://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r:
                    api_results = json.loads(r.read().decode())
                ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]
                    country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}
                    results[hostname] = country
            except Exception:
                for hostname in hostnames_to_api:
                    results[hostname] = cache.get(hostname, {}).get("country", "??")
    config["geo_cache"] = cache
    with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    return results, resolved_data

with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f:
    config = json.load(f)
url = config['subscription']['url']
if not url:
    print("Ошибка: в конфиге нет ссылки на подписку"); raise SystemExit(1)

ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
print("Загружаем список серверов...\n")
try:
    with urllib.request.urlopen(url, context=ctx, timeout=30) as r:
        decoded = base64.b64decode(r.read().decode().strip()).decode()
    urls = [line.strip() for line in decoded.split('\n') if line.strip().startswith('vless://') and '#' in line]
    geo_data, resolved_data = get_smart_geo_data(urls, config)
    servers = []
    for i, u in enumerate(urls):
        name = unquote(u.split('#', 1)[1])
        hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
        ip = resolved_data.get(hostname, "N/A")
        cc = geo_data.get(hostname, "??")
        cname = COUNTRY_NAMES.get(cc, cc)
        mark = " [RU-BLOCK]" if cc == 'RU' else ""
        servers.append((i, name, ip, "%s: %s%s" % (cc, cname, mark)))
    print("Доступные серверы:")
    for i, name, ip, geo_str in servers:
        print("  [%02d] %s  [IP: %s | %s]" % (i, name, ip, geo_str))
    print("\n" + "="*70)
    choice = input("1. Номера для ПРИОРИТЕТА или [Enter] авто-выбор: ")
    print("="*70)
    if 'priority' not in config: config['priority'] = {}
    if not choice.strip():
        config['priority']['patterns'] = []
        print("Авто-выбор по пингу.")
    else:
        nums = [int(x.strip()) for x in choice.split(',') if x.strip().isdigit()]
        chosen = [servers[i][1] for i in nums if i < len(servers)]
        config['priority']['patterns'] = chosen
        print("Приоритет: %s" % ', '.join(chosen))
    print("\n" + "="*70)
    bl = input("2. Номера для ЧЕРНОГО СПИСКА или [Enter] не менять: ")
    print("="*70)
    if bl.strip():
        bl_nums = [int(x.strip()) for x in bl.split(',') if x.strip().isdigit()]
        new_bl = [servers[n][2] for n in bl_nums if n < len(servers) and servers[n][2] != "N/A"]
        if 'exclusions' not in config: config['exclusions'] = {}
        config['exclusions']['manual_ip_blacklist'] = new_bl
        print("Черный список: %s" % ', '.join(new_bl))
    else:
        print("Черный список не изменен.")
    cur = config.get("balancer", {}).get("tolerance_percent", 50)
    print("\n" + "="*70)
    print("Текущая разница пинга для переключения: %s%%" % cur)
    tol = input("3. Новая разница в %% или [Enter] оставить %s%%: " % cur)
    print("="*70)
    if tol.strip():
        try:
            nt = int(tol.strip())
            if 0 <= nt <= 100:
                if 'balancer' not in config: config['balancer'] = {}
                config['balancer']['tolerance_percent'] = nt
                print("Разница пинга: %s%%" % nt)
        except ValueError:
            print("Оставлено старое значение.")
    else:
        print("Оставлено: %s%%" % cur)
    with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print("\nНастройки сохранены")
except Exception as e:
    print("Ошибка: %s" % e)
CHOOSE_EOF
chmod +x /opt/sbin/choose-servers.py

cat > /opt/bin/choose << 'CHOOSE_CMD'
#!/bin/sh
echo "Обновляем приоритеты..."
/opt/bin/python3 /opt/sbin/choose-servers.py
echo ""
echo "Применяем настройки..."
/opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py
echo "Готово!"
CHOOSE_CMD
chmod +x /opt/bin/choose
echo "  Создано"

# ===== [10/13] INIT-СКРИПТЫ =====
echo ""
echo "[10/13] Создание init-скриптов..."

cat > /opt/etc/init.d/S05xkeen << 'S05_EOF'
#!/bin/sh
XRAY=/opt/bin/xray
CONF=/opt/etc/xray/configs
case "$1" in
    start)
        if ps | grep -v grep | grep -q "$XRAY"; then exit 0; fi
        $XRAY run -confdir $CONF >/dev/null 2>&1 &
        ;;
    stop)
        killall xray 2>/dev/null
        ;;
    restart)
        $0 stop; sleep 2; $0 start
        ;;
esac
S05_EOF
chmod +x /opt/etc/init.d/S05xkeen

cat > /opt/etc/init.d/S10crond << 'S10_EOF'
#!/bin/sh
case "$1" in
    start)
        if ps | grep -v grep | grep -q crond; then exit 0; fi
        crond -L /dev/null
        ;;
    stop) killall crond 2>/dev/null ;;
    restart) $0 stop; sleep 1; $0 start ;;
esac
S10_EOF
chmod +x /opt/etc/init.d/S10crond

cat > /opt/etc/init.d/S90restore_cron << 'S90_EOF'
#!/bin/sh
case "$1" in
    start)
        if [ -f /opt/etc/crontabs.subkeen ]; then
            ( sleep 10; crontab /opt/etc/crontabs.subkeen ) &
        fi
        ;;
esac
S90_EOF
chmod +x /opt/etc/init.d/S90restore_cron

cat > /opt/etc/init.d/S99xray_net << 'S99_EOF'
#!/bin/sh
(
  sleep 20
  /opt/sbin/iptables -t nat -N xkeen 2>/dev/null
  /opt/sbin/iptables -t nat -C PREROUTING -j xkeen 2>/dev/null || /opt/sbin/iptables -t nat -I PREROUTING 1 -j xkeen
  /opt/sbin/iptables -t nat -C xkeen -p tcp -j REDIRECT --to-ports 1181 2>/dev/null || /opt/sbin/iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports 1181
  echo "$(date): Xray rules applied" >> /opt/var/log/xray_net.log
) &
S99_EOF
chmod +x /opt/etc/init.d/S99xray_net
echo "  Создано: S05xkeen, S10crond, S90restore_cron, S99xray_net"

# ===== [11/13] ПОДПИСКА =====
echo ""
echo "[11/13] Настройка подписки..."
echo "Введите ссылку на подписку (vless://):"
read SUB_URL
if [ -z "$SUB_URL" ]; then echo "ОШИБКА: ссылка не указана"; exit 1; fi

python3 - "$SUB_URL" << 'PYURL'
import json, sys
with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f:
    cfg = json.load(f)
cfg['subscription']['url'] = sys.argv[1]
with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
PYURL
echo "  Ссылка сохранена"

# ===== [12/13] ОЧИСТКА =====
echo ""
echo "[12/13] Очистка временных файлов..."
rm -rf /opt/var/opkg-lists/*
rm -rf /opt/_xkeen/02_install
rm -f /tmp/*.zip /tmp/*.tar.gz /tmp/cron_subkeen.txt
echo "  Очищено. Свободно: $(df -h /opt | tail -1 | awk '{print $4}')"

# ===== [13/13] ПЕРВЫЙ ЗАПУСК =====
echo ""
echo "[13/13] Первый запуск..."
mkdir -p /opt/var/spool/cron/crontabs
/opt/etc/init.d/S05xkeen start
sleep 3
/opt/bin/choose

echo ""
echo "============================================"
echo "  УСТАНОВКА ЗАВЕРШЕНА!"
echo "============================================"
echo "  Xray:   $(ps | grep -v grep | grep -c xray) процесс(ов)"
echo "  Cron:   $(crontab -l 2>/dev/null | grep -c subkeen_cron) задача"
echo "  Место:  $(df -h /opt | tail -1 | awk '{print $4}') свободно"
echo "============================================"
