# 原理与取证

本文记录"为什么打不出来"的判断过程与每个结论的证据，方便复现、复查、以及适配同族机型。

---

## 1. 现场：三个互相矛盾的信号

```
lpstat -t                    → 打印机 idle，接受请求
lp -d <queue> file.pdf       → 任务 id 生成，几分钟后状态"已完成"
出纸槽                       → 空的，且打印机不报任何错误
```

CUPS 的"已完成"只代表**数据已经交给后端**，不代表打印机渲染过。判断是否真的出纸，
必须看打印机自己的硬件计数器（见第 5 节）。

另外，这台机器原本的队列是：

```
device-uri = dnssd://..._printer._tcp.local./auto       ← LPD，不是 IPP
printer-make-and-model = Generic PCL Laser Printer      ← 通用 PCL 驱动
```

LPD + 通用 PCL 双错叠加：既发错了协议，又发错了语言。

---

## 2. 证据一：固件只声明两种格式

```bash
ipptool -tv ipp://<IP>:631/ipp/print /usr/share/cups/ipptool/get-printer-attributes.test
```

```
printer-make-and-model     = HP Laser 105w
document-format-supported  = application/octet-stream, application/PCLm
printer-device-id          = MFG:HP;CMD:SPL,URF,FWV,PIC,EXT,DCU,PWGRaster;PRN:A00F0A;
                             MDL:HP Laser 101-105;CLS:PRINTER;CID:HPLJPCLMSMV1;
                             MODE:SPL3,R000105,SCP;
ipp-features-supported     = document-object, airprint-2.1
```

关键在 `MODE:SPL3` —— SPL（Samsung Printing Language）第三代，也就是 **QPDL v3**。
`CID:HPLJPCLMSMV1` 进一步说明这是三星机芯 + HP 的 PCLm 变体。

对照 SNMP，解释器家族也对得上：

```bash
snmpwalk -v1 -c public <IP> 1.3.6.1.2.1.43.15.1.1.2
# mib-2.43.15.1.1.2.1.1 = INTEGER: 18
snmpget  -v1 -c public <IP> 1.3.6.1.2.1.43.15.1.1.5.1.1
# "Auto Page Description Language interpreter"  V11.91_231025
```

---

## 3. 证据二：把常见格式挨个喂进去

```bash
ipptool -tv -d filetype=image/urf -f page.urf ipp://<IP>/ipp/print print-job.test
ipptool -tv -d filetype=image/pwg-raster -f page.pwg ipp://<IP>/ipp/print print-job.test
ipptool -tv -d filetype=application/pdf -f page.pdf ipp://<IP>/ipp/print print-job.test
```

| document-format | 固件回应 |
|---|---|
| `image/urf` | `client-error-document-format-not-supported` |
| `image/pwg-raster` | 同上 |
| `application/pdf` | 同上 |
| `application/PCLm`（普通 PDF 冒充） | 同上 |

**一个反直觉的细节**：同一个 MIME 类型，喂 CUPS 光栅（`3SaR` 流）就返回 `successful-ok`，
喂真 PWG 光栅（`RaS2` 流）就被拒。说明它不只比对声明，还看内容字节 ——
"接受"不等于"能渲染"，必须用页计数器验证。

---

## 4. 补齐缺失的一环

CUPS 的打印语言由 **PPD + 过滤器链**决定，不是编译进系统的。所以只要提供两样东西：

1. 一个能把 CUPS 光栅转成 QPDL 的过滤器；
2. 一个声明"输入光栅、输出 QPDL"的 PPD。

现成的编码器是 [SpliX](https://github.com/OpenPrinting/splix)（GPLv2，支持三星 SPL2/SPLc）。
它默认依赖 libjbig，本项目用 `DISABLE_JBIG=1` 编译，避免额外依赖：

```bash
make -C splix DISABLE_JBIG=1 LDFLAGS="-lcups"
```

PPD 取同族机型 `ml2160.ppd`（同为 SPL3 机芯），只改品牌与默认纸张：

```diff
-*Product: "(ML-2160)"            +*Product: "(HP Laser 105w)"
-*Manufacturer: "Samsung"         +*Manufacturer: "HP"
-*DefaultPageSize: Letter         +*DefaultPageSize: A4
```

机器语言参数原样保留：

```
*QPDL QPDLVersion: "3"        ← 与固件 MODE:SPL3 对齐
*QPDL BandSize: "128"
*QPDL PacketSize: "512"
*General DocHeaderValues: "<0><0><1>"
*cupsFilter: "application/vnd.cups-raster 0 rastertoqpdl"
```

---

## 5. 验证：只信页计数器

```bash
snmpwalk -v1 -c public <IP> 1.3.6.1.2.1.43.10.2.1.4
# prtMarkerLifeCount = N
```

投递一次 → 数字 +1，才算真打出来了。本项目所有验证（单页、多页、中文、拖拽、系统队列）
都用这个口径，`hp105w-print -w` 就是把这件事自动化。

---

## 6. 两个坑

### 坑一：IPP 后端会把格式写成 `application/octet-stream`

通过 `ipp://` 走 CUPS 时，打印机的 job log 显示实际收到的 `document-format` 是
`application/octet-stream`，固件因此按"原生 SPL"解析我们的 PWG 数据，回一句
`不支持光栅数据`。

所以本项目**不走 IPP**，直接 `socket://<ip>:9100` 送原始字节流，由固件自己嗅探。
这也是 `install.sh` 用 `socket://` 而不是 `ipp://` 的原因。

### 坑二：CUPS 只肯执行 root 拥有的过滤器

第一次把过滤器放在家目录并写绝对路径，CUPS 报：

```
文件"…/probe_filter.sh"有不安全权限（0100755/uid=502/gid=20）
```

CUPS 接受绝对路径，但要求过滤器属主是 root 且组/他人不可写。
这就是整个安装流程里唯一需要 `sudo` 的一步 —— 只是 `install -o root -g wheel -m 0755` 两个文件。

---

## 7. 已知边界

- **不支持双面**：PPD 里虽有 `ManualDuplex`，硬件无自动双面单元。
- **只验证了 600dpi**：PPD 也提供 1200dpi 选项，未做长时间稳定性测试。
- **PaperSize 以 A4/Letter 为主**：其它尺寸理论可用，但未逐一验证边距。
- **依赖 9100 端口**：若网络策略封了 raw 打印端口，需要改用其它通道（LPD 亦可）。
- **固件差异**：不同固件版本的 band 上限不同，出现条带时优先调 `*QPDL BandSize`。

---

## 8. 时间线（一次真实排查）

| 时间 | 动作 | 结果 |
|---|---|---|
| T+0 | `lpstat -t` / `lpoptions` | 发现队列是 LPD + Generic PCL |
| T+1m | `ippfind` / 端口探测 | 网络全通，排除连接问题 |
| T+3m | `get-printer-attributes` | 拿到 `MODE:SPL3`，锁定 PDL |
| T+8m | 逐格式探测 | 四连拒，确认固件只认 QPDL |
| T+12m | SNMP 页计数器 | 建立"是否真出纸"的判定口径 |
| T+20m | 编译 SpliX、改 PPD | 得到 QPDL 数据 |
| T+22m | `nc <ip> 9100 < job.spl` | **页计数器 +1，出纸** |
| T+30m | 装成 CUPS 队列 | ⌘P 可用 |
