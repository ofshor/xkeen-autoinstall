#!/bin/sh
# ============================================================
# XKeen autoinstall (на основе install.sh jameszeroX/XKeen)
# Вариант для накопителей малого объёма (~66 МБ свободно)
# Репозиторий: https://github.com/ofshor/xkeen-autoinstall
#
# Отличия от оригинала:
#   1. /opt/tmp -> симлинк на /tmp (tmpfs, ОЗУ). Установщик XKeen
#      распаковывает архив Xray ЦЕЛИКОМ (xray + geoip.dat +
#      geosite.dat, ~50 МБ) в /opt/tmp/xray, после чего dat-файлы
#      удаляются. На разделе 66 МБ этот транзиент переполняет UBIFS
#      (внешне — «зависание»). Симлинк переносит транзиент в ОЗУ.
#   2. Архив xkeen.tar.gz качается в /tmp, а не в текущий каталог.
#   3. Чистка хвостов прошлых неудачных попыток до начала работы.
#   4. Fail-fast проверка места + повтор распаковки при ENOSPC.
#   5. TMPDIR=/tmp для opkg-фазы внутри xkeen -i.
#   6. Ввод меню читается с /dev/tty: при `curl | sh` stdin занят
#      самим скриптом, и read «съедал» его строки, ломая парсер.
#      Финальный exec тоже получает /dev/tty, иначе меню xkeen
#      зацикливается на EOF пайпа.
# ============================================================

green="\033[92m"
red="\033[91m"
yellow="\033[93m"
light_blue="\033[96m"
italic="\033[3m"
reset="\033[0m"

url_stable="https://github.com/jameszeroX/XKeen/releases/latest/download/xkeen.tar.gz"
url_beta="https://raw.githubusercontent.com/jameszeroX/XKeen/main/test/xkeen.tar.gz"
archive_name="xkeen.tar.gz"

# Архив всегда качаем в /tmp (tmpfs в ОЗУ) — на накопителе он не появляется
archive_path="/tmp/${archive_name}"

# Каталог распаковки; используется trap-уборкой при прерывании
stage_dir=""

xkeen_config="/opt/etc/xkeen/xkeen.json"

# ---------------------------------------------------------------------------
# Свободное место (КБ) на файловой системе, где расположен путь
# ---------------------------------------------------------------------------
free_kb() {
    df -k "$1" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9'
}

# ---------------------------------------------------------------------------
# Хвосты прерванных прошлых установок — скрытый пожиратель места.
# .xkeen.stage.* — stage-каталоги самого установщика XKeen (03_install_xkeen.sh)
# ---------------------------------------------------------------------------
cleanup_stale() {
    rm -rf /opt/sbin/.xkeen-install.* 2>/dev/null
    rm -rf /opt/sbin/.xkeen.stage.* 2>/dev/null
    rm -f  /opt/sbin/xkeen.old /opt/sbin/xkeen.new 2>/dev/null
    rm -f  /tmp/xkeen.tar.gz /tmp/xkeen.tar.gz.sha256ref.* 2>/dev/null
    sync
}

# ---------------------------------------------------------------------------
# Уборка за текущим запуском (ошибки, Ctrl+C / TERM)
# ---------------------------------------------------------------------------
cleanup_runtime() {
    rm -f "${archive_path}".sha256ref.* "$archive_path" 2>/dev/null
    [ -n "$stage_dir" ] && rm -rf "$stage_dir" 2>/dev/null
    return 0
}
trap cleanup_runtime INT TERM

