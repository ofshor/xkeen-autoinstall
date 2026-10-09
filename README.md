<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🚀 XKeen AutoInstall — Установка на Keenetic</title>
<meta name="description" content="Автоматическая установка XKeen + Xray + SubKeen на встроенную память Keenetic в одну команду">
<style>
:root {
  --bg: #0d1117;
  --surface: #161b22;
  --surface-2: #21262d;
  --border: #30363d;
  --text: #e6edf3;
  --text-muted: #8b949e;
  --accent: #58a6ff;
  --accent-hover: #79c0ff;
  --green: #3fb950;
  --orange: #f0883e;
  --red: #f85149;
  --purple: #a371f7;
  --code-bg: #0d1117;
  --shadow: 0 8px 24px rgba(0,0,0,0.4);
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #ffffff;
    --surface: #f6f8fa;
    --surface-2: #eaeef2;
    --border: #d0d7de;
    --text: #1f2328;
    --text-muted: #656d76;
    --accent: #0969da;
    --accent-hover: #0550ae;
    --code-bg: #f6f8fa;
    --shadow: 0 8px 24px rgba(140,149,159,0.2);
  }
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
  padding: 0;
}
.container { max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem; }

/* HERO */
.hero {
  text-align: center;
  padding: 3rem 1rem 2rem;
  background: linear-gradient(135deg, rgba(88,166,255,0.1), rgba(163,113,247,0.1));
  border-radius: 16px;
  margin-bottom: 2rem;
  border: 1px solid var(--border);
}
.hero h1 {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
  background: linear-gradient(90deg, var(--accent), var(--purple));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.hero .subtitle { color: var(--text-muted); font-size: 1.1rem; margin-bottom: 1.5rem; }
.badges { display: flex; gap: 0.5rem; flex-wrap: wrap; justify-content: center; margin-bottom: 1.5rem; }
.badge {
  display: inline-block;
  padding: 0.3rem 0.8rem;
  border-radius: 20px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  font-size: 0.85rem;
  font-weight: 500;
}

/* QUICK COMMAND */
.quick-cmd {
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1rem;
  margin: 1.5rem auto;
  max-width: 700px;
  position: relative;
  font-family: 'SF Mono', Consolas, Monaco, monospace;
  font-size: 0.9rem;
  overflow-x: auto;
  white-space: nowrap;
}
.quick-cmd code { color: var(--green); }
.copy-btn {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  padding: 0.3rem 0.7rem;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.8rem;
  transition: all 0.2s;
}
.copy-btn:hover { background: var(--accent); color: white; }
.copy-btn.copied { background: var(--green); color: white; border-color: var(--green); }

/* SECTIONS */
.section {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 1.5rem;
  margin-bottom: 1.5rem;
}
.section h2 {
  font-size: 1.5rem;
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.5rem;
}
.section h3 { font-size: 1.1rem; margin: 1rem 0 0.5rem; color: var(--accent); }

/* NAV */
.nav {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
  justify-content: center;
  margin-bottom: 2rem;
  padding: 0.5rem;
  background: var(--surface);
  border-radius: 10px;
  border: 1px solid var(--border);
}
.nav a {
  color: var(--text);
  text-decoration: none;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  font-weight: 500;
  transition: all 0.2s;
}
.nav a:hover { background: var(--surface-2); color: var(--accent); }

/* STEPS */
.steps { counter-reset: step; }
.step {
  position: relative;
  padding-left: 3rem;
  margin-bottom: 1.5rem;
}
.step::before {
  counter-increment: step;
  content: counter(step);
  position: absolute;
  left: 0;
  top: 0;
  width: 2rem;
  height: 2rem;
  background: var(--accent);
  color: white;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: bold;
}
.step h4 { margin-bottom: 0.5rem; font-size: 1.05rem; }
.step p { color: var(--text-muted); margin-bottom: 0.5rem; }

/* CODE BLOCKS */
pre {
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1rem;
  overflow-x: auto;
  position: relative;
  margin: 0.5rem 0;
}
pre code {
  font-family: 'SF Mono', Consolas, Monaco, monospace;
  font-size: 0.85rem;
  color: var(--green);
  white-space: pre;
}
.cmd { position: relative; }
.cmd .copy-btn { top: 0.3rem; right: 0.3rem; font-size: 0.75rem; padding: 0.2rem 0.5rem; }

/* TABLES */
table {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
  font-size: 0.9rem;
}
th, td {
  padding: 0.7rem;
  text-align: left;
  border-bottom: 1px solid var(--border);
}
th { background: var(--surface-2); font-weight: 600; }
tr:hover td { background: var(--surface-2); }

/* DETAILS */
details {
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.7rem 1rem;
  margin: 0.5rem 0;
}
details summary {
  cursor: pointer;
  font-weight: 500;
  user-select: none;
}
details summary:hover { color: var(--accent); }
details[open] { padding-bottom: 0.7rem; }
details[open] summary { margin-bottom: 0.5rem; }

/* ALERTS */
.alert {
  padding: 0.8rem 1rem;
  border-radius: 8px;
  margin: 0.8rem 0;
  border-left: 4px solid;
  font-size: 0.9rem;
}
.alert-info { background: rgba(88,166,255,0.1); border-color: var(--accent); }
.alert-warn { background: rgba(240,136,62,0.1); border-color: var(--orange); }
.alert-success { background: rgba(63,185,80,0.1); border-color: var(--green); }
.alert-danger { background: rgba(248,81,73,0.1); border-color: var(--red); }

/* LINKS */
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; color: var(--accent-hover); }

