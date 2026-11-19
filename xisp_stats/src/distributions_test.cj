package ystyle::xisp_stats

import std.unittest.*
import std.unittest.testmacro.*
import std.math.*

/**
 * 分布函数族的测试
 *
 * ## 三套互相独立的证据
 *
 * 数值代码最怕「自己跟自己一致，但一起错」。所以这里的验证分三层，
 * 每层的错误来源不同：
 *
 * 1. **外部锚点** —— 三类完全独立的参照：
 *    - 正态：Python 标准库的 `math.erfc`（C 库实现，与本仓的 `gammaInc` 毫无关系）
 *    - 泊松 / 二项：逐项**精确求和**（定义式，不经过任何特殊函数）
 *    - t 分布 `df=1`：柯西分布解析式 `0.5 + atan(t)/π`；`df=2`：`0.5 + t/(2√(2+t²))`
 * 2. **跨分布恒等式** —— 数学上必然成立、实现上却走了不同代码路径的关系：
 *    - `χ²₁` 就是标准正态的平方：`chisqCdf(x,1) = 2·normCdf(√x) − 1`
 *    - `χ²_{2k}` 与泊松：`chisqCdf(x,2k) = 1 − poisCdf(k−1, x/2)`
 *    - `F(1,v)` 就是 `t(v)²`：`fDistCdf(x,1,v) = tCdf(√x,v) − tCdf(−√x,v)`
 * 3. **内部自洽** —— CDF 的数值导数必须等于 PDF；分位数反解回去必须落在原处。
 *
 * ## 容差为什么不是一个数
 *
 * - 精确求和 / 解析式的参照值：1e-14（浮点累积误差的量级）
 * - 数值积分的参照值：1e-8（Simpson 在重尾上只有这个精度）
 * - 统计表的分位数：1e-6（表上只给 6~7 位有效数字）
 * - 分位数互逆：1e-10（二分收敛到 1e-15 的相对精度，但 CDF 平坦处会放大）
 */

/** `Float64` 是否 NaN（`std.math` 没有 `isNaN`，用自身比较实现） */
func isNaNValue(v: Float64): Bool {
    v != v
}

func expectNaNValue(v: Float64, what: String): Unit {
    if (!isNaNValue(v)) {
        @Fail("${what}：期望 NaN，实际 ${v}")
    }
}

@Test
class NormDistTest {
    /**
     * 正态 CDF —— 参照 Python 标准库的 `math.erfc`
     *
     * 本仓的路径是 `normCdf → erfcOf → gammaIncUpper → gammaCF`（连分式）；
     * Python 的路径是 C 库的 `erfc`（Chebyshev 有理逼近）。两条完全不同的路走出同一个值，
     * 才说明 `erf(x) = Q(1/2, x²)` 这个换算没写错方向。
     */
    @TestCase
    func testNormCdfAgainstLibmErfc() {
        println("\n=== 正态 CDF（对照 Python 标准库 math.erfc）===")
        expectNear(normCdf(-2.5, 0.0, 1.0), 0.0062096653257761392, 1e-15, "Φ(−2.5)")
        expectNear(normCdf(-1.0, 0.0, 1.0), 0.15865525393145707, 1e-15, "Φ(−1)")
        expectNear(normCdf(0.0, 0.0, 1.0), 0.5, 1e-16, "Φ(0)")
        expectNear(normCdf(1.0, 0.0, 1.0), 0.84134474606854293, 1e-15, "Φ(1)")
        expectNear(normCdf(3.5, 0.0, 1.0), 0.99976737092096446, 1e-15, "Φ(3.5)")
        // 非标准参数化：μ=100, σ=15（IQ 尺度）
        expectNear(normCdf(70.0, 100.0, 15.0), 0.022750131948179216, 1e-15, "Φ(70; 100,15)")
        expectNear(normCdf(100.0, 100.0, 15.0), 0.5, 1e-16, "Φ(100; 100,15)")
    }