# ---------------------------------------------------------------------------
# Ввод с терминала, а не со stdin.
# При `curl ... | sh` stdin скрипта — пайп с текстом скрипта: обычный read
# «съедает» его строки, парсер рассинхронизируется (syntax error), меню
# ломается. Читаем с /dev/tty, если stdin — не терминал. Результат — в
# глобальной REPLY_TTY (без eval — безопасно при любом вводе).
# ---------------------------------------------------------------------------
read_from_tty() {
    REPLY_TTY=""
    if [ -t 0 ]; then
        read -r REPLY_TTY
    elif [ -c /dev/tty ]; then
        read -r REPLY_TTY < /dev/tty 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Ключевая правка для малого накопителя (см. шапку).
# Идемпотентно: повторный запуск увидит симлинк и пропустит шаг.
# Существующее содержимое /opt/tmp переносится в /tmp — там временные
# файлы, потеря которых при перезагрузке безопасна.
# После переустановки Entware симлинк нужно создать заново.
# ---------------------------------------------------------------------------
prepare_opt_tmp() {
    if [ -L /opt/tmp ]; then
        return 0
    fi

    if [ -d /opt/tmp ]; then
        if [ -n "$(ls -A /opt/tmp 2>/dev/null)" ]; then
            _ott_backup="/tmp/opt-tmp-backup.$$"
            mkdir -p "$_ott_backup" 2>/dev/null
            find /opt/tmp -mindepth 1 -maxdepth 1 -exec mv {} "$_ott_backup"/ \; 2>/dev/null
            printf "  ${yellow}Содержимое${reset} /opt/tmp перемещено в ${light_blue}%s${reset}\n" "$_ott_backup"
        fi
        rmdir /opt/tmp 2>/dev/null || rm -rf /opt/tmp
    elif [ -e /opt/tmp ]; then
        rm -f /opt/tmp
    fi

    if ! ln -s /tmp /opt/tmp; then
        printf "  ${red}Ошибка${reset}: не удалось создать симлинк ${yellow}/opt/tmp -> /tmp${reset}\n"
        exit 1
    fi

    printf "  ${green}/opt/tmp${reset} перенесён в ${light_blue}tmpfs${reset} (ОЗУ)\n"
    printf "  Транзиент установки Xray (~50 МБ) больше не занимает накопитель\n\n"
    return 0
}

# Функция для вывода справки
show_help() {
echo
echo -e "  ${yellow}Использование${reset}: $0 [ОПЦИИ]"
echo
echo -e "  ${yellow}Опции${reset}"
echo -e "    -s, --stable	${italic}Установить стабильную версию${reset}"
echo -e "    -b, --beta		${italic}Установить бета-версию${reset}"
echo -e "    -l, --legacy ВЕРСИЯ	${italic}Установить предыдущую версию (например, 1.1.3.9)${reset}"
echo -e "    -h, --help		${italic}Показать эту справку${reset}"
echo
echo -e "  ${yellow}Примеры${reset}"
echo  "    $0 --stable"
echo  "    $0 --beta"
echo  "    $0 --legacy 1.1.3.9"
echo  "    $0 --help"
echo  "    curl -sSL https://raw.githubusercontent.com/ofshor/xkeen-autoinstall/main/install.sh | tr -d '\r' | sh -s -- --stable"
}

# Дубль функции из scripts/_xkeen/01_info/01_info_common.sh
strip_json_comments() {
    awk '
    {
        line = ""; i = 1; n = length($0); instr = 0; esc = 0
        while (i <= n) {
            c = substr($0, i, 1)
            if (inblk) {
                if (c == "*" && substr($0, i + 1, 1) == "/") { inblk = 0; i += 2 } else i++
                continue
            }
            if (instr) {
                line = line c
                if (esc) esc = 0
                else if (c == "\\") esc = 1
                else if (c == "\"") instr = 0
                i++
                continue
            }
            if (c == "\"") { instr = 1; line = line c; i++; continue }
            if (c == "/" && substr($0, i + 1, 1) == "*") { inblk = 1; i += 2; continue }
            if (c == "/" && substr($0, i + 1, 1) == "/") break
            line = line c; i++
        }
        print line
    }' "$@"
}

# Функция извлечения пользовательского прокси из /opt/etc/xkeen/xkeen.json
get_user_proxy() {
    gh_proxy_user=""
    [ ! -f "$xkeen_config" ] && return 1

    gh_proxy_user=$(strip_json_comments "$xkeen_config" | \
        sed -n 's/.*"gh_proxy"[[:space:]]*: *"\([^"]*\)".*/\1/p' | \
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//' 2>/dev/null)

    [ "$gh_proxy_user" = "null" ] && gh_proxy_user=""
    [ -z "$gh_proxy_user" ] && return 1

    gh_proxy_user="${gh_proxy_user%/}"
    return 0
}

# Функция проверки доступности версии
check_version_available() {
    local test_url="$1"
    curl -sI -f --connect-timeout 3 -m 7 "$test_url" >/dev/null && return 0

    if [ -n "$gh_proxy_user" ]; then
        curl -sI -f --connect-timeout 3 -m 7 "$gh_proxy_user/$test_url" >/dev/null && return 0
    fi

    curl -sI -f --connect-timeout 3 -m 7 "https://gh-proxy.com/$test_url" >/dev/null || \
    curl -sI -f --connect-timeout 3 -m 7 "https://ghfast.top/$test_url" >/dev/null
}

# Функция загрузки XKeen (архив пишется в $archive_path — tmpfs)
download_xkeen_release() {
    if curl -fLo "$archive_path" --connect-timeout 10 -m 60 "$1"; then
        return 0
    fi

    if [ -n "$gh_proxy_user" ] && curl -fLo "$archive_path" --connect-timeout 10 -m 60 "$gh_proxy_user/$1"; then
        return 0
    fi

    if curl -fLo "$archive_path" --connect-timeout 10 -m 60 "https://gh-proxy.com/$1"; then
        return 0
    fi

    if curl -fLo "$archive_path" --connect-timeout 10 -m 60 "https://ghfast.top/$1"; then
        return 0
    fi

    printf "  ${red}Ошибка${reset}: не удалось загрузить ${yellow}xkeen.tar.gz${reset}\n"
    return 1
}

# Best-effort проверка SHA-256 через GitHub Releases API.
# На чистой установке jq отсутствует — предупреждение и пропуск.
verify_install_sha256() {
    _vis_file="$1"
    _vis_url="$2"
    _vis_asset=$(basename "$_vis_url")

    _vis_api_url=$(printf '%s' "$_vis_url" | \
        sed -n 's#^https://github\.com/\([^/]*\)/\([^/]*\)/releases/download/\([^/]*\)/.*#https://api.github.com/repos/\1/\2/releases/tags/\3#p')
    if [ -z "$_vis_api_url" ]; then
        _vis_api_url=$(printf '%s' "$_vis_url" | \
            sed -n 's#^https://github\.com/\([^/]*\)/\([^/]*\)/releases/latest/download/.*#https://api.github.com/repos/\1/\2/releases/latest#p')
    fi

    [ -z "$_vis_api_url" ] && return 0

    if ! command -v jq >/dev/null 2>&1; then
        printf "  ${yellow}Предупреждение${reset}: jq не установлен, проверка контрольной суммы ${light_blue}SHA-256${reset} пропущена\n"
        return 0
    fi

    _vis_ref="${_vis_file}.sha256ref.$$"
    if ! curl -fLsS --connect-timeout 10 -m 15 -o "$_vis_ref" "$_vis_api_url"; then
        if [ -n "$gh_proxy_user" ] && curl -fLsS --connect-timeout 10 -m 15 -o "$_vis_ref" "$gh_proxy_user/$_vis_api_url"; then
            :
        elif curl -fLsS --connect-timeout 10 -m 15 -o "$_vis_ref" "https://gh-proxy.com/$_vis_api_url"; then
            :
        elif curl -fLsS --connect-timeout 10 -m 15 -o "$_vis_ref" "https://ghfast.top/$_vis_api_url"; then
            :
        else
            rm -f "$_vis_ref"
            printf "  ${yellow}Предупреждение${reset}: GitHub API недоступен, проверка контрольной суммы ${light_blue}SHA-256${reset} пропущена\n"
            return 0
        fi
    fi

    _vis_expected=$(jq -r --arg asset "$_vis_asset" '.assets[]? | select(.name == $asset) | .digest // ""' "$_vis_ref" 2>/dev/null | head -n 1)
    rm -f "$_vis_ref"

    case "$_vis_expected" in
        sha256:*) _vis_expected="${_vis_expected#sha256:}" ;;
    esac

    case "$_vis_expected" in
        [0-9a-fA-F][0-9a-fA-F]*) ;;
        *)
            printf "  ${yellow}Предупреждение${reset}: контрольная сумма ${light_blue}SHA-256${reset} не найдена в GitHub API, проверка пропущена\n"
            return 0
            ;;
    esac

    if ! command -v sha256sum >/dev/null 2>&1; then
        printf "  ${yellow}Предупреждение${reset}: sha256sum не установлен, проверка контрольной суммы ${light_blue}SHA-256${reset} пропущена\n"
        return 0
    fi

    _vis_actual=$(sha256sum "$_vis_file" 2>/dev/null | awk '{print $1}')
    if [ "$_vis_actual" = "$_vis_expected" ]; then
        printf "  Контрольная сумма ${light_blue}SHA-256${reset} файла %s ${green}проверена${reset}\n" "$_vis_asset"
        return 0
    fi

    printf "  ${red}Ошибка${reset}: контрольная сумма ${light_blue}SHA-256${reset} файла %s не совпала с ожидаемой\n" "$_vis_asset"
    return 1
}

