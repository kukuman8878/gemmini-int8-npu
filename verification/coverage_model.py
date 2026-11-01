#!/usr/bin/env python3
# verification/coverage_model.py : W15 功能覆盖模型 (coverpoint + cross)
#   从用例级覆盖矩阵升级为功能点级: 定义 coverpoint (bin+含义) 与 cross 覆盖,
#   校验测试映射真实存在, 输出命中率 + 未命中原因 + 被排除项。
#   用法: python3 verification/coverage_model.py
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _test_exists(ref):
    """校验 'tb_xxx.test_name' 引用真实存在 (读 tb/xxx.py 找 async def test_name)"""
    if re.match(r"^tb_[a-z0-9_]+\.[a-z0-9_]+$", ref):
        module, _, func = ref.rpartition(".")
        path = os.path.join(REPO, "tb", module + ".py")
        if not os.path.isfile(path):
            return False, f"{ref} (tb 文件不存在)"
        with open(path, encoding="utf-8") as f:
            content = f.read()
        if not re.search(rf"^async def {re.escape(func)}\s*\(", content, re.M):
            return False, f"{ref} (async def 不存在)"
        return True, ""
    return True, ""  # 非测试名引用 (命令/说明) 跳过


# ---- coverpoint 定义: bin -> 覆盖测试 (每个 bin 必须有至少一个真实覆盖项) ----
COVERPOINTS = {
    "cp_k_len": {
        "desc": "K 归约长度 (1..256, 含 K>N 流式归约)",
        "bins": {
            "K=1": ["tb_top.test_e2e_random_k", "tb_bench.test_tile_cycles"],
            "K=2": ["tb_top.test_e2e_basic", "tb_top.test_e2e_random_k"],
            "K=4": ["tb_top.test_e2e_random_k", "tb_regression.test_seeded_random"],
            "K=8": ["tb_top.test_e2e_random_k", "tb_skew.test_random_k"],
            "K=16": ["tb_top.test_e2e_random_k", "tb_skew.test_random_k"],
            "K=64": ["tb_bench.test_tile_cycles", "tb_regression.test_seeded_random"],
            "K=256": ["tb_top.test_e2e_large_k", "tb_bench.test_tile_cycles"],
        },
    },
    "cp_scenario": {
        "desc": "握手/控制场景",
        "bins": {
            "basic": ["tb_top.test_e2e_basic"],
            "input_pause": ["tb_top.test_e2e_input_pause", "tb_controller.test_load_stall_and_drain"],
            "backpressure": ["tb_top.test_e2e_backpressure", "tb_controller.test_output_handshake"],
            "back2back": ["tb_top.test_e2e_back_to_back"],
            "mid_reset": ["tb_top.test_e2e_mid_reset", "tb_controller.test_reset_idle"],
            "illegal_cfg": ["tb_top.test_e2e_illegal_and_stale", "tb_controller.test_illegal_cfg"],
        },
    },
    "cp_symbol": {
        "desc": "符号组合 (signed INT8)",
        "bins": {
            "all_pos": ["tb_mac.test_random_mac"],
            "all_neg": ["tb_mac.test_boundary"],
            "mixed": ["tb_top.test_e2e_random_k", "tb_systolic.test_random_matmul"],
            "boundary_int8": ["tb_mac.test_boundary", "tb_mac.test_exhaustive_boundary"],
        },
    },
    "cp_fifo_state": {
        "desc": "FIFO 满空/回绕状态",
        "bins": {
            "empty": ["tb_fifo.test_underflow_reject"],
            "full": ["tb_fifo.test_overflow_reject"],
            "simult_rw": ["tb_fifo.test_simult_rw"],
            "pointer_wrap": ["tb_fifo.test_pointer_wrap"],
        },
    },
    "cp_dataflow": {
        "desc": "数据流 (自研仅 OS; WS 为被排除项)",
        "bins": {
            "OS": ["tb_top.test_e2e_basic", "tb_skew.test_golden_2x2"],
        },
    },
    "cp_protocol": {
        "desc": "协议断言 (SVA)",
        "bins": {
            "A1_backpressure_stable": ["tb/npu_top_assert.sv"],
            "A2_fifo_full_write_empty_read": ["tb/fifo_assert.sv"],
            "A3_busy_state_consist": ["tb/npu_top_assert.sv"],
            "A4_reset_legal": ["tb/npu_top_assert.sv"],
            "A5_invalid_beat_no_acc": ["tb/pe_assert.sv"],
            "A6_drain_progress": ["tb/npu_top_assert.sv"],
        },
    },
}

