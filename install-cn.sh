#!/bin/bash
#
# ============================================================
#   3x-ui 中文一键安装脚本 (install-cn.sh)
#   镜像仓库: https://github.com/freekm-dev/3x-ui
#
#   基于官方 3x-ui，全程中文交互，资源自托管，
#   不依赖官方 mhsanaei 仓库。
# ============================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

# ---------- 镜像与版本配置（集中管理） ----------
mirror_repo="freekm-dev/3x-ui"
raw_base="https://raw.githubusercontent.com/${mirror_repo}/master"
release_base="https://github.com/${mirror_repo}/releases/download"

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service_folder="/etc/systemd/system"
xui_service_name="x-ui"

RAND_USER_LEN=10
RAND_PASS_LEN=12

# 用户选择结果（全局）
CHOICE_DB="sqlite"
CHOICE_SSL="4"
SSL_DOMAIN=""
SSL_CERT_PATH=""
SSL_KEY_PATH=""

# ---------- 输出辅助 ----------
echo_red()    { echo -e "${red}$*${plain}"; }
echo_green()  { echo -e "${green}$*${plain}"; }
echo_yellow() { echo -e "${yellow}$*${plain}"; }
echo_blue()   { echo -e "${blue}$*${plain}"; }
echo_cyan()   { echo -e "${cyan}$*${plain}"; }

# ---------- 旋转进度指示器（真动画）----------
# 用法： spin_start "提示文字"  →  spin_stop "成功文字" | spin_fail "失败文字"
SPIN_PID=""
_SPIN_MSG=""
_spin_loop() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while :; do
        printf "\r${cyan}  %s${plain} %s" "${frames[$i]}" "$_SPIN_MSG"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
}

# 启动旋转动画（需要传入一段要执行的命令）
spin_run() {
    local msg="$1"; shift
    local ok_msg="$1"; shift
    local fail_msg="$1"; shift
    _SPIN_MSG="$msg"
    if [[ -t 1 ]]; then
        _spin_loop &
        SPIN_PID=$!
        "$@" >/dev/null 2>&1
        local rc=$?
        kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null
        printf "\r\033[K"
        if [[ $rc -eq 0 ]]; then
            echo -e "${green}  ✔ ${ok_msg}${plain}"
        else
            echo -e "${red}  ✘ ${fail_msg}${plain}"
        fi
        return $rc
    else
        # 非交互环境：直接执行，输出常规提示
        "$@" >/dev/null 2>&1
        local rc=$?
        if [[ $rc -eq 0 ]]; then echo -e "${green}  ✔ ${ok_msg}${plain}"; else echo -e "${red}  ✘ ${fail_msg}${plain}"; fi
        return $rc
    fi
}

# ---------- 带百分比的下载（真进度）----------
# 用法： download_file <url> <输出文件> <描述>
download_file() {
    local url="$1" out="$2" desc="${3:-下载文件}"
    local size_hint=""
    echo -e "${blue}  ↓ ${desc}${plain}"
    if command -v curl >/dev/null 2>&1; then
        # --progress-bar 会画出真实进度条；若不可用则退回静默
        curl -fLR --retry 3 --retry-delay 2 --connect-timeout 20 \
            --progress-bar -o "${out}" "${url}" || return 1
    else
        wget -q --show-progress -O "${out}" "${url}" || return 1
    fi
    return 0
}

print_logo() {
    echo -e "${cyan}"
    cat <<'LOGO'
    ______               __ __
   / ____/______  ___  / //_/___ ___  ____ _
  / /_  / ___/ _ \/ _ \/ ,< / __ `__ \/ __ `/
 / __/ / /  /  __/  __/ /| |/ / / / / /_/ /
/_/   /_/   \___/\___/_/ |_/_/ /_/ /_/\__, /
                                      /____/
LOGO
    echo -e "${plain}"
    echo -e "${green}        FreeKm  3x-ui 中文一键安装脚本${plain}"
    echo -e "${blue}        镜像仓库: https://github.com/${mirror_repo}${plain}"
    echo -e "${cyan}        ==========================================${plain}"
    echo ""
}

