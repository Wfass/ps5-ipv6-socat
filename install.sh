#!/usr/bin/env bash
# =============================================================================
# PS5 公网异地串流 —— IPv6 + socat 一键安装脚本
#
# 原理：
#   家里宽带是 IPv4 CGNAT（外面连不进），但 IPv6 是真公网。
#   PS5 的 Remote Play 端口只监听 IPv4，本脚本用 socat 把本机的
#   IPv6 端口（9295-9302）转发到 PS5 的 IPv4 端口，实现：
#     外面设备(IPv6) -> 本机IPv6:9295 -> socat -> PS5(IPv4):9295
#
# 用法：
#   sudo bash install.sh
#
# 适用：Ubuntu/Debian/CentOS/Alpine 等常见 Linux（需 root 或 sudo）
# =============================================================================
set -e

# ---------- 颜色 ----------
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
step() { echo -e "${CYAN}==>${NC} $1"; }

# ---------- 1. 权限检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    warn "当前非 root，将使用 sudo"
  else
    err "需要 root 权限，请用 sudo bash install.sh 运行"
    exit 1
  fi
else
  SUDO=""
fi

# ---------- 2. 系统与包管理器检测 ----------
step "检测系统环境"
OS="unknown"; PM=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
fi
for p in apt-get yum dnf apk; do
  if command -v "$p" >/dev/null 2>&1; then PM="$p"; break; fi
done
if [ -z "$PM" ]; then
  err "未检测到支持的包管理器（apt-get/yum/dnf/apk）"
  exit 1
fi
info "系统: ${OS:-unknown}，包管理器: $PM，架构: $(uname -m)"

# ---------- 3. 询问 PS5 地址 ----------
step "配置 PS5 地址"
read -r -p "请输入 PS5 的 IPv4 地址（默认 192.168.1.19）: " PS5_IP
PS5_IP="${PS5_IP:-192.168.1.19}"
if ! echo "$PS5_IP" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  err "IPv4 地址格式错误: $PS5_IP"
  exit 1
fi
info "PS5 地址: $PS5_IP"

# ---------- 4. 自动探测本机 IPv6 地址 ----------
step "探测本机全局 IPv6 地址"
# 优先取稳定地址（非 temporary、非 fe80 链路本地）
IPV6_ADDR=""
# 1) 优先稳定地址（非 temporary / deprecated）
IPV6_ADDR=$(ip -6 addr show scope global 2>/dev/null \
  | awk '/inet6/ && !/temporary/ && !/deprecated/ {print $2; exit}' \
  | cut -d/ -f1 | grep -vE '^fe80')
# 2) 没有稳定地址则取任意全局地址
if [ -z "$IPV6_ADDR" ]; then
  IPV6_ADDR=$(ip -6 addr show scope global 2>/dev/null \
    | awk '/inet6/ {print $2; exit}' | cut -d/ -f1 | grep -vE '^fe80')
fi
if [ -z "$IPV6_ADDR" ]; then
  err "未检测到全局 IPv6 地址！请确认本机已接入支持 IPv6 的网络（家里路由器已开 IPv6）"
  exit 1
fi
info "本机 IPv6 地址: $IPV6_ADDR"

# ---------- 5. 安装 socat ----------
step "安装 socat"
if command -v socat >/dev/null 2>&1; then
  info "socat 已安装: $(socat -V 2>&1 | grep -oE 'version [0-9.]+' | head -1)"
else
  info "通过 $PM 安装 socat ..."
  case "$PM" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y socat ;;
    yum)     $SUDO yum install -y socat ;;
    dnf)     $SUDO dnf install -y socat ;;
    apk)     $SUDO apk add socat ;;
  esac
  info "socat 安装完成"
fi

# ---------- 6. 写转发脚本 ----------
step "写入转发脚本 /usr/local/bin/ps5-socat.sh"
$SUDO tee /usr/local/bin/ps5-socat.sh >/dev/null <<'SCRIPT'
#!/bin/bash
# PS5 Remote Play IPv6 -> IPv4 socat 转发器（自恢复版）
PS5_IP="__PS5_IP__"

