# PS5 公网异地串流 · IPv6 + socat 方案

> 家里宽带是 **IPv4 CGNAT**（运营商级 NAT，外面永远连不进你家的 IPv4），但 **IPv6 是真公网**。
> 本方案用一台 Linux 主机跑 `socat`，把它的公网 IPv6 端口转发到 PS5 的 IPv4 端口，
> 让外面的设备通过 IPv6 直连家里的 PS5，**绕过 CGNAT**，实现低延迟异地串流。

---

## 一、为什么需要这个方案

| 问题 | 说明 |
|---|---|
| 运营商 CGNAT | 家里宽带拨号拿到的是 `100.64.0.0/10` 共享地址，公网无法主动连入 |
| PS5 只监听 IPv4 | Remote Play 端口（9295-9302）只绑在 IPv4 上，IPv6 上不开 |
| 结果 | 官方 App 走中转又卡又断；Chiaki / Console Remote 直连连不上 |

**方案本质**：`公网 IPv6 打洞进门 → socat 把 IPv6 翻译成 PS5 认的 IPv4`。

## 二、架构

```
  外面手机(4G/5G 有 IPv6)
      │ IPv6 直连（无 NAT，全球可达）
      ▼
  Linux 主机 :9295-9302（socat 监听 IPv6）
      │ socat 转发（IPv6 → IPv4）
      ▼
  PS5 (IPv4:9295-9302)   ← PS5 真正监听的地址
```

## 三、前置条件

1. **家里宽带已开通 IPv6**（光猫/路由器开启 IPv6，设备能拿到 `2409:` 等公网前缀）
2. **一台能常开的 Linux 主机**（树莓派 / NAS / 软路由 / 旧电脑），与 PS5 同一局域网
3. **外面设备支持 IPv6**（手机 4G/5G 一般都有）

## 四、快速开始（一键安装）

在 Linux 主机上执行：

```bash
sudo bash install.sh
```

脚本会**自动完成**：
1. 询问你的 **PS5 的 IPv4 地址**（默认 `192.168.1.19`）
2. **自动探测**本机的公网 IPv6 地址（优先稳定地址）
3. 安装 `socat`
4. 写入转发脚本 + systemd 服务（开机自启）
5. 禁用 IPv6 临时地址（关键，避免串流断开）
6. **自动测试链路**（PS5 端口 / 服务状态 / 监听端口 / IPv6 转发）

安装完成后屏幕会显示一串 IPv6 地址，这就是你的**串流连接地址**。

## 五、使用方式

### Console Remote / Chiaki

- **主机地址**填脚本输出的 IPv6 地址（或你的 DDNS 域名）
- PS5 上需先开启「设置 → 系统 → 远程游玩 → 启用远程游玩」，并完成「关联设备」PIN 注册

### 端口说明

| 端口 | 协议 | 用途 |
|---|---|---|
| 9302 | TCP+UDP | Remote Play 注册/发现 |
| 9295 | TCP+UDP | 控制 + 数据 |
| 9296 | TCP+UDP | 音视频流 |
| 9297 | TCP+UDP | 音频流 |

## 六、配合 DDNS（地址变了也不怕）

IPv6 前缀会因光猫重拨变化。用 [ddns-go](https://github.com/jeessy2/ddns-go) 把域名自动指向主机 IPv6：

1. 安装 ddns-go：`sudo ddns-go -s install`
2. 浏览器打开 `http://<主机IP>:9876` 配置你的 DNS 服务商（阿里云/腾讯云/Cloudflare 等）
3. 记录类型选 **AAAA**，IPv6 获取方式选 **网卡**，域名填 `ps5.你的域名.com`
4. 之后 Console Remote 里填域名即可，前缀变了自动跟上

## 七、排障手册（本方案实测踩过的坑）

| 现象 | 原因 | 解决 |
|---|---|---|
| 连上 1 秒就断 | Linux IPv6 **临时地址**导致回包源地址漂移 | 禁用临时地址（脚本已自动做） |
| 串流无画面但能连 | UDP 音视频流没通 | 确认 UDP 9296/9297 转发存在，用 `ss -ulnp` 检查 |
| 外面完全连不上 | 光猫 IPv6 防火墙拦截 | 关闭/放行光猫 IPv6 防火墙的 9295-9302 |
| 抓包看到外部流量但 PS5 不回 | PS5 未开远程游玩/未在关联设备界面 | PS5 开远程游玩 + 关联设备出 PIN |
| 提示输入 PIN 后失败 | 地址填错 / PSN account-id 不对 | 填 socat 主机的 IPv6（不是 PS5 的），核对 account-id |

### 手动排障命令

```bash
# 看 socat 进程（应 8 条：4 TCP + 4 UDP）
pgrep -a socat

# 看监听端口（应 8 个：4 TCP + 4 UDP）
ss -tulnp | grep -E '9295|9296|9297|9302'

# 抓包看链路（外部连一次，观察双向流量）
sudo tcpdump -i any -n -l 'port 9295 or port 9296 or port 9297 or port 9302'

# 查本机 IPv6
ip -6 addr show scope global | grep inet6
```

## 八、卸载

```bash
sudo bash uninstall.sh
```

## 九、目录结构

```
.
├── README.md        # 本教程
├── install.sh       # 一键安装脚本
└── uninstall.sh     # 卸载脚本
```

---

## 致谢与免责声明

- 本方案依赖运营商提供 IPv6，部分地区/运营商可能未开通，请先确认。
- 请遵守 PS5 远程游玩的用户协议，仅在自有设备间使用。
- 公网暴露存在一定安全风险，建议配合防火墙限制访问来源。