download_with_check() {
    url="$1"
    output_file="$2"
    min_size="${3:-50000}"

    curl --connect-timeout 5 -m 15 -y 1000 -Y 5 -s -L "$url" -o "$output_file" 2>/dev/null

    if [ -f "$output_file" ]; then
        size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
        if [ "$size" -gt "$min_size" ]; then
            if head -c 100 "$output_file" 2>/dev/null | grep -iqE '^(<!doctype|<html|<head|<body|404|error|not found)'; then
                rm -f "$output_file" 2>/dev/null
                return 1
            fi
            return 0
        fi
    fi

    rm -f "$output_file" 2>/dev/null
    return 1
}

check_entware_repo() {
    printf "  ${yellow}Проверка готовности${reset} к установке. Пожалуйста, подождите...\n"

    repo_url=$(awk '/^src/ {print $3; exit}' /opt/etc/opkg.conf 2>/dev/null)

    if [ -z "$repo_url" ]; then
        printf "  ${red}Не удалось${reset} определить используемый репозиторий Entware\n"
        printf "  Проверьте файл ${yellow}/opt/etc/opkg.conf${reset}\n"
        exit 1
    fi

    tmp_file="/tmp/pkg_check_$$"

    if download_with_check "$repo_url/Packages.gz" "$tmp_file"; then
        rm -f "$tmp_file" 2>/dev/null
        clear && echo
        return 0
    fi

    rm -f "$tmp_file" 2>/dev/null
    printf "  Репозиторий Entware ${red}недоступен${reset}\n"
    printf "  Установка ${red}прервана${reset}. Выберите рабочее зеркало по ссылке ${light_blue}https://entware.net/mirrors.html${reset}\n"
    printf "  и укажите его в файле ${yellow}/opt/etc/opkg.conf${reset}, после чего запустите установку повторно\n"
    exit 1
}