    /** 正态 PDF */
    @TestCase
    func testNormPdf() {
        println("\n=== 正态 PDF ===")
        expectNear(normPdf(-3.0, 0.0, 1.0), 0.0044318484119380075, 1e-17, "φ(−3)")
        expectNear(normPdf(0.0, 0.0, 1.0), 0.3989422804014327, 1e-16, "φ(0)")
        expectNear(normPdf(2.0, 0.0, 1.0), 0.053990966513188063, 1e-17, "φ(2)")
        // 尺度变换：φ(x/σ)/σ
        expectNear(normPdf(115.0, 100.0, 15.0), normPdf(1.0, 0.0, 1.0) / 15.0, 1e-17, "φ(115;100,15)")
    }

    /**
     * 正态分位数 —— 对照标准正态表
     *
     * `Φ⁻¹(0.975) = 1.959964` 是 95% 置信区间里那个 1.96，任何统计教材都有。
     */
    @TestCase
    func testNormQuantile() {
        println("\n=== 正态分位数 ===")
        expectNear(normQuantile(0.975, 0.0, 1.0), 1.959963984540054, 1e-9, "Φ⁻¹(0.975)")
        expectNear(normQuantile(0.5, 0.0, 1.0), 0.0, 1e-10, "Φ⁻¹(0.5)")
        expectNear(normQuantile(0.025, 0.0, 1.0), -1.959963984540054, 1e-9, "Φ⁻¹(0.025)")
        // 对称性：Φ⁻¹(p) = −Φ⁻¹(1−p)
        let a = normQuantile(0.99, 0.0, 1.0)
        let b = normQuantile(0.01, 0.0, 1.0)
        expectNear(a + b, 0.0, 1e-9, "Φ⁻¹ 对称")
        // 尺度：Φ⁻¹(p; μ,σ) = μ + σ·Φ⁻¹(p)
        expectNear(normQuantile(0.975, 100.0, 15.0), 100.0 + 15.0 * 1.959963984540054, 1e-8, "Φ⁻¹(0.975;100,15)")
    }
}

@Test
class StudentTDistTest {
    /**
     * t 分布 CDF —— 用 `df=1` / `df=2` 的**闭式解**当锚点
     *
     * - `df=1` 是柯西分布：`F(t) = 0.5 + atan(t)/π`
     * - `df=2`：`F(t) = 0.5 + t/(2√(2+t²))`
     *
     * 这两个是初等函数，与 `betaInc`（连分式）没有任何共同代码。
     * 它们对上了，就说明 `tCdf` 里 `I_x(df/2, 1/2)` 的参数化是对的 ——
     * 而这正是最容易搞反的地方（`x = df/(df+t²)` 的分子分母、正负半轴该取 0.5·I 还是 1−0.5·I）。
     */
    @TestCase
    func testTCdfClosedForms() {
        println("\n=== t 分布 CDF（df=1 柯西、df=2 闭式解）===")
        expectNear(tDistCdf(-2.0, 1.0), 0.14758361765043326, 1e-14, "F_t(−2; df=1)")
        expectNear(tDistCdf(-1.0, 1.0), 0.25, 1e-14, "F_t(−1; df=1)")
        expectNear(tDistCdf(1.0, 1.0), 0.75, 1e-14, "F_t(1; df=1)")
        expectNear(tDistCdf(2.0, 1.0), 0.85241638234956674, 1e-14, "F_t(2; df=1)")
        expectNear(tDistCdf(-2.0, 2.0), 0.091751709536136927, 1e-14, "F_t(−2; df=2)")
        expectNear(tDistCdf(-1.0, 2.0), 0.21132486540518708, 1e-14, "F_t(−1; df=2)")
        expectNear(tDistCdf(1.0, 2.0), 0.78867513459481287, 1e-14, "F_t(1; df=2)")
        expectNear(tDistCdf(2.0, 2.0), 0.90824829046386313, 1e-14, "F_t(2; df=2)")
    }

