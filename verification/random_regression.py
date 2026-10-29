#!/usr/bin/env python3
# verification/random_regression.py : 批量随机回归
#   固定种子集合 × K{1,2,4,8,16} × PAIRS, 逐种子记录 PASS/FAIL 与 DUT 版本
#   用法: python3 verification/random_regression.py [--seeds 10] [--pairs 20] [--start 1]
#   目标口径: 每个关键配置 >= 100 个可复现随机种子 (如 --seeds 100 --pairs 1)
import argparse
import datetime
import json
import os
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
K_LIST = (1, 2, 4, 8, 16)


def git_rev():
    r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                       capture_output=True, text=True)
    return r.stdout.strip()


def run_seed(seed, pairs):
    env = dict(os.environ, SEED=str(seed), PAIRS=str(pairs))
    p = subprocess.run(["make", "sim_top_seeded"], cwd=REPO, env=env,
                       capture_output=True, text=True, timeout=600)
    tail = "\n".join(l for l in p.stdout.splitlines()
                     if "TESTS=" in l or "seeded regression" in l)
    return p.returncode == 0, tail


def main():
    ap = argparse.ArgumentParser(description="批量固定种子随机回归")
    ap.add_argument("--seeds", type=int, default=10, help="种子数 (每个种子跑 K_LIST x PAIRS 个 tile)")
    ap.add_argument("--pairs", type=int, default=20, help="每种 K 的随机 tile 对数")
    ap.add_argument("--start", type=int, default=1, help="起始种子编号")
    args = ap.parse_args()

    rev = git_rev()
    results = []
    t0 = datetime.datetime.now()
    for s in range(args.start, args.start + args.seeds):
        ok, tail = run_seed(s, args.pairs)
        results.append({"seed": s, "pairs": args.pairs, "pass": ok})
        print(f"seed={s}: {'PASS' if ok else 'FAIL'}")
        if not ok:
            print(tail)
            print("(stop on first failure for debugging)")
            break

    passed = sum(1 for r in results if r["pass"])
    os.makedirs(os.path.join(REPO, "logs"), exist_ok=True)
    report = {
        "dut_rev": rev,
        "cmd": "python3 verification/random_regression.py " + " ".join(sys.argv[1:]),
        "date": t0.isoformat(),
        "k_list": list(K_LIST),
        "results": results,
        "summary": {"passed": passed, "failed": len(results) - passed,
                    "tiles_per_seed": len(K_LIST) * args.pairs,
                    "total_tiles": len(results) * len(K_LIST) * args.pairs},
    }
    path = os.path.join(REPO, "logs", f"random_regression_{rev}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"{passed}/{len(results)} seeds passed -> {path}")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