run_tcp() {
  while true; do
    socat TCP6-LISTEN:$1,reuseaddr,fork TCP4:$PS5_IP:$1
    sleep 2
  done
}
run_udp() {
  while true; do
    socat -T 3600 UDP6-LISTEN:$1,reuseaddr UDP4:$PS5_IP:$1
    sleep 2
  done
}

run_tcp 9295 & run_tcp 9296 & run_tcp 9297 & run_tcp 9302 &
run_udp 9295 & run_udp 9296 & run_udp 9297 & run_udp 9302 &
wait
SCRIPT
$SUDO sed -i "s/__PS5_IP__/$PS5_IP/g" /usr/local/bin/ps5-socat.sh
$SUDO chmod +x /usr/local/bin/ps5-socat.sh

# ---------- 7. 写 systemd 服务 ----------
step "写入 systemd 服务 ps5-forward.service"
$SUDO tee /etc/systemd/system/ps5-forward.service >/dev/null <<'SVC'
[Unit]
Description=PS5 Remote Play IPv6-to-IPv4 socat forwarder
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ps5-socat.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
$SUDO systemctl daemon-reload
$SUDO systemctl enable ps5-forward >/dev/null 2>&1
$SUDO systemctl restart ps5-forward
sleep 2

# ---------- 8. 禁用 IPv6 临时地址（关键：避免回包源地址漂移导致串流断开）----------
step "禁用 IPv6 临时地址（固定回包源地址）"
if command -v sysctl >/dev/null 2>&1; then
  $SUDO sysctl -w net.ipv6.conf.all.use_tempaddr=0 >/dev/null 2>&1 || true
  $SUDO sysctl -w net.ipv6.conf.default.use_tempaddr=0 >/dev/null 2>&1 || true
  echo "net.ipv6.conf.all.use_tempaddr=0" | $SUDO tee /etc/sysctl.d/10-ipv6-tempaddr.conf >/dev/null
  $SUDO ip -6 addr flush scope global temporary 2>/dev/null || true
  info "临时地址已禁用（若本机 IPv6 地址变化，重新运行探测）"
fi

# ---------- 9. 测试链路 ----------
echo
step "测试链路"

echo -n "  [1/4] PS5 端口可达性 (TCP 9295): "
if command -v nc >/dev/null 2>&1 && nc -z -w 3 "$PS5_IP" 9295 >/dev/null 2>&1; then
  echo -e "${GREEN}通${NC}"
elif command -v bash >/dev/null 2>&1 && (echo >/dev/tcp/"$PS5_IP"/9295) 2>/dev/null; then
  echo -e "${GREEN}通${NC}"
else
  echo -e "${YELLOW}不通${NC}（请确认 PS5 已开机且开启了「远程游玩」）"
fi

echo -n "  [2/4] socat 服务状态: "
if $SUDO systemctl is-active ps5-forward >/dev/null 2>&1; then
  echo -e "${GREEN}运行中${NC}"
else
  echo -e "${RED}未运行${NC}"
fi

echo -n "  [3/4] socat 监听端口: "
LISTEN_NUM=$(ss -tulnp 2>/dev/null | grep -cE ':(9295|9296|9297|9302) ' || true)
if [ "$LISTEN_NUM" -ge 8 ]; then
  echo -e "${GREEN}8 个端口全部监听${NC}"
else
  echo -e "${YELLOW}${LISTEN_NUM}/8 个端口监听${NC}（可能部分 UDP 未就绪）"
fi

echo -n "  [4/4] IPv6 转发 (本机 -> $IPV6_ADDR:9295): "
if command -v nc >/dev/null 2>&1 && nc -6 -z -w 3 "$IPV6_ADDR" 9295 >/dev/null 2>&1; then
  echo -e "${GREEN}通${NC}"
else
  echo -e "${YELLOW}本机未验证${NC}（稍后从外部 IPv6 网络测）"
fi

echo
info "安装完成！"
echo -e "  ${CYAN}串流连接地址（填 Console Remote/Chiaki 的主机地址）:${NC}"
echo -e "  ${GREEN}$IPV6_ADDR${NC}"
echo
warn "外部设备需支持 IPv6（手机 4G/5G 一般都有）才能直连。"
warn "若 IPv6 前缀因光猫重拨变化，重新运行本脚本或查看本机新地址。"