    /** 对称性 `F(−t) = 1 − F(t)`；`df` 越大越接近正态 */
    @TestCase
    func testTSymmetryAndNormalLimit() {
        println("\n=== t 的对称性与正态极限 ===")
        for (df in [1.0, 5.0, 30.0, 200.0]) {
            let lo = tDistCdf(-1.5, df)
            let hi = tDistCdf(1.5, df)
            expectNear(lo + hi, 1.0, 1e-15, "F(−1.5)+F(1.5), df=${df}")
        }
        // df=10000 时 t 与正态的差 < 3e-5（Berry–Esseen 给的上界），用来确认趋势方向对
        let bigDf = tDistCdf(2.0, 10000.0)
        expectNear(bigDf, normCdf(2.0, 0.0, 1.0), 5e-4, "df→∞ 趋近正态")
    }

    /** t 的 PDF（闭式解，无积分误差） */
    @TestCase
    func testTPdf() {
        println("\n=== t 分布 PDF ===")
        // df=1 时是柯西密度 1/(π(1+t²))
        expectNear(tDistPdf(0.0, 1.0), 1.0 / Float64.getPI(), 1e-15, "f_t(0; df=1)")
        expectNear(tDistPdf(1.0, 1.0), 1.0 / (2.0 * Float64.getPI()), 1e-15, "f_t(1; df=1)")
        // 一般 df
        expectNear(tDistPdf(0.0, 5.0), 0.37960668982249413, 1e-14, "f_t(0; df=5)")
        expectNear(tDistPdf(1.0, 5.0), 0.21967979735098042, 1e-14, "f_t(1; df=5)")
        expectNear(tDistPdf(2.0, 5.0), 0.0650903103262164, 1e-14, "f_t(2; df=5)")
        expectNear(tDistPdf(0.0, 30.0), 0.39563218489409546, 1e-14, "f_t(0; df=30)")
    }

    /**
     * t 分位数 —— 对照教科书 t 表
     *
     * 这几个数字是任何统计教材附录里的：`t_{0.975,5} = 2.5706`、`t_{0.975,30} = 2.0423`。
     * 表上只给到 7 位，所以容差 1e-6。
     */
    @TestCase
    func testTQuantileAgainstTable() {
        println("\n=== t 分位数（教科书表）===")
        expectNear(tDistQuantile(0.975, 5.0), 2.570581835636, 1e-6, "t_{0.975,5}")
        expectNear(tDistQuantile(0.975, 10.0), 2.228138852, 1e-6, "t_{0.975,10}")
        expectNear(tDistQuantile(0.975, 30.0), 2.042272456, 1e-6, "t_{0.975,30}")
        expectNear(tDistQuantile(0.95, 5.0), 2.015048373, 1e-6, "t_{0.95,5}")
        expectNear(tDistQuantile(0.5, 7.0), 0.0, 1e-10, "t_{0.5,7}")
        // df=1 时 t 就是柯西：t_{0.975,1} = tan(π·0.475) = 12.706
        expectNear(tDistQuantile(0.975, 1.0), 12.706204736174707, 1e-6, "t_{0.975,1}")
    }
}

@Test
class ChisqDistTest {
    /**
     * 卡方 CDF —— 三路夹击
     *
     * 1. `df=2` 有解析式 `1 − e^{−x/2}`
     * 2. 与正态的关系 `chisqCdf(x,1) = 2·Φ(√x) − 1`
     * 3. 与泊松的关系 `chisqCdf(x,2k) = 1 − poisCdf(k−1, x/2)`
     *
     * 第 3 条最有价值：两条路径分别走不完全 Gamma 的**级数**和**连分式**
     * （`chisqCdf` 与 `poisCdf` 在 `x < a+1` 时一个用 `P` 一个用 `Q`），
     * 交叉验证能同时抓住两个方向的错误。
     */
    @TestCase
    func testChisqCdfCrossChecks() {
        println("\n=== 卡方 CDF（解析式 + 正态 + 泊松三路交叉）===")
        // df=2 解析：1 − exp(−x/2)
        expectNear(chisqCdf(0.5, 2.0), 1.0 - exp(-0.25), 1e-15, "χ²(0.5; df=2)")
        expectNear(chisqCdf(10.0, 2.0), 1.0 - exp(-5.0), 1e-15, "χ²(10; df=2)")
        expectNear(chisqCdf(3.841458820694124, 2.0), 1.0 - exp(-3.841458820694124 / 2.0), 1e-15,
            "χ²(3.8415; df=2)")

        // df=1 与正态：χ²₁ 就是 Z²
        for (x in [0.5, 1.0, 3.841458820694124, 10.0]) {
            let viaNorm = 2.0 * normCdf(sqrt(x), 0.0, 1.0) - 1.0
            expectNear(chisqCdf(x, 1.0), viaNorm, 1e-14, "χ²(${x}; df=1) = 2Φ(√x)−1")
        }

        // df=2k 与泊松：P(χ²_{2k} ≤ x) = P(N ≥ k), N ~ Poisson(x/2)
        for ((k, x) in [(2, 10.0), (3, 10.0), (5, 20.0)]) {
            let viaPois = 1.0 - poisCdf(k - 1, x / 2.0)
            expectNear(chisqCdf(x, Float64(2 * k)), viaPois, 1e-13, "χ²(${x}; df=${2*k}) = 1−Poisson")
        }
    }

