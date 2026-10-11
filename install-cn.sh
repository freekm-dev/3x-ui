#!/bin/bash
#
# ============================================================
#   3x-ui 中文一键安装脚本 (install-cn.sh)
#   镜像仓库: https://github.com/freekm-dev/3x-ui
#   项目主页: https://freekm.com
#
#   基于官方 3x-ui v3.9.0，全程中文交互，资源自托管，
#   不依赖官方 mhsanaei 仓库。
# ============================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
plain='\033[0m'

# ---------- 镜像与版本配置（集中管理） ----------
mirror_repo="freekm-dev/3x-ui"
raw_base="https://raw.githubusercontent.com/${mirror_repo}/master"
release_base="https://github.com/${mirror_repo}/releases/download"

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service_folder="/etc/systemd/system"
xui_service_name="x-ui"

# 随机凭据长度
RAND_USER_LEN=10
RAND_PASS_LEN=12

# ---------- 输出辅助 ----------
echo_red()    { echo -e "${red}$*${plain}"; }
echo_green()  { echo -e "${green}$*${plain}"; }
echo_yellow() { echo -e "${yellow}$*${plain}"; }
echo_blue()   { echo -e "${blue}$*${plain}"; }
echo_cyan()   { echo -e "${cyan}$*${plain}"; }

print_logo() {
    echo -e "${cyan}"
    cat <<'LOGO'
    ______               __ __
   / ____/______  ___  / //_/___ ___  ____ _
  / /_  / ___/ _ \/ _ \/ ,< / __ `__ \/ __ `/
 / __/ / /  /  __/  __/ /| |/ / / / / / /_/ /
/_/   /_/   \___/\___/_/ |_/_/ /_/ /_/\__, /
                                      /____/
LOGO
    echo -e "${plain}"
    echo -e "${green}        FreeKm  3x-ui 中文一键安装脚本${plain}"
    echo -e "${blue}        项目主页: https://freekm.com${plain}"
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
    release_version="${VERSION_ID:-}"
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

# ---------- 依赖安装 ----------
install_base_deps() {
    echo_blue "正在安装基础依赖..."
    local pkgs="curl tar tzdata socat ca-certificates openssl cron"
    case "${release}" in
        ubuntu | debian | armbian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -q >/dev/null 2>&1
            apt-get install -y -q $pkgs >/dev/null 2>&1
            ;;
        centos | almalinux | rocky | rhel | fedora | amzn | ol)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y -q $pkgs >/dev/null 2>&1 || dnf makecache -y >/dev/null 2>&1 && dnf install -y -q $pkgs >/dev/null 2>&1
            else
                yum install -y -q $pkgs >/dev/null 2>&1 || yum makecache -y >/dev/null 2>&1 && yum install -y -q $pkgs >/dev/null 2>&1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm $pkgs >/dev/null 2>&1
            ;;
        alpine)
            apk update >/dev/null 2>&1
            apk add curl tar tzdata socat ca-certificates openssl dcron >/dev/null 2>&1
            ;;
        opensuse* | sles)
            zypper refresh >/dev/null 2>&1
            zypper -q install -y curl tar timezone socat ca-certificates openssl cron >/dev/null 2>&1
            ;;
        *)
            echo_yellow "未知系统（${release}），将尝试使用 apt/yum。"
            command -v apt-get >/dev/null 2>&1 && apt-get install -y -q $pkgs >/dev/null 2>&1
            command -v yum >/dev/null 2>&1 && yum install -y -q $pkgs >/dev/null 2>&1
            ;;
    esac
    echo_green "基础依赖安装完成。"
}

