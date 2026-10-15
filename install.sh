#!/bin/sh
# ============================================================
# Автоустановка Xray/XKeen на Keenetic (Heavy Mode) v8.5
# ИСПРАВЛЕНО: Извлечение конкретных элементов кортежа в choose-servers.py
# ============================================================
set -e
sed -i 's/\r$//' "$0" 2>/dev/null || true

echo "============================================"
echo "  XKeen + SubKeen Auto-Install v8.5"
echo "============================================"

if [ "$(id -u)" != "0" ]; then echo "ОШИБКА: запускать от root"; exit 1; fi
if [ ! -f /opt/bin/opkg ]; then echo "ОШИБКА: Entware не установлен"; exit 1; fi
if ! command -v curl >/dev/null 2>&1; then
    echo "ОШИБКА: curl не установлен! Выполните: opkg update && opkg install curl"
    exit 1
fi

FREE_MB=$(df /opt | tail -1 | awk '{print int($4/1024)}')
if [ "$FREE_MB" -lt 20 ]; then echo "ОШИБКА: мало памяти"; exit 1; fi

# [1] PACKAGES
echo "[1/6] Установка пакетов..."
opkg update >/dev/null 2>&1 || true
for pkg in python3 curl iptables; do
    opkg list-installed 2>/dev/null | grep -q "^$pkg " || opkg install $pkg >/dev/null 2>&1
done

# [2] XRAY & XKEEN
echo "[2/6] Установка Xray и XKeen..."
killall xray 2>/dev/null || true
sleep 1
cd /tmp
curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.9.30/Xray-linux-arm64-v8a.zip" || \
curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.6.1/Xray-linux-arm64-v8a.zip"
mkdir -p /opt/bin
unzip -o xray.zip xray -d /opt/bin/ >/dev/null
chmod +x /opt/bin/xray
rm -f xray.zip

curl -fsSL -o xkeen.tar.gz "https://github.com/jameszeroX/XKeen/releases/download/2.1/xkeen.tar.gz"
tar -xzf xkeen.tar.gz -C /opt/ >/dev/null
rm -f xkeen.tar.gz
chmod +x /opt/xkeen
ln -sf /opt/xkeen /opt/bin/xkeen
ln -sfn /opt/_xkeen /opt/bin/.xkeen