    /** 卡方 CDF 的一般 df（数值积分参照值） */
    @TestCase
    func testChisqCdfGeneralDf() {
        println("\n=== 卡方 CDF（一般 df）===")
        expectNear(chisqCdf(0.5, 4.0), 0.026499021160744169, 1e-12, "χ²(0.5; df=4)")
        expectNear(chisqCdf(10.0, 4.0), 0.95957231800551168, 1e-12, "χ²(10; df=4)")
        expectNear(chisqCdf(3.841458820694124, 4.0), 0.57211295303773901, 1e-12, "χ²(3.8415; df=4)")
        expectNear(chisqCdf(10.0, 10.0), 0.55950671493478876, 1e-12, "χ²(10; df=10)")
        expectNear(chisqCdf(3.841458820694124, 10.0), 0.045784270445334417, 1e-12, "χ²(3.8415; df=10)")
        // 深左尾：df=10 时 0.5 处的概率只有 6.6e-6，走的是级数分支，相对精度要足够
        expectNear(chisqCdf(0.5, 10.0), 6.6117105610341899e-06, 1e-15, "χ²(0.5; df=10) 深尾")
    }

    /** 卡方 PDF（闭式解）与端点极限 */
    @TestCase
    func testChisqPdf() {
        println("\n=== 卡方 PDF ===")
        expectNear(chisqPdf(1.0, 4.0), 0.15163266492815836, 1e-16, "f(1; df=4)")
        expectNear(chisqPdf(5.0, 4.0), 0.10260624827987348, 1e-16, "f(5; df=4)")
        expectNear(chisqPdf(1.0, 10.0), 0.00078975346316749202, 1e-17, "f(1; df=10)")
        expectNear(chisqPdf(5.0, 10.0), 0.066800942890542669, 1e-16, "f(5; df=10)")
        // 端点：df=2 时 f(0) = 1/(2·Γ(1)) = 0.5
        expectNear(chisqPdf(0.0, 2.0), 0.5, 1e-16, "f(0; df=2)")
        // df>2 时 f(0) = 0；df<2 时发散到 +∞
        expectNear(chisqPdf(0.0, 4.0), 0.0, 1e-16, "f(0; df=4)")
        if (!(chisqPdf(0.0, 1.0) > 1e300)) {
            @Fail("f(0; df=1) 应发散到 +∞")
        }
    }

    /** 卡方分位数 —— 对照卡方表 */
    @TestCase
    func testChisqQuantileAgainstTable() {
        println("\n=== 卡方分位数（教科书表）===")
        expectNear(chisqQuantile(0.95, 1.0), 3.841458820694124, 1e-6, "χ²_{0.95,1}")
        expectNear(chisqQuantile(0.95, 2.0), 5.991464547107979, 1e-6, "χ²_{0.95,2}")
        expectNear(chisqQuantile(0.95, 4.0), 9.487729036781154, 1e-6, "χ²_{0.95,4}")
        expectNear(chisqQuantile(0.95, 10.0), 18.30703805327515, 1e-6, "χ²_{0.95,10}")
        expectNear(chisqQuantile(0.5, 2.0), 2.0 * log(2.0), 1e-9, "χ²_{0.5,2} = 2ln2")
    }
}

