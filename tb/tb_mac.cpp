// =============================================================
// tb_mac.cpp : Verilator testbench for INT8 MAC
// =============================================================
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vmac.h"
#include <cstdio>
#include <cstdint>

static vluint64_t sim_time = 0;
static int err_cnt = 0;

// 打一拍: 设 a,b,acc_in,en, 翻时钟, 返回沿后的 acc_out (int32 视角)
static int32_t do_mac(Vmac *dut, VerilatedVcdC *tfp,
                      int8_t a, int8_t b, int32_t acc_in, int en)
{
    dut->a = (uint8_t)a; // 补码比特直接塞进 8 位端口
    dut->b = (uint8_t)b;
    dut->acc_in = (uint32_t)acc_in;
    dut->en = en;
    dut->clk = 1;
    dut->eval();
    tfp->dump(sim_time++);
    int32_t out = (int32_t)dut->acc_out;
    dut->clk = 0;
    dut->eval();
    tfp->dump(sim_time++);
    return out;
}

static void check(int32_t got, int32_t want, const char *msg)
{
    if (got == want)
    {
        printf("  [PASS] %-28s acc=%d\n", msg, got);
    }
    else
    {
        printf("  [FAIL] %-28s got=%d want=%d\n", msg, got, want);
        err_cnt++;
    }
}

static void do_reset(Vmac *dut, VerilatedVcdC *tfp)
{
    dut->rst_n = 0;
    do_mac(dut, tfp, 0, 0, 0, 0);
    do_mac(dut, tfp, 0, 0, 0, 0);
    dut->rst_n = 1;
    do_mac(dut, tfp, 0, 0, 0, 0);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);

    Vmac *dut = new Vmac;

    Verilated::traceEverOn(true);
    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("mac.vcd");

    dut->clk = 0;
    dut->rst_n = 0;
    dut->a = 0;
    dut->b = 0;
    dut->acc_in = 0;
    dut->en = 0;

    printf("== Test 1: reset ==\n");
    do_reset(dut, tfp);
    check((int32_t)dut->acc_out, 0, "after reset");

    printf("== Test 2: basic & accumulate ==\n");
    int32_t r = do_mac(dut, tfp, 3, 4, 0, 1);
    check(r, 12, "3 x 4");
    r = do_mac(dut, tfp, -5, 6, r, 1);
    check(r, -18, "accum -5 x 6 -> 12-30");

    printf("== Test 3: INT8 boundaries ==\n");
    r = do_mac(dut, tfp, -128, -128, 0, 1);
    check(r, 16384, "-128 x -128");
    r = do_mac(dut, tfp, 127, 127, 0, 1);
    check(r, 16129, "127 x 127");
    r = do_mac(dut, tfp, -128, 127, 0, 1);
    check(r, -16256, "-128 x 127");

    printf("== Test 4: en=0 holds ==\n");
    r = do_mac(dut, tfp, 7, 7, 12345, 0); // 不使能: 输入无效, 应保持
    check(r, 12345, "en=0 hold");

    printf("== Test 5: 100x accumulate 127x127 ==\n");
    int32_t acc = 0;
    for (int i = 0; i < 100; i++)
        acc = do_mac(dut, tfp, 127, 127, acc, 1);
    check(acc, 100 * 16129, "100 x (127*127)");

    printf("== Test 6: reset clears ==\n");
    do_reset(dut, tfp);
    check((int32_t)dut->acc_out, 0, "reset clears acc");

    dut->final();
    tfp->close();
    delete dut;
    delete tfp;

    if (err_cnt == 0)
    {
        printf("\n========== ALL TESTS PASSED ==========\n");
        return 0;
    }
    else
    {
        printf("\n========== %d CHECKS FAILED ==========\n", err_cnt);
        return 1;
    }
}
