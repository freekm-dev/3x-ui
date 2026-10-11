<div align="center">

# FreeKm 3x-ui 中文版

自托管镜像版 3x-ui，**不依赖官方 mhsanaei 仓库**，全程中文一键安装。

[![Version](https://img.shields.io/badge/3x--ui-v3.9.0-2f81f7?style=for-the-badge)](https://github.com/freekm-dev/3x-ui/releases/tag/v3.9.0)
[![Mirror](https://img.shields.io/badge/mirror-self_hosted-238636?style=for-the-badge)](https://github.com/freekm-dev/3x-ui)
[![Site](https://img.shields.io/badge/site-freekm.com-8957e5?style=for-the-badge)](https://freekm.com)

</div>

## 一键安装（中文）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/freekm-dev/3x-ui/master/install-cn.sh)
```

安装脚本会全程中文提示，自动完成：检测系统 → 下载安装包 → 校验完整性 → 安装服务 → **随机生成安全凭据** → **自动放行防火墙端口** → 展示访问信息与安全加固建议。

## 项目说明

| 项目 | 说明 |
| --- | --- |
| 面板版本 | 3x-ui **v3.9.0**（最新稳定版） |
| 安装脚本 | `install-cn.sh`（中文，自研精简版） |
| 官方脚本 | `install.sh`（原版，仅将地址指向本仓库） |
| 管理菜单 | `x-ui.sh`（安装后可用 `x-ui` 命令调出） |
| 安装资源 | 自托管于本仓库 Release |
| 官方依赖 | **已完全移除** |

## 为什么用这个仓库

官方项目一直在更新。本仓库把安装所需的全部资源（二进制包、服务文件、Geo 数据）保存到**自己的 Release**，安装脚本的所有下载地址都指向本仓库，因此：

- **即使官方仓库消失，安装依然可用**
- 安装过程**不再访问任何 mhsanaei 地址**
- 中文提示，对新手更友好

## 自托管了哪些资源

| 类型 | 文件 |
| --- | --- |
| Linux 安装包 | `x-ui-linux-amd64.tar.gz` 等各架构 |
| 校验文件 | `.tar.gz.sha256` |
| 安装脚本 | `install.sh` / `install-cn.sh` |
| 管理菜单 | `x-ui.sh` |
| systemd 服务 | `x-ui.service.debian` / `.arch` / `.rhel` |
| Alpine 脚本 | `x-ui.rc` |

> 注：Geo 数据文件（geoip.dat / geosite.dat 等）已打包在安装包内，安装时无需额外下载。

## 安全特性

- **随机凭据**：安装时自动生成随机的用户名、密码、面板端口、访问路径，避免默认弱口令
- **完整性校验**：下载后自动校验 SHA256，防止篡改
- **防火墙放行**：自动检测 ufw / firewalld 并放行面板端口
- **隐藏入口**：面板使用随机访问路径，直接访问根路径返回 404

安装完成后脚本会给出进一步加固建议（SSH 密钥登录、fail2ban 等）。

## 管理命令

```bash
x-ui                      # 打开管理菜单
systemctl status x-ui     # 查看服务状态
systemctl restart x-ui    # 重启面板
journalctl -u x-ui -f     # 查看实时日志
```

安装凭据保存在：`/etc/x-ui/install-result.env`

## 项目主页

https://freekm.com