/* FOOTER */
.footer {
  text-align: center;
  padding: 2rem 1rem;
  color: var(--text-muted);
  font-size: 0.85rem;
  border-top: 1px solid var(--border);
  margin-top: 2rem;
}

/* CODE inline */
code:not(pre code) {
  background: var(--surface-2);
  padding: 0.15rem 0.4rem;
  border-radius: 4px;
  font-family: 'SF Mono', Consolas, Monaco, monospace;
  font-size: 0.85em;
  color: var(--orange);
}

/* PRINT */
@media print {
  body { background: white; color: black; }
  .hero, .section { border: 1px solid #ddd; page-break-inside: avoid; }
  .nav, .copy-btn { display: none; }
  pre { white-space: pre-wrap; }
}

/* MOBILE */
@media (max-width: 600px) {
  .hero h1 { font-size: 1.8rem; }
  .container { padding: 1rem; }
  .step { padding-left: 2.5rem; }
  .quick-cmd { font-size: 0.75rem; }
}
</style>
</head>
<body>

<div class="container">

<!-- HERO -->
<div class="hero">
  <h1>🚀 XKeen AutoInstall</h1>
  <p class="subtitle">Автоматическая установка XKeen + Xray + SubKeen на встроенную память Keenetic</p>
  <div class="badges">
    <span class="badge">XKeen 2.1</span>
    <span class="badge">Xray v26.x</span>
    <span class="badge">Python 3.13</span>
    <span class="badge">KeeneticOS 3.7+</span>
    <span class="badge">Без USB</span>
  </div>
  <p style="color: var(--text-muted); margin-bottom: 1rem;">
    Без USB-флешки • С автобалансировкой по пингу • Исключение российских серверов
  </p>
  <div class="quick-cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋 Копировать</button>
    <code>sh -c "$(curl -fsSL https://raw.githubusercontent.com/ofshor/xkeen-autoinstall/main/install.sh)"</code>
  </div>
</div>

<!-- NAV -->
<nav class="nav">
  <a href="#requirements">📋 Требования</a>
  <a href="#install">🔧 Установка</a>
  <a href="#verify">✅ Проверка</a>
  <a href="#commands">📝 Команды</a>
  <a href="#faq">❓ FAQ</a>
  <a href="#errors">🛡️ Учтённые ошибки</a>
</nav>

<!-- REQUIREMENTS -->
<section class="section" id="requirements">
  <h2>📋 Требования</h2>
  <table>
    <tr><th>Параметр</th><th>Значение</th></tr>
    <tr><td>Роутер</td><td>Keenetic с UBIFS (Hopper KN-3811, Giga, Ultra и др.)</td></tr>
    <tr><td>KeeneticOS</td><td>3.7 и новее</td></tr>
    <tr><td>Встроенная память</td><td>~66 МБ UBIFS</td></tr>
    <tr><td>Подписка</td><td>VLESS-формат (<code>vless://...</code>)</td></tr>
    <tr><td>Свободно после установки</td><td>~25 МБ</td></tr>
  </table>

  <details>
    <summary><b>🎯 Что будет установлено</b></summary>
    <table>
      <tr><th>Компонент</th><th>Версия</th><th>Назначение</th></tr>
      <tr><td>Entware</td><td>последняя</td><td>Пакетный менеджер</td></tr>
      <tr><td>Python</td><td>3.13.x</td><td>Для работы SubKeen</td></tr>
      <tr><td>Xray</td><td>v26.6.1+</td><td>Ядро проксирования</td></tr>
      <tr><td>XKeen</td><td>2.1</td><td>Конфигуратор</td></tr>
      <tr><td>SubKeen</td><td>актуальная</td><td>Обработка подписок</td></tr>
    </table>
  </details>
</section>

<!-- INSTALL -->
<section class="section" id="install">
  <h2>🔧 Установка (5 минут)</h2>

  <div class="steps">

    <div class="step">
      <h4>Очистка встроенной памяти</h4>
      <p>В веб-интерфейсе Keenetic:</p>
      <ol style="margin-left: 1.5rem; color: var(--text-muted);">
        <li><b>Накопители и устройства</b> → <b>Встроенное хранилище</b></li>
        <li><code>⋮</code> → <b>Отключить</b></li>
        <li><code>⋮</code> → <b>Стереть</b> → подтвердить</li>
        <li><code>⋮</code> → <b>Подключить</b></li>
      </ol>
      <div class="alert alert-info">
        Статус должен стать <b>ПОДКЛЮЧЕНО</b>, занято 0 МБ.
      </div>
    </div>

    <div class="step">
      <h4>Установка Entware</h4>
      <p>Скачай установщик:</p>
      <p>
        <a href="http://bin.entware.net/aarch64-k3.10/installer/aarch64-installer.tar.gz" target="_blank">
          📥 aarch64-installer.tar.gz
        </a>
      </p>
      <ol style="margin-left: 1.5rem; color: var(--text-muted);">
        <li>В файловом менеджере <code>storage:</code> создай папку <code>install</code></li>
        <li>Загрузи архив <b>внутрь</b> <code>install/</code></li>
      </ol>
      <p>В CLI роутера (SSH порт 22, admin/Keenetic):</p>
      <div class="cmd">
        <button class="copy-btn" onclick="copyCmd(this)">📋</button>
        <pre><code>opkg disk storage:/</code></pre>
      </div>
      <div class="alert alert-info">
        Роутер перезагрузится. Подожди 2-3 минуты.
      </div>
    </div>

    <div class="step">
      <h4>Запуск скрипта установки</h4>
      <p>Подключись по SSH на <b>порт 222</b> (логин <code>root</code>, пароль <code>keenetic</code>):</p>
      <div class="cmd">
        <button class="copy-btn" onclick="copyCmd(this)">📋</button>
        <pre><code>ssh -p 222 root@192.168.1.1</code></pre>
      </div>
      <p>Выполни одну команду:</p>
      <div class="cmd">
        <button class="copy-btn" onclick="copyCmd(this)">📋</button>
        <pre><code>sh -c "$(curl -fsSL https://raw.githubusercontent.com/ofshor/xkeen-autoinstall/main/install.sh)"</code></pre>
      </div>
    </div>

    <div class="step">
      <h4>Ответь на вопросы скрипта</h4>
      <ul style="margin-left: 1.5rem; color: var(--text-muted);">
        <li><b>Выбор версии Xray</b> — нажми Enter (по умолчанию v26.6.1) или выбери другую</li>
        <li><b>Ссылка на подписку</b> — вставь свою vless-ссылку</li>
      </ul>
    </div>

  </div>
</section>

<!-- VERIFY -->
<section class="section" id="verify">
  <h2>✅ Финальная проверка</h2>
  <p>Перезагрузи роутер:</p>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>reboot</code></pre>
  </div>
  <p>После перезагрузки (1-2 минуты) проверь:</p>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>ps | grep -E "xray|crond"          # По 1 процессу
cat /var/spool/cron/crontabs/root  # Задача на месте
curl -s ifconfig.me                # IP европейский
df -h /opt                         # ~25 МБ свободно</code></pre>
  </div>
  <div class="alert alert-success">
    ✅ Если все 4 проверки прошли — система полностью рабочая и автозапускается при перезагрузке.
  </div>
</section>

<!-- COMMANDS -->
<section class="section" id="commands">
  <h2>📝 Команды после установки</h2>

  <h3>🔄 Обновить подписку вручную</h3>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>/opt/bin/python3 /opt/sbin/SubKeen-current/subkeen_multi.py -url "ССЫЛКА"</code></pre>
  </div>

  <h3>🔁 Перезапустить Xray</h3>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>/opt/etc/init.d/S05xkeen restart</code></pre>
  </div>

  <h3>🚫 Добавить паттерн в исключения</h3>
  <p>Серверы с этим паттерном не попадут в балансировку:</p>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>echo "новый-паттерн" >> /opt/etc/xray/subkeen_exclude.txt</code></pre>
  </div>

  <h3>🌐 Посмотреть текущий IP</h3>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>curl -s ifconfig.me</code></pre>
  </div>

  <h3>🔐 Сменить пароль root</h3>
  <div class="cmd">
    <button class="copy-btn" onclick="copyCmd(this)">📋</button>
    <pre><code>passwd root</code></pre>
  </div>
</section>

<!-- FAQ -->
<section class="section" id="faq">
  <h2>❓ FAQ</h2>

  <details>
    <summary><b>🔒 Почему не через USB-флешку?</b></summary>
    <p>USB нужен для 4G-модема. На встроенной памяти Keenetic (66 МБ UBIFS) достаточно места для всей системы. Скрипт оптимизирован под малую память.</p>
  </details>

  <details>
    <summary><b>📊 Как работает автобалансировка?</b></summary>
    <p>Observatory пингует серверы каждые <b>60 секунд</b>. Balancer со стратегией <code>leastPing</code> автоматически выбирает самый быстрый сервер. Если текущий сервер падает — переключение происходит мгновенно.</p>
  </details>

  <details>
    <summary><b>🇷🇺 Какие серверы исключаются из балансировки?</b></summary>
    <p>Паттерны в <code>/opt/etc/xray/subkeen_exclude.txt</code>: <code>ru</code>, <code>msk</code>, <code>moscow</code>, <code>russia</code>, <code>cashgruz</code>. Серверы с этими подстроками в hostname помечаются как <code>excl-XX</code> и не участвуют в балансировке.</p>
  </details>

  <details>
    <summary><b>⏰ Как часто обновляется подписка?</b></summary>
    <p>Cron-задача выполняет обновление <b>каждые 3 часа</b> (0 */3 * * *). Задача автоматически восстанавливается после перезагрузки скриптом <code>S90restore_cron</code>.</p>
  </details>

  <details>
    <summary><b>🐛 Почему не работает <code>xkeen -version</code>?</b></summary>
    <p>Это не критично. XKeen установлен, но CLI требует регистрации через установщик. Наш скрипт работает напрямую с конфигами Xray — это даже стабильнее.</p>
  </details>

  <details>
    <summary><b>🔧 Как добавить домен в исключения routing?</b></summary>
    <p>Отредактируй <code>/opt/etc/xray/configs/05_routing.json</code>, добавь домен в секцию <code>direct</code>. После этого перезапусти Xray: <code>/opt/etc/init.d/S05xkeen restart</code></p>
  </details>
</section>

<!-- ERRORS -->
<section class="section" id="errors">
  <h2>🛡️ Учтённые ошибки (из реальной практики)</h2>
  <table>
    <tr><th>Проблема</th><th>Решение</th></tr>
    <tr><td>UBIFS зависает при массовой установке пакетов</td><td>Установка по одному с индикацией</td></tr>
    <tr><td>OOM kill при запуске установщика XKeen</td><td>Ручная установка Xray/XKeen через curl</td></tr>
    <tr><td><code>ext:geosite_v2fly.dat</code> ломает Xray</td><td>Чистый routing.json без geo-файлов (экономия 20 МБ)</td></tr>
    <tr><td>Crontab в tmpfs теряется после reboot</td><td>S90restore_cron восстанавливает задачу</td></tr>
    <tr><td>Дублирование crond</td><td>Проверка через pgrep перед запуском</td></tr>
    <tr><td>XKeen 2.1 требует Xray v25+</td><td>Только современные версии в меню</td></tr>
    <tr><td><code>unknown encoding: idna</code></td><td>Автоматическая установка python3-idna</td></tr>
  </table>
</section>

<!-- FOOTER -->
<div class="footer">
  <p>⭐ Если инструкция помогла — поставьте звёздочку на <a href="https://github.com/ofshor/xkeen-autoinstall">GitHub</a></p>
  <p style="margin-top: 0.5rem;">Свободное использование • Указывайте источник при распространении</p>
  <p style="margin-top: 1rem; font-size: 0.75rem;">Последнее обновление: 2026-10-10</p>
</div>

</div>

<script>
function copyCmd(btn) {
  const code = btn.parentElement.querySelector('code').textContent;
  navigator.clipboard.writeText(code).then(() => {
    const original = btn.textContent;
    btn.textContent = '✅ Скопировано!';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 2000);
  });
}

// Smooth scroll for nav links
document.querySelectorAll('a[href^="#"]').forEach(a => {
  a.addEventListener('click', e => {
    e.preventDefault();
    document.querySelector(a.getAttribute('href')).scrollIntoView({
      behavior: 'smooth', block: 'start'
    });
  });
});
</script>

</body>
</html>