# ---------- 防火墙放行 ----------
open_firewall_port() {
    local port="$1"
    [[ -z "$port" ]] && return 0
    echo_blue "正在尝试放行面板端口 TCP ${port} ..."
    local done=0

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 && done=1
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1 && done=1
    fi

    if [[ $done -eq 0 ]]; then
        echo_yellow "未检测到已启用的 ufw / firewalld。"
        echo_yellow "如果你的服务商有外部安全组，请手动放行 TCP ${port}。"
    else
        echo_green "防火墙已放行 TCP ${port}。"
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

    echo_blue "正在从镜像仓库下载安装包..."
    echo_cyan "  ${url}"
    if ! curl -fLR --retry 3 --retry-delay 2 --connect-timeout 20 -o "${tarball}" "${url}"; then
        echo_red "下载失败，请检查网络或稍后重试。"
        cd / && rm -rf "${tmp_dir}"
        exit 1
    fi
    if [[ ! -s "${tarball}" ]]; then
        echo_red "下载的安装包为空。"
        cd / && rm -rf "${tmp_dir}"
        exit 1
    fi

    # 校验 sha256（存在则校验）
    if curl -fsLR --retry 2 --connect-timeout 15 -o "${tarball}.sha256" "${sha_url}" 2>/dev/null; then
        local expected actual
        expected=$(awk 'NR==1{print $1}' "${tarball}.sha256")
        actual=$(sha256sum "${tarball}" | awk '{print $1}')
        if [[ "${expected}" == "${actual}" && -n "${actual}" ]]; then
            echo_green "安装包完整性校验通过。"
        else
            echo_red "安装包校验失败，可能被篡改，已中止。"
            cd / && rm -rf "${tmp_dir}"
            exit 1
        fi
    else
        echo_yellow "未获取到校验文件，跳过完整性校验。"
    fi

    echo_blue "正在解压..."
    tar -xzf "${tarball}" || { echo_red "解压失败。"; cd / && rm -rf "${tmp_dir}"; exit 1; }

    # 停旧服务
    if systemctl is-active --quiet "${xui_service_name}" 2>/dev/null; then
        echo_blue "检测到旧面板，正在停止..."
        systemctl stop "${xui_service_name}" >/dev/null 2>&1
    fi

    # 解压后为 x-ui/ 目录
    cd x-ui || { echo_red "安装包结构异常。"; cd / && rm -rf "${tmp_dir}"; exit 1; }
    chmod +x x-ui bin/xray-linux-* 2>/dev/null || true

    mkdir -p "${xui_folder}"
    cp -f x-ui "${xui_folder}/x-ui"
    cp -rf bin "${xui_folder}/"
    [[ -f x-ui.sh ]] && cp -f x-ui.sh "${xui_folder}/x-ui.sh"
    chmod +x "${xui_folder}/x-ui" "${xui_folder}/x-ui.sh" 2>/dev/null || true

    # 服务文件（包内自带三种）
    local svc_src=""
    case "${release}" in
        ubuntu | debian | armbian) svc_src="x-ui.service.debian" ;;
        arch | manjaro | parch)    svc_src="x-ui.service.arch" ;;
        *)                         svc_src="x-ui.service.rhel" ;;
    esac
    if [[ -f "${svc_src}" ]]; then
        cp -f "${svc_src}" "${xui_service_folder}/${xui_service_name}.service"
    else
        # 回退：从镜像仓库拉
        curl -fsLR -o "${xui_service_folder}/${xui_service_name}.service" \
            "${raw_base}/x-ui.service.debian" >/dev/null 2>&1 || true
    fi

    cd / && rm -rf "${tmp_dir}"
    echo_green "文件安装完成。"
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

# ---------- 初始化面板配置 ----------
init_panel_settings() {
    local port="$1" user="$2" pass="$3" webpath="$4"
    mkdir -p /etc/x-ui

    # 停止可能运行的进程后再设置
    "${xui_folder}/x-ui" setting -port "${port}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -username "${user}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -password "${pass}" >/dev/null 2>&1 || true
    "${xui_folder}/x-ui" setting -webBasePath "${webpath}" >/dev/null 2>&1 || true
}