@Test
class FDistTest {
    /**
     * F 分布 CDF —— 与 t 的关系式当锚点
     *
     * `T ~ t(v)` 时 `T² ~ F(1,v)`，所以
     * `F_{F}(x; 1,v) = F_t(√x; v) − F_t(−√x; v)`。
     *
     * 这条尤其能抓参数化的错：`fDistCdf` 走的是 `I_{d1x/(d1x+d2)}(d1/2, d2/2)`，
     * 而 `tCdf` 走的是 `I_{df/(df+t²)}(df/2, 1/2)` —— 两套换元都要对，结果才能处处相等。
     */
    @TestCase
    func testFCdfAgainstTRelation() {
        println("\n=== F 分布 CDF（与 t 的关系式交叉）===")
        for ((v, x) in [(10.0, 1.0), (10.0, 2.0), (10.0, 4.964602956185408), (20.0, 1.0), (20.0, 3.098391212)]) {
            let viaT = tDistCdf(sqrt(x), v) - tDistCdf(-sqrt(x), v)
            expectNear(fDistCdf(x, 1.0, v), viaT, 1e-14, "F(${x}; 1,${v}) = t² 关系")
        }
    }

    /** F 的一般自由度（数值积分参照值） */
    @TestCase
    func testFCdfGeneral() {
        println("\n=== F 分布 CDF（一般自由度）===")
        expectNear(fDistCdf(1.0, 3.0, 20.0), 0.58674808398645284, 1e-7, "F(1; 3,20)")
        expectNear(fDistCdf(2.0, 3.0, 20.0), 0.85356119139484543, 1e-7, "F(2; 3,20)")
        expectNear(fDistCdf(4.964602956185408, 3.0, 20.0), 0.99021249988140714, 1e-7, "F(4.9646; 3,20)")
        // 退化情形：d1=d2=∞ 时 F 退化成 1 处的点质量，但有限大自由度下 CDF(1) 应接近 0.5
        expectNear(fDistCdf(1.0, 200.0, 200.0), 0.5, 0.01, "F(1; 200,200) ≈ 0.5")
    }

    /** F 的 PDF */
    @TestCase
    func testFPdf() {
        println("\n=== F 分布 PDF ===")
        expectNear(fDistPdf(1.0, 3.0, 20.0), 0.43085353159465328, 1e-13, "f(1; 3,20)")
        expectNear(fDistPdf(2.0, 3.0, 20.0), 0.14877202261762443, 1e-13, "f(2; 3,20)")
        // d1=2 时 f(0) 的极限恰为 1（推导见 distributions.cj 的注释）
        expectNear(fDistPdf(0.0, 2.0, 10.0), 1.0, 1e-16, "f(0; 2,10)")
    }

    /** F 分位数 —— 对照 F 表 */
    @TestCase
    func testFQuantileAgainstTable() {
        println("\n=== F 分位数（教科书表）===")
        expectNear(fDistQuantile(0.95, 1.0, 10.0), 4.964602956185408, 1e-6, "F_{0.95}(1,10)")
        expectNear(fDistQuantile(0.95, 3.0, 20.0), 3.098391212, 1e-6, "F_{0.95}(3,20)")
        expectNear(fDistQuantile(0.95, 2.0, 10.0), 4.102821015, 1e-6, "F_{0.95}(2,10)")
    }
}

