#!/usr/bin/env bash
# RealiTLScanner v0.2.3 一键运行器（Debian / Ubuntu）
set -Eeuo pipefail
usage() {
  cat <<'HELP'
用法：
  bash reality-scanner.sh                     交互式选择
  bash reality-scanner.sh --addr 地址或CIDR  扫描 IP、域名或 CIDR
  bash reality-scanner.sh --file 文件        扫描文件中的目标（每行一个）
  bash reality-scanner.sh --url 网址         提取网页中的域名并扫描
  bash reality-scanner.sh --help             显示帮助

单个 IP 或域名会触发上游的无限扩展扫描，需要按 Ctrl+C 停止。
CIDR 是有限扫描范围。只扫描有权限扫描的目标。
HELP
}
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
mode=${1:-}; shift || true
case $mode in
  -h|--help) usage; exit 0 ;;
  --addr|--url) [[ $# -eq 1 && -n $1 ]] || die '请提供一个目标。'; target=$1 ;;
  --file) [[ $# -eq 1 && -f $1 && -r $1 ]] || die '请提供可读取的目标列表文件。'; target=$1 ;;
  '') [[ $# -eq 0 ]] || die '参数无效。' ;;
  *) usage >&2; die '未知参数。' ;;
esac
if [[ -z $mode ]]; then
  printf 'RealiTLScanner 一键扫描\n\n1) 扫描 VPS IP 所在的 /24 网段（有限范围）\n2) 按 IP、域名或 CIDR 扫描\n3) 从文件读取目标\n4) 从网页提取域名\n'
  read -r -p '请选择 [1-4]：' choice || die '无法读取输入。'
  case $choice in
    1)
      read -r -p '输入 VPS IPv4 地址：' ip || die '无法读取输入。'
      [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || die '请输入有效 IPv4 地址。'
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}; c=${BASH_REMATCH[3]}; d=${BASH_REMATCH[4]}
      for n in "$a" "$b" "$c" "$d"; do (( 10#$n <= 255 )) || die 'IPv4 地址无效。'; done
      target="$((10#$a)).$((10#$b)).$((10#$c)).0/24"; mode=--addr ;;
    2) read -r -p '输入 IP、域名或 CIDR：' target || die '无法读取输入。'; mode=--addr ;;
    3) read -r -p '输入目标列表文件路径：' target || die '无法读取输入。'; [[ -f $target && -r $target ]] || die '文件不存在或不可读取。'; mode=--file ;;
    4) read -r -p '输入网页 URL：' target || die '无法读取输入。'; mode=--url ;;
    *) die '无效选择。' ;;
  esac
  [[ -n $target ]] || die '目标不能为空。'
fi
if [[ $mode == --addr && $target != */* ]]; then
  printf '提示：单个 IP 或域名会触发无限扩展扫描，请按 Ctrl+C 停止。\n' >&2
fi
printf '提示：上游建议在本地运行；只扫描已获授权的目标。\n' >&2
[[ $(uname -s) == Linux ]] || die '需要 Debian 或 Ubuntu Linux。'
[[ -r /etc/os-release ]] || die '无法识别系统。'
. /etc/os-release
[[ ${ID:-} == debian || ${ID:-} == ubuntu ]] || die '仅支持 Debian 和 Ubuntu。'
case $(uname -m) in
  x86_64|amd64) arch=amd64; hash=a55595446de9f1c2e6c5c3cd766a7320a11115947df48f101749bb62c8055592 ;;
  aarch64|arm64) arch=arm64; hash=27bdd3e53d4391c66c8df3391d3c3fb5eb2dc356125f2fb33ac58fcaaf8f88b3 ;;
  *) die '仅支持 x86_64 和 ARM64。' ;;
esac
for cmd in curl sha256sum; do command -v "$cmd" >/dev/null 2>&1 || die "缺少 $cmd，请使用 apt 安装 curl、coreutils 和 ca-certificates。"; done
results=$(mktemp -d "${PWD%/}/realitlscanner-$(date +%Y%m%d-%H%M%S)-XXXXXX")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
url="https://github.com/XTLS/RealiTLScanner/releases/download/v0.2.3/RealiTLScanner-linux-${arch}"
printf '正在下载 RealiTLScanner v0.2.3（%s）...\n' "$arch"
curl -fL --retry 3 --connect-timeout 15 -o "$tmp/scanner" "$url" || die '下载失败，请检查 GitHub 连接。'
printf '%s  %s\n' "$hash" "$tmp/scanner" | sha256sum -c - || die 'SHA-256 校验失败。'
chmod +x "$tmp/scanner"
case $mode in --addr) option=-addr ;; --file) option=-in ;; --url) option=-url ;; esac
printf '\n扫描目标：%s\n结果文件：%s/results.csv\n端口：443；并发：10；超时：5 秒\n\n' "$target" "$results"
"$tmp/scanner" "$option" "$target" -port 443 -thread 10 -timeout 5 -out "$results/results.csv"
printf '\n扫描结束，结果：%s/results.csv\n' "$results"