# ---------- 基础检查 ----------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_red "错误：请使用 root 权限运行此脚本！"
        echo_yellow "可以尝试：sudo bash $0"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
        source /usr/lib/os-release
        release=$ID
    else
        echo_red "无法检测系统版本，/etc/os-release 不存在。"
        exit 1
    fi
    echo_green "当前系统：${PRETTY_NAME:-$release}"
}

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo 'unknown' ;;
    esac
}

gen_random_string() {
    local length="$1"
    head -c $((length * 3)) /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {found=1} END {exit !found}'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk -v p=":${port} " '$4 ~ p {found=1} END {exit !found}'
    else
        return 1
    fi
}

# ---------- 依赖安装（带实时进度 + 快速跳过）----------
# 检查依赖是否齐全；齐全则直接跳过，避免多余的 apt-get update（通常 5~10 秒）
deps_all_present() {
    local c
    for c in curl tar socat openssl; do
        command -v "$c" >/dev/null 2>&1 || return 1
    done
    [[ -f /usr/share/zoneinfo/UTC || -d /usr/share/zoneinfo ]] || return 1
    [[ -f /etc/ssl/certs/ca-certificates.crt || -d /etc/ssl/certs ]] || return 1
    command -v crontab >/dev/null 2>&1 || command -v cron >/dev/null 2>&1 || \
        systemctl list-unit-files 2>/dev/null | grep -qE '^(cron|cronie|crond)\.service' || return 1
    return 0
}

install_base_deps() {
    echo ""
    echo_cyan "[1/6] 检查并安装基础依赖"

    if deps_all_present; then
        echo_green "  ✔ 基础依赖已齐全，跳过安装（节省时间）"
        return 0
    fi

    local pkgs="curl tar tzdata socat ca-certificates openssl cron"

    case "${release}" in
        ubuntu | debian | armbian)
            export DEBIAN_FRONTEND=noninteractive
            spin_run "更新软件源索引..." "软件源索引已更新" "软件源更新失败（继续尝试）" \
                apt-get update -q
            spin_run "安装依赖 (curl tar openssl 等)..." "基础依赖安装完成" "部分依赖安装失败" \
                apt-get install -y -q $pkgs
            ;;
        centos | almalinux | rocky | rhel | fedora | amzn | ol)
            if command -v dnf >/dev/null 2>&1; then
                spin_run "更新 dnf 缓存..." "dnf 缓存已更新" "dnf 缓存更新失败" dnf makecache -y
                spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" dnf install -y -q cronie curl tar tzdata socat ca-certificates openssl
            else
                spin_run "更新 yum 缓存..." "yum 缓存已更新" "yum 缓存更新失败" yum makecache -y
                spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" yum install -y -q cronie curl tar tzdata socat ca-certificates openssl
            fi
            ;;
        arch | manjaro | parch)
            spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" pacman -Sy --noconfirm $pkgs
            ;;
        alpine)
            spin_run "更新 apk 索引..." "apk 索引已更新" "apk 更新失败" apk update
            spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" apk add curl tar tzdata socat ca-certificates openssl dcron
            ;;
        opensuse* | sles)
            spin_run "刷新 zypper 源..." "zypper 源已刷新" "zypper 刷新失败" zypper refresh
            spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" zypper -q install -y curl tar timezone socat ca-certificates openssl cron
            ;;
        *)
            if command -v apt-get >/dev/null 2>&1; then
                spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" apt-get install -y -q $pkgs
            elif command -v yum >/dev/null 2>&1; then
                spin_run "安装依赖..." "基础依赖安装完成" "部分依赖安装失败" yum install -y -q $pkgs
            else
                echo_yellow "  未识别的包管理器，跳过依赖安装。"
            fi
            ;;
    esac
}

