# verification/golden_model.py : MAC 的黄金模型 (纯 Python)
# Python 整数天然支持任意精度有符号运算, 无需处理补码/符号扩展 —— 完美的"真理"

def mac_ref(acc, a, b, en):
    """参考模型: en=1 时 acc + a*b, en=0 时 acc 保持"""
    if en:
        return acc + a * b
    return acc


def matmul_ref(A, B):
    """参考模型: C = A x B (支持矩形, 纯 Python 整数, 教科书定义)"""
    rows = len(A)
    K = len(A[0])
    cols = len(B[0])
    C = [[0] * cols for _ in range(rows)]
    for i in range(rows):
        for j in range(cols):
            C[i][j] = sum(A[i][k] * B[k][j] for k in range(K))
    return C


if __name__ == "__main__":
    # 自检: 期望值来自已通过的 C++ 定向测试 (两个仿真器交叉验证过)
    vectors = [
        (0,     3,    4,    1, 12),        # 基本乘法
        (12,    -5,   6,    1, -18),       # 累加 + 负数
        (0,     -128, -128, 1, 16384),     # 负负得正最大乘积
        (0,     127,  127,  1, 16129),     # 最大正乘积
        (0,     -128, 127,  1, -16256),    # 最小负乘积
        (12345, 7,    7,    0, 12345),     # en=0 保持
    ]
    ok = True
    for acc, a, b, en, want in vectors:
        got = mac_ref(acc, a, b, en)
        mark = "PASS" if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  [{mark}] acc={acc:6d} a={a:5d} b={b:5d} en={en} -> {got} (want {want})")

    # 矩阵乘法自检: 单位阵 x 单位阵 = 单位阵; 全1 x 全1 = 全4
    I = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    O = [[1, 1, 1, 1]] * 4
    F = [[4, 4, 4, 4]] * 4
    for name, A, B, want in [("I x I", I, I, I), ("ones x ones", O, O, F)]:
        got = matmul_ref(A, B)
        mark = "PASS" if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  [{mark}] matmul {name}: got {got}")
    print("=" * 40)
    print("golden model self-check:", "ALL PASS" if ok else "HAS FAILURE")
