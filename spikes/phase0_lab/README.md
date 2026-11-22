# moye_phase0

MOYE Phase 0 技术风险验证工程。**不是 V1 产品代码**，不要把这里的 Lab 页面直接复制进 `lib/`。

- 总报告：`../../docs/phase-0/PHASE_0_REPORT.md`
- 测试：`test/`、`integration_test/`
- 真实样书：`assets/fixtures/`（由 `scripts/generate_fixtures.py` 生成）

快速运行：

```bash
export TOOLS="<TOOLCHAINS>"
export PATH="$TOOLS/flutter/bin:$TOOLS/jdk/bin:$TOOLS/nuget:$PATH"
flutter pub get
flutter test test
flutter test integration_test/phase0_labs_test.dart -d windows
flutter build windows --debug
```

Android 构建必须从 ASCII 路径执行，原因见 `docs/phase-0/environment.md`。
