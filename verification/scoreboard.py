# verification/scoreboard.py : 可复用 Scoreboard 组件
#   黄金模型比对计分板: check_matrix 逐元素精确比对 (无浮点容差), 统计与报告

class Scoreboard:
    """逐元素精确比对计分板 (与 golden model 配套使用)

    log: 可调用日志对象 (默认 print); 报告前 max_detail 条失败明细
    """

    def __init__(self, log=None, name="scoreboard", max_detail=5):
        self.log = log or print
        self.name = name
        self.max_detail = max_detail
        self.checks = 0
        self.fails = 0

    def check(self, got, want, ctx=""):
        self.checks += 1
        if got != want:
            self.fails += 1
            if self.fails <= self.max_detail:
                self.log("[%s] MISMATCH %s: got %d, want %d", self.name, ctx, got, want)
            return False
        return True

    def check_matrix(self, got, want, tag):
        """按矩阵逐元素比对, 返回失败数"""
        fails = 0
        for i in range(len(want)):
            for j in range(len(want[i])):
                if not self.check(got[i][j], want[i][j], f"{tag}[{i}][{j}]"):
                    fails += 1
        return fails

    def summary(self):
        return f"{self.name}: {self.checks} checks, {self.fails} fails"