# Парсинг аргументов командной строки
VERSION_TYPE=""
LEGACY_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -s|--stable)
            VERSION_TYPE="stable"
            shift
            ;;
        -b|--beta)
            VERSION_TYPE="beta"
            shift
            ;;
        -l|--legacy)
            VERSION_TYPE="legacy"
            LEGACY_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            printf "  ${red}Неизвестный параметр${reset}: $1\n"
            show_help
            exit 1
            ;;
    esac
done

[ -t 1 ] && clear
echo

# 1) Чистим хвосты прошлых неудачных попыток
cleanup_stale

# 2) Проверяем доступность репозитория Entware
check_entware_repo

# 3) Транзиент установки — в ОЗУ (ключевая правка, см. шапку)
prepare_opt_tmp

# 4) Контроль свободного места на накопителе (fail-fast)
avail_kb=$(free_kb /opt)
case "$avail_kb" in ''|*[!0-9]*) avail_kb="" ;; esac
if [ -n "$avail_kb" ]; then
    if [ "$avail_kb" -lt 15360 ]; then
        printf "  ${red}Недостаточно места${reset}: свободно ${yellow}%d КБ${reset}\n" "$avail_kb"
        printf "  Стационарно установка займёт ~40-45 МБ (Xray ~30 + пакеты ~9 + модули ~3)\n"
        printf "  Освободите место на накопителе и запустите установку повторно\n"
        echo
        exit 1
    elif [ "$avail_kb" -lt 46080 ]; then
        printf "  ${yellow}Внимание${reset}: свободно ${yellow}%d МБ${reset} из ~45 МБ, необходимых для установки\n" $((avail_kb / 1024))
        echo
    fi
