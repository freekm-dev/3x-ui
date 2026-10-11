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
NEED_PORT_80=""   # 选 1/2 时置 1，安装完成后统一放行 80

# 运行环境信息（全局）
MACHINE_ARCH=""
SERVER_IP=""
SSH_PORT=""     # 运行期动态检测；空 = 未检测到 SSH 服务
SSH_PORTS=""    # 同上，可能为多端口

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
# 注意：443 为保留端口，任何情况下都不允许关闭（用户后续自配服务需要它）
close_firewall_port() {
    local port="$1"
    [[ -z "$port" ]] && return 0
    # 硬保护：443 永不关闭
    if [[ "${port}" == "443" ]]; then
        echo_yellow "  ! 443 为保留端口，已跳过关闭操作。"
        return 0
    fi
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

# ---------- 汉化管理菜单（整体重写 show_menu，修复边框 + 精简菜单项）----------
localize_menu() {
    local target="$1"
    [[ ! -f "${target}" ]] && return 0
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    python3 - "${target}" <<'PYEOF' >/dev/null 2>&1 || true
import sys, re

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    c = f.read()

NEW_MENU = r"""show_menu() {
    echo -e "
╔══════════════════════════════════════════════╗
│  ${green}3X-UI 面板管理脚本 (FreeKm 中文版)${plain}          │
│  ${green}0.${plain} 退出脚本                                 │
│──────────────────────────────────────────────│
│  ${green}1.${plain} 重置用户名和密码                         │
│  ${green}2.${plain} 重置访问路径                             │
│  ${green}3.${plain} 重置配置                                 │
│  ${green}4.${plain} 修改端口                                 │
│  ${green}5.${plain} 查看当前配置                             │
│──────────────────────────────────────────────│
│  ${green}6.${plain} 启动                                     │
│  ${green}7.${plain} 停止                                     │
│  ${green}8.${plain} 重启                                     │
│  ${green}9.${plain} 重启 Xray                                │
│  ${green}10.${plain} 查看状态                                │
│  ${green}11.${plain} 日志管理                                │
│──────────────────────────────────────────────│
│  ${green}12.${plain} 开启开机自启                            │
│  ${green}13.${plain} 关闭开机自启                            │
│──────────────────────────────────────────────│
│  ${green}14.${plain} SSL 证书管理                            │
│  ${green}15.${plain} Cloudflare SSL 证书                     │
│  ${green}16.${plain} IP 限制管理                             │
│  ${green}17.${plain} 防火墙管理                              │
│  ${green}18.${plain} SSH 端口转发管理                        │
│  ${green}19.${plain} PostgreSQL 管理                         │
│──────────────────────────────────────────────│
│  ${green}20.${plain} 开启 BBR 加速                           │
│  ${green}21.${plain} 更新 Geo 数据文件                       │
│  ${green}22.${plain} Ookla 测速                              │
╚══════════════════════════════════════════════╝
"
    show_status
    echo && read -rp "请输入选项 [0-22]: " num

    case "${num}" in
        0)
            exit 0
            ;;
        1)
            check_install && reset_user
            ;;
        2)
            check_install && reset_webbasepath
            ;;
        3)
            check_install && reset_config
            ;;
        4)
            check_install && set_port
            ;;
        5)
            check_install && check_config
            ;;
        6)
            check_install && start
            ;;
        7)
            check_install && stop
            ;;
        8)
            check_install && restart
            ;;
        9)
            check_install && restart_xray
            ;;
        10)
            check_install && status
            ;;
        11)
            check_install && show_log
            ;;
        12)
            check_install && enable
            ;;
        13)
            check_install && disable
            ;;
        14)
            ssl_cert_issue_main
            ;;
        15)
            ssl_cert_issue_CF
            ;;
        16)
            iplimit_main
            ;;
        17)
            firewall_menu
            ;;
        18)
            SSH_port_forwarding
            ;;
        19)
            postgresql_menu
            ;;
        20)
            bbr_menu
            ;;
        21)
            update_geo
            ;;
        22)
            run_speedtest
            ;;
        *)
            LOGE "请输入正确的选项 [0-22]"
            ;;
    esac
}"""


def replace_func(content, name, new_text):
    """定位函数定义并整体替换到匹配的右花括号。
    必须匹配行首的 name() {，避免误中 before_show_menu() 之类。"""
    m = re.search(r"(?m)^" + re.escape(name) + r"\(\) \{", content)
    if not m:
        return content
    start = m.start()
    depth = 1
    i = content.find("{", start) + 1
    while i < len(content):
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    if i >= len(content):
        return content
    return content[:start] + new_text + content[i + 1:]


# 1) 整体重写主菜单（修复边框 + 去掉更新/卸载等无意义项）
c = replace_func(c, "show_menu", NEW_MENU)

# 2) 状态行 & 常用 UI 文案定点替换（长串优先）
REPL = [
    ('echo -e "Panel state: ${green}Running${plain}"', 'echo -e "面板状态: ${green}运行中${plain}"'),
    ('echo -e "Panel state: ${yellow}Not Running${plain}"', 'echo -e "面板状态: ${yellow}未运行${plain}"'),
    ('echo -e "Panel state: ${red}Not Installed${plain}"', 'echo -e "面板状态: ${red}未安装${plain}"'),
    ('echo -e "Xray 状态: ${green}Running${plain}"', 'echo -e "Xray 状态: ${green}运行中${plain}"'),
    ('echo -e "Xray 状态: ${red}Not Running${plain}"', 'echo -e "Xray 状态: ${red}未运行${plain}"'),
    ('echo -e "Xray state:', 'echo -e "Xray 状态:'),
    ('echo -e "xray state:', 'echo -e "Xray 状态:'),
    ('echo -e "MTProto state:', 'echo -e "MTProto 状态:'),
    ('Start automatically: ${green}Managed by Docker${plain}', '开机自启: ${green}由 Docker 托管${plain}'),
    ('Start automatically: ${green}Yes${plain}', '开机自启: ${green}是${plain}'),
    ('Start automatically: ${red}No${plain}', '开机自启: ${red}否${plain}'),
    ('echo -e "启动 automatically:', 'echo -e "开机自启:'),
    ('echo -e "Enabled: ${green}Yes${plain}"', 'echo -e "开机自启: ${green}是${plain}"'),
    ('echo -e "Enabled: ${red}No${plain}"', 'echo -e "开机自启: ${red}否${plain}"'),
    ("Panel state:", "面板状态:"),
    ("Xray state:", "Xray 状态:"),
    ("xray state:", "Xray 状态:"),
    ("MTProto state:", "MTProto 状态:"),
    ("Start automatically:", "开机自启:"),
    ("automatically: Yes", "开机自启: 是"),
    ("automatically: No", "开机自启: 否"),
    ("${green}Running${plain}", "${green}运行中${plain}"),
    ("${red}Not Running${plain}", "${red}未运行${plain}"),
    ("${yellow}Not Running${plain}", "${yellow}未运行${plain}"),
    ("${red}Not Installed${plain}", "${red}未安装${plain}"),
    ("Please enter your selection", "请输入选项"),
    ("Please enter the correct number", "请输入正确的选项"),
    ("The OS release is:", "当前系统:"),
    ("Press Enter to continue", "按回车键继续"),
]
for en, zh in REPL:
    c = c.replace(en, zh)

with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(c)
PYEOF
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
    echo_yellow "  说明：选 1 或 2 会在安装完成时自动为你放行 80 端口用于证书签发。"
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
            # 80 端口放行延后到安装完成时统一处理（见 main 中防火墙节点）
            NEED_PORT_80="1"
            echo_blue "  域名证书需要 80 端口做验证，将在安装完成时自动放行 80 端口。"
            ;;
        2)
            CHOICE_SSL="2"
            echo_green "  已选择：IP 证书"
            # 80 端口放行延后到安装完成时统一处理
            NEED_PORT_80="1"
            echo_blue "  IP 证书需要 80 端口做验证，将在安装完成时自动放行 80 端口。"
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

# ---------- SSL 应用（用 acme.sh，参照官方实现）----------
# 返回 0 表示已成功配置证书，返回 1 表示退回 HTTP
apply_ssl() {
    local port="$1" domain="$2" ip="$3"

    # ★ 先清除上一次安装残留的证书配置，保证本次选择生效
    # （否则若上次配了 HTTPS、这次选"不加证书"，面板仍会沿用旧证书）
    if [[ "${CHOICE_SSL}" == "4" ]]; then
        # 选"不加证书"：清空面板证书路径 + 删除旧证书文件，回到纯 HTTP
        "${xui_folder}/x-ui" cert -webCert "" -webCertKey "" >/dev/null 2>&1 || true
        rm -rf /etc/x-ui/cert >/dev/null 2>&1 || true
        echo_yellow "  已跳过 SSL，面板使用 HTTP（已清除历史证书配置）。"
        return 1
    fi
    # 选 1/2/3：清掉旧证书文件，避免残留干扰
    rm -rf /etc/x-ui/cert >/dev/null 2>&1 || true

    # 先确保 acme.sh 就绪
    if [[ "${CHOICE_SSL}" == "1" || "${CHOICE_SSL}" == "2" ]]; then
        if [[ ! -f "${HOME}/.acme.sh/acme.sh" ]]; then
            echo_blue "  正在安装 acme.sh 证书工具..."
            if ! curl -s https://get.acme.sh | sh >/dev/null 2>&1; then
                echo_yellow "  ! acme.sh 安装失败，退回 HTTP 模式。"
                CHOICE_SSL="4"; return 1
            fi
        fi
        local ACME="${HOME}/.acme.sh/acme.sh"
        if [[ ! -f "$ACME" ]]; then
            echo_yellow "  ! 未找到 acme.sh，退回 HTTP 模式。"
            CHOICE_SSL="4"; return 1
        fi

        local cert_dir="/etc/x-ui/cert"
        mkdir -p "${cert_dir}"
        local reload_cmd="systemctl restart x-ui"

        case "${CHOICE_SSL}" in
            1)
                # ---- 域名证书 ----
                local target="${domain}"
                echo_blue "  正在申请域名证书：${target}（需要 80 端口可达）..."
                "$ACME" --set-default-ca --server letsencrypt --force >/dev/null 2>&1 || true
                local err_log="/tmp/acme-domain.log"
                if ! "$ACME" --issue -d "${target}" --standalone --httpport 80 --force >"${err_log}" 2>&1; then
                    echo_red "  ✘ 域名证书签发失败。"
                    echo_yellow "    可能原因：80 端口不通 / 域名未解析到本机 / 防火墙拦截"
                    echo_yellow "    详细日志：${err_log}"
                    tail -n 3 "${err_log}" 2>/dev/null | sed 's/^/      /'
                    CHOICE_SSL="4"; return 1
                fi
                "$ACME" --installcert --force -d "${target}" \
                    --key-file "${cert_dir}/privkey.pem" \
                    --fullchain-file "${cert_dir}/fullchain.pem" \
                    --reloadcmd "${reload_cmd}" >/dev/null 2>&1 || true
                ;;
            2)
                # ---- IP 证书（shortlived profile，约 6 天有效，自动续期）----
                echo_blue "  正在申请 IP 证书：${ip}（需要 80 端口可达，约 6 天有效）..."
                "$ACME" --set-default-ca --server letsencrypt --force >/dev/null 2>&1 || true
                local err_log="/tmp/acme-ip.log"
                if ! "$ACME" --issue -d "${ip}" --standalone \
                        --server letsencrypt \
                        --certificate-profile shortlived \
                        --days 6 --httpport 80 --force >"${err_log}" 2>&1; then
                    echo_red "  ✘ IP 证书签发失败。"
                    echo_yellow "    可能原因：80 端口不通 / 安全组未放行 / Let's Encrypt 短证书限流"
                    echo_yellow "    详细日志：${err_log}"
                    tail -n 3 "${err_log}" 2>/dev/null | sed 's/^/      /'
                    rm -rf ~/.acme.sh/${ip} ~/.acme.sh/${ip}_ecc 2>/dev/null
                    CHOICE_SSL="4"; return 1
                fi
                # 安装证书文件（reloadcmd 失败也会返回非零，故用 || true，再校验文件）
                "$ACME" --installcert --force -d "${ip}" \
                    --key-file "${cert_dir}/privkey.pem" \
                    --fullchain-file "${cert_dir}/fullchain.pem" \
                    --reloadcmd "${reload_cmd}" >/dev/null 2>&1 || true
                ;;
        esac

        # 校验证书文件（不依赖退出码）
        if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
            chmod 600 "${cert_dir}/privkey.pem" 2>/dev/null
            chmod 644 "${cert_dir}/fullchain.pem" 2>/dev/null
            "$ACME" --upgrade --auto-upgrade >/dev/null 2>&1 || true
            "${xui_folder}/x-ui" cert -webCert "${cert_dir}/fullchain.pem" -webCertKey "${cert_dir}/privkey.pem" >/dev/null 2>&1 || true
            echo_green "  ✔ 证书已申请并配置（有效期约 6~90 天，acme.sh 会自动续期）"
            return 0
        else
            echo_yellow "  ! 证书文件未生成，退回 HTTP 模式。"
            CHOICE_SSL="4"; return 1
        fi
    fi

    # 自有证书
    if [[ "${CHOICE_SSL}" == "3" ]]; then
        echo_blue "  正在配置自有证书..."
        if "${xui_folder}/x-ui" cert -webCert "${SSL_CERT_PATH}" -webCertKey "${SSL_KEY_PATH}" >/dev/null 2>&1; then
            echo_green "  ✔ 自有证书已配置"
            return 0
        else
            echo_red "  ✘ 自有证书配置失败，退回 HTTP 模式。"
            CHOICE_SSL="4"; return 1
        fi
    fi

    echo_yellow "  已跳过 SSL，面板使用 HTTP。"
    return 1
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

