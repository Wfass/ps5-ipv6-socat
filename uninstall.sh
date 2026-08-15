#!/usr/bin/env bash
# =============================================================================
# PS5 串流 socat 转发 —— 卸载脚本
# 用法：sudo bash uninstall.sh
# =============================================================================
set -e

GREEN='\033[32m'; RED='\033[31m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
  SUDO=""
  command -v sudo >/dev/null 2>&1 && SUDO="sudo" || { err "需要 root 权限"; exit 1; }
else
  SUDO=""
fi

info "停止并移除 ps5-forward 服务"
$SUDO systemctl stop ps5-forward 2>/dev/null || true
$SUDO systemctl disable ps5-forward 2>/dev/null || true
$SUDO rm -f /etc/systemd/system/ps5-forward.service
$SUDO rm -f /usr/local/bin/ps5-socat.sh
$SUDO systemctl daemon-reload

info "删除临时地址配置"
$SUDO rm -f /etc/sysctl.d/10-ipv6-tempaddr.conf
$SUDO sysctl -w net.ipv6.conf.all.use_tempaddr=1 >/dev/null 2>&1 || true

read -r -p "是否同时卸载 socat 软件包？[y/N] " yn
if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
  if command -v apt-get >/dev/null 2>&1; then $SUDO apt-get remove -y socat; fi
  if command -v yum >/dev/null 2>&1; then $SUDO yum remove -y socat; fi
  if command -v dnf >/dev/null 2>&1; then $SUDO dnf remove -y socat; fi
  if command -v apk >/dev/null 2>&1; then $SUDO apk del socat; fi
  info "socat 已卸载"
fi

info "卸载完成"
