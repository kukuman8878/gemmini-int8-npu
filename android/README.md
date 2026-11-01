# Android 端侧实测（W13）准备说明

## 状态

- [x] adb 环境：34.0.4（`/usr/bin/adb`）
- [x] 模型冻结：MobileNetV2 1.0 224 INT8 quant（`android/models/mobilenet_v2_1.0_224_quant.tflite`，3.5MB）
  - 来源：`https://storage.googleapis.com/download.tensorflow.org/models/tflite_11_05_08/mobilenet_v2_1.0_224_quant.tgz`
  - SHA-256（tgz）：`d6a04d78f76f656c902413be432eb349ec4a458240e3739119eb44977f77a79`
  - SHA-256（tflite）：`f08d447cde49b4e0446428aa921aff0a14ea589fa9c5817b31f83128e9a43c1d`
  - 许可证：Apache-2.0（TensorFlow 官方预训练模型）
- [ ] 设备连接（`adb devices` 需显示小米 10）
- [ ] benchmark 工具获取（见下）

## benchmark 工具获取（二选一）

### 方案 A：benchmark_model 命令行二进制（推荐，可脚本化）

LiteRT 官方 benchmark 工具，需 arm64-v8a ABI 二进制。获取方式：

1. LiteRT 源码构建，或从 LiteRT release 下载 Android AAR/二进制；
2. 推送到设备：`adb push benchmark_model /data/local/tmp/`。

> 注意：二进制必须匹配设备 ABI（小米 10 = arm64-v8a）与 LiteRT 版本。

### 方案 B：Android benchmark App

官方 TFLite/LiteRT benchmark APK，图形界面选模型 + 设置线程数/运行次数，可导出 JSON。
适合快速验证，但命令行自动化不如方案 A。

## 运行流程（设备连接后）

```bash
bash android/scripts/device_audit.sh      # 1. 设备审计 → device_manifest.json
bash android/scripts/download_model.sh    # 2. 模型下载 + 校验（已完成）
bash android/scripts/run_benchmark.sh     # 3. benchmark 50 次推理 + 解析延迟
```

## 网络说明

- 系统配置了 Clash 代理（`127.0.0.1:7890`），但代理未运行时需**绕过代理直连** Google storage
  （脚本已用 `env -u http_proxy ...` 处理）。

## 隐私红线

- 不采集/提交个人照片、真实设备 IMEI/序列号；`device_manifest.json` 只记型号/SoC/版本等非敏感字段。
- 日志中的设备 ID 需脱敏后再入库。