# [3] CONFIGS & CRITICAL FIXES
echo "[3/6] Настройка конфигов..."
mkdir -p /opt/etc/xray/configs
cp -r /opt/_xkeen/02_install/08_install_configs/02_configs_xray/* /opt/etc/xray/configs/ 2>/dev/null || true
touch /opt/etc/xray/geoip.dat /opt/etc/xray/geosite.dat

# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ 1: Гарантируем наличие direct и block
cat > /opt/etc/xray/configs/04_outbounds.json << 'OB_EOF'
{
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
OB_EOF

# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ 2: Гарантируем правильную структуру routing
cat > /opt/etc/xray/configs/05_routing.json << 'ROUTING_EOF'
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "block", "network": "udp", "port": "135, 137, 138, 139" },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "block", "domain": ["appcenter.ms"] },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "direct", "domain": ["regexp:^([\\w\\-\\.]+\\.)ru$", "regexp:^([\\w\\-\\.]+\\.)su$", "regexp:^([\\w\\-\\.]+\\.)xn--p1ai$", "regexp:^([\\w\\-\\.]+\\.)xn--p1acf$", "regexp:^([\\w\\-\\.]+\\.)xn--80asehdb$", "regexp:^([\\w\\-\\.]+\\.)xn--c1avg$", "regexp:^([\\w\\-\\.]+\\.)xn--80aswg$", "regexp:^([\\w\\-\\.]+\\.)xn--80adxhks$", "regexp:^([\\w\\-\\.]+\\.)moscow$", "regexp:^([\\w\\-\\.]+\\.)xn--d1acj3b$"] },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "direct", "protocol": ["bittorrent"] }
    ],
    "balancers": []
  }
}
ROUTING_EOF

# [4] SCRIPTS
echo "[4/6] Создание скриптов..."

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
                else: hostnames_to_api.append(hostname)
            else: hostnames_to_api.append(hostname)
        except: resolved_data[hostname] = None
    if hostnames_to_api:
        ips_to_query = list(set([resolved_data[h] for h in hostnames_to_api if resolved_data[h]]))
        if ips_to_query:
            try:
                data = json.dumps(ips_to_query).encode('utf-8')
                req = urllib.request.Request('http://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r: api_results = json.loads(r.read().decode())
                ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]; country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}; results[hostname] = country
            except:
                for hostname in hostnames_to_api: results[hostname] = cache.get(hostname, {}).get("country", "??")
    config["geo_cache"] = cache; save_config(config)
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
        if pat.lower() in friendly_name or pat.lower() in hostname: is_priority = True; break
    if not excluded and not is_priority:
        ip_blacklist = excl_cfg.get("manual_ip_blacklist", [])
        current_ip = resolved_data.get(hostname)
        if ip_blacklist and current_ip and current_ip in ip_blacklist: excluded = True
        if not excluded and current_ip and geo_data.get(hostname, '??') == 'RU':
            excluded = True; print("  [!] %s авто-исключён (Россия)" % hostname)
    tag = "excl-%02d" % idx if excluded else ("priority-%02d" % idx if is_priority else "proxy-%02d" % idx)
    sec = q.get("security", ["none"])[0]; net = q.get("type", ["tcp"])[0]
    ss = {}; ssn = None
    if sec == "reality":
        ssn = "realitySettings"
        ss = {"fingerprint": q.get("fp", ["chrome"])[0], "publicKey": q.get("pbk", [""])[0],
              "serverName": q.get("sni", q.get("serverName", [""]))[0], "shortId": q.get("sid", [""])[0]}
    elif sec == "tls":
        ssn = "tlsSettings"; sni = q.get("sni", q.get("serverName", [""]))[0]
        if sni: ss["serverName"] = sni
    ts = {}; tsn = "tcpSettings"
    if net == "ws":
        tsn = "wsSettings"; ts = {"path": q.get("path", ["/"])[0]}
        if q.get("host"): ts["host"] = q.get("host", [""])[0]
    elif net == "grpc":
        tsn = "grpcSettings"; ts = {"serviceName": q.get("serviceName", [""])[0]}
    user = {"id": d.username, "encryption": "none"}
    if "flow" in q: user["flow"] = q.get("flow", [""])[0]
    out = {"protocol": "vless", "settings": {"vnext": [{"address": d.hostname, "port": int(d.port), "users": [user]}]},
           "streamSettings": {"network": net, "security": sec}, "tag": tag}
    if ssn: out["streamSettings"][ssn] = ss
    if ts: out["streamSettings"][tsn] = ts
    return out, excluded, is_priority

def xray_test():
    p = subprocess.run(["/opt/bin/xray", "run", "-test", "-confdir", CONF_DIR], capture_output=True, text=True)
    if p.returncode == 0: print("  xray -test: OK"); return True
    print("  xray -test FAIL:\n" + (p.stderr or p.stdout)); return False

def main():
    cfg = load_config(); sub_url = cfg["subscription"]["url"]
    if not sub_url: sys.exit("URL пуст")
    print("Скачиваем подписку..."); urls = get_sub(sub_url)
    print("Smart Geo-Caching...")
    geo_data, resolved_data = get_smart_geo_data(urls, cfg)
    
    ob = load_jsonc(OB)
    if isinstance(ob, list): ob = {"outbounds": ob}
    if "outbounds" not in ob: ob["outbounds"] = []
    ob["outbounds"] = [o for o in ob["outbounds"] if not str(o.get("tag","")).startswith(("proxy-","excl-","priority-"))]
    
    n_excl = n_pri = n_proxy = 0
    for i, u in enumerate(urls):
        out, ex, pri = parse_vless(u, i, cfg, geo_data, resolved_data)
        if ex: n_excl += 1
        elif pri: n_pri += 1
        else: n_proxy += 1
        ob["outbounds"].append(out)
    atomic_write_json(OB, ob)
    
    rt = load_jsonc(RT)
    if "routing" not in rt: rt["routing"] = {"rules": [], "balancers": []}
    r = rt["routing"]
    if "rules" not in r: r["rules"] = []
        
    r["balancers"] = [b for b in r.get("balancers", []) if b.get("tag") != "auto-balancer"]
    bal_cfg = cfg.get("balancer", {})
    r["balancers"].append({
        "tag": "auto-balancer", "selector": ["priority-", "proxy-"],
        "strategy": {"type": bal_cfg.get("strategy", "leastLoad"), "settings": {"tolerance": bal_cfg.get("tolerance_percent", 50) / 100.0}}
    })
    
    known = {"vless-reality", "proxy", "proxy-00", "main", "vpn"}
    for rule in r.get("rules", []):
        if rule.get("outboundTag") in known:
            rule["balancerTag"] = "auto-balancer"
            if "outboundTag" in rule: del rule["outboundTag"]
            
    atomic_write_json(RT, rt)
    
    print("Результат: приоритетных %d, обычных %d, исключено %d" % (n_pri, n_proxy, n_excl))
    if not xray_test(): 
        print("ОТКАТ: Конфиг не прошёл тест.")
        sys.exit(1)
        
    subprocess.run(["xkeen", "-restart"], check=False)
    interval = cfg["subscription"].get("update_interval_hours", 3)
    p = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    lines = [l for l in (p.stdout.splitlines() if p.returncode == 0 else []) if "# subkeen_cron" not in l]
    lines.append("0 */%d * * * /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py # subkeen_cron" % interval)
    with open("/tmp/cron_subkeen.txt", "w") as f: f.write("\n".join(lines) + "\n")
    subprocess.run(["crontab", "/tmp/cron_subkeen.txt"], check=True)
    print("Готово. Cron каждые %d ч." % interval)

