# W13 手机端实测结果（小米 10 CPU）

日期：2026-11-01 | 设备：Mi 10（kona=骁龙 865，Android 13，arm64-v8a，11.3GB RAM）

## CPU 基准（benchmark_model，XNNPACK，4 线程）

模型：MobileNetV2 1.0 224 INT8（`f08d447c...`，Apache-2.0）

| 组 | 初始化 (ms) | 推理 avg (ms) | min (ms) | max (ms) | runs |
|:---|:---|:---|:---|:---|:---|
| 1 | 21.09 | 9.17 | 9.14 | 9.29 | 110 |
| 2 | 22.06 | 9.16 | 9.14 | 9.22 | 110 |
| 3 | 19.10 | 9.16 | 9.14 | 9.39 | 110 |

- 推理延迟 **9.16 ms**（3 组 avg 9.17/9.16/9.16，各 110 runs，极稳定 std ~0.01-0.04ms；benchmark_model 仅输出 avg/min/max，无逐 run 分布故不报 median/p90）
- 吞吐：15.65 MB/s；内存占用：~14.6 MB
- 后端：**CPU（XNNPACK）**；GPU delegate 未编译进 benchmark_model（`--use_gpu` 未注册），NPU 未测

## 口径

- 这是**手机物理实测延迟**（真实 Android 设备），不等于 Gemmini/RTL 芯片时延。
- 参考：桌面 x86（开发机）同模型 3.27ms（`benchmark_litert_model.py`），手机 CPU 慢 ~2.8×。
- benchmark_model 构建：LiteRT Bazel（android_arm64，NDK r25c，`-Wl,-z,norelro` 规避 Android 13 RELRO 加载失败）。

## 证据文件

- `reports/mobile/benchmark_*.log`：3 组原始输出
- `android/device_manifest.json`：设备审计
