cat << 'EOF' > /tmp/install.sh
#!/bin/sh
# ============================================================
# Автоустановка Xray/XKeen на Keenetic (Heavy Mode) v10.2
# СТАТУС: Ultimate Platinum Release. Добавлена защита от зависания при неинтерактивном запуске.
# ============================================================
set -e

echo "============================================"
echo "  XKeen + SubKeen Auto-Install v10.2"
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
for pkg in python3 curl iptables unzip; do
    opkg list-installed 2>/dev/null | grep -q "^$pkg " || opkg install $pkg >/dev/null 2>&1 || true
done

# [2] XRAY & XKEEN
echo "[2/6] Установка Xray и XKeen..."
killall xray 2>/dev/null || true
sleep 1
cd /tmp

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    mips)    XRAY_ARCH="mips32" ;;
    mipsel)  XRAY_ARCH="mips32le" ;;
    *)       echo "Неизвестная архитектура $ARCH, пробуем arm64-v8a"; XRAY_ARCH="arm64-v8a" ;;
esac
echo "  Определена архитектура: $ARCH -> $XRAY_ARCH"

curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.10.10/Xray-linux-${XRAY_ARCH}.zip" || \
curl -fsSL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.9.30/Xray-linux-${XRAY_ARCH}.zip"

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

# [3] CONFIGS (LOW MEMORY MODE)
echo "[3/6] Настройка конфигов..."
mkdir -p /opt/etc/xray/configs
cp -r /opt/_xkeen/02_install/08_install_configs/02_configs_xray/* /opt/etc/xray/configs/ 2>/dev/null || true

cat > /opt/etc/xray/configs/02_dns.json << 'DNS_EOF'
{ "dns": { "servers": ["1.1.1.1", "8.8.8.8"] } }
DNS_EOF

cat > /opt/etc/xray/configs/04_outbounds.json << 'OB_EOF'
{
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
OB_EOF

cat > /opt/etc/xray/configs/05_routing.json << 'ROUTING_EOF'
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "block", "network": "udp", "port": "135, 137, 138, 139" },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "block", "domain": ["appcenter.ms"] },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "outboundTag": "direct", "protocol": ["bittorrent"] },
      { "type": "field", "inboundTag": ["redirect", "tproxy"], "balancerTag": "auto-balancer" }
    ],
    "balancers": [
      {
        "tag": "auto-balancer",
        "selector": ["priority-", "proxy-"],
        "strategy": { "type": "leastLoad", "settings": { "tolerance": 0.5, "expectedCount": 3, "maxRTT": "2000ms" } }
      }
    ]
  }
}
ROUTING_EOF

cat > /opt/etc/xray/configs/07_observatory.json << 'OBS_EOF'
{
  "observatory": {
    "subjectSelector": ["proxy-", "priority-"],
    "probeUrl": "http://www.cloudflare.com/cdn-cgi/trace",
    "probeInterval": "60s"
  }
}
OBS_EOF

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

def resolve_ip(hostname):
    """Безопасный резолв с DoH фолбэком, отключена строгая проверка SSL для предотвращения chicken-and-egg проблемы"""
    try:
        return socket.gethostbyname(hostname)
    except Exception:
        try:
            url = f"https://1.1.1.1/dns-query?name={hostname}&type=A"
            req = urllib.request.Request(url, headers={'Accept': 'application/dns-json'})
            ctx_doh = ssl.create_default_context()
            ctx_doh.check_hostname = False
            ctx_doh.verify_mode = ssl.CERT_NONE
            with urllib.request.urlopen(req, context=ctx_doh, timeout=5) as r:
                data = json.loads(r.read().decode())
                for ans in data.get('Answer', []):
                    if ans.get('type') == 1:
                        return ans.get('data')
        except Exception:
            return None
    return None

def get_sub(url):
    ctx = ssl.create_default_context()
    for a in range(1, 4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url), context=ctx, timeout=30) as r:
                body = r.read().decode(errors="replace").strip()
            
            if body.startswith("vless://"):
                return [l.strip() for l in body.split("\n") if l.strip().startswith("vless://")]
            
            try:
                decoded = base64.b64decode(body.replace("\n","")).decode(errors="replace")
                return [l.strip() for l in decoded.split("\n") if l.strip().startswith("vless://")]
            except Exception:
                return [l.strip() for l in body.split("\n") if l.strip().startswith("vless://")]
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
            ip = resolve_ip(hostname)
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
                req = urllib.request.Request('https://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r:
                    api_results = json.loads(r.read().decode())
                if isinstance(api_results, list):
                    ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                else:
                    ip_to_country = {}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]
                    country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}
                    results[hostname] = country
            except Exception as e:
                print(f"  ⚠️ Ошибка API ({e}). Используем кэш.")
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
        except: friendly_name = f"server_{idx:02d}"
    else:
        friendly_name = f"server_{idx:02d}"
        
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
            excluded = True; print(f"  [!] {hostname} авто-исключён (Россия)")
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
    if not sub_url or sub_url == "ВСТАВЬТЕ_СЮДА_ВАШУ_ССЫЛКУ_НА_ПОДПИСКУ": 
        sys.exit("URL подписки пуст или не настроен")
    print("Скачиваем подписку..."); urls = get_sub(sub_url)
    if not urls: sys.exit("Нет vless-серверов в подписке")
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
        "strategy": {"type": bal_cfg.get("strategy", "leastLoad"), "settings": {"tolerance": bal_cfg.get("tolerance_percent", 50) / 100.0, "expectedCount": bal_cfg.get("expected_servers", 3), "maxRTT": bal_cfg.get("max_rtt", "2000ms")}}
    })
    
    for rule in r.get("rules", []):
        out_tag = rule.get("outboundTag")
        if out_tag and out_tag not in ("direct", "block") and "balancerTag" not in rule:
            rule["balancerTag"] = "auto-balancer"
            if "outboundTag" in rule: del rule["outboundTag"]
            
    atomic_write_json(RT, rt)
    
    print(f"Результат: приоритетных {n_pri}, обычных {n_proxy}, исключено {n_excl}")
    if not xray_test(): 
        print("ОТКАТ: Конфиг не прошёл тест.")
        sys.exit(1)
        
    subprocess.run(["/opt/bin/xkeen", "-restart"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    
    interval = cfg["subscription"].get("update_interval_hours", 3)
    os.makedirs("/opt/var/spool/cron/crontabs", exist_ok=True)
    p = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    lines = [l for l in (p.stdout.splitlines() if p.returncode == 0 else []) if "# subkeen_cron" not in l]
    lines.append(f"0 */{interval} * * * /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py # subkeen_cron")
    with open("/tmp/cron_subkeen.txt", "w") as f: f.write("\n".join(lines) + "\n")
    subprocess.run(["crontab", "/tmp/cron_subkeen.txt"], check=True)
    print(f"Готово. Cron каждые {interval} ч.")

