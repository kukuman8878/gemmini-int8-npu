#!/usr/bin/env bash
# download_model.sh : 冻结 MobileNetV2 INT8 模型 (W13 §3.2)
# 下载官方 quant .tflite 到 android/models/, 计算 SHA-256, 更新 device_manifest.json
# 用法: bash android/scripts/download_model.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

MODEL_DIR="android/models"
MODEL_TGZ="mobilenet_v2_1.0_224_quant.tgz"
MODEL_TFLITE="mobilenet_v2_1.0_224_quant.tflite"
URL="https://storage.googleapis.com/download.tensorflow.org/models/tflite_11_05_08/${MODEL_TGZ}"
TGZ_SHA256="d6a04d780f76f656c902413be432eb349ec4a458240e3739119eb44977f77a79"

mkdir -p "$MODEL_DIR"

# 绕过失效的系统代理直连 (代理 127.0.0.1:7890 未运行时直连 Google storage)
echo "=== 下载模型 (直连, 绕过代理) ==="
if [ ! -f "$MODEL_DIR/$MODEL_TFLITE" ]; then
  tmp="/tmp/opencode_${MODEL_TGZ}"
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
    curl -sS --max-time 120 -o "$tmp" "$URL"
  echo "校验 tgz SHA-256 ..."
  actual=$(sha256sum "$tmp" | awk '{print $1}')
  if [ "$actual" != "$TGZ_SHA256" ]; then
    echo "SHA-256 不匹配: 期望 $TGZ_SHA256 实际 $actual" >&2
    exit 1
  fi
  tar xzf "$tmp" -C "$MODEL_DIR" "$MODEL_TFLITE"
  rm -f "$tmp"
else
  echo "已存在 $MODEL_DIR/$MODEL_TFLITE，跳过下载"
fi

echo "=== 模型信息 ==="
ls -la "$MODEL_DIR/$MODEL_TFLITE"
TFLITE_SHA=$(sha256sum "$MODEL_DIR/$MODEL_TFLITE" | awk '{print $1}')
echo "tflite SHA-256: $TFLITE_SHA"

python3 - "$TFLITE_SHA" << 'EOF'
import json, sys
sha = sys.argv[1]
p = "android/device_manifest.json"
d = json.load(open(p))
d["model"].update({
    "source_url": "https://storage.googleapis.com/download.tensorflow.org/models/tflite_11_05_08/mobilenet_v2_1.0_224_quant.tgz",
    "license": "Apache-2.0 (TensorFlow 官方预训练模型)",
    "sha256": sha,
})
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print("manifest.model.sha256 已写入")
EOF
