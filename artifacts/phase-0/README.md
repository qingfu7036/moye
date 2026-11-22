# Phase 0 本地构建产物

## Android

- 文件：`moye_phase0-debug.apk`
- SHA-256：见 `SHA256SUMS.txt`
- 包名：`app.moye.moye_phase0`
- 类型：debug 通用包，含 armeabi-v7a / arm64-v8a / x86_64
- 大小：约 180 MB
- 构建方式：源码复制到 ASCII 路径 `<ASCII_BUILD_DIR>` 后执行 `flutter build apk --debug`

APK 未纳入 Git（`.gitignore` 已忽略），避免仓库膨胀。它用于 Android 真机功能验证，不是发布包。

## Windows

Windows 调试构建位于：

`spikes/phase0_lab/build/windows/x64/runner/Debug/moye_phase0.exe`

该目录包含 Flutter/PDFium/TTS 运行所需 DLL 与 `data/`，不能只复制 exe。

## 未验证声明

Android APK 已构建并做过包结构静态检查，但**没有安装到 Android 设备运行**。PDF 渲染、选区、TTS 声音与暂停/继续仍待真机验证。