# ---------- 防火墙放行（可放行多个端口） ----------
open_firewall_ports() {
    local ports=("$@")
    [[ ${#ports[@]} -eq 0 ]] && return 0
    local port_list=""
    local p
    for p in "${ports[@]}"; do
        [[ -z "$p" ]] && continue
        port_list="${port_list} ${p}/tcp"
    done
    [[ -z "$port_list" ]] && return 0

    local done=0

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        for p in "${ports[@]}"; do
            [[ -n "$p" ]] && ufw allow "${p}/tcp" >/dev/null 2>&1
        done
        done=1
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        for p in "${ports[@]}"; do
            [[ -n "$p" ]] && firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
        done
        firewall-cmd --reload >/dev/null 2>&1
        done=1
    fi

    if [[ $done -eq 0 ]]; then
        echo_yellow "  ! 未检测到已启用的 ufw / firewalld。"
        echo_yellow "    如服务商有安全组，请手动放行:${port_list}"
    else
        echo_green "  ✔ 防火墙已放行:${port_list}"
    fi
}

# ---------- 防火墙关闭某端口 ----------
close_firewall_port() {
    local port="$1"
    [[ -z "$port" ]] && return 0
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
}

# ---------- 下载并解压安装包 ----------
download_and_install() {
    local arch="$1"
    local tag="$2"
    local tmp_dir="/tmp/x-ui-install.$$"
    local tarball="x-ui-linux-${arch}.tar.gz"
    local url="${release_base}/${tag}/${tarball}"
    local sha_url="${url}.sha256"

    mkdir -p "${tmp_dir}"
    cd "${tmp_dir}" || exit 1

    echo ""
    echo_cyan "[3/6] 下载安装包"
    download_file "${url}" "${tarball}" "正在下载 3x-ui 安装包（约 80MB，请耐心等待）"
    if [[ ! -s "${tarball}" ]]; then
        echo_red "下载失败或文件为空，请检查网络后重试。"
        cd / && rm -rf "${tmp_dir}"; exit 1
    fi
    echo_green "  ✔ 下载完成 ($(du -h "${tarball}" | cut -f1))"

    echo ""
    echo_cyan "[4/6] 校验安装包完整性"
    if curl -fsLR --retry 2 --connect-timeout 15 -o "${tarball}.sha256" "${sha_url}" 2>/dev/null; then
        local expected actual
        expected=$(awk 'NR==1{print $1}' "${tarball}.sha256")
        actual=$(sha256sum "${tarball}" | awk '{print $1}')
        if [[ "${expected}" == "${actual}" && -n "${actual}" ]]; then
            echo_green "  ✔ SHA256 完整性校验通过"
        else
            echo_red "  ✘ 校验失败，安装包可能被篡改，已中止。"
            cd / && rm -rf "${tmp_dir}"; exit 1
        fi
    else
        echo_yellow "  ! 未获取到校验文件，跳过校验"
    fi

    spin_run "解压安装包..." "解压完成" "解压失败" tar -xzf "${tarball}"
    if [[ ! -d x-ui ]]; then
        echo_red "安装包结构异常。"
        cd / && rm -rf "${tmp_dir}"; exit 1
    fi

    if systemctl is-active --quiet "${xui_service_name}" 2>/dev/null; then
        spin_run "停止旧面板服务..." "旧面板已停止" "旧面板停止失败" systemctl stop "${xui_service_name}"
    fi

    cd x-ui || { echo_red "安装包结构异常。"; cd / && rm -rf "${tmp_dir}"; exit 1; }
    chmod +x x-ui bin/xray-linux-* 2>/dev/null || true

    echo ""
    echo_cyan "[5/6] 安装程序文件"
    mkdir -p "${xui_folder}"
    cp -f x-ui "${xui_folder}/x-ui"
    cp -rf bin "${xui_folder}/"
    [[ -f x-ui.sh ]] && cp -f x-ui.sh "${xui_folder}/x-ui.sh"
    chmod +x "${xui_folder}/x-ui" "${xui_folder}/x-ui.sh" 2>/dev/null || true
    echo_green "  ✔ 程序文件已安装到 ${xui_folder}"

    # service 文件
    local svc_src=""
    case "${release}" in
        ubuntu | debian | armbian) svc_src="x-ui.service.debian" ;;
        arch | manjaro | parch)    svc_src="x-ui.service.arch" ;;
        *)                         svc_src="x-ui.service.rhel" ;;
    esac
    if [[ -f "${svc_src}" ]]; then
        cp -f "${svc_src}" "${xui_service_folder}/${xui_service_name}.service"
    else
        curl -fsLR -o "${xui_service_folder}/${xui_service_name}.service" \
            "${raw_base}/x-ui.service.debian" >/dev/null 2>&1 || true
    fi
    echo_green "  ✔ 服务文件已配置"

    # 注册 x-ui 命令到 /usr/bin
    echo ""
    echo_cyan "[6/6] 注册 x-ui 管理命令"
    if [[ -f "${xui_folder}/x-ui.sh" ]]; then
        cp -f "${xui_folder}/x-ui.sh" /usr/bin/x-ui
        chmod +x /usr/bin/x-ui
        mkdir -p /var/log/x-ui
        spin_run "汉化管理菜单..." "管理菜单已汉化" "菜单汉化跳过" localize_menu /usr/bin/x-ui
        echo_green "  ✔ 已注册命令: x-ui"
    else
        echo_yellow "  ! 未找到 x-ui.sh，命令注册跳过"
    fi

    cd / && rm -rf "${tmp_dir}"
}