# ---------- 检测 sshd 服务状态 ----------
# 输出：running / installed / absent
ssh_service_status() {
    # 1) 有 sshd 进程在运行（最可靠：真能连上的就是它）
    if ss -ltnp 2>/dev/null | grep -qi sshd; then
        echo "running"; return 0
    fi
    if command -v netstat >/dev/null 2>&1 && netstat -ltnp 2>/dev/null | grep -qi sshd; then
        echo "running"; return 0
    fi
    # 2) systemd 判定
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
            echo "running"; return 0
        fi
        if systemctl list-unit-files 2>/dev/null | grep -qE '^\s*(ssh|sshd)\.service'; then
            echo "installed"; return 0
        fi
    fi
    # 3) 二进制存在视为已安装（但未运行）
    if command -v sshd >/dev/null 2>&1 || [[ -x /usr/sbin/sshd ]]; then
        echo "installed"; return 0
    fi
    echo "absent"
}

# ---------- 检测 SSH 端口（动态：优先实际监听，其次配置）----------
detect_ssh_port() {
    local port=""
    # 1) 最可靠：从实际监听的 sshd 进程反查（这才是真正能连上的端口）
    if command -v ss >/dev/null 2>&1; then
        port=$(ss -ltnp 2>/dev/null | grep -i sshd | grep -oE ':[0-9]+' | head -1 | tr -d ':')
    fi
    if [[ -z "$port" ]] && command -v netstat >/dev/null 2>&1; then
        port=$(netstat -ltnp 2>/dev/null | grep -i sshd | grep -oE ':[0-9]+' | head -1 | tr -d ':')
    fi
    # 2) 其次：sshd_config 里的 Port 配置
    if [[ -z "$port" ]] && [[ -f /etc/ssh/sshd_config ]]; then
        port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null)
    fi
    # 3) 再次：sshd_config.d/*.conf 里的 Port 配置
    if [[ -z "$port" ]] && [[ -d /etc/ssh/sshd_config.d ]]; then
        port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config.d/*.conf 2>/dev/null)
    fi
    # 4) 未检测到 SSH 服务时返回空（不再假装 22，避免误导）
    echo "$port"
}

# 检测所有正在监听的 SSH 端口（可能多个，如 22 与 2222）
detect_all_ssh_ports() {
    local ports=""
    if command -v ss >/dev/null 2>&1; then
        ports=$(ss -ltnp 2>/dev/null | grep -i sshd | grep -oE ':[0-9]+' | tr -d ':' | sort -un)
    fi
    if [[ -z "$ports" ]] && command -v netstat >/dev/null 2>&1; then
        ports=$(netstat -ltnp 2>/dev/null | grep -i sshd | grep -oE ':[0-9]+' | tr -d ':' | sort -un)
    fi
    if [[ -z "$ports" ]]; then
        # 未在监听时，回落到配置里的端口；仍为空则说明无 SSH
        ports=$(detect_ssh_port)
    fi
    echo "$ports" | tr '\n' ' ' | sed 's/ *$//'
}

# 检查某端口是否被防火墙放行
ssh_port_is_allowed() {
    local port="$1"
    # ufw
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        ufw status 2>/dev/null | grep -qE "(^|[^0-9])${port}(/tcp)?([^0-9]|$)" && return 0
        return 1
    fi
    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --list-ports 2>/dev/null | grep -qE "(^| )${port}/tcp($| )" && return 0
        firewall-cmd --list-services 2>/dev/null | grep -qE 'ssh' && return 0
        return 1
    fi
    # iptables：无显式 DROP/REJECT 视为放行
    if command -v iptables >/dev/null 2>&1; then
        iptables -L INPUT -n 2>/dev/null | grep -qE "dpt:${port}.*(ACCEPT)" && return 0
    fi
    # 未检测到有效防火墙 → 视为放行
    return 0
}

# 检查是否有任何防火墙处于激活状态
firewall_active() {
    command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active && return 0
    command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1 && return 0
    return 1
}

# ---------- 首屏：显示系统配置并请求确认 ----------
show_system_info_and_confirm() {
    echo ""
    echo_cyan "======================================================"
    echo_cyan "  安装前系统检测"
    echo_cyan "======================================================"
    echo -e "${green}  操作系统  ${plain}: ${PRETTY_NAME:-$release}"
    echo -e "${green}  内核版本  ${plain}: $(uname -r)"
    echo -e "${green}  CPU 架构  ${plain}: ${MACHINE_ARCH} ($(uname -m))"
    echo -e "${green}  公网 IP   ${plain}: ${SERVER_IP}"

    local ssh_stat
    ssh_stat=$(ssh_service_status)
    if [[ "${ssh_stat}" == "running" ]]; then
        echo -e "${green}  SSH 端口  ${plain}: ${SSH_PORT}"
    else
        echo -e "${green}  SSH 服务  ${plain}: 未检测到（你将通过 VNC / 物理终端等方式操作）"
    fi
    echo -e "${green}  镜像仓库  ${plain}: https://github.com/${mirror_repo}"
    echo ""

    # SSH 端口放行检查：仅在确认存在 SSH 服务时执行
    if [[ "${ssh_stat}" != "running" ]]; then
        echo_yellow "  ! 未检测到正在运行的 SSH 服务，跳过 SSH 端口放行检查。"
        echo_yellow "    （若你实际通过 SSH 连接，说明检测有误，请忽略此项）"
    elif firewall_active; then
        local blocked=""
        local sp
        for sp in ${SSH_PORTS}; do
            if ! ssh_port_is_allowed "${sp}"; then
                blocked="${blocked} ${sp}"
            fi
        done
        blocked="${blocked# }"
        if [[ -z "${blocked}" ]]; then
            echo_green "  ✔ 检测到防火墙已放行 SSH 端口: ${SSH_PORTS}"
        else
            echo ""
            echo_red   "  ⚠ 警告：检测到 SSH 端口 ${blocked} 未在防火墙中放行！"
            echo_red   "     如果你在安装过程中断开连接，可能会被挡在外面无法重连！"
            echo_yellow "     请先放行 SSH 端口再继续，例如："
            local bp
            for bp in ${blocked}; do
                echo_yellow "       ufw allow ${bp}/tcp        （Ubuntu/Debian）"
                echo_yellow "       firewall-cmd --permanent --add-port=${bp}/tcp && firewall-cmd --reload"
            done
            echo ""
            local aw
            read -rp "  仍要继续安装吗？(y 继续 / 其它键退出先去放行): " aw
            case "$aw" in
                y|Y|yes|YES) echo_yellow "  已选择继续（请自行注意安全）。" ;;
                *) echo_yellow "  已退出。请放行 SSH 端口后重新运行。"; exit 0 ;;
            esac
        fi
    else
        echo_yellow "  ! 未检测到已启用的 ufw / firewalld 防火墙（如为云服务商安全组，请自行确认 ${SSH_PORTS} 已放行）"
    fi

    echo ""
    echo_cyan "------------------------------------------------------"
    echo_yellow "  即将开始安装 3x-ui 面板，是否继续？"
    echo_cyan "------------------------------------------------------"
    local ans
    read -rp "  输入 y 开始安装，其它任意键退出: " ans
    case "$ans" in
        y|Y|yes|YES)
            echo_green "  已确认，开始安装..."
            ;;
        *)
            echo_yellow "  已取消，未做任何改动。"
            exit 0
            ;;
    esac
}

# ---------- 主流程 ----------
main() {
    print_logo
    check_root
    check_os

    MACHINE_ARCH=$(arch)
    if [[ "${MACHINE_ARCH}" == "unknown" ]]; then
        echo_red "不支持的 CPU 架构：$(uname -m)"
        exit 1
    fi

    SERVER_IP=$(curl -s --connect-timeout 8 https://api4.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 8 https://ipv4.icanhazip.com 2>/dev/null)
    SERVER_IP=$(echo "${SERVER_IP}" | tr -d '[:space:]')
    [[ -z "${SERVER_IP}" ]] && SERVER_IP="<你的服务器IP>"

    SSH_PORT=$(detect_ssh_port)
    SSH_PORTS=$(detect_all_ssh_ports)
    # 未检测到 SSH 服务时 SSH_PORT 为空，SSH_PORTS 亦为空 -> 不要伪造 22
    if [[ -z "${SSH_PORT}" ]] && [[ -n "${SSH_PORTS}" ]]; then
        SSH_PORT="${SSH_PORTS%% *}"
    fi

    # ★ 首屏：展示系统配置 + 安装确认（未确认不进入下一步）
    show_system_info_and_confirm

    install_base_deps

    # 交互选择
    echo ""
    echo_cyan "[2/6] 配置选项"
    ask_database
    ask_ssl

    # 版本
    local tag="${XUI_VERSION:-}"
    [[ -z "${tag}" ]] && tag=$(resolve_latest_tag)
    echo_green "将安装版本：${tag}"

    download_and_install "${MACHINE_ARCH}" "${tag}"

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
    apply_ssl "${config_port}" "${SSL_DOMAIN}" "${SERVER_IP}" && true
    [[ "${CHOICE_SSL}" != "4" ]] && scheme="https"

    # ============================================================
    # 防火墙策略（仅在用户已确认安装、且面板安装完成后执行）
    #   · 443          → 永远放行（保留给用户后续自配服务使用，面板本身不用 443）
    #   · 选 1/2/3     → 额外放行面板端口（对公网开放）
    #   · 选 4（隧道） → 不放行面板端口，但 443 仍保持放行
    #   · 选 1/2       → 额外放行 80 端口（证书签发验证用）
    # 注：用户若在“输入 y 开始安装”处选择退出，则不会执行到此处，
    #     防火墙不会有任何改动。
    # ============================================================
    echo ""
    echo_cyan "[防火墙] 根据你的选择配置端口放行..."

    if [[ "${CHOICE_SSL}" == "4" ]]; then
        # 隧道模式：确保面板端口不对公网开放
        close_firewall_port "${config_port}"
        open_firewall_ports 443
    else
        open_firewall_ports 443 "${config_port}"
    fi

    # 选 1/2 需要 80 端口做证书签发验证
    if [[ -n "${NEED_PORT_80}" ]]; then
        open_firewall_ports 80
    fi

    # 兜底复查：确保 443 确实处于放行状态
    if firewall_active; then
        if ssh_port_is_allowed 443; then
            echo_green "  ✔ 已确认 443 端口放行（保留给后续自配服务）"
        else
            echo_yellow "  ! 443 端口首次放行未生效，正在重试..."
            open_firewall_ports 443 >/dev/null 2>&1 || true
            if ssh_port_is_allowed 443; then
                echo_green "  ✔ 已确认 443 端口放行（保留给后续自配服务）"
            else
                echo_red "  ⚠ 443 端口放行失败，请手动执行： ufw allow 443/tcp"
            fi
        fi
    fi

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
    echo -e "${green}  面板地址${plain} : ${cyan}${scheme}://${SERVER_IP}:${config_port}/${config_webpath}${plain}"
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
        if [[ -n "${SSH_PORT}" ]]; then
            echo -e "${blue}    ssh -L ${config_port}:127.0.0.1:${config_port} root@${SERVER_IP} -p ${SSH_PORT}${plain}"
        else
            echo -e "${blue}    ssh -L ${config_port}:127.0.0.1:${config_port} root@${SERVER_IP}${plain}"
            echo_yellow "    （未检测到 SSH 服务端口，未加 -p 参数；如你的 SSH 不是 22，请自行补 -p <端口>）"
        fi
        echo -e "${blue}  然后浏览器打开：${plain}http://127.0.0.1:${config_port}/${config_webpath}"
        if [[ -n "${SSH_PORT}" ]] && firewall_active && ! ssh_port_is_allowed "${SSH_PORT}"; then
            echo ""
            echo_red "  ⚠ 警告：检测到 SSH 端口 ${SSH_PORT} 未放行，请先放行再断开连接，"
            echo_red "     否则会把自己拦在外面！"
            echo_yellow "     放行命令： ufw allow ${SSH_PORT}/tcp"
        fi
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
