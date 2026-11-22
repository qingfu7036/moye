# Phase 0 环境报告

采集时间：2026-11-02（Asia/Shanghai）
工作区：`<REPO_ROOT>`

## 1. 主机

| 项目 | 实际值 |
|---|---|
| 操作系统 | Windows 11 家庭中文版 25H2，Build 26200.9711 |
| CPU | 12th Gen Intel Core i7-12700H，14 核 / 20 线程 |
| 内存 | 15.7 GB |
| 磁盘 | C: 约 22.1 GB 可用（验证期间持续下降） |
| 架构 | x64 |
| 虚拟化固件 | 已开启（VT-x / SLAT 可用） |
| Hypervisor | 未运行；HypervisorPlatform、VirtualMachinePlatform 均未启用 |

`flutter doctor` 结论：

- Flutter、Windows 桌面、Android 工具链、Visual Studio 均通过。
- 可用设备只有 Windows、Chrome、Edge，**没有 Android 设备**。
- Network resources 检查在 4 分 30 秒后超时。pub.dev、Google SDK 下载可用，但 GitHub/Maven 存在间歇性连接重置或超时。
- Visual Studio 为 2022 Community 17.2.6，Windows 10 SDK 10.0.19041.0。

## 2. 工具链

安装在项目外，避免污染仓库：

`<TOOLCHAINS>`

| 组件 | 版本 / 路径 |
|---|---|
| Flutter | 3.47.9 stable，revision `c197ca5199` |
| Dart | 3.13.7 |
| Java | Temurin OpenJDK 17.0.20.1+1 |
| Android SDK | Platform 36 / Build-Tools 36.0.0 / Platform-Tools 37.0.1 |
| Android NDK | 28.2.13676358 |
| CMake | 3.22.1 |
| NuGet CLI | 7.9.0.83（`flutter_tts` Windows 构建必需） |
| Gradle | Flutter 模板生成的 Gradle Wrapper（构建日志 9.3.1） |

Flutter SDK 下载并解压到项目外；`flutter --version`、`flutter doctor`、`flutter build windows` 均成功。

### Windows Developer Mode

pdfrx 文档要求开启 Windows Developer Mode，因为 native assets 构建使用符号链接。本机注册表未开启 Developer Mode，但当前 shell 具备管理员符号链接权限，因此 Windows 构建成功。**换到普通权限 shell 可能失败**，风险已记录。V1 开发机应统一开启 Developer Mode 或使用管理员/CI 构建。

### Android 路径问题

仓库绝对路径包含 `MOYE（墨页）` 中文与全角括号。

- 直接构建：失败，报 `CopyFlutterJniLibsTask` 的中间目录不存在。
- 添加 `android.overridePathCheck=true`：绕过 Gradle 的首层路径检查，但在 `jni` 的 CMake/NDK 阶段仍失败。
- 将同一源码树复制到 `<ASCII_BUILD_DIR>`（纯 ASCII）后：`flutter build apk --debug` 成功。

结论：**中文路径不是“警告”，而是当前 Windows + Android 工具链的构建阻塞项。** Phase 1 前必须确定仓库路径或固定 ASCII 构建流程。

同一路径还会导致 `flutter analyze` 的 analysis server 以 code 255 崩溃；`dart analyze lib` 正常。不要把工具崩溃误判为代码错误。

## 3. Android 运行环境缺口

本机：

- 未连接 Android 真机。
- 未安装 Android Emulator 与系统镜像。
- HypervisorPlatform / VirtualMachinePlatform 禁用，启用通常需要重启。
- `adb.exe version` 可执行，但 `adb start-server` 在 PowerShell/CMD 下挂起；已经等待并触发工具 15 分钟上限，无法安全用于设备管理。

因此 Android 结论严格限定为：

- **APK 构建通过（ASCII 路径）**
- **APK 包结构校验通过**
- **Android 上的 PDF 渲染、选区、TTS 均未运行验证**

本报告不把 APK 构建成功当作 Android 运行验收。

## 4. 网络与依赖

- pub.dev API 可用；`flutter pub get` 成功。
- GitHub raw 文档曾出现连接重置；Flutter SDK 自更新 `fetch --tags` 也出现 reset，但不影响使用。
- `maven.google.com` 曾超时。Android 首次构建耗时约 25 分钟，主要花在 SDK/依赖下载；第二次 ASCII 构建约 85 秒。
- 未配置代理或镜像。V1 团队如在国内网络长期构建，应固化 pub / Gradle / Maven 镜像策略，并记录校验方式。

## 5. 复现命令

```bash
export TOOLS="<TOOLCHAINS>"
export PATH="$TOOLS/flutter/bin:$TOOLS/jdk/bin:$TOOLS/nuget:$PATH"
export JAVA_HOME="$TOOLS/jdk"
export ANDROID_SDK_ROOT="$TOOLS/android-sdk"
export ANDROID_HOME="$TOOLS/android-sdk"

cd spikes/phase0_lab
flutter pub get
flutter test test
flutter build windows --debug

# Android：必须从 ASCII 路径构建
cd $HOME/.kun/moye_build/phase0_lab
flutter pub get
flutter build apk --debug
```

## 6. 结论

Windows 技术验证环境可用。Android 编译环境可用，但运行环境缺失；这是 Phase 0 尚未闭合的验收项，而不是代码构建失败。