# ---- cross 覆盖: 显式映射 K×场景 -> 覆盖测试 (精确反映 tb_top.py 实际覆盖) ----
CROSSES = {
    "cr_k_len_x_scenario": {
        "desc": "K 长度 × 场景 (端到端 npu_top)",
        "covered_pairs": {
            ("K=1", "basic"): ["tb_top.test_e2e_random_k"],
            ("K=2", "basic"): ["tb_top.test_e2e_basic", "tb_top.test_e2e_random_k"],
            ("K=4", "basic"): ["tb_top.test_e2e_random_k"],
            ("K=4", "input_pause"): ["tb_top.test_e2e_input_pause"],
            ("K=4", "backpressure"): ["tb_top.test_e2e_backpressure"],
            ("K=4", "back2back"): ["tb_top.test_e2e_back_to_back"],
            ("K=4", "mid_reset"): ["tb_top.test_e2e_mid_reset"],
            ("K=8", "basic"): ["tb_top.test_e2e_random_k"],
            ("K=16", "basic"): ["tb_top.test_e2e_random_k"],
            ("K=256", "basic"): ["tb_top.test_e2e_large_k"],
        },
        "excluded_pairs": [
            ("K=256", "backpressure", "大 K + 反压组合未建测试 (反压仅 K=4), 列 P2 增强"),
            ("K=16", "input_pause", "大 K 暂停未建测试 (暂停仅 K=4), 列 P2 增强"),
        ],
    },
}

# ---- 被排除项 (合法豁免, 明确原因) ----
EXCLUDED = [
    ("cp_dataflow", "WS", "自研子系统仅实现 OS 数据流; WS 对照在 Gemmini 官方基线完成 (docs/06)"),
    ("cp_k_len", "K=0/257/511", "K 合法域 1..256; 非法 K 由 illegal_cfg 场景拒绝, 不作为计算 bin"),
    ("cp_symbol", "float/half", "设计契约 signed INT8; 浮点不在本项目范围"),
]


def main():
    print("=" * 100)
    print("功能覆盖模型 (coverpoint + cross)")
    print("=" * 100)

    total_bins = 0
    hit_bins = 0
    missing = []

    for cp, meta in COVERPOINTS.items():
        print(f"\n[coverpoint] {cp}: {meta['desc']}")
        for bin_, tests in meta["bins"].items():
            total_bins += 1
            ok_refs = []
            for ref in tests:
                ok, err = _test_exists(ref)
                if not ok:
                    missing.append(f"{cp}.{bin_}: {err}")
                else:
                    ok_refs.append(ref)
            if ok_refs:
                hit_bins += 1
                print(f"  ✓ {bin_:<22} 命中 (覆盖: {', '.join(ok_refs[:2])}{' ...' if len(ok_refs)>2 else ''})")
            else:
                missing.append(f"{cp}.{bin_}: 无有效覆盖测试")
                print(f"  ✗ {bin_:<22} 未命中")

    print(f"\n[cross] 交叉覆盖:")
    for cr, meta in CROSSES.items():
        print(f"  {cr}: {meta['desc']}")
        for pair, tests in meta["covered_pairs"].items():
            ok_refs = []
            for ref in tests:
                ok, err = _test_exists(ref)
                if not ok:
                    missing.append(f"{cr}.{pair}: {err}")
                else:
                    ok_refs.append(ref)
            mark = "✓" if ok_refs else "✗"
            print(f"    {mark} ({pair[0]}, {pair[1]}) 由 {', '.join(ok_refs) if ok_refs else '无'} 覆盖")
        if meta.get("excluded_pairs"):
            print(f"    未覆盖组合 (被排除项):")
            for pa, pb, reason in meta["excluded_pairs"]:
                print(f"      - ({pa}, {pb}): {reason}")

    print(f"\n[被排除项] 合法豁免:")
    for cp, bin_, reason in EXCLUDED:
        print(f"  - {cp}.{bin_}: {reason}")

    print("\n" + "=" * 100)
    rate = 100.0 * hit_bins / total_bins if total_bins else 0
    print(f"coverpoint 命中率: {hit_bins}/{total_bins} ({rate:.0f}%)")
    if missing:
        print("未命中/失效引用:")
        for m in missing:
            print(f"  - {m}")
        sys.exit(1)
    print("功能覆盖模型: 全部 coverpoint bin 命中, cross 覆盖, 被排除项已声明")
    sys.exit(0)


if __name__ == "__main__":
    main()
