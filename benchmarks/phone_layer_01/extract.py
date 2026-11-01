#!/usr/bin/env python3
# extract.py : 从 MobileNetV2 INT8 .tflite 抽取真实 1×1 pointwise 层 (W14)
#   定位 Cin=320->Cout=1280 层, 提取输入/权重/bias/量化参数 → npy + quant.json + manifest.json
#   用法: python3 benchmarks/phone_layer_01/extract.py [--list | --cin CIN --cout COUT]
import os
import sys
import json
import hashlib
import numpy as np
from ai_edge_litert.interpreter import Interpreter

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "..", "android", "models", "mobilenet_v2_1.0_224_quant.tflite")

DEFAULT_CIN, DEFAULT_COUT = 320, 1280


def load_ops(interp):
    ops = interp._get_ops_details()
    td = interp.get_tensor_details()
    tshape = {t["index"]: list(t["shape"]) for t in td}
    tquant = {t["index"]: t["quantization_parameters"] for t in td}
    return ops, tshape, tquant


def find_pointwise(ops, tshape, cin=None, cout=None):
    """返回 (cin,cout,input_index,filter_index,bias_index,output_index,op) 列表"""
    rows = []
    for o in ops:
        if o["op_name"] != "CONV_2D":
            continue
        inp, filt, bias = o["inputs"][0], o["inputs"][1], o["inputs"][2]
        f = tshape[filt]
        if len(f) == 4 and f[1] == 1 and f[2] == 1:
            c_out, _, _, c_in = f
            if cin is not None and c_in != cin:
                continue
            if cout is not None and c_out != cout:
                continue
            rows.append((c_in, c_out, inp, filt, bias, o["outputs"][0], o))
    return rows


def main():
    args = sys.argv[1:]
    interp = Interpreter(model_path=MODEL)
    interp.allocate_tensors()
    ops, tshape, tquant = load_ops(interp)

    if "--list" in args:
        rows = find_pointwise(ops, tshape)
        print("=== 全部 1×1 pointwise 层 (Cin→Cout) ===")
        for c_in, c_out, *_ in sorted(rows, key=lambda r: r[0]):
            print(f"  Cin={c_in:4d} -> Cout={c_out:4d}")
        print(f"共 {len(rows)} 个")
        return

    cin = DEFAULT_CIN
    cout = DEFAULT_COUT
    if "--cin" in args:
        cin = int(args[args.index("--cin") + 1])
    if "--cout" in args:
        cout = int(args[args.index("--cout") + 1])

    rows = find_pointwise(ops, tshape, cin=cin, cout=cout)
    if not rows:
        print(f"未找到 Cin={cin} Cout={cout} 的 pointwise 层")
        return
    c_in, c_out, inp_i, filt_i, bias_i, out_i, op = rows[0]

    td = {t["index"]: t for t in interp.get_tensor_details()}
    inp_shape = [int(x) for x in td[inp_i]["shape"]]
    assert inp_shape[-1] == c_in, "NHWC 输入通道与 Cin 不符"
    M = int(np.prod(inp_shape[:-1]))          # N·H·W 展平
    K = int(c_in)
    N = int(c_out)

    # 权重 filter: [Cout,1,1,Cin] -> B[K,N] = B[Cin,Cout] (转置)
    filt = interp.get_tensor(filt_i)          # uint8 [Cout,1,1,Cin]
    W = filt.reshape(c_out, c_in)             # [Cout,Cin]
    B = W.T.astype(np.int16).copy()           # [Cin,Cout] uint8→int16 存原始字节
    B_uint8 = W.T.copy()                      # [K,N] uint8

    bias = interp.get_tensor(bias_i)          # int32 [Cout]

    # 量化参数
    inp_q = td[inp_i]["quantization_parameters"]
    filt_q = td[filt_i]["quantization_parameters"]
    out_q = td[out_i]["quantization_parameters"]
    inp_scale, inp_zp = float(inp_q["scales"][0]), int(inp_q["zero_points"][0])
    # filter per-channel scale/zero_point (可能 length==1 或 ==Cout)
    f_scales = np.array(filt_q["scales"], dtype=np.float64)
    f_zps = np.array(filt_q["zero_points"], dtype=np.int32)
    out_scale, out_zp = float(out_q["scales"][0]), int(out_q["zero_points"][0])

    # 真实输入激活：无真实图片时用 uint8 均匀随机（脚本内注明可替换真实激活）
    rng = np.random.default_rng(20261101)
    A_uint8 = rng.integers(0, 256, size=(M, K), dtype=np.uint8)

    # INT32 黄金累加 (按文档 §1.2 核心对齐式): acc(m,n)=Σ_k (qA-zA)(qB-zB_n) + bias(n)
    qA = A_uint8.astype(np.int32) - inp_zp                 # [M,K]
    qB = B_uint8.astype(np.int32) - f_zps[np.newaxis, :]   # [K,N] per-channel 去零点
    golden = qA @ qB                                       # [M,N] INT32
    golden = golden + bias[np.newaxis, :].astype(np.int64) # + bias
    golden = golden.astype(np.int32)

    os.makedirs(HERE, exist_ok=True)
    np.save(os.path.join(HERE, "input_a_int8.npy"), A_uint8)
    np.save(os.path.join(HERE, "weight_b_int8.npy"), B_uint8)
    np.save(os.path.join(HERE, "bias_int32.npy"), bias)
    np.save(os.path.join(HERE, "golden_acc_int32.npy"), golden)

    quant = {
        "model": "mobilenet_v2_1.0_224_quant.tflite",
        "op": f"pointwise_conv_1x1_{cin}_{cout}",
        "layout": "NHWC",
        "M": M, "K": K, "N": N,
        "input": {"dtype": "uint8", "scale": inp_scale, "zero_point": inp_zp},
        "weight": {"dtype": "uint8", "per_channel": bool(len(f_scales) > 1),
                   "scales": f_scales.tolist(), "zero_points": f_zps.tolist()},
        "bias": {"dtype": "int32"},
        "output": {"scale": out_scale, "zero_point": out_zp},
        "golden": {"acc_dtype": "int32", "note": "INT32 精确累加, 未做 requantize"},
    }
    with open(os.path.join(HERE, "quant.json"), "w") as fh:
        json.dump(quant, fh, indent=2, ensure_ascii=False)

    manifest = {
        "model_hash_sha256": hashlib.sha256(open(MODEL, "rb").read()).hexdigest(),
        "op_name": quant["op"],
        "dims": {"M": M, "K": K, "N": N},
        "dtype": "int8 (uint8 量化表示)",
        "layout": "NHWC",
        "input_shape_raw": inp_shape,
        "filter_shape_raw": [int(x) for x in filt.shape],
        "generated_by": "benchmarks/phone_layer_01/extract.py",
    }
    with open(os.path.join(HERE, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)

    print(f"抽取完成: pointwise {cin}->{cout}")
    print(f"  GEMM: A[{M},{K}] × B[{K},{N}] = C[{M},{N}]  (K 分块: {K}=256+{K-256 if K>256 else 0})")
    print(f"  输入量化: scale={inp_scale} zp={inp_zp}")
    print(f"  权重量化: per_channel={bool(len(f_scales)>1)} scale 数={len(f_scales)} zp 数={len(f_zps)}")
    print(f"  输出量化: scale={out_scale} zp={out_zp}")
    print(f"  golden INT32 形状: {golden.shape} (值域 [{golden.min()},{golden.max()}])")
    print(f"  文件写入 {HERE}/")


if __name__ == "__main__":
    main()