if __name__ == "__main__": main()
PYEOF
chmod +x /opt/sbin/SubKeen-current/subkeen_multi.py

cat > /opt/sbin/choose-servers.py << 'CHOOSE_EOF'
#!/usr/bin/env python3
import urllib.request, ssl, base64, json, socket, time
from urllib.parse import urlparse, unquote
COUNTRY_NAMES = {'RU': 'Россия', 'US': 'США', 'DE': 'Германия', 'NL': 'Нидерланды', 'FI': 'Финляндия', 'SE': 'Швеция'}
CACHE_TTL = 7 * 24 * 60 * 60

def get_smart_geo_data(urls, config):
    cache = config.get("geo_cache", {}); current_time = int(time.time())
    hostnames_to_api = []; results = {}; resolved_data = {}
    for u in urls:
        try:
            hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
            if not hostname: continue
            ip = socket.gethostbyname(hostname); resolved_data[hostname] = ip
            if hostname in cache:
                cached = cache[hostname]
                if cached.get("ip") == ip and (current_time - cached.get("timestamp", 0)) < CACHE_TTL: results[hostname] = cached["country"]
                else: hostnames_to_api.append(hostname)
            else: hostnames_to_api.append(hostname)
        except: resolved_data[hostname] = None
    if hostnames_to_api:
        ips_to_query = list(set([resolved_data[h] for h in hostnames_to_api if resolved_data[h]]))
        if ips_to_query:
            try:
                data = json.dumps(ips_to_query).encode('utf-8')
                req = urllib.request.Request('http://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r: api_results = json.loads(r.read().decode())
                ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]; country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}; results[hostname] = country
            except:
                for hostname in hostnames_to_api: results[hostname] = cache.get(hostname, {}).get("country", "??")
    config["geo_cache"] = cache
    with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f: json.dump(config, f, indent=2, ensure_ascii=False)
    return results, resolved_data

with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f: config = json.load(f)
url = config['subscription']['url']
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
try:
    with urllib.request.urlopen(url, context=ctx, timeout=30) as r: decoded = base64.b64decode(r.read().decode().strip()).decode()
    urls = [line.strip() for line in decoded.split('\n') if line.strip().startswith('vless://') and '#' in line]
    geo_data, resolved_data = get_smart_geo_data(urls, config)
    servers = []
    for i, u in enumerate(urls):
        name = unquote(u.split('#', 1)[1])
        hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
        ip = resolved_data.get(hostname, "N/A"); cc = geo_data.get(hostname, "??")
        cname = COUNTRY_NAMES.get(cc, cc); mark = " [RU-BLOCK]" if cc == 'RU' else ""
        servers.append((i, name, ip, "%s: %s%s" % (cc, cname, mark)))
    
    print("Доступные серверы:")
    for i, name, ip, geo_str in servers: print("  [%02d] %s  [IP: %s | %s]" % (i, name, ip, geo_str))
    
    print("\n" + "="*70)
    choice = input("1. Номера для ПРИОРИТЕТА или [Enter] авто-выбор: ")
    print("="*70)
    if 'priority' not in config: config['priority'] = {}
    if not choice.strip(): 
        config['priority']['patterns'] = []
    else:
        nums = [int(x.strip()) for x in choice.split(',') if x.strip().isdigit()]
        # КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: извлекаем именно имя (индекс 1), а не весь кортеж
        config['priority']['patterns'] = [str(servers[i][1]) for i in nums if i < len(servers)]
        
    print("\n" + "="*70)
    bl = input("2. Номера для ЧЕРНОГО СПИСКА или [Enter] не менять: ")
    print("="*70)
    if bl.strip():
        bl_nums = [int(x.strip()) for x in bl.split(',') if x.strip().isdigit()]
        if 'exclusions' not in config: config['exclusions'] = {}
        # КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: извлекаем именно IP (индекс 2), а не весь кортеж
        config['exclusions']['manual_ip_blacklist'] = [str(servers[n][2]) for n in bl_nums if n < len(servers) and servers[n][2] != "N/A"]
        
    cur = config.get("balancer", {}).get("tolerance_percent", 50)
    print("\n" + "="*70)
    tol = input("3. Новая разница в %% или [Enter] оставить %s%%: " % cur)
    print("="*70)
    if tol.strip():
        try:
            nt = int(tol.strip())
            if 0 <= nt <= 100:
                if 'balancer' not in config: config['balancer'] = {}
                config['balancer']['tolerance_percent'] = nt
        except: pass
        
    with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f: json.dump(config, f, indent=2, ensure_ascii=False)
    print("Настройки сохранены")