# ---------- 汉化管理菜单 ----------
localize_menu() {
    local target="$1"
    [[ ! -f "${target}" ]] && return 0
    if command -v python3 >/dev/null 2>&1; then
        python3 - "${target}" <<'PYEOF' >/dev/null 2>&1 || true
import sys
path = sys.argv[1]
REPL = [
    ("3X-UI Panel Management Script", "3X-UI 面板管理脚本 (FreeKm 中文版)"),
    ("Update to Dev Channel (latest commit)", "更新到开发版 (最新提交)"),
    ("Reset Username & Password", "重置用户名和密码"),
    ("Reset Web Base Path", "重置访问路径"),
    ("IP Limit Management", "IP 限制管理"),
    ("Cloudflare SSL Certificate", "Cloudflare SSL 证书"),
    ("SSL Certificate Management", "SSL 证书管理"),
    ("SSH Port Forwarding Management", "SSH 端口转发管理"),
    ("View Current Settings", "查看当前配置"),
    ("Check Status", "查看状态"),
    ("Logs Management", "日志管理"),
    ("Enable Autostart", "开启开机自启"),
    ("Disable Autostart", "关闭开机自启"),
    ("PostgreSQL Management", "PostgreSQL 管理"),
    ("Firewall Management", "防火墙管理"),
    ("Update Geo Files", "更新 Geo 数据文件"),
    ("Speedtest by Ookla", "Ookla 测速"),
    ("Legacy Version", "历史版本"),
    ("Update Menu", "更新菜单"),
    ("Restart Xray", "重启 Xray"),
    ("Enable BBR", "开启 BBR 加速"),
    ("Exit Script", "退出脚本"),
    ("Uninstall", "卸载"),
    ("Install", "安装"),
    ("Update", "更新"),
    ("Restart", "重启"),
    ("Change Port", "修改端口"),
    ("Reset Settings", "重置配置"),
    ("Start", "启动"),
    ("Stop", "停止"),
    ("Back to Main Menu", "返回主菜单"),
    ("Updating Menu", "正在更新菜单"),
    ("Please choose an option", "请选择操作"),
    ("Panel state:", "面板状态:"),
    ("Xray state:", "Xray 状态:"),
    ("xray state:", "Xray 状态:"),
    ("启动 automatically:", "开机自启:"),
    ("automatically:", "开机自启:"),
    ("开机自启: Yes", "开机自启: 是"),
    ("开机自启: No", "开机自启: 否"),
    ("MTProto state:", "MTProto 状态:"),
    ("Running", "运行中"),
    ("Not Running", "未运行"),
    ("Not Installed", "未安装"),
    ("Please enter your selection", "请输入选项"),
    ("The OS release is:", "当前系统:"),
    ("Failed to start", "启动失败"),
    ("Failed to", "操作失败："),
    ("Successfully", "操作成功"),
    ("Are you sure", "你确定要"),
    ("y/n", "y/n"),
    ("Please enter", "请输入"),
    ("Invalid", "无效输入"),
    ("Cancelled", "已取消"),
    ("Done", "完成"),
    ("Exiting", "正在退出"),
    ("Press Enter to continue", "按回车键继续"),
    ("Enable", "开启"),
    ("Disable", "关闭"),
    ("Local time", "本机时间"),
    ("System time", "系统时间"),
    ("Version", "版本"),
]
with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    c = f.read()
for en, zh in REPL:
    c = c.replace(en, zh)
with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(c)
PYEOF
        return 0
    fi
    return 0
}

