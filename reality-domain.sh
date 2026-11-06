#!/usr/bin/env bash
# REALITY 目标域名筛选：RealiTLScanner + RealityChecker
set -Eeuo pipefail

usage() {
  cat <<'HELP'
用法：
  bash reality-domain.sh                        交互菜单
  bash reality-domain.sh --csv 文件.csv         检测扫描得到的 CSV
  bash reality-domain.sh --domains 域名...      批量检测指定域名
  bash reality-domain.sh --scan IPv4/24          扫描网段并检测结果
  bash reality-domain.sh --help                 显示帮助

扫描建议在本地 Linux 主机运行；检测建议在 VPS 上运行。
使用 --scan 会连接整个 /24 的 443 端口，仅扫描获授权的网段。
程序从 GitHub 下载固定版本的第三方二进制并校验 SHA-256。
HELP
}
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
mode=${1:-}; shift || true
case "$mode" in
  -h|--help) usage; exit 0 ;;
  --csv) [[ $# -eq 1 && -f $1 && -r $1 ]] || die '请指定可读取的 CSV 文件。'; csv=$1 ;;
  --domains) [[ $# -gt 0 ]] || die '请至少指定一个域名。'; domains=("$@") ;;
  --scan) [[ $# -eq 1 ]] || die '请指定一个 IPv4 /24 网段。'; subnet=$1 ;;
  '') ;;
  *) usage >&2; die '未知参数。' ;;
esac
if [[ -z $mode ]]; then
  printf '1) 检测已有 CSV\n2) 检测指定域名\n3) 扫描 IPv4 /24 并检测\n'
  read -r -p '请选择 [1-3]：' choice
  case "$choice" in
    1) read -r -p 'CSV 文件路径：' csv; [[ -f $csv && -r $csv ]] || die 'CSV 不存在或不可读取。'; mode=--csv ;;
    2) read -r -p '输入域名，以空格分隔：' line; read -r -a domains <<< "$line"; (( ${#domains[@]} > 0 )) || die '请输入域名。'; mode=--domains ;;
    3) read -r -p '输入 IPv4 /24 网段，例如 192.0.2.0/24：' subnet; mode=--scan ;;
    *) die '无效选择。' ;;
  esac
fi
if [[ $mode == --scan ]]; then
  [[ $subnet =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0/24$ ]] || die '仅接受 IPv4 /24 网段，例如 192.0.2.0/24。'
  for octet in "${BASH_REMATCH[@]:1:3}"; do (( 10#$octet <= 255 )) || die 'IPv4 网段无效。'; done
  printf '注意：将从本机扫描 %s 的全部地址。博文及扫描器作者建议不要在 VPS 上扫描。\n' "$subnet" >&2
fi
[[ $(uname -s) == Linux ]] || die '此脚本需要 Debian 或 Ubuntu Linux。'
[[ -r /etc/os-release ]] || die '无法识别系统。'
. /etc/os-release
[[ ${ID:-} == debian || ${ID:-} == ubuntu ]] || die '仅支持 Debian 和 Ubuntu。'
case $(uname -m) in
  x86_64|amd64) arch=amd64; check_hash=e021022b3486153abe738d318cb1cf8b2e3909ae9b2e19cbc2e6215db881c9; scan_hash=a55595446de9f1c2e6c5c3cd766a7320a11115947df48f101749bb62c8055592 ;;
  aarch64|arm64) arch=arm64; check_hash=f609bc17be50bc1b2e010eff233d9d9906cfd29081b0e0afb912f75117783cbb; scan_hash=27bdd3e53d4391c66c8df3391d3c3fb5eb2dc356125f2fb33ac58fcaaf8f88b3 ;;
  *) die '仅支持 x86_64 和 arm64。' ;;
esac
missing=()
for c in curl unzip sha256sum; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if (( ${#missing[@]} )); then
  printf '缺少依赖：%s；将通过 apt 安装。\n' "${missing[*]}"
  if (( EUID == 0 )); then aptcmd=(apt-get); elif command -v sudo >/dev/null 2>&1; then aptcmd=(sudo apt-get); else die '需要 root 或 sudo 安装依赖。'; fi
  "${aptcmd[@]}" update
  "${aptcmd[@]}" install -y curl unzip coreutils ca-certificates
fi
outdir=$(mktemp -d "${PWD%/}/reality-results-$(date +%Y%m%d-%H%M%S)-XXXXXX")
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
fetch() {
  local url=$1 file=$2 hash=$3
  curl -fL --retry 3 --connect-timeout 15 -o "$file" "$url" || die "下载失败：$url"
  printf '%s  %s\n' "$hash" "$file" | sha256sum -c - || die '下载文件校验失败。'
}
printf '结果目录：%s\n' "$outdir"
fetch "https://github.com/V2RaySSR/RealityChecker/releases/download/v2.2.3/reality-checker-linux-${arch}.zip" "$tmp/checker.zip" "$check_hash"
unzip -p "$tmp/checker.zip" reality-checker > "$tmp/reality-checker"
chmod +x "$tmp/reality-checker"
if [[ $mode == --scan ]]; then
  fetch "https://github.com/XTLS/RealiTLScanner/releases/download/v0.2.3/RealiTLScanner-linux-${arch}" "$tmp/scanner" "$scan_hash"
  chmod +x "$tmp/scanner"
  printf '开始扫描 %s；并发 10，单次超时 5 秒。\n' "$subnet"
  "$tmp/scanner" -addr "$subnet" -port 443 -thread 10 -timeout 5 -out "$outdir/candidates.csv" || die '扫描失败。'
  [[ -s $outdir/candidates.csv ]] || die '扫描未生成候选 CSV；可更换网段或导入已有 CSV。'
  csv=$outdir/candidates.csv; mode=--csv
fi
printf '\n开始检测，详细报告同步保存到 %s/report.txt\n' "$outdir"
if [[ $mode == --csv ]]; then
  [[ $csv == "$outdir/candidates.csv" ]] || cp -- "$csv" "$outdir/candidates.csv"
  "$tmp/reality-checker" csv "$outdir/candidates.csv" 2>&1 | tee "$outdir/report.txt"
else
  "$tmp/reality-checker" batch "${domains[@]}" 2>&1 | tee "$outdir/report.txt"
fi
printf '\n完成。报告：%s/report.txt\n' "$outdir"