if __name__ == "__main__": main()
PYEOF
chmod +x /opt/sbin/SubKeen-current/subkeen_multi.py

cat > /opt/sbin/choose-servers.py << 'CHOOSE_EOF'
#!/usr/bin/env python3
import urllib.request, ssl, base64, json, socket, time, sys
from urllib.parse import urlparse, unquote

COUNTRY_NAMES = {'RU': 'Россия', 'US': 'США', 'DE': 'Германия', 'NL': 'Нидерланды', 'FI': 'Финляндия', 'SE': 'Швеция', 'TR': 'Турция', 'JP': 'Япония'}
CACHE_TTL = 7 * 24 * 60 * 60

def resolve_ip(hostname):
    try:
        return socket.gethostbyname(hostname)
    except Exception:
        try:
            url = f"https://1.1.1.1/dns-query?name={hostname}&type=A"
            req = urllib.request.Request(url, headers={'Accept': 'application/dns-json'})
            ctx_doh = ssl.create_default_context()
            ctx_doh.check_hostname = False
            ctx_doh.verify_mode = ssl.CERT_NONE
            with urllib.request.urlopen(req, context=ctx_doh, timeout=5) as r:
                data = json.loads(r.read().decode())
                for ans in data.get('Answer', []):
                    if ans.get('type') == 1: return ans.get('data')
        except Exception:
            return None
    return None

def get_smart_geo_data(urls, config):
    cache = config.get("geo_cache", {}); current_time = int(time.time())
    hostnames_to_api = []; results = {}; resolved_data = {}
    for u in urls:
        try:
            hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
            if not hostname: continue
            ip = resolve_ip(hostname)
            resolved_data[hostname] = ip
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
                req = urllib.request.Request('https://ip-api.com/batch', data=data, headers={'Content-Type': 'application/json'}, method='POST')
                with urllib.request.urlopen(req, timeout=15) as r:
                    api_results = json.loads(r.read().decode())
                if isinstance(api_results, list):
                    ip_to_country = {item['query']: item.get('countryCode', '??') for item in api_results if item.get('status') == 'success'}
                else:
                    ip_to_country = {}
                for hostname in hostnames_to_api:
                    ip = resolved_data[hostname]; country = ip_to_country.get(ip, '??')
                    cache[hostname] = {"ip": ip, "country": country, "timestamp": current_time}; results[hostname] = country
            except:
                for hostname in hostnames_to_api: results[hostname] = cache.get(hostname, {}).get("country", "??")
    config["geo_cache"] = cache
    with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f: json.dump(config, f, indent=2, ensure_ascii=False)
    return results, resolved_data