# ---------- 获取最新版本 ----------
resolve_latest_tag() {
    local url tag
    url=$(curl -sSLI -o /dev/null -w '%{url_effective}' --retry 3 --connect-timeout 15 \
        "https://github.com/${mirror_repo}/releases/latest" 2>/dev/null)
    tag=${url##*/tag/}
    if [[ "$tag" != "$url" && -n "$tag" && "$tag" != "latest" ]]; then
        echo "$tag"; return 0
    fi
    echo "v3.9.0"
}

# ---------- 交互：数据库选择 ----------
ask_database() {
    echo ""
    echo_cyan "======================================================"
    echo_cyan "  请选择数据库类型"
    echo_cyan "======================================================"
    echo -e "${green}  1  SQLite${plain}      —— 单文件数据库，本机自带，零配置"
    echo -e "${green}  2  PostgreSQL${plain}  —— 独立数据库服务，适合大量客户端"
    echo ""
    echo_yellow "  简单说："
    echo -e "${blue}    · 就你自己一个人用 / 客户端没几个  → 选 ${green}1${plain}"
    echo -e "${blue}    · 要给很多人用 / 节点多 / 追求稳定   → 选 ${green}2${plain}"
    echo ""
    local choice
    read -rp "  请输入选项（直接回车默认选 1）: " choice
    choice="${choice// /}"
    case "$choice" in
        2) CHOICE_DB="postgres" ;;
        *) CHOICE_DB="sqlite" ;;
    esac
    if [[ "${CHOICE_DB}" == "sqlite" ]]; then
        echo_green "  已选择：SQLite（适合个人使用）"
    else
        echo_green "  已选择：PostgreSQL（适合多人使用）"
    fi
}

# ---------- 交互：SSL 选择 ----------
ask_ssl() {
    echo ""
    echo_cyan "======================================================"
    echo_cyan "  请选择 SSL 证书方式（给面板加锁，防止被窃听）"
    echo_cyan "======================================================"
    echo -e "${green}  1  域名证书${plain}   —— 需要你有域名，证书 90 天有效，自动续期"
    echo -e "${green}  2  IP 证书${plain}     —— 用服务器 IP 申请，证书约 6 天有效，自动续期"
    echo -e "${green}  3  自有证书${plain}     —— 你已有证书文件，填路径即可"
    echo -e "${green}  4  不加证书（跳过）${plain} —— 面板走 HTTP，仅适合靠 SSH 隧道访问"
    echo ""
    echo_yellow "  打个比方："
    echo -e "${blue}    · 有域名、想让别人也能 https 访问      → 选 ${green}1${plain}"
    echo -e "${blue}    · 没域名，想用 https 直接访问 IP       → 选 ${green}2${plain}（推荐）"
    echo -e "${blue}    · 已有证书文件                        → 选 ${green}3${plain}"
    echo -e "${blue}    · 只想自己用、习惯走 SSH 隧道最安全    → 选 ${green}4${plain}"
    echo ""
    echo_yellow "  说明：选 1 或 2 会自动为你放行 80 端口用于证书签发。"
    local choice
    read -rp "  请输入选项（直接回车默认选 4 跳过）: " choice
    choice="${choice// /}"
    case "$choice" in
        1)
            CHOICE_SSL="1"
            local d
            while :; do
                read -rp "  请输入你的域名（例如 panel.example.com）: " d
                d="${d// /}"
                if [[ "$d" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    SSL_DOMAIN="$d"; break
                fi
                echo_yellow "  域名格式不正确，请重新输入。"
            done
            echo_green "  已选择：域名证书（${SSL_DOMAIN}）"
            # 自动放行 80 端口用于证书签发
            echo_blue "  域名证书需要 80 端口做验证，正在自动放行 80 端口..."
            open_firewall_ports 80
            ;;
        2)
            CHOICE_SSL="2"
            echo_green "  已选择：IP 证书"
            # 自动放行 80 端口用于证书签发
            echo_blue "  IP 证书需要 80 端口做验证，正在自动放行 80 端口..."
            open_firewall_ports 80
            ;;
        3)
            CHOICE_SSL="3"
            while :; do
                read -rp "  请输入证书文件路径（.crt / .pem）: " SSL_CERT_PATH
                [[ -f "$SSL_CERT_PATH" ]] && break
                echo_yellow "  文件不存在，请重新输入。"
            done
            while :; do
                read -rp "  请输入私钥文件路径（.key）: " SSL_KEY_PATH
                [[ -f "$SSL_KEY_PATH" ]] && break
                echo_yellow "  文件不存在，请重新输入。"
            done
            echo_green "  已选择：自有证书"
            ;;
        *)
            CHOICE_SSL="4"
            echo_green "  已选择：不加证书（HTTP，仅走 SSH 隧道）"
            ;;
    esac
}

