# homelab-reverse-ssh

[![CI](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml/badge.svg)](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

用一台公网 VPS，把 NAT 后面的 Home Lab 安全地接回任何只有 OpenSSH 的 laptop。

```text
Laptop -- SSH / ProxyJump --> VPS <-- persistent reverse SSH -- Home Lab
```

- 家里路由器不需要端口转发或公网 IP。
- Laptop 不需要 Tailscale、VPN 或额外客户端。
- Home Lab 开机自动连接，断网后自动重连。
- VPS 上的反向端口只监听 `localhost`，不暴露给公网。
- Tunnel 使用独立用户、独立密钥和受限的 SSH forwarding 权限。

> 请只在公司政策允许访问个人基础设施时使用。监听 443 是为了兼容只开放该端口的网络，不应被用于规避公司安全政策。

## 支持环境

- VPS：Ubuntu 20.04+ / Debian 11+，使用 OpenSSH + systemd
- Home Lab：Ubuntu 20.04+ / Debian 11+，使用 OpenSSH + systemd
- Laptop：macOS / Linux / Windows OpenSSH

## 最快开始

先确认 Home Lab 当前用户能登录 VPS，并且能在 VPS 上使用 `sudo`：

```bash
ssh your-vps-user@VPS_IP
```

然后在 Home Lab 上运行：

```bash
git clone https://github.com/zx3xyy/homelab-reverse-ssh.git
cd homelab-reverse-ssh

./setup.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user your-vps-user
```

默认使用 VPS 现有的 SSH 端口 `22`，并在 VPS 内部创建：

```text
127.0.0.1:22022 -> Home Lab localhost:22
```

如果 laptop 所在网络只允许出站 TCP 443，而且 VPS 的 443 没有被网站占用：

```bash
./setup.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user your-vps-user \
  --public-port 443
```

脚本结束时会生成 `client-ssh-config`。复制到 laptop：

```bash
./install-client.sh --config ./client-ssh-config
ssh homelab
```

Laptop 必须已经能用密钥登录 `your-vps-user@VPS`。如果它使用不同的密钥，先从 laptop 执行：

```bash
ssh-copy-id -p PUBLIC_PORT your-vps-user@VPS_IP
```

macOS 没有自带 `ssh-copy-id` 时，把 `~/.ssh/id_ed25519.pub` 追加到 VPS 用户的 `~/.ssh/authorized_keys` 即可。

## 常用参数

```text
--vps-host HOST          VPS IP 或域名（必填）
--vps-user USER          用于首次配置和 ProxyJump 的 VPS 用户（必填）
--admin-port PORT        VPS 当前管理 SSH 端口，默认 22
--public-port PORT       安装后 tunnel/laptop 连接的 SSH 端口，默认同 admin-port
--remote-port PORT       VPS localhost 上的反向端口，默认 22022
--homelab-user USER      laptop 最终登录 Home Lab 的用户，默认当前用户
--tunnel-user USER       VPS 上的受限 tunnel 用户，默认 homelab-tunnel
--identity PATH          Home Lab tunnel 专用私钥路径
--alias NAME             laptop 上使用的 Host 别名，默认 homelab
--vps-alias NAME         laptop 上使用的 VPS Host 别名，默认 homelab-vps
```

完整帮助：

```bash
./setup.sh --help
```

## 验证和排错

Home Lab：

```bash
./doctor.sh
sudo systemctl status homelab-reverse-ssh
sudo journalctl -u homelab-reverse-ssh -f
```

VPS：

```bash
sudo ss -ltnp | grep 22022
sudo sshd -t
```

Laptop：

```bash
ssh -v homelab
```

如果 VPS 使用云防火墙 / Security Group，还需要在那里放行 laptop 和 Home Lab 要连接的 SSH 端口（例如 `22/tcp` 或 `443/tcp`）。脚本会自动更新处于 active 状态的 UFW，但无法修改云厂商防火墙。

## 开机、重启和断电恢复

脚本会同时启用：

- Home Lab 的 `ssh.service`
- Home Lab 的 `homelab-reverse-ssh.service`
- systemd 的无限重启策略
- autossh 的 keepalive 和断线检测

软件层面的 reboot、网络闪断会自动恢复。物理断电后自动开机还需要在 Home Lab 的 BIOS/UEFI 中把以下选项设成 `Power On`：

```text
Restore on AC Power Loss
AC Power Recovery
After Power Failure
```

## 安全设计

- `22022` 仅绑定在 VPS 的 `localhost`。
- VPS tunnel 用户禁止 TTY、agent forwarding、X11 和本地转发。
- `PermitListen` 限制它只能创建指定的反向端口。
- Tunnel 密钥只用于转发，不复用个人 SSH key。
- Home Lab 会校验新 SSH 端口的 VPS host key 与首次管理连接一致，再写入固定的 `known_hosts`。
- 修改 VPS sshd 前运行 `sshd -t`；失败会回滚配置。

## 为什么默认不使用 Docker

这条链路直接复用宿主机的 OpenSSH 和 systemd，比容器方案少一层网络命名空间、`host network`、密钥 volume 和 Docker daemon 启动依赖。Docker 很适合部署应用，但对“宿主机 SSH 的保底入口”并不会更简单；因此本仓库不要求安装 Docker。

OpenSSH 的 `AllowTcpForwarding remote`、`PermitListen`、`MaxSessions 0` 和 authorized-key 限制均用于缩小 tunnel 用户权限。systemd 使用 `Restart=always` 和禁用启动限流来保证持续恢复。

参考：[OpenSSH sshd_config](https://man.openbsd.org/sshd_config)、[OpenSSH ssh](https://man.openbsd.org/ssh)、[systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)、[systemd.unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)。

参考：[OpenSSH `sshd_config(5)`](https://man.openbsd.org/sshd_config)、[systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)、[systemd.unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)。

## 更新配置

用相同参数重新运行 `setup.sh` 即可。脚本是幂等的，会保留相同 tunnel key 并更新配置。

## 卸载

Home Lab：

```bash
sudo ./uninstall-homelab.sh
```

VPS：

```bash
sudo ./scripts/uninstall-vps.sh
```

VPS 卸载脚本只删除本仓库创建的 sshd drop-in 和 tunnel 用户，不会修改其他 SSH 用户。

## License

[MIT](LICENSE). Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