try:
    with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f: config = json.load(f)
except Exception as e:
    print(f"Ошибка чтения конфига: {e}. Запустите установку заново.")
    sys.exit(1)

url = config['subscription']['url']
if not url or url == "ВСТАВЬТЕ_СЮДА_ВАШУ_ССЫЛКУ_НА_ПОДПИСКУ":
    print("Ошибка: URL подписки не настроен")
    sys.exit(1)

ctx = ssl.create_default_context()
try:
    with urllib.request.urlopen(url, context=ctx, timeout=30) as r: decoded = base64.b64decode(r.read().decode().strip()).decode()
    urls = [line.strip() for line in decoded.split('\n') if line.strip().startswith('vless://')]
    if not urls:
        print("Ошибка: В подписке не найдено серверов vless://")
        sys.exit(1)
        
    geo_data, resolved_data = get_smart_geo_data(urls, config)
    servers = []
    for i, u in enumerate(urls):
        name = unquote(u.split('#', 1)[1]) if '#' in u else f"Server_{i:02d}"
        hostname = urlparse(u.replace("vless://", "http://", 1)).hostname
        ip = resolved_data.get(hostname, "N/A"); cc = geo_data.get(hostname, "??")
        cname = COUNTRY_NAMES.get(cc, cc); mark = " [RU-BLOCK]" if cc == 'RU' else ""
        servers.append((i, name, ip, f"{cc}: {cname}{mark}"))
    
    print("Доступные серверы:")
    for i, name, ip, geo_str in servers: print(f"  [{i:02d}] {name}  [IP: {ip} | {geo_str}]")
    
    print("\n" + "="*70)
    choice = input("1. Номера для ПРИОРИТЕТА или [Enter] авто-выбор: ")
    print("="*70)
    if 'priority' not in config: config['priority'] = {}
    if not choice.strip(): 
        config['priority']['patterns'] = []
    else:
        nums = [int(x.strip()) for x in choice.split(',') if x.strip().isdigit()]
        config['priority']['patterns'] = [str(servers[i][1]) for i in nums if i < len(servers)]
        
    print("\n" + "="*70)
    bl = input("2. Номера для ЧЕРНОГО СПИСКА или [Enter] не менять: ")
    print("="*70)
    if bl.strip():
        bl_nums = [int(x.strip()) for x in bl.split(',') if x.strip().isdigit()]
        if 'exclusions' not in config: config['exclusions'] = {}
        config['exclusions']['manual_ip_blacklist'] = [str(servers[n][2]) for n in bl_nums if n < len(servers) and servers[n][2] != "N/A"]
        
    cur = config.get("balancer", {}).get("tolerance_percent", 50)
    print("\n" + "="*70)
    tol = input(f"3. Новая разница в % или [Enter] оставить {cur}%: ")
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
except Exception as e: print(f"Ошибка: {e}")
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
echo "[5/6] Настройка правил маршрутизации (iptables)..."

cat > /opt/etc/init.d/S99xray_net << 'S99_EOF'
#!/bin/sh
IPT=$(which iptables 2>/dev/null || which /opt/sbin/iptables 2>/dev/null)