@Test
class PoisDistTest {
    /**
     * 泊松 —— 对照**逐项精确求和**
     *
     * 参照值不经过任何特殊函数：`Σ_{i=0}^{k} e^{−λ}λ^i/i!`，用 Python 的
     * `math.exp` + `math.lgamma` 直接算。本仓走的却是 `Q(k+1, λ)`（连分式）。
     * 两条路差得越远，对上了越说明 `P(X≤k) = Q(k+1,λ)` 这个恒等式用得对。
     */
    @TestCase
    func testPoisPmfAndCdf() {
        println("\n=== 泊松分布（λ=2.5，对照精确求和）===")
        let lam = 2.5
        let pmfs = [0.0820849986238988, 0.20521249655974699, 0.25651562069968387,
            0.2137630172497364, 0.13360188578108539]
        let cdfs = [0.0820849986238988, 0.28729749518364578, 0.5438131158833297,
            0.75757613313306604, 0.89117801891415149]
        var i: Int64 = 0
        while (i < 5) {
            expectNear(poisPmf(i, lam), pmfs[i], 1e-15, "P(X=${i})")
            expectNear(poisCdf(i, lam), cdfs[i], 1e-15, "P(X≤${i})")
            i++
        }
        // 全域求和 = 1（到 k=40 时尾部已经 < 1e-20）
        expectNear(poisCdf(40, lam), 1.0, 1e-14, "Σ P(X=k) = 1")
        // 退化：λ=0 时概率全部压在 0 上
        expectNear(poisPmf(0, 0.0), 1.0, 1e-16, "λ=0 的 P(X=0)")
        expectNear(poisPmf(3, 0.0), 0.0, 1e-16, "λ=0 的 P(X=3)")
    }

    /** 泊松分位数：最小 `k` 使 `CDF(k) ≥ p` */
    @TestCase
    func testPoisQuantile() {
        println("\n=== 泊松分位数 ===")
        // λ=2.5：CDF(4)=0.8912 < 0.95 ≤ CDF(5)=0.9580
        if (poisQuantile(0.95, 2.5) != 5) {
            @Fail("Pois_{0.95}(2.5) 应为 5，实际 ${poisQuantile(0.95, 2.5)}")
        }
        if (poisQuantile(0.5, 2.5) != 2) {
            @Fail("Pois_{0.5}(2.5) 应为 2，实际 ${poisQuantile(0.5, 2.5)}")
        }
        // 大 λ：分位数应贴近 λ + z·√λ ≈ 100 + 1.645·10 = 116.4
        let big = poisQuantile(0.95, 100.0)
        if (big < 114 || big > 119) {
            @Fail("Pois_{0.95}(100) 应在 114~119，实际 ${big}")
        }
    }
}

@Test
class BinomDistTest {
    /**
     * 二项 —— 对照**逐项精确求和**
     *
     * 本仓走 `I_{1−p}(n−k, k+1)`（不完全 Beta），参照值是
     * `Σ C(n,i)p^i(1−p)^{n−i}`。这也是 `fDistCdf` 之外的第二个 Beta 换元使用者，
     * 两者一起对，说明 `betaInc` 的参数顺序没错。
     */
    @TestCase
    func testBinomPmfAndCdf() {
        println("\n=== 二项分布（n=10, p=0.3，对照精确求和）===")
        let pmfs = [0.02824752489999998, 0.12106082100000007, 0.23347444049999977,
            0.26682793199999943, 0.20012094899999941, 0.10291934519999965]
        let cdfs = [0.02824752489999998, 0.14930834590000006, 0.38278278639999985,
            0.64961071839999929, 0.84973166739999872, 0.9526510125999984]
        var i: Int64 = 0
        while (i < 6) {
            expectNear(binomPmf(i, 10, 0.3), pmfs[i], 1e-15, "P(X=${i})")
            expectNear(binomCdf(i, 10, 0.3), cdfs[i], 1e-14, "P(X≤${i})")
            i++
        }
        // 端点：k ≥ n 时 CDF = 1（不经过 betaInc，直接给）
        expectNear(binomCdf(10, 10, 0.3), 1.0, 1e-16, "P(X≤10)")
        expectNear(binomCdf(20, 10, 0.3), 1.0, 1e-16, "P(X≤20)")
        expectNear(binomCdf(-1, 10, 0.3), 0.0, 1e-16, "P(X≤−1)")
        // 全域求和 = 1
        expectNear(binomCdf(10, 10, 0.3), 1.0, 1e-16, "Σ P(X=k) = 1")
        // 对称性：B(n,p) 的 k 与 B(n,1−p) 的 n−k 同分布
        expectNear(binomPmf(3, 10, 0.3), binomPmf(7, 10, 0.7), 1e-15, "p ↔ 1−p 对称")
    }

