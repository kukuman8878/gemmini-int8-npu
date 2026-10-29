#!/usr/bin/env python3
# verification/coverage_matrix.py : P0 覆盖矩阵核对
#   输出 V01-V12 用例 x 覆盖测试的矩阵, 并检查每个 bin 至少有一个覆盖项
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

COVERAGE = {
    "V01 零矩阵/单位阵": [
        "tb_systolic.test_zero_matrix", "tb_systolic.test_directed_identity",
        "tb_skew.test_zero", "tb_top.test_e2e_basic",
    ],
    "V02 符号混合": [
        "tb_mac.test_boundary", "tb_mac.test_random_mac",
        "tb_top.test_e2e_random_k",
    ],
    "V03 INT8 边界组合": [
        "tb_mac.test_boundary", "tb_mac.test_exhaustive_boundary",
        "tb_pe.test_accumulate",
    ],
    "V04 K 归约长度": [
        "tb_systolic.test_partial_k", "tb_skew.test_random_k",
        "tb_top.test_e2e_random_k", "tb_regression.test_seeded_random",
    ],
    "V05 零填充边界块": [
        "tb_skew.test_golden_2x2", "tb_top.test_e2e_basic",
    ],
    "V06 随机矩阵固定种子": [
        "tb_systolic.test_random_matmul", "tb_skew.test_random_k",
        "tb_top.test_e2e_random_k", "tb_regression.test_seeded_random",
    ],
    "V07 输入暂停/输出反压": [
        "tb_controller.test_load_stall_and_drain", "tb_controller.test_output_handshake",
        "tb_top.test_e2e_input_pause", "tb_top.test_e2e_backpressure",
    ],
    "V08 FIFO 空/满/同时读写/回绕": [
        "tb_fifo.test_fill_drain", "tb_fifo.test_overflow_reject",
        "tb_fifo.test_underflow_reject", "tb_fifo.test_simult_rw",
        "tb_fifo.test_pointer_wrap", "tb_fifo.test_random_handshake",
    ],
    "V09 连续任务": [
        "tb_systolic.test_back_to_back", "tb_skew.test_back_to_back",
        "tb_top.test_e2e_back_to_back",
    ],
    "V10 中途复位": [
        "tb_systolic.test_mid_reset", "tb_skew.test_mid_reset",
        "tb_top.test_e2e_mid_reset", "tb_fifo.test_reset",
        "tb_controller.test_reset_idle",
    ],
    "V11 非法配置/busy 时 start": [
        "tb_controller.test_illegal_cfg", "tb_controller.test_busy_reject",
        "tb_controller.test_reconfig_same_cycle", "tb_top.test_e2e_illegal_and_stale",
    ],
    "V12 故障注入": [
        "scripts/fault_injection.sh (en 门控变异, 期望回归 FAIL)",
        "多轮 agent 突变验证记录: docs/08_bug_log.md",
    ],
    "SVA 断言 A1-A6": [
        "tb/npu_top_assert.sv",
        "tb/pe_assert.sv",
        "tb/fifo_assert.sv",
        "make sim_top_sva / sim_pe_sva / sim_fifo_sva (Verilator --assert)",
    ],
}


def main():
    print(f"{'用例':<34} {'覆盖项数':<6} 覆盖测试")
    print("-" * 110)
    uncovered = []
    missing_refs = []
    for case, tests in COVERAGE.items():
        mark = "✓" if tests else "✗ 未覆盖"
        if not tests:
            uncovered.append(case)
        for ref in tests:
            # 校验 "tb_xxx.test_name" 与 "tb/xxx.sv" 形式的引用; 其余 (命令/说明) 跳过
            if re.match(r"^tb_[a-z0-9_]+\.[a-z0-9_]+$", ref):
                module, _, func = ref.rpartition(".")
                tb_path = os.path.join(REPO, "tb", module + ".py")
                if not os.path.isfile(tb_path):
                    missing_refs.append(f"{case}: {ref} (tb 文件不存在)")
                    continue
                with open(tb_path, encoding="utf-8") as f:
                    content = f.read()
                if not re.search(rf"^async def {re.escape(func)}\s*\(", content, re.M):
                    missing_refs.append(f"{case}: {ref}")
            elif re.match(r"^tb/[a-z0-9_]+\.sv$", ref):
                if not os.path.isfile(os.path.join(REPO, ref)):
                    missing_refs.append(f"{case}: {ref} (断言文件不存在)")
            else:
                continue
        print(f"{case:<32} {len(tests):<8} {', '.join(tests[:3])}"
              + (" ..." if len(tests) > 3 else ""))
    print("-" * 110)
    if uncovered or missing_refs:
        if uncovered:
            print(f"未覆盖 bin: {uncovered}")
        if missing_refs:
            print(f"失效引用 (测试名不存在): {missing_refs}")
        sys.exit(1)
    print("P0 覆盖矩阵: 全部 bin 至少一个覆盖项, 全部引用有效")
    sys.exit(0)


if __name__ == "__main__":
    main()