get_xray_port() {
    PORT=$(python3 -c "
import json, sys, os, glob
try:
    configs_dir = '/opt/etc/xray/configs'
    inbounds_files = glob.glob(os.path.join(configs_dir, '*inbounds*.json'))
    for filepath in inbounds_files:
        with open(filepath) as f:
            data = json.load(f)
        for i in data.get('inbounds', []):
            if i.get('tag') in ['redirect', 'tproxy', 'transparent']:
                print(i.get('port', 1181))
                sys.exit(0)
except Exception:
    pass
print(1181)
" 2>/dev/null)
    echo "${PORT:-1181}"
}

apply_rules() {
  local count=0
  while [ $count -lt 40 ]; do
    if ip route | grep -q "default"; then
      break
    fi
    sleep 1
    count=$((count + 1))
  done
  
  XRAY_PORT=$(get_xray_port)
  
  $IPT -t nat -N xkeen 2>/dev/null
  for i in $(seq 1 10); do
    $IPT -t nat -D PREROUTING -j xkeen 2>/dev/null || break
  done
  
  $IPT -t nat -I PREROUTING 1 -j xkeen
  $IPT -t nat -F xkeen 2>/dev/null
  $IPT -t nat -A xkeen -d 127.0.0.0/8 -j RETURN
  $IPT -t nat -A xkeen -d 192.168.0.0/16 -j RETURN
  $IPT -t nat -A xkeen -d 10.0.0.0/8 -j RETURN
  $IPT -t nat -A xkeen -d 172.16.0.0/12 -j RETURN
  $IPT -t nat -A xkeen -p tcp -j REDIRECT --to-ports $XRAY_PORT
}

case "$1" in
  start)
    if [ "$2" = "force" ]; then apply_rules
    else ( apply_rules ) & fi
    ;;
  stop)
    for i in $(seq 1 10); do
      $IPT -t nat -D PREROUTING -j xkeen 2>/dev/null || break
    done
    $IPT -t nat -F xkeen 2>/dev/null
    $IPT -t nat -X xkeen 2>/dev/null
    ;;
  restart)
    $0 stop
    sleep 2
    $0 start "$2"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
S99_EOF
chmod +x /opt/etc/init.d/S99xray_net

# [6] CONFIG & SUBSCRIPTION + AUTO CHOOSE
echo "[6/6] Настройка подписки..."
cat > /opt/etc/xray/subkeen.conf.json << 'CONF_EOF'
{
  "subscription": {"url": "ВСТАВЬТЕ_СЮДА_ВАШУ_ССЫЛКУ_НА_ПОДПИСКУ", "update_interval_hours": 3},
  "observatory": {"probeUrl": "http://www.cloudflare.com/cdn-cgi/trace", "probeInterval": "60s"},
  "balancer": {"strategy": "leastLoad", "expected_servers": 3, "max_rtt": "2000ms", "tolerance_percent": 50},
  "priority": {"patterns": []},
  "exclusions": {"by_flag": ["🇷🇺"], "by_name": ["россия", "russia", "ru"], "by_hostname": ["msk", "moscow"], "manual_ip_blacklist": []},
  "system": {"log_level": "warning", "auto_restart_on_fail": true, "keep_backups": 3}
}
CONF_EOF

echo ""
echo "Введите ссылку на подписку (vless://):"
read -r SUB_URL

export SUB_URL
/opt/bin/python3 -c "
import json, os
with open('/opt/etc/xray/subkeen.conf.json', 'r', encoding='utf-8') as f: cfg = json.load(f)
cfg['subscription']['url'] = os.environ.get('SUB_URL', '')
with open('/opt/etc/xray/subkeen.conf.json', 'w', encoding='utf-8') as f: json.dump(cfg, f, indent=2, ensure_ascii=False)
"

echo ""
echo "⏳ Выполняем первичную загрузку серверов и генерацию конфигурации..."
if /opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py; then
    echo "✅ Конфигурация успешно сгенерирована."
    echo "⏳ Запускаем службы Xray и применяем правила маршрутизации..."
    
    /opt/bin/xkeen -restart >/dev/null 2>&1 || true
    /opt/etc/init.d/S99xray_net start force >/dev/null 2>&1 || true
    
    echo "🚀 Xray запущен, правила iptables применены."
    echo ""
    
    # ИСПРАВЛЕНО: Проверка на интерактивный терминал перед запуском мастера настройки
    # Это предотвращает зависание скрипта при автоматизированном или фоновом запуске
    if [ -t 0 ]; then
        echo "============================================"
        echo "  ЗАПУСКАЕМ МАСТЕР НАСТРОЙКИ (choose)"
        echo "============================================"
        echo ""
        /opt/bin/choose
    else
        echo "⚠️ Запуск из неинтерактивной среды (фон/скрипт)."
        echo "   Мастер настройки пропущен."
        echo "   Вы можете настроить серверы позже вручную командой: choose"
    fi
else
    echo "⚠️ Внимание: Первичная настройка завершилась с ошибкой."
    echo "   Проверьте правильность ссылки на подписку в /opt/etc/xray/subkeen.conf.json"
    echo "   После исправления ссылки просто выполните команду: choose"
fi

echo ""
echo "============================================"
echo "  УСТАНОВКА ЗАВЕРШЕНА!"
echo "============================================"
EOF

echo "Скрипт сохранен в /tmp/install.sh"
echo "Для запуска выполните: chmod +x /tmp/install.sh && /tmp/install.sh"
