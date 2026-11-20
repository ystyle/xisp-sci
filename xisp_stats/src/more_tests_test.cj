package ystyle::xisp_stats

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.HashMap
import std.math.*

/**
 * 第三批检验的白盒测试
 *
 * ## 参照值从哪来
 *
 * 统计量（F、χ²、Q、W、K²、D）都是闭式公式，能手算；p 值需要一个分布的 CDF ——
 * 这里用 Python 侧**独立实现**的同一套公式算出来作对照（分布尾部用数值积分
 * 或精确求和，与本仓的 `gammaInc` / `betaInc` 路径不同）。
 *
 * 顺带记一个自己踩的坑：正态性检验的峰度分支里有个三次根，底数**可能是负的**，
 * 用 `exp(log(x)/3)` 会静默退化成 0（`log` 对负底数无意义），把 p 值从 0.28
 * 压到 1e-104 还不报错。所以那里专门写了 `cbrtOf`，测试也钉住了正常量级的 p。
 */

func fld(v: LispValue, key: String): Float64 {
    match (v) {
        case HashMap(m) => match (m.get(key)) {
            case Some(Float(x)) => x
            case Some(Int(x)) => Float64(x)
            case _ => Float64.getNaN()
        }
        case _ => Float64.getNaN()
    }
}

func meth(v: LispValue): String {
    match (v) {
        case HashMap(m) => match (m.get("method")) {
            case Some(Str(x)) => x
            case _ => ""
        }
        case _ => ""
    }
}