# ---------- 生成安装结果 ----------
write_install_result() {
    local user="$1" pass="$2" port="$3" webpath="$4" ip="$5"
    local result_file="/etc/x-ui/install-result.env"
    mkdir -p /etc/x-ui
    {
        printf 'XUI_USERNAME=%s\n' "$user"
        printf 'XUI_PASSWORD=%s\n' "$pass"
        printf 'XUI_PANEL_PORT=%s\n' "$port"
        printf 'XUI_WEB_BASE_PATH=%s\n' "$webpath"
        printf 'XUI_ACCESS_URL=%s\n' "http://${ip}:${port}/${webpath}"
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

    # 检测公网 IP
    local server_ip
    server_ip=$(curl -s --connect-timeout 8 https://api4.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 8 https://ipv4.icanhazip.com 2>/dev/null)
    server_ip=$(echo "${server_ip}" | tr -d '[:space:]')
    [[ -z "${server_ip}" ]] && server_ip="<你的服务器IP>"
    echo_green "公网 IP：${server_ip}"

    install_base_deps

    # 解析版本
    local tag="${XUI_VERSION:-}"
    if [[ -z "${tag}" ]]; then
        echo_blue "正在获取最新版本..."
        tag=$(resolve_latest_tag)
    fi
    echo_green "将安装版本：${tag}"

    download_and_install "${machine_arch}" "${tag}"

    # ---- 面板参数：随机凭据 ----
    echo_blue "正在生成安全的随机凭据..."
    local config_username config_password config_port config_webpath
    config_username="${XUI_USERNAME:-$(gen_random_string ${RAND_USER_LEN})}"
    config_password="${XUI_PASSWORD:-$(gen_random_string ${RAND_PASS_LEN})}"
    config_webpath="${XUI_WEB_BASE_PATH:-$(gen_random_string 18)}"

    if [[ -n "${XUI_PANEL_PORT:-}" ]]; then
        config_port="${XUI_PANEL_PORT}"
    else
        # 随机挑一个未占用端口
        local tries=0
        while :; do
            config_port=$(( (RANDOM % 20000) + 20000 ))
            if ! is_port_in_use "${config_port}"; then break; fi
            tries=$((tries+1))
            [[ $tries -gt 50 ]] && { config_port=54321; break; }
        done
    fi

    # 写配置
    init_panel_settings "${config_port}" "${config_username}" "${config_password}" "${config_webpath}"

    # 服务：开机自启 + 崩溃重启
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable "${xui_service_name}" >/dev/null 2>&1
    systemctl restart "${xui_service_name}" >/dev/null 2>&1
    sleep 1

    # 防火墙放行
    open_firewall_port "${config_port}"

    write_install_result "${config_username}" "${config_password}" "${config_port}" "${config_webpath}" "${server_ip}"

    # ---- 中文结果展示 ----
    echo ""
    echo_cyan "======================================================"
    if systemctl is-active --quiet "${xui_service_name}" 2>/dev/null; then
        echo_green "        3x-ui 面板安装成功！"
    else
        echo_yellow "        服务已安装，但状态异常，请运行：systemctl status x-ui"
    fi
    echo_cyan "======================================================"
    echo ""
    echo -e "${green}  面板地址${plain} : ${cyan}http://${server_ip}:${config_port}/${config_webpath}${plain}"
    echo -e "${green}  端口    ${plain} : ${config_port}"
    echo -e "${green}  访问路径${plain} : /${config_webpath}"
    echo -e "${green}  用户名  ${plain} : ${config_username}"
    echo -e "${green}  密码    ${plain} : ${config_password}"
    echo ""
    echo_yellow "  ★ 请立即保存以上信息，凭据不会再次显示！"
    echo_yellow "  ★ 凭据也保存在：/etc/x-ui/install-result.env"
    echo ""
    echo_cyan "  ---- 管理命令 ----"
    echo -e "${blue}  运行管理菜单 : ${plain}x-ui"
    echo -e "${blue}  查看服务状态 : ${plain}systemctl status x-ui"
    echo -e "${blue}  重启面板     : ${plain}systemctl restart x-ui"
    echo -e "${blue}  查看实时日志 : ${plain}journalctl -u x-ui -f"
    echo ""
    echo_cyan "  ---- 安全加固建议 ----"
    echo -e "${blue}  1) 修改 SSH 密码并禁用密码登录，改用密钥：${plain}"
    echo -e "${blue}     passwd ; 编辑 /etc/ssh/sshd_config 设置 PasswordAuthentication no${plain}"
    echo -e "${blue}  2) 安装 fail2ban 防暴力破解：${plain}"
    echo -e "${blue}     apt install -y fail2ban   （或 yum install -y fail2ban）${plain}"
    echo -e "${blue}  3) 定期更新面板：${plain}x-ui 菜单选择更新，或运行 update.sh"
    echo ""
    echo_cyan "  镜像仓库: https://github.com/${mirror_repo}"
    echo_cyan "  项目主页: https://freekm.com"
    echo_cyan "======================================================"
}

main "$@"
