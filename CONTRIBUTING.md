# 贡献指南

## 报告机型适配结果

最有价值的贡献是"这台机器能不能用"。请在 Issue 里贴出：

```bash
./scripts/diagnose.sh
```

的输出（会自动打印 `printer-device-id` 与格式矩阵），并注明：

- 机型 / 固件版本（诊断输出里就有）
- macOS 版本（`sw_vers`）
- 结果：能打 / 只能打一页 / 条带 / 空白

## 提交代码

1. Fork → 新建分支 `feat/xxx` 或 `fix/xxx`
2. 保持 `bash 3.2` 兼容（macOS 自带 bash 是 3.2，别用 `mapfile`、`${var,,}`、关联数组）
3. 本地跑通：
   ```bash
   make lint    # shellcheck
   make test    # 不需要打印机
   ```
4. 提交 PR，说明动机与验证方式

## 不要做的事

- 不要把编译产物（`build/`、`bin/vendor/`、`*.app`）提交进仓库
- 不要修改 `LICENSE`（GPL-2.0 是上游 SpliX 的要求）
- 不要在 PPD 里改机器语言参数（`QPDLVersion` / `BandSize` / `PacketSize`）而不说明机型与固件版本

## 代码风格

- shell 统一 `#!/usr/bin/env bash` + `set -euo pipefail`
- 输出分两类：给人看的走 `say()`，报错走 stderr
- 新增脚本必须能被 `make lint` 覆盖（放在 `scripts/` 下即可）