# ---------- 交互：安装前确认 ----------
ask_confirm() {
    echo ""
    echo_cyan "======================================================"
    echo_cyan "  安装前确认"
    echo_cyan "======================================================"
    echo -e "${blue}  数据库  : ${plain}${CHOICE_DB}"
    case "${CHOICE_SSL}" in
        1) echo -e "${blue}  SSL     : ${plain}域名证书 (${SSL_DOMAIN})" ;;
        2) echo -e "${blue}  SSL     : ${plain}IP 证书" ;;
        3) echo -e "${blue}  SSL     : ${plain}自有证书" ;;
        *) echo -e "${blue}  SSL     : ${plain}不加证书（仅 SSH 隧道访问）" ;;
    esac
    echo ""
    echo_yellow "  以上配置将开始安装 3x-ui 面板，是否继续？"
    local choice
    read -rp "  输入 y 确认安装，输入 n 取消（直接回车默认确认）: " choice
    choice="${choice// /}"
    case "$choice" in
        n|N|no|NO)
            echo_yellow "  已取消安装。"
            exit 0
            ;;
        *)
            echo_green "  已确认，开始安装..."
            return 0
            ;;
    esac
}

# ---------- 交互：安全加固 ----------
ask_security_hardening() {
    echo ""
    echo_cyan "======================================================"
    echo_cyan "  安全加固（可选）"
    echo_cyan "======================================================"
    echo_yellow "  风险提示：如果 VPS 直接暴露在公网，SSH 和面板都可能被"
    echo_yellow "  暴力破解。以下加固能显著降低风险："
    echo -e "${blue}    · 安装 fail2ban：自动封禁多次登录失败的 IP${plain}"
    echo ""
    local choice
    read -rp "  是否安装 fail2ban 防暴力破解？[y/N]: " choice
    case "$choice" in
        y|Y|yes|YES)
            case "${release}" in
                ubuntu|debian|armbian)
                    spin_run "正在安装 fail2ban..." "fail2ban 已安装" "fail2ban 安装失败" apt-get install -y -q fail2ban
                    ;;
                centos|almalinux|rocky|rhel|fedora|amzn|ol)
                    if command -v dnf >/dev/null 2>&1; then
                        spin_run "正在安装 fail2ban..." "fail2ban 已安装" "fail2ban 安装失败" dnf install -y -q fail2ban
                    else
                        spin_run "正在安装 fail2ban..." "fail2ban 已安装" "fail2ban 安装失败" yum install -y -q fail2ban
                    fi
                    ;;
                *) echo_yellow "  未知系统，跳过 fail2ban 安装" ;;
            esac
            systemctl enable fail2ban >/dev/null 2>&1
            systemctl restart fail2ban >/dev/null 2>&1
            echo_green "  ✔ fail2ban 已启用"
            ;;
        *)
            echo_yellow "  - 已跳过 fail2ban。"
            ;;
    esac
}

# ---------- 应用面板配置 ----------
apply_panel_settings() {
    local port="$1" user="$2" pass="$3" webpath="$4"
    mkdir -p /etc/x-ui
    "${xui_folder}/x-ui" setting -port "${port}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -username "${user}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -password "${pass}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -webBasePath "${webpath}" >/dev/null 2>&1 || true
}

