# 一键发布应用更新

项目根目录已经新增：

- `publish_release.bat`
- `publish_release_gui.bat`
- `build_release_package_arm64.bat`
- `publish_built_release.bat`
- `repair_release_manifest.bat`
- `tool/publish_app_update.ps1`
- `tool/publish_release_gui.ps1`
- `tool/publish_release_node.mjs`

## 最简单用法

直接双击：

```bat
publish_release.bat
```

如果你更想用可视化面板：

```bat
publish_release_gui.bat
```

如果你只想直接打一份 64 位 APK：

```bat
build_release_package_arm64.bat
```

或在终端执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -BuildOnly
node .\tool\publish_release_node.mjs publish
```

默认行为：

1. 读取 `pubspec.yaml` 当前版本
2. 自动将 `VersionCode` 在当前基础上 `+1`
3. `VersionName` 未传入时沿用当前值，传入时使用你指定的新版本名
4. 自动把新版本写回 `pubspec.yaml`
5. 默认构建 `arm64-v8a` 64 位专用发布包，而不是通用 APK
6. 执行 `flutter pub get`
7. 执行 arm64 发布打包
8. 通过 Node 发布脚本上传 APK 到 Gitee Release
9. 通过 Node 发布脚本自动更新云端版本文件 `photo_namer/photo_namer_app_update.json`

也就是说，直接运行脚本就会生成“同版本名、版本号自增、arm64 专用”的新发布。

GUI 面板支持：

1. 读取当前 `pubspec.yaml` 版本
2. 明确选择 `64 位 APK（arm64-v8a）` 或 `通用 APK`
3. 编辑版本名、版本号、标题、更新说明
4. 分开执行“打包”“发布”“修复云端版本清单”
5. 其中“发布”和“修复云端版本清单”已切到 Node 脚本

## 常用参数

### 最省事的发布方式

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1
```

这会自动把例如 `1.2.3+23` 变成 `1.2.3+24` 后再发布。

### 打通用 APK

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -UniversalApk
```

默认不建议这么做，因为体积会明显更大。

### 明确打 64 位 APK

默认就是 64 位 `arm64-v8a`。如果想走最省事方式，可以直接双击：

```bat
build_release_package_arm64.bat
```

### 只手动改 `VersionName`

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -VersionName 1.2.4
```

这会把例如 `1.2.3+23` 变成 `1.2.4+24`。

### 同时指定版本号和版本名

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -VersionName 1.2.4 -VersionCode 24
```

### 指定更新说明

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -Notes "新增云端更新发布；优化同步页"
```

### 从文本文件读取更新说明

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -NotesFile .\docs\release_notes.txt
```

### 发布为重要更新

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -ForceUpdate
```

### 跳过重新打包

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\publish_app_update.ps1 -SkipBuild
```

### 只修复云端版本清单

适合 Release 和 APK 已经上传成功，但最后一步 `photo_namer/photo_namer_app_update.json` 写入失败的情况：

```powershell
node .\tool\publish_release_node.mjs repair
```

如果要修某个指定版本，也可以一起带版本号：

```powershell
node .\tool\publish_release_node.mjs repair -VersionName 1.0.0 -VersionCode 2004
```

## 产物位置

脚本会把版本化 APK 和发布摘要写到：

```text
build/release_publish/
```

其中 `last_publish_summary.json` 会记录本次发布后的下载地址和 APK 类型。

## 注意

当前 `android/app/build.gradle.kts` 里的 `release` 仍然使用 debug 签名，仅适合你现在这种内部团队发布流程。