fi

# 5) Бюджет tmpfs: пик фазы Xray ~65-70 МБ (zip ~15 + распаковка ~50)
tmp_free_kb=$(free_kb /tmp)
case "$tmp_free_kb" in ''|*[!0-9]*) tmp_free_kb="" ;; esac
if [ -n "$tmp_free_kb" ] && [ "$tmp_free_kb" -lt 71680 ]; then
    printf "  ${yellow}Внимание${reset}: в /tmp (ОЗУ) свободно ~%d МБ, пик установки Xray ~65-70 МБ\n" $((tmp_free_kb / 1024))
    printf "  При нехватке tmpfs установка может упасть или уйти в swap (медленно)\n\n"
fi

# Проверяем наличие пользовательского прокси в конфиге
if get_user_proxy; then
    printf "  Используется ${green}пользовательский прокси${reset}: ${yellow}%s${reset}\n\n" "$gh_proxy_user"
fi

# Если параметры не переданы, показываем интерактивное меню
if [ -z "$VERSION_TYPE" ]; then
    while true; do
        printf "  Какую версию ${yellow}XKeen${reset} вы хотите установить?\n\n"
        printf "  1) Стабильную версию (${light_blue}Stable${reset})\n"
        printf "  2) Новую Бета-версию (${light_blue}Beta${reset})\n"
        printf "  3) Предыдущую версию (${light_blue}Legacy${reset})\n\n"
        printf "  0) Отмена\n\n"
        printf "  Выберите пункт меню [по умолчанию 1]: "
        read_from_tty
        version_choice="$REPLY_TTY"

        [ -z "$version_choice" ] && version_choice=1

        case "$version_choice" in
            0)
                printf "\n  Установка отменена.\n"
                exit 0
                ;;
            1)
                url="$url_stable"
                echo
                printf "  Выбрана ${light_blue}Стабильная версия${reset}\n"
                break
                ;;
            2)
                url="$url_beta"
                echo
                printf "  Выбрана ${light_blue}Бета-версия${reset}\n"
                break
                ;;
            3)
                echo
                while true; do
                    printf "  ${red}Внимание!${reset}\n  Предыдущие версии могут быть несовместимы с новыми прошивками\n"
                    printf "  Продолжайте только если уверены в том, что делаете\n\n"
                    printf "  Введите интересующую версию XKeen (например, ${light_blue}1.1.3.9${reset} или ${light_blue}0${reset} для выхода): "
                    read_from_tty
                    legacy_version="$REPLY_TTY"

                    if [ -z "$legacy_version" ]; then
                        printf "  ${red}Ошибка${reset}: версия не может быть пустой.\n\n"
                        continue
                    fi

                    [ "$legacy_version" = 0 ] && exit 0

                    url="https://github.com/jameszeroX/XKeen/releases/download/${legacy_version}/xkeen.tar.gz"

                    printf "  Проверяем доступность версии ${yellow}%s${reset}...\n" "$legacy_version"

                    if check_version_available "$url"; then
                        break 2
                    else
                        printf "  ${red}Ошибка${reset}: версия ${yellow}%s${reset} не найдена в репозитории или недоступна.\n\n" "$legacy_version"
                    fi
                done
                ;;
            *)
                [ -t 1 ] && clear
                printf "\n  ${red}Неверный выбор.${reset} Пожалуйста, выберите пункт от 0 до 3.\n\n"
                ;;
        esac
    done