# ---------- 简化版 SSL 应用（用 acme.sh）----------
apply_ssl() {
    local port="$1" domain="$2" ip="$3"
    case "${CHOICE_SSL}" in
        1|2)
            spin_run "安装 acme.sh 证书工具..." "acme.sh 已就绪" "acme.sh 安装失败" \
                bash -c 'curl -s https://get.acme.sh | sh'
            local ACME="/root/.acme.sh/acme.sh"
            [[ ! -f "$ACME" ]] && ACME="$HOME/.acme.sh/acme.sh"
            if [[ ! -f "$ACME" ]]; then
                echo_yellow "  ! 未找到 acme.sh，退回 HTTP 模式。"
                CHOICE_SSL="4"; return 1
            fi
            local target="${domain:-$ip}"
            if [[ "${CHOICE_SSL}" == "2" ]]; then
                echo_blue "  正在申请 IP 证书（需要 80 端口可达，可能耗时较长）..."
                if ! "$ACME" --issue -d "${ip}" --standalone --server letsencrypt --days 6 >/dev/null 2>&1; then
                    echo_yellow "  ! IP 证书签发失败（可能 80 端口不通），退回 HTTP 模式。"
                    CHOICE_SSL="4"; return 1
                fi
            else
                echo_blue "  正在申请域名证书（需要 80 端口可达）..."
                if ! "$ACME" --issue -d "${target}" --standalone >/dev/null 2>&1; then
                    echo_yellow "  ! 域名证书签发失败（可能 80 端口不通），退回 HTTP 模式。"
                    CHOICE_SSL="4"; return 1
                fi
            fi
            local cert_dir="/etc/x-ui/cert"
            mkdir -p "${cert_dir}"
            "$ACME" --install-cert -d "${target}" \
                --key-file "${cert_dir}/privkey.pem" \
                --fullchain-file "${cert_dir}/fullchain.pem" \
                --reloadcmd "systemctl restart x-ui" >/dev/null 2>&1 || true
            if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
                "${xui_folder}/x-ui" cert -webCert "${cert_dir}/fullchain.pem" -webCertKey "${cert_dir}/privkey.pem" >/dev/null 2>&1 || true
                echo_green "  ✔ 证书已申请并配置"
                return 0
            else
                echo_yellow "  ! 证书文件未生成，退回 HTTP 模式。"
                CHOICE_SSL="4"; return 1
            fi
            ;;
        3)
            echo_blue "  正在配置自有证书..."
            "${xui_folder}/x-ui" cert -webCert "${SSL_CERT_PATH}" -webCertKey "${SSL_KEY_PATH}" >/dev/null 2>&1 || true
            echo_green "  ✔ 自有证书已配置"
            ;;
        *)
            echo_yellow "  已跳过 SSL，面板使用 HTTP。"
            ;;
    esac
    return 0
}

# ---------- 写安装结果 ----------
write_install_result() {
    local user="$1" pass="$2" port="$3" webpath="$4" scheme="$5" ip="$6"
    local result_file="/etc/x-ui/install-result.env"
    mkdir -p /etc/x-ui
    {
        printf 'XUI_USERNAME=%s\n' "$user"
        printf 'XUI_PASSWORD=%s\n' "$pass"
        printf 'XUI_PANEL_PORT=%s\n' "$port"
        printf 'XUI_WEB_BASE_PATH=%s\n' "$webpath"
        printf 'XUI_SSL_MODE=%s\n' "${CHOICE_SSL}"
        printf 'XUI_ACCESS_URL=%s\n' "${scheme}://${ip}:${port}/${webpath}"
    } > "${result_file}"
    chmod 600 "${result_file}"
}

