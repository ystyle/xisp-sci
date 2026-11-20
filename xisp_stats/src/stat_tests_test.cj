package ystyle::xisp_stats

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.HashMap
import std.math.*

/**
 * 第二批假设检验的白盒测试
 *
 * ## 参照值从哪来
 *
 * 统计量（χ²、F、U）都是**闭式公式**，能手算或独立用 Python 算；
 * p 值需要一个分布的 CDF —— 这里用的是独立实现的数值积分（Python 侧），
 * 与本仓的 `gammaInc` / `betaInc` 路径完全不同。
 *
 * 两边算法不同却给出同一个答案，才是「算对了」的证据。
 */

func f2(v: LispValue, key: String): Float64 {
    match (v) {
        case HashMap(m) => match (m.get(key)) {
            case Some(Float(x)) => x
            case Some(Int(x)) => Float64(x)
            case _ => Float64.getNaN()
        }
        case _ => Float64.getNaN()
    }
}

func s2(v: LispValue, key: String): String {
    match (v) {
        case HashMap(m) => match (m.get(key)) {
            case Some(Str(x)) => x
            case _ => ""
        }
        case _ => ""
    }
}

func near2(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

@Test
class CorTestTest {
    /**
     * 相关显著性：`r = 0.9833, n = 10` → `t = 15.297, df = 8, p = 3.31e-7`
     *
     * p 值极小是因为这份数据几乎是一条直线 —— 正好演示「r 高不代表一定显著，
     * 但 r 高到这个程度就一定是真的」的另一面。
     */
    @TestCase
    func testCorTest() {
        println("\n=== 相关显著性 ===")
        let x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
        let y = [2.0, 3.0, 3.0, 4.0, 5.0, 5.0, 6.0, 7.0, 7.0, 9.0]
        let r = corTest(x, y)
        near2(f2(r, "r"), 0.98333216603563345, 1e-14, "r")
        near2(f2(r, "t"), 15.297058540778355, 1e-12, "t")
        near2(f2(r, "df"), 8.0, 1e-15, "df")
        near2(f2(r, "p"), 3.3096529050702372e-07, 1e-9, "p")
        near2(f2(r, "n"), 10.0, 0.0, "n")
    }

    /** 完全相关时 t 发散、p = 0，不能返回 NaN */
    @TestCase
    func testPerfectCorrelation() {
        println("\n=== 完全相关 ===")
        let x = [1.0, 2.0, 3.0, 4.0]
        let y = [2.0, 4.0, 6.0, 8.0]
        let r = corTest(x, y)
        near2(f2(r, "r"), 1.0, 1e-14, "r = 1")
        near2(f2(r, "p"), 0.0, 0.0, "p = 0")
    }

    /** 成对删除缺失值 */
    @TestCase
    func testPairwiseNaN() {
        println("\n=== 成对删除 ===")
        let x = [1.0, 2.0, Float64.getNaN(), 4.0, 5.0]
        let y = [2.0, 4.0, 6.0, Float64.getNaN(), 10.0]
        let r = corTest(x, y)
        // 只剩 3 对：(1,2) (2,4) (5,10)
        near2(f2(r, "n"), 3.0, 0.0, "有效对数")
    }

    /** 长度不等 / 样本太少要报错 */
    @TestCase
    func testCorTestErrors() {
        println("\n=== 相关检验的报错 ===")
        var caught = false
        try {
            corTest([1.0, 2.0, 3.0], [1.0, 2.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("长度不等应报错")
        }
        caught = false
        try {
            corTest([1.0, 2.0], [3.0, 4.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("少于 3 对应报错")
        }
    }
}

@Test
class ChisqTestTest {
    /**
     * 拟合优度：`obs = [10,20,30]`、`exp = [20,20,20]`
     *
     * `χ² = (100 + 0 + 100)/20 = 10`，`df = 2`，`p = e^{-5} ≈ 0.006738`
     * —— `χ²(2)` 的 CDF 有解析式 `1 − e^{−x/2}`，所以这个 p 值是精确的。
     */
    @TestCase
    func testGof() {
        println("\n=== 卡方拟合优度 ===")
        let r = chisqGof([10.0, 20.0, 30.0], [20.0, 20.0, 20.0])
        near2(f2(r, "stat"), 10.0, 1e-14, "χ²")
        near2(f2(r, "df"), 2.0, 1e-14, "df")
        near2(f2(r, "p"), 0.0067379469991074581, 1e-12, "p")
    }

    /** 不传期望时按均匀分布 —— 「这批数据是不是均匀的」的直接形式 */
    @TestCase
    func testGofUniform() {
        println("\n=== 均匀假设 ===")
        let r = chisqGofUniform([10.0, 10.0, 10.0, 10.0])
        near2(f2(r, "stat"), 0.0, 1e-14, "完全均匀时 χ² = 0")
        near2(f2(r, "p"), 1.0, 1e-14, "完全均匀时 p = 1")
    }

    /**
     * 独立性：`[[20,30],[30,20]]`
     *
     * 期望全是 25，`χ² = 4×(−5)²/25 = 4`，`df = 1`。
     * `χ²(1)` 就是标准正态的平方，所以 `p = 2(1−Φ(2)) = 0.0455003`。
     */
    @TestCase
    func testIndependence() {
        println("\n=== 卡方独立性 ===")
        let table = [[20.0, 30.0], [30.0, 20.0]]
        let r = chisqIndep(table)
        near2(f2(r, "stat"), 4.0, 1e-14, "χ²")
        near2(f2(r, "df"), 1.0, 1e-14, "df")
        near2(f2(r, "p"), 0.045500263896358417, 1e-12, "p")
        near2(f2(r, "rows"), 2.0, 0.0, "行数")
        near2(f2(r, "cols"), 2.0, 0.0, "列数")
    }

    /** 期望频数为 0 / 负频数要报错 */
    @TestCase
    func testChisqErrors() {
        println("\n=== 卡方的报错 ===")
        var caught = false
        try {
            chisqGof([10.0, 20.0], [20.0, 0.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("期望频数为 0 应报错")
        }
        caught = false
        try {
            chisqIndep([[10.0, -1.0], [5.0, 6.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("负频数应报错")
        }
    }
}

@Test
class WilcoxTestTest {
    /**
     * 精确检验：`x = [1,2,3]`、`y = [4,5,6]` 完全分离
     *
     * 三三组合共 `C(6,3) = 20` 种秩分配，U 取到 0（最极端）的方案只有 1 种，
     * 双侧 p = 2/20 = 0.1。这就是「完全分离但样本太小，还不足以显著」的经典例子
     * —— 6 个样本的两组，哪怕一点重叠都没有，p 也到不了 0.05。
     */
    @TestCase
    func testExactWilcox() {
        println("\n=== 秩和检验（精确）===")
        let r = wilcoxTest([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
        near2(f2(r, "w"), 6.0, 1e-14, "第一组秩和")
        near2(f2(r, "u"), 0.0, 1e-14, "U")
        near2(f2(r, "p"), 0.1, 1e-14, "精确 p")
        if (s2(r, "method") != "exact") {
            @Fail("无并列且样本小时应走精确分布，实际 ${s2(r, "method")}")
        }
    }

    /** 完全不分离（两组合并后交错）时 U 接近平衡 */
    @TestCase
    func testOverlapping() {
        println("\n=== 完全交错 ===")
        let r = wilcoxTest([1.0, 3.0, 5.0], [2.0, 4.0, 6.0])
        // W = 1+2+3 = 6，U1 = 6 - 6 = 0 ... 不对：秩是 [1,3,5]，W = 1+3+5 = 9
        near2(f2(r, "w"), 9.0, 1e-14, "交错时的秩和")
        // U1 = 9 - 6 = 3 = n1n2/2，正好在平衡点。
        //
        // 注意这里 p **不是 1**：精确分布是离散的，U 取到平衡点的概率只有
        // 3/20，所以双侧 p = 2·P(U ≤ 3) = 2·7/20 = 0.7。这是离散检验的固有特性，
        // 不是 bug —— 连续分布（如 t 检验）才有「统计量为 0 时 p 恰好为 1」。
        near2(f2(r, "p"), 0.7, 1e-14, "精确双侧 p")
    }

    /** 有并列时精确分布不再适用，退回正态近似（带并列校正） */
    @TestCase
    func testTiesFallback() {
        println("\n=== 并列 → 正态近似 ===")
        let r = wilcoxTest([1.0, 2.0, 2.0, 3.0, 4.0], [2.0, 3.0, 3.0, 4.0, 5.0])
        let m = s2(r, "method")
        if (m != "normal-approx-ties") {
            @Fail("含并列时应走带校正的正态近似，实际 `${m}`")
        }
        let p = f2(r, "p")
        if (!(p > 0.0 && p <= 1.0)) {
            @Fail("p 应落在 (0,1]，实际 ${p}")
        }
    }

    /** 空组要报错 */
    @TestCase
    func testWilcoxErrors() {
        println("\n=== 秩和检验的报错 ===")
        var caught = false
        try {
            wilcoxTest(Array<Float64>(0, repeat: 0.0), [1.0, 2.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("空组应报错")
        }
    }
}

@Test
class AnovaTest {
    /**
     * 单因素方差分析：三组各 6 个观测
     *
     * `SSB = 84`、`SSW = 68`、`F = 9.2647`、`df = (2, 15)`、`p = 0.0024`。
     * 手工可算：组均值 5.0 / 9.0 / 10.0，总均值 8.0。
     */
    @TestCase
    func testAnova() {
        println("\n=== 单因素方差分析 ===")
        let g1 = [6.0, 8.0, 4.0, 5.0, 3.0, 4.0]
        let g2 = [8.0, 12.0, 9.0, 11.0, 6.0, 8.0]
        let g3 = [13.0, 9.0, 11.0, 8.0, 7.0, 12.0]
        let r = anovaOf([g1, g2, g3])
        near2(f2(r, "ss-between"), 84.0, 1e-12, "SSB")
        near2(f2(r, "ss-within"), 68.0, 1e-12, "SSW")
        near2(f2(r, "f"), 9.264705882352942, 1e-12, "F")
        near2(f2(r, "df1"), 2.0, 1e-14, "df1")
        near2(f2(r, "df2"), 15.0, 1e-14, "df2")
        near2(f2(r, "p"), 0.0023987773294105175, 1e-12, "p")
        near2(f2(r, "n"), 18.0, 0.0, "总观测数")
    }

    /**
     * 两组时 ANOVA 与两样本 t 检验必须一致：`F = t²`
     *
     * 这不是巧合 —— 两组情形下 `F(1, n1+n2−2)` 就是 `t(n1+n2−2)` 的平方。
     * 两条**完全不同的代码路径**给出自洽的结果，是这个实现最有力的验证。
     */
    @TestCase
    func testAnovaEqualsTSquared() {
        println("\n=== ANOVA 与 t 检验的一致性 ===")
        let a = [2.0, 4.0, 5.0, 6.0, 7.0]
        let b = [3.0, 5.0, 6.0, 7.0, 9.0]
        let r = anovaOf([a, b])
        let f = f2(r, "f")
        let tRes = tTestTwo(a, b)
        let t = f2(tRes, "t")
        near2(f, t * t, 1e-10, "F = t²")
        // 两组时 Welch 的 df 与 ANOVA 的 df 不一定相等（方差不等时），所以只比 p 的量级
        let pA = f2(r, "p")
        if (!(pA > 0.0 && pA < 1.0)) {
            @Fail("p 应在 (0,1)，实际 ${pA}")
        }
    }

    /** 只有 1 组 / 组内方差为 0 要报错 */
    @TestCase
    func testAnovaErrors() {
        println("\n=== ANOVA 的报错 ===")
        var caught = false
        try {
            anovaOf([[1.0, 2.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("只有 1 组应报错")
        }
        caught = false
        try {
            anovaOf([[1.0, 1.0], [2.0, 2.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("组内方差为 0 应报错")
        }
    }
}

@Test
class RobustStatsTest {
    /** `mad`：中位数绝对偏差 */
    @TestCase
    func testMad() {
        println("\n=== 中位数绝对偏差 ===")
        // median([1,2,3,4,5]) = 3；|x-3| = [2,1,0,1,2]；median = 1
        near2(madOf([1.0, 2.0, 3.0, 4.0, 5.0]), 1.0, 1e-14, "MAD")
        // 离群点：MAD 几乎不动，标准差会被拉爆
        let clean = [1.0, 2.0, 3.0, 4.0, 5.0]
        let dirty = [1.0, 2.0, 3.0, 4.0, 1000.0]
        near2(madOf(dirty), 1.0, 1e-14, "含离群点的 MAD 仍然是 1")
        // 对照：标准差变化巨大
        let sdClean = sqrt(varianceOf(finiteOf(clean), 1))
        let sdDirty = sqrt(varianceOf(finiteOf(dirty), 1))
        if (!(sdDirty > sdClean * 100.0)) {
            @Fail("标准差应被离群点拉到百倍以上（${sdClean} → ${sdDirty}）")
        }
    }

    /** `range`：极差 */
    @TestCase
    func testRange() {
        println("\n=== 极差 ===")
        near2(rangeOf([1.0, 5.0, 3.0]), 4.0, 1e-14, "range([1,5,3])")
        near2(rangeOf([7.0]), 0.0, 1e-14, "单元素极差为 0")
        // 跳过 NaN
        near2(rangeOf([1.0, Float64.getNaN(), 9.0]), 8.0, 1e-14, "跳过 NaN")
    }
}