else
    case "$VERSION_TYPE" in
        stable)
            url="$url_stable"
            printf "  Выбрана ${light_blue}Стабильная версия${reset} (автоматическая установка)\n"
            ;;
        beta)
            url="$url_beta"
            printf "  Выбрана ${light_blue}Бета-версия${reset} (автоматическая установка)\n"
            ;;
        legacy)
            if [ -z "$LEGACY_VERSION" ]; then
                printf "  ${red}Ошибка${reset}: для параметра --legacy необходимо указать версию\n"
                echo
                show_help
                exit 1
            fi
            url="https://github.com/jameszeroX/XKeen/releases/download/${LEGACY_VERSION}/xkeen.tar.gz"
            printf "  Выбрана предыдущая версия ${yellow}%s${reset} (автоматическая установка)\n" "$LEGACY_VERSION"
            printf "  Проверяем доступность версии ${yellow}%s${reset}...\n" "$LEGACY_VERSION"

            if ! check_version_available "$url"; then
                printf "  ${red}Ошибка${reset}: версия ${yellow}%s${reset} не найдена в репозитории или недоступна.\n" "$LEGACY_VERSION"
                exit 1
            fi
            printf "  ${green}Версия найдена${reset}, продолжаем установку...\n"
            ;;
        *)
            printf "  ${red}Неизвестный тип версии${reset}\n"
            exit 1
            ;;
    esac
fi

echo

if ! download_xkeen_release "$url"; then
    cleanup_runtime
    exit 1
fi

if ! verify_install_sha256 "$archive_path" "$url"; then
    cleanup_runtime
    exit 1
fi

# 6) Распаковка на накопитель (модули XKeen ~3 МБ). Архив в этот момент
#    в ОЗУ. При ENOSPC снимаем весь балласт со старой установки и повторяем.
stage_dir="/opt/sbin/.xkeen-install.$$"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"

tar_output=$(tar -xzf "$archive_path" -C "$stage_dir" 2>&1)
tar_status=$?

if [ "$tar_status" -ne 0 ]; then
    case "$tar_output" in
        *[Ss]pace*left*)
            printf "  ${yellow}Нехватка места${reset} при распаковке: освобождаем накопитель и повторяем\n"
            rm -rf "$stage_dir" /opt/sbin/.xkeen.old 2>/dev/null
            rm -f /opt/sbin/xkeen.old 2>/dev/null
            [ -d /opt/sbin/.xkeen ] && rm -rf /opt/sbin/.xkeen
            rm -rf /opt/sbin/.xkeen-install.* /opt/sbin/.xkeen.stage.* 2>/dev/null
            sync
            mkdir -p "$stage_dir"
            tar -xzf "$archive_path" -C "$stage_dir" 2>/dev/null
            ;;
        *)
            printf "  ${red}Ошибка${reset} распаковки: %s\n" "$tar_output"
            ;;
    esac
fi

