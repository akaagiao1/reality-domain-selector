# REALITY 目标域名筛选

适用于 Debian 和 Ubuntu 的 Bash 脚本，基于 [V2RaySSR 的教程](https://v2rayssr.com/reality-2.html)，调用 RealiTLScanner 寻找候选网站，并调用 RealityChecker 进行检测。

## 要求

- Debian 或 Ubuntu，x86_64（amd64）或 ARM64。
- 能访问 GitHub Releases；需要 `curl`、`unzip` 和 `sha256sum`。缺少时，脚本会使用 `apt-get` 安装，需要 root 或 sudo 权限。
- 检测时需要能访问候选网站。结果反映运行脚本的机器到目标站的连接情况。

## 一键运行

在 Debian 或 Ubuntu 的终端复制运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/reality-domain-selector/main/reality-domain.sh)
```

启动后按提示选择扫描或检测。系统需要预先安装 `curl`；如果提示找不到该命令，可先运行 `apt-get update && apt-get install -y curl ca-certificates`（需要 root 权限，或在每条命令前加 `sudo`）。

## 单独使用 RealiTLScanner

只需要扫描候选域名时，复制这条命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/reality-domain-selector/main/reality-scanner.sh)
```

菜单支持根据 VPS IPv4 地址扫描其所在的 `/24` 网段，也支持输入 IP、域名、CIDR、目标列表文件或网页 URL。脚本使用端口 443、并发 10、单次超时 5 秒，结果写入当前目录新建的 `realitlscanner-*/results.csv`。扫描单个 IP 或域名时，上游会自动启用无限扩展扫描，需要按 Ctrl+C 停止；选择 `/24` 则会有限扫描。仅扫描获授权的目标，上游建议在本地运行扫描，避免 VPS 被标记。

脚本下载并校验上游 v0.2.3 的 Linux 二进制；目标列表中的每行是一个 IP、CIDR 或域名。可以将生成的 CSV 交给前面的域名筛选脚本，但不同版本的工具格式可能不兼容；请检查实际检测结果。扫描发现的证书域名未必可直接用于 REALITY，需要进一步验证 SNI 和证书等条件，也不代表 ASN 匹配。

## 其他使用方法

下载仓库后运行：

```bash
bash reality-domain.sh
```

按菜单选择导入 CSV、检测指定域名或扫描 IPv4 `/24` 网段。也可以直接传参：

```bash
# 批量检测已有域名
bash reality-domain.sh --domains example.com www.example.org

# 检测 RealiTLScanner 导出的 CSV
bash reality-domain.sh --csv file.csv

# 扫描一个 IPv4 /24 网段，然后检测结果
bash reality-domain.sh --scan 192.0.2.0/24

# 帮助
bash reality-domain.sh --help
```

`192.0.2.0/24` 仅为示例，请换成实际网段。扫描会尝试连接该网段的 443 端口，只应扫描获授权的目标。[RealiTLScanner 作者建议在本地运行扫描，避免在 VPS 上大范围扫描](https://github.com/XTLS/RealiTLScanner)。

每次运行会在当前目录新建 `reality-results-时间-随机字符`，保存检测报告 `report.txt`。CSV 模式还会保存 `candidates.csv`。为了测量 VPS 到目标站的握手和延迟，请在实际运行 REALITY 的 VPS 上进行检测；本机扫描结果可以复制到 VPS 后使用 `--csv` 检测。

## 如何看结果

RealityChecker 会检查 TLS 1.3、X25519、HTTP/2、证书和 SNI 等条件，并提供跳转、CDN 等参考信息。检测通过不代表一定适合作为目标站，也不能保证连接稳定或避免封锁。建议结合实际节点网络选择合理的目标，优先考虑节点与目标站属于同一 ASN，并在配置后实测。脚本不核验 ASN 是否匹配，也不判断 IP 段的信誉。域名热度、CDN 检测和地理位置等结果仅供参考。

## 依赖与版本

脚本在临时目录下载并运行以下第三方程序，结束时清理二进制。下载文件以脚本内固定的 SHA-256 值校验：

- [V2RaySSR/RealityChecker v2.2.3](https://github.com/V2RaySSR/RealityChecker/releases/tag/v2.2.3)
- [XTLS/RealiTLScanner v0.2.3](https://github.com/XTLS/RealiTLScanner/releases/tag/v0.2.3)（仅扫描模式）

程序版本固定，更新上游版本时需同时更新下载地址和校验值。第三方工具有其各自的许可和行为，请参阅其项目说明。
