# 更新日志

## [1.0.0] - 2026-11-07

首个公开版本。

### 新增
- `bin/hp105w-print`：命令行驱动，文档 → CUPS 光栅 → QPDL → TCP 9100
- `scripts/build.sh`：从上游拉取 SpliX 并编译（`DISABLE_JBIG=1`，sha256 校验）
- `scripts/install.sh` / `uninstall.sh`：安装为 CUPS 队列 `HP_Laser_105w_SPL`
- `scripts/diagnose.sh`：取证式体检（IPP 属性、格式矩阵、页计数器）
- `scripts/make-app.sh`：生成可拖拽的 `HP105w-Print.app`
- `ppd/HP_Laser_105w.ppd`：QPDL v3 / BandSize 128 / PacketSize 512 / A4 / 600dpi
- `tests/smoke.sh` + GitHub Actions CI

### 已验证
- HP Laser 105w，firmware V3.82.05.16，macOS 26 / 27
- 单页、多页、中文渲染、拖拽打印、系统队列打印均正常出纸
- 页计数器（`prtMarkerLifeCount`）逐次 +1

### 已知限制
- 无自动双面
- 仅 600dpi 做长期验证