    /** 二项分位数 */
    @TestCase
    func testBinomQuantile() {
        println("\n=== 二项分位数 ===")
        // CDF(4)=0.8497 < 0.95 ≤ CDF(5)=0.9527
        if (binomQuantile(0.95, 10, 0.3) != 5) {
            @Fail("Binom_{0.95}(10,0.3) 应为 5，实际 ${binomQuantile(0.95, 10, 0.3)}")
        }
        if (binomQuantile(0.5, 10, 0.3) != 3) {
            @Fail("Binom_{0.5}(10,0.3) 应为 3，实际 ${binomQuantile(0.5, 10, 0.3)}")
        }
        if (binomQuantile(0.99, 10, 0.3) != 7) {
            @Fail("Binom_{0.99}(10,0.3) 应为 7，实际 ${binomQuantile(0.99, 10, 0.3)}")
        }
    }
}

@Test
class DensityCdfConsistencyTest {
    /**
     * CDF 的数值导数必须等于 PDF
     *
     * 这条不依赖任何外部参照，却能同时钉住两个函数：`PDF` 写错了会被抓到，
     * `CDF` 写错了（比如参数化换了方向）也会被抓到。两者必须**同时**错得互相抵消
     * 才能骗过它，而那种巧合极难发生。
     *
     * 中心差分误差 `O(h²) + O(ε/h)`，取 `h = 1e-6·(1+|x|)` 时约 1e-10。
     */
    @TestCase
    func testCdfDerivativeEqualsPdf() {
        println("\n=== CDF 导数 = PDF（全部连续分布）===")
        // 正态
        let h = 1e-6
        for (x in [-2.0, -0.5, 0.5, 2.0]) {
            let d = (normCdf(x + h, 0.0, 1.0) - normCdf(x - h, 0.0, 1.0)) / (2.0 * h)
            expectNear(d, normPdf(x, 0.0, 1.0), 1e-7, "dΦ/dx @ ${x}")
        }
        // t（选 df 让 pdf 在测试点良态）
        for ((x, df) in [(-1.5, 5.0), (0.3, 5.0), (1.2, 30.0), (-2.0, 10.0)]) {
            let d = (tDistCdf(x + h, df) - tDistCdf(x - h, df)) / (2.0 * h)
            expectNear(d, tDistPdf(x, df), 1e-7, "dF_t/dx @ ${x}, df=${df}")
        }
        // 卡方
        for ((x, df) in [(1.0, 4.0), (3.0, 4.0), (5.0, 10.0), (12.0, 10.0)]) {
            let d = (chisqCdf(x + h, df) - chisqCdf(x - h, df)) / (2.0 * h)
            expectNear(d, chisqPdf(x, df), 1e-7, "dχ²/dx @ ${x}, df=${df}")
        }
        // F
        for ((x, d1, d2) in [(1.0, 3.0, 20.0), (2.5, 3.0, 20.0), (0.8, 5.0, 15.0)]) {
            let d = (fDistCdf(x + h, d1, d2) - fDistCdf(x - h, d1, d2)) / (2.0 * h)
            expectNear(d, fDistPdf(x, d1, d2), 1e-7, "dF/dx @ ${x}, (${d1},${d2})")
        }
    }

    /** 泊松的 PMF 差分 = PDF（离散版的同一件事） */
    @TestCase
    func testPoisPmfIsCdfDifference() {
        println("\n=== 泊松 PMF = CDF 差 ===")
        let lam = 3.7
        var k: Int64 = 0
        while (k < 8) {
            let diff = poisCdf(k, lam) - poisCdf(k - 1, lam)
            expectNear(diff, poisPmf(k, lam), 1e-14, "P(X=${k}) 差分")
            k++
        }
    }