func ck(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

@Test
class VarTestTest {
    /** F 检验：两组方差比 */
    @TestCase
    func testVarTest() {
        println("\n=== 方差比 F 检验 ===")
        let x = [2.1, 2.5, 2.9, 3.2, 2.8, 3.0]
        let y = [4.1, 5.2, 4.8, 5.5, 4.2, 5.0]
        let r = varTest(x, y)
        ck(fld(r, "var1"), 0.155, 1e-12, "第一组方差")
        ck(fld(r, "var2"), 0.308, 1e-12, "第二组方差")
        ck(fld(r, "f"), 0.50324675324675305, 1e-12, "F")
        ck(fld(r, "df1"), 5.0, 1e-15, "df1")
        ck(fld(r, "df2"), 5.0, 1e-15, "df2")
        ck(fld(r, "p"), 0.46912637013253006, 1e-10, "p")
    }

    /** 两组方差相同 → F = 1，p = 1 */
    @TestCase
    func testEqualVariance() {
        println("\n=== 方差相同时 F ≈ 1 ===")
        let r = varTest([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0])
        ck(fld(r, "f"), 1.0, 1e-14, "F")
        ck(fld(r, "p"), 1.0, 1e-10, "p")
    }
}

@Test
class ProportionTestTest {
    /** 精确二项检验：`k=7, n=10, p₀=0.5` → p = 0.34375 */
    @TestCase
    func testBinomTest() {
        println("\n=== 精确二项检验 ===")
        let r = binomTest(7, 10, 0.5)
        ck(fld(r, "p"), 0.34375, 1e-12, "p")
        ck(fld(r, "estimate"), 0.7, 1e-15, "估计值")
        // 观测正好等于零假设时 p 应为 1
        let r2 = binomTest(5, 10, 0.5)
        ck(fld(r2, "p"), 1.0, 1e-10, "k 等于期望时 p = 1")
    }

    /** 两样本比例检验（带连续性校正） */
    @TestCase
    func testPropTest() {
        println("\n=== 两样本比例检验 ===")
        let r = propTest(45, 100, 30, 100)
        ck(fld(r, "p1"), 0.45, 1e-15, "p1")
        ck(fld(r, "p2"), 0.30, 1e-15, "p2")
        ck(fld(r, "pooled"), 0.375, 1e-15, "合并比例")
        ck(fld(r, "z"), 2.0448308813526204, 1e-10, "z")
        ck(fld(r, "p"), 0.040871534089006234, 1e-10, "p")
    }

    /** 两组比例相同时 z = 0、p = 1 */
    @TestCase
    func testSameProportion() {
        println("\n=== 比例相同时 p = 1 ===")
        let r = propTest(30, 100, 30, 100)
        ck(fld(r, "p"), 1.0, 1e-10, "p")
    }
}

@Test
class SignedRankTestTest {
    /**
     * 精确分支：6 个全正的差值
     *
     * `W⁻ = 0` 是最极端的情形。6 个秩的零分布共 `2⁶ = 64` 种，
     * 只有一种能让 `W⁻ = 0`，所以双侧 `p = 2/64 = 0.03125`。
     */
    @TestCase
    func testExact() {
        println("\n=== 符号秩检验（精确）===")
        let x = [1.2, 2.5, 3.1, 4.8, 5.2, 6.0]
        let y = [1.0, 2.0, 2.5, 4.0, 4.5, 5.0]
        let r = signedRankTest(x, y)
        ck(fld(r, "w"), 21.0, 1e-12, "W⁺")
        ck(fld(r, "w2"), 0.0, 1e-12, "W⁻")
        ck(fld(r, "p"), 0.03125, 1e-12, "精确 p")
        if (meth(r) != "exact") {
            @Fail("无并列的小样本应走精确分布，实际 ${meth(r)}")
        }
    }

    /**
     * 并列分支：走正态近似 + 并列校正
     *
     * `|d|` 里 0.2 出现两次、0.5 出现三次，秩是 1.5 和 4。
     * 注意 `W⁻` 只有 1.5，但 `p = 0.129` 而不是 0.03 —— 因为样本只有 5 对，
     * **精确分布的最小可能 p 也只有 2/32 = 0.0625**，小样本本来就很难显著。
     */
    @TestCase
    func testTies() {
        println("\n=== 符号秩检验（并列）===")
        let x = [1.5, 2.0, 3.5, 4.0, 5.5]
        let y = [1.0, 2.2, 3.0, 3.8, 5.0]
        let r = signedRankTest(x, y)
        ck(fld(r, "w"), 13.5, 1e-12, "W⁺")
        ck(fld(r, "w2"), 1.5, 1e-12, "W⁻")
        ck(fld(r, "z"), 1.5181442305531794, 1e-9, "z")
        ck(fld(r, "p"), 0.12897804299196425, 1e-10, "p")
        if (meth(r) != "normal-approx-ties") {
            @Fail("含并列应走带校正的正态近似，实际 ${meth(r)}")
        }
    }

    /** 差值为 0 的观测被丢弃；全为 0 时报错 */
    @TestCase
    func testZeroDifferences() {
        println("\n=== 零差值处理 ===")
        let r = signedRankTest([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 5.0])
        // 只剩 (4,5) 一对
        ck(fld(r, "n"), 1.0, 0.0, "有效对数")
        var caught = false
        try {
            signedRankTest([1.0, 2.0], [1.0, 2.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("全部差值为 0 应报错")
        }
    }
}

@Test
class KruskalTestTest {
    /**
     * 三组完全分离：`H = 7.2`，`p = e^{−3.6} = 0.0273`
     *
     * 手算：N=9，秩和 6 / 15 / 24，
     * `H = 12/(9·10)·(36/3 + 225/3 + 576/3) − 3·10 = 37.2 − 30 = 7.2`。
     * `χ²(2)` 的 CDF 是 `1 − e^{−x/2}`，所以 p 是精确的。
     */
    @TestCase
    func testKruskal() {
        println("\n=== Kruskal-Wallis ===")
        let r = kruskalTest([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]])
        ck(fld(r, "h"), 7.2, 1e-12, "H")
        ck(fld(r, "df"), 2.0, 1e-15, "df")
        ck(fld(r, "p"), 0.027323722447292521, 1e-12, "p")
    }

    /** 三组数据交错但没有差异 → H 接近 0 */
    @TestCase
    func testNoDifference() {
        println("\n=== 无差异时 H 接近 0 ===")
        let r = kruskalTest([[1.0, 2.0, 3.0], [1.0, 2.0, 3.0], [1.0, 2.0, 3.0]])
        ck(fld(r, "h"), 0.0, 1e-12, "H")
        ck(fld(r, "p"), 1.0, 1e-12, "p")
        if (!meth(r).contains("ties")) {
            @Fail("完全相同的三组必然有并列，应走并列校正，实际 ${meth(r)}")
        }
    }

    /** 只有 1 组 / 空组报错 */
    @TestCase
    func testKruskalErrors() {
        println("\n=== Kruskal 的报错 ===")
        var caught = false
        try {
            kruskalTest([[1.0, 2.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("只有 1 组应报错")
        }
    }
}

@Test
class FriedmanTestTest {
    /**
     * 3 区组 × 3 处理，每个区组内的排序都是 `1,2,3`
     *
     * 各列秩和 3 / 6 / 9，`Q = 12/(3·3·4)·(9+36+81) − 3·3·4 = 42 − 36 = 6`，
     * p = e^{−3} = 0.0498。
     */
    @TestCase
    func testFriedman() {
        println("\n=== Friedman ===")
        let table = [
            [1.0, 2.0, 3.0],
            [2.0, 4.0, 6.0],
            [10.0, 20.0, 30.0]]
        let r = friedmanTest(table)
        ck(fld(r, "q"), 6.0, 1e-12, "Q")
        ck(fld(r, "df"), 2.0, 1e-15, "df")
        ck(fld(r, "p"), 0.049787068367863944, 1e-12, "p")
    }

    /** 处理之间没有系统差异时 Q 接近 0 */
    @TestCase
    func testNoEffect() {
        println("\n=== 无处理效应时 Q 接近 0 ===")
        let table = [
            [1.0, 2.0, 3.0],
            [3.0, 1.0, 2.0],
            [2.0, 3.0, 1.0]]
        let r = friedmanTest(table)
        ck(fld(r, "q"), 0.0, 1e-12, "Q")
    }

    /** 少于 3 个处理报错（2 个处理时应该用符号检验） */
    @TestCase
    func testFriedmanErrors() {
        println("\n=== Friedman 的报错 ===")
        var caught = false
        try {
            friedmanTest([[1.0, 2.0], [2.0, 1.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("只有 2 个处理应报错")
        }
    }
}

@Test
class FisherTestTest {
    /**
     * `[[3,1],[1,3]]`：`p = 34/70 = 0.4857`，优势比 = 9
     *
     * 超几何：`C(8,4) = 70` 种表格，概率分布是 1/16/36/16/1（除 70）。
     * 观测表 `x=3` 的概率 16/70，不比它更可能的是 `x=0,1,3,4` 四格，
     * 合计 `(1+16+16+1)/70 = 34/70`。
     */
    @TestCase
    func testFisher() {
        println("\n=== Fisher 精确检验 ===")
        let r = fisherTest([[3.0, 1.0], [1.0, 3.0]])
        ck(fld(r, "p"), 0.48571428571428571, 1e-12, "双侧 p")
        ck(fld(r, "p-less"), 0.98571428571428565, 1e-12, "左侧 p")
        ck(fld(r, "p-greater"), 0.24285714285714285, 1e-12, "右侧 p")
        ck(fld(r, "odds-ratio"), 9.0, 1e-12, "优势比")
    }

    /** 完全分离的表：p 很小 */
    @TestCase
    func testPerfectSeparation() {
        println("\n=== 完全分离的 2×2 表 ===")
        let r = fisherTest([[10.0, 0.0], [0.0, 10.0]])
        if (!(fld(r, "p") < 1e-4)) {
            @Fail("完全分离时 p 应很小，实际 ${fld(r, "p")}")
        }
        // inf 不能用 |a−b| ≤ tol 比较（inf − inf = NaN），单独判
        if (!(fld(r, "odds-ratio") > 1e300)) {
            @Fail("完全分离时优势比应为 inf，实际 ${fld(r, "odds-ratio")}")
        }
    }

    /** 非 2×2 的表报错（应改用 chisq-test） */
    @TestCase
    func testFisherErrors() {
        println("\n=== Fisher 的报错 ===")
        var caught = false
        try {
            fisherTest([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("非 2×2 表应报错")
        }
    }
}

@Test
class KsTestTest {
    /**
     * 两样本完全分离：`D = 1`、`λ = √5 ≈ 2.236`、`p ≈ 9.08e-5`
     *
     * 渐近公式 `Q(λ) = 2·Σ(−1)^{j−1}e^{−2j²λ²}`，`λ` 这么大时第一项就主导。
     */
    @TestCase
    func testSeparated() {
        println("\n=== K-S 检验（完全分离）===")
        let x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
        let y = [11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0]
        let r = ksTwoSample(x, y)
        ck(fld(r, "d"), 1.0, 1e-14, "D")
        ck(fld(r, "p"), 9.0799859524961048e-05, 1e-12, "p")
    }

    /** 两组来自同一批值 → D = 0、p = 1 */
    @TestCase
    func testIdentical() {
        println("\n=== 两组相同 → D = 0 ===")
        let v = [1.0, 2.0, 3.0, 4.0, 5.0]
        let r = ksTwoSample(v, v)
        ck(fld(r, "d"), 0.0, 1e-14, "D")
        ck(fld(r, "p"), 1.0, 1e-14, "p")
    }

    /** 部分重叠：D 应落在 (0,1) */
    @TestCase
    func testPartialOverlap() {
        println("\n=== 部分重叠 ===")
        let r = ksTwoSample([1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 3.0, 4.0, 5.0, 6.0])
        let d = fld(r, "d")
        ck(d, 0.2, 1e-14, "D")
        if (!(fld(r, "p") > 0.9)) {
            @Fail("这么大的 D 配这么小的样本，p 应该接近 1，实际 ${fld(r, "p")}")
        }
    }
}

@Test
class NormalityTestTest {
    /**
     * 正态数据：`K² = 2.51`、`p = 0.285`（不拒绝正态）
     *
     * 数据是 `np.random.seed(0); np.random.randn(30)`（取了 6 位小数）。
     * 参照值由 Python 侧按同一套 D'Agostino 公式独立算出。
     */
    @TestCase
    func testNormalData() {
        println("\n=== 正态性检验（正态数据）===")
        let v = [
            1.764052, 0.400157, 0.978738, 2.240893, 1.867558,
            -0.977278, 0.950088, -0.151357, -0.103219, 0.410599,
            0.144044, 1.454274, 0.761038, 0.121675, 0.443863,
            0.333674, 1.494079, -0.205158, 0.313068, -0.854096,
            -2.552990, 0.653619, 0.864436, -0.742165, 2.269755,
            -1.454366, 0.045759, -0.187184, 1.532779, 1.469359]
        let r = normalityTest(v)
        ck(fld(r, "skew"), -0.50983482873845576, 1e-9, "偏度")
        ck(fld(r, "kurtosis"), 0.32683213504392938, 1e-9, "超额峰度")
        ck(fld(r, "z-skew"), -1.2927059705378112, 1e-9, "Z1")
        ck(fld(r, "z-kurt"), 0.91756222898874729, 1e-9, "Z2")
        ck(fld(r, "k2"), 2.513009170330903, 1e-9, "K²")
        ck(fld(r, "p"), 0.28464724984442308, 1e-9, "p")
        if (meth(r) != "dagostino-pearson") {
            @Fail("方法应为 dagostino-pearson，实际 ${meth(r)}")
        }
    }

    /**
     * 偏态数据（指数分布）：`p = 0.031`，在 0.05 水平上拒绝正态
     *
     * 这条同时是**三次根那个坑的回归测试**：如果峰度分支里的负底数被当成 0，
     * Z2 会从 1.02 飙到 22.6，p 从 0.031 掉到 1e-113 —— 一个明显到不合理的数量级差。
     */
    @TestCase
    func testSkewedData() {
        println("\n=== 正态性检验（偏态数据）===")
        let v = [
            0.795875, 1.255931, 0.923223, 0.787201, 0.551048,
            1.038159, 0.575519, 2.223524, 3.314912, 0.483602,
            1.568896, 0.752674, 0.839433, 2.598254, 0.073685,
            0.091161, 0.020426, 1.787488, 1.505784, 2.040314,
            3.845222, 1.605240, 0.618929, 1.516536, 0.125874,
            1.021432, 0.154730, 2.894420, 0.737827, 0.535566]
        let r = normalityTest(v)
        ck(fld(r, "skew"), 1.0356044096401367, 1e-9, "偏度")
        ck(fld(r, "z-kurt"), 1.0236145698946402, 1e-9, "Z2")
        ck(fld(r, "k2"), 6.9295548653167227, 1e-9, "K²")
        ck(fld(r, "p"), 0.031279966550645577, 1e-9, "p")
        // Z2 必须在个位数——如果三次根退化，它会变成几十
        if (!(fld(r, "z-kurt") < 10.0)) {
            @Fail("Z2 大得离谱（${fld(r, "z-kurt")}），三次根那里很可能又退化了")
        }
    }

    /** 样本太少 / 方差为 0 报错 */
    @TestCase
    func testNormalityErrors() {
        println("\n=== 正态性检验的报错 ===")
        var caught = false
        try {
            normalityTest([1.0, 2.0, 3.0, 4.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("少于 8 个观测应报错")
        }
        caught = false
        try {
            normalityTest([5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("方差为 0 应报错")
        }
    }
}