if [ ! -f "$stage_dir/xkeen" ] || [ ! -d "$stage_dir/_xkeen" ]; then
    cleanup_runtime
    printf "  ${red}Ошибка${reset}: не удалось распаковать ${yellow}xkeen.tar.gz${reset}\n"
    exit 1
fi

# Архив больше не нужен — удаляем сразу после распаковки
rm -f "$archive_path" 2>/dev/null
sync

# 7) Перенос в рабочие пути (переименования внутри одного раздела)
chmod +x "$stage_dir/xkeen"
if ! mv "$stage_dir/xkeen" /opt/sbin/xkeen.new; then
    cleanup_runtime
    printf "  ${red}Ошибка${reset}: после распаковки не найден исполняемый файл ${yellow}/opt/sbin/xkeen${reset}\n"
    exit 1
fi
rm -f /opt/sbin/xkeen.old
[ -f /opt/sbin/xkeen ] && mv /opt/sbin/xkeen /opt/sbin/xkeen.old
if ! mv /opt/sbin/xkeen.new /opt/sbin/xkeen; then
    [ -f /opt/sbin/xkeen.old ] && mv /opt/sbin/xkeen.old /opt/sbin/xkeen
    cleanup_runtime
    printf "  ${red}Ошибка${reset}: после распаковки не найден исполняемый файл ${yellow}/opt/sbin/xkeen${reset}\n"
    exit 1
fi
rm -rf /opt/sbin/.xkeen.old
[ -d /opt/sbin/.xkeen ] && mv /opt/sbin/.xkeen /opt/sbin/.xkeen.old
if ! mv "$stage_dir/_xkeen" /opt/sbin/.xkeen; then
    [ -f /opt/sbin/xkeen.old ] && mv /opt/sbin/xkeen.old /opt/sbin/xkeen
    [ -d /opt/sbin/.xkeen.old ] && mv /opt/sbin/.xkeen.old /opt/sbin/.xkeen
    cleanup_runtime
    printf "  ${red}Ошибка${reset}: не удалось установить модули XKeen\n"
    exit 1
fi
rm -f /opt/sbin/xkeen.old
rm -rf /opt/sbin/.xkeen.old "$stage_dir"
stage_dir=""
sync

# 8) Перед самым тяжёлым этапом выгружаем с накопителя необязательное:
#    кэш opkg, временные каталоги opkg, устаревшие списки пакетов
#    (xkeen -i всё равно выполнит opkg update и скачает свежие)
rm -rf /opt/var/cache/opkg/* 2>/dev/null
rm -rf /opt/tmp/opkg-* 2>/dev/null
rm -rf /opt/var/opkg-lists/* 2>/dev/null
sync

# 9) Памятка перед передачей управления штатному установщику
printf "  ${yellow}Памятка для накопителя малого объёма${reset}\n"
printf "  В меню установщика:\n"
printf "    - Mihomo — ${red}откажитесь${reset} (требует ~86 МБ, не поместится)\n"
printf "    - GeoFile (geoip/geosite, ~20 МБ на накопителе) — откажитесь, если\n"
printf "      правила geosite:/geoip: не используются; доустановить можно позже\n"
printf "      повторным запуском ${light_blue}xkeen -i${reset}\n\n"
printf "  Запуск штатного установщика XKeen...\n\n"

# Временные файлы opkg (.ipk, каталоги распаковки) — в ОЗУ
export TMPDIR="/tmp"

# Интерактивному установщику нужен живой stdin: при `curl | sh` stdin —
# пайп с EOF, меню xkeen зациклится. Отдаём ему терминал.
if [ -t 0 ]; then
    exec /opt/sbin/xkeen -i
elif [ -c /dev/tty ]; then
    exec /opt/sbin/xkeen -i < /dev/tty
else
    printf "  ${red}Ошибка${reset}: нет терминала для интерактивной установки\n"
    printf "  Скачайте скрипт в файл и запустите: sh install.sh --stable\n"
    exit 1
fi