    /** 二项的 PMF 差分 = PDF */
    @TestCase
    func testBinomPmfIsCdfDifference() {
        println("\n=== 二项 PMF = CDF 差 ===")
        var k: Int64 = 0
        while (k <= 12) {
            let diff = binomCdf(k, 12, 0.45) - binomCdf(k - 1, 12, 0.45)
            expectNear(diff, binomPmf(k, 12, 0.45), 1e-14, "P(X=${k}) 差分")
            k++
        }
    }

    /**
     * 分位数反解回 CDF 必须落在原处
     *
     * 这是分位数算法唯一的真检验：二分写错了（比如单调方向搞反）会直接在这里暴露。
     */
    @TestCase
    func testQuantileRoundTrip() {
        println("\n=== 分位数互逆 ===")
        for (p in [1e-6, 0.01, 0.25, 0.5, 0.75, 0.99, 1.0 - 1e-6]) {
            expectNear(normCdf(normQuantile(p, 0.0, 1.0), 0.0, 1.0), p, 1e-12, "正态 p=${p}")
        }
        for (p in [0.001, 0.025, 0.5, 0.975, 0.999]) {
            expectNear(tDistCdf(tDistQuantile(p, 5.0), 5.0), p, 1e-10, "t(df=5) p=${p}")
            expectNear(tDistCdf(tDistQuantile(p, 1.0), 1.0), p, 1e-10, "t(df=1) p=${p}")
            expectNear(chisqCdf(chisqQuantile(p, 4.0), 4.0), p, 1e-10, "卡方(df=4) p=${p}")
            expectNear(fDistCdf(fDistQuantile(p, 3.0, 20.0), 3.0, 20.0), p, 1e-10, "F(3,20) p=${p}")
        }
    }
}

@Test
class DistributionsEdgeCaseTest {
    /** 非法参数一律 NaN，不抛异常也不返回垃圾值 */
    @TestCase
    func testInvalidParamsGiveNaN() {
        println("\n=== 非法参数 ===")
        expectNaNValue(normCdf(0.0, 0.0, 0.0), "σ=0 的 Φ")
        expectNaNValue(normCdf(0.0, 0.0, -1.0), "σ<0 的 Φ")
        expectNaNValue(normPdf(0.0, 0.0, 0.0), "σ=0 的 φ")
        expectNaNValue(normQuantile(0.0, 0.0, 1.0), "p=0 的 Φ⁻¹")
        expectNaNValue(normQuantile(1.0, 0.0, 1.0), "p=1 的 Φ⁻¹")
        expectNaNValue(tDistCdf(1.0, 0.0), "df=0 的 t CDF")
        expectNaNValue(tDistPdf(1.0, -2.0), "df<0 的 t PDF")
        expectNaNValue(chisqCdf(-1.0, 4.0), "x<0 的 χ² CDF")
        expectNaNValue(chisqPdf(1.0, 0.0), "df=0 的 χ² PDF")
        expectNaNValue(fDistCdf(-0.5, 3.0, 20.0), "x<0 的 F CDF")
        expectNaNValue(fDistCdf(1.0, 0.0, 20.0), "d1=0 的 F CDF")
        expectNaNValue(poisPmf(-1, 2.5), "k<0 的泊松 PMF")
        expectNaNValue(poisCdf(1, -1.0), "λ<0 的泊松 CDF")
        expectNaNValue(binomPmf(11, 10, 0.3), "k>n 的二项 PMF")
        expectNaNValue(binomCdf(2, 10, 1.5), "p>1 的二项 CDF")
    }

    /** 分位数的非法输入返回 -1（离散分布没有 NaN 可以返回） */
    @TestCase
    func testDiscreteQuantileInvalid() {
        println("\n=== 离散分位数的非法输入 ===")
        if (poisQuantile(0.0, 2.5) != -1) {
            @Fail("p=0 的泊松分位数应为 -1")
        }
        if (poisQuantile(0.95, -1.0) != -1) {
            @Fail("λ<0 的泊松分位数应为 -1")
        }
        if (binomQuantile(1.5, 10, 0.3) != -1) {
            @Fail("p>1 的二项分位数应为 -1")
        }
    }
}