except Exception as e: print("Ошибка: %s" % e)
CHOOSE_EOF
chmod +x /opt/sbin/choose-servers.py

cat > /opt/bin/choose << 'CHOOSE_CMD'
#!/bin/sh
/opt/bin/python3 /opt/sbin/choose-servers.py
/opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py
echo "Готово!"
CHOOSE_CMD
chmod +x /opt/bin/choose

# [5] INIT-СКРИПТЫ
echo "[5/6] Создание init-скриптов..."

cat > /opt/etc/init.d/S05xkeen << 'S05_EOF'
#!/bin/sh
case "$1" in
    start) ps | grep -v grep | grep -q "/opt/bin/xray" || /opt/bin/xray run -confdir /opt/etc/xray/configs >/dev/null 2>&1 & ;;
    stop) killall xray 2>/dev/null ;;
    restart) $0 stop; sleep 2; $0 start ;;
esac
S05_EOF
chmod +x /opt/etc/init.d/S05xkeen

cat > /opt/etc/init.d/S99xray_net << 'S99_EOF'
#!/bin/sh
IPT=$(which iptables 2>/dev/null || which /opt/sbin/iptables 2>/dev/null)
apply_rules() {
  $IPT -t nat -N xkeen 2>/dev/null
  $IPT -t nat -C PREROUTING -j xkeen 2>/dev/null || $IPT -t nat -I PREROUTING 1 -j xkeen
  $IPT -t nat -F xkeen 2>/dev/null
  $IPT -t nat -A xkeen -d 127.0.0.0/8 -j RETURN
  $IPT -t nat -A xkeen -d 192.168.0.0/16 -j RETURN
  $IPT -t nat -A xkeen -d 10.0.0.0/8 -j RETURN
  $IPT -t nat -A xkeen -d 172.16.0.0/12 -j RETURN
  $IPT -t nat -A xkeen -p tcp -j REDIRECT --to-ports 1181
}
case "$1" in
    start)
        if [ "$2" = "force" ]; then apply_rules
        else ( sleep 20; apply_rules ) & fi
        ;;
esac
S99_EOF
chmod +x /opt/etc/init.d/S99xray_net

# [6] CONFIG & SUBSCRIPTION
echo "[6/6] Настройка подписки..."
cat > /opt/etc/xray/subkeen.conf.json << 'CONF_EOF'
{
  "subscription": {"url": "", "update_interval_hours": 3},
  "observatory": {"probe_url": "http://cp.cloudflare.com/generate_204", "probe_interval": "60s"},
  "balancer": {"strategy": "leastLoad", "expected_servers": 3, "max_rtt": "2000ms", "tolerance_percent": 50},
  "priority": {"patterns": []},
  "exclusions": {"by_flag": ["🇷🇺"], "by_name": ["россия", "russia", "ru"], "by_hostname": ["msk", "moscow"], "manual_ip_blacklist": []},
  "system": {"log_level": "warning", "auto_restart_on_fail": true, "keep_backups": 3}
}
CONF_EOF

echo "Введите ссылку на подписку (vless://):"
read SUB_URL
python3 -c "
import json, sys
with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f: cfg = json.load(f)
cfg['subscription']['url'] = sys.argv[1]
with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f: json.dump(cfg, f, indent=2, ensure_ascii=False)
" "$SUB_URL"

echo ""
echo "============================================"
echo "  УСТАНОВКА ЗАВЕРШЕНА!"
echo "============================================"
echo "  Для запуска VPN выполните команду: choose"
echo "============================================"