# ---------- 主流程 ----------
main() {
    print_logo
    check_root
    check_os

    local machine_arch
    machine_arch=$(arch)
    if [[ "${machine_arch}" == "unknown" ]]; then
        echo_red "不支持的 CPU 架构：$(uname -m)"
        exit 1
    fi
    echo_green "CPU 架构：${machine_arch}"

    local server_ip
    server_ip=$(curl -s --connect-timeout 8 https://api4.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 8 https://ipv4.icanhazip.com 2>/dev/null)
    server_ip=$(echo "${server_ip}" | tr -d '[:space:]')
    [[ -z "${server_ip}" ]] && server_ip="<你的服务器IP>"
    echo_green "公网 IP：${server_ip}"

    install_base_deps

    # 交互选择
    echo ""
    echo_cyan "[2/6] 配置选项"
    ask_database
    ask_ssl
    ask_confirm

    # 版本
    local tag="${XUI_VERSION:-}"
    [[ -z "${tag}" ]] && tag=$(resolve_latest_tag)
    echo_green "将安装版本：${tag}"

    download_and_install "${machine_arch}" "${tag}"

    # 生成随机凭据
    echo ""
    echo_blue "正在生成安全随机凭据..."
    local config_username config_password config_port config_webpath
    config_username="${XUI_USERNAME:-$(gen_random_string ${RAND_USER_LEN})}"
    config_password="${XUI_PASSWORD:-$(gen_random_string ${RAND_PASS_LEN})}"
    config_webpath="${XUI_WEB_BASE_PATH:-$(gen_random_string 18)}"

    if [[ -n "${XUI_PANEL_PORT:-}" ]]; then
        config_port="${XUI_PANEL_PORT}"
    else
        local tries=0
        while :; do
            config_port=$(( (RANDOM % 20000) + 20000 ))
            ! is_port_in_use "${config_port}" && break
            tries=$((tries+1)); [[ $tries -gt 50 ]] && { config_port=54321; break; }
        done
    fi

    apply_panel_settings "${config_port}" "${config_username}" "${config_password}" "${config_webpath}"

    # 启动服务
    spin_run "启动 x-ui 面板服务..." "面板服务已启动" "面板服务启动异常" \
        bash -c "systemctl daemon-reload && systemctl enable x-ui >/dev/null 2>&1 && systemctl restart x-ui"
    sleep 1
    systemctl daemon-reload >/dev/null 2>&1

    # SSL
    local scheme="http"
    apply_ssl "${config_port}" "${SSL_DOMAIN}" "${server_ip}" && true
    [[ "${CHOICE_SSL}" != "4" ]] && scheme="https"

    # 防火墙：443 始终放行；面板端口按 SSL 选择决定
    local fw_ports=("443")
    if [[ "${CHOICE_SSL}" == "4" ]]; then
        close_firewall_port "${config_port}"
    else
        fw_ports+=("${config_port}")
    fi
    open_firewall_ports "${fw_ports[@]}"

    write_install_result "${config_username}" "${config_password}" "${config_port}" "${config_webpath}" "${scheme}" "${server_ip}"

    ask_security_hardening

    # ---- 结果展示 ----
    echo ""
    echo_cyan "======================================================"
    if systemctl is-active --quiet "${xui_service_name}" 2>/dev/null; then
        echo_green "             3x-ui 面板安装成功！"
    else
        echo_yellow "        服务已安装，但状态异常，请运行：systemctl status x-ui"
    fi
    echo_cyan "======================================================"
    echo ""
    echo_cyan "  ---- 账号信息（请立即保存）----"
    echo -e "${green}  访问协议${plain} : ${scheme}"
    echo -e "${green}  面板地址${plain} : ${cyan}${scheme}://${server_ip}:${config_port}/${config_webpath}${plain}"
    echo -e "${green}  端口    ${plain} : ${config_port}"
    echo -e "${green}  访问路径${plain} : /${config_webpath}"
    echo -e "${green}  用户名  ${plain} : ${config_username}"
    echo -e "${green}  密码    ${plain} : ${config_password}"
    echo -e "${green}  数据库  ${plain} : ${CHOICE_DB}"
    echo ""
    echo_yellow "  ★ 请立即保存以上信息，凭据不会再次显示！"
    echo_yellow "  ★ 凭据保存在：/etc/x-ui/install-result.env"

    # 隧道提示：仅当跳过 SSL 时
    if [[ "${CHOICE_SSL}" == "4" ]]; then
        echo ""
        echo_cyan "  ---- 访问方式：SSH 隧道（已跳过 SSL）----"
        echo_yellow "  由于未配置 SSL，面板未对公网开放端口，请用 SSH 隧道访问："
        echo -e "${blue}    ssh -L ${config_port}:127.0.0.1:${config_port} root@${server_ip} -p <你的SSH端口>${plain}"
        echo -e "${blue}  然后浏览器打开：${plain}http://127.0.0.1:${config_port}/${config_webpath}"
    else
        echo ""
        echo_cyan "  ---- 访问方式：直接用浏览器打开上面的面板地址即可 ----"
    fi

    echo ""
    echo_cyan "  ---- 管理命令 ----"
    echo -e "${blue}  运行管理菜单 : ${plain}x-ui"
    echo -e "${blue}  查看服务状态 : ${plain}systemctl status x-ui"
    echo -e "${blue}  重启面板     : ${plain}systemctl restart x-ui"
    echo -e "${blue}  查看实时日志 : ${plain}journalctl -u x-ui -f"
    echo ""
    echo_cyan "  镜像仓库: https://github.com/${mirror_repo}"
    echo_cyan "======================================================"
}

main "$@"
