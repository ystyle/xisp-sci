package ystyle::xisp_stats

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * t 分布与假设检验的白盒测试
 *
 * ## 为什么先测 tCritical
 *
 * 整套 p 值都建立在「t 分布算得对」上。如果 tCritical 系统性偏小，所有 p 值都会偏小，
 * 于是**什么都"显著"** —— 这种错误最难发现，因为结果看起来"有发现"。
 *
 * 所以第一条测试就是拿**教科书 t 分位数表**逐个对：
 * df=1 时 12.706、df=30 时 2.042 —— 这些数字在任何统计教材的附录里都能查到。
 */

func expectNear(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}（差 ${abs(actual - want)}）")
    }
}

@Test
class GammaTest {
    /**
     * `log Γ(x)` 的已知值
     *
     * `Γ(1)=Γ(2)=1`、`Γ(5)=24`、`Γ(1/2)=√π`
     */
    @TestCase
    func testLogGammaKnownValues() {
        println("\n=== log Γ 已知值 ===")
        expectNear(lgammaOf(1.0), 0.0, 1e-12, "Γ(1)")
        expectNear(lgammaOf(2.0), 0.0, 1e-12, "Γ(2)")
        expectNear(lgammaOf(5.0), log(24.0), 1e-12, "Γ(5)=24")
        expectNear(lgammaOf(0.5), log(sqrt(Float64.getPI())), 1e-12, "Γ(1/2)=√π")
        // 递推：Γ(x+1) = x·Γ(x)
        expectNear(lgammaOf(6.5), lgammaOf(5.5) + log(5.5), 1e-12, "递推关系")
        println("✓ Γ(1)/Γ(2)/Γ(5)/Γ(1/2) 与递推关系都正确")
    }

    /** 不完全 Beta 的边界 */
    @TestCase
    func testBetaIncBoundaries() {
        println("\n=== 不完全 Beta 边界 ===")
        expectNear(betaInc(2.0, 3.0, 0.0), 0.0, 1e-15, "x=0")
        expectNear(betaInc(2.0, 3.0, 1.0), 1.0, 1e-15, "x=1")
        // 对称性：I_x(a,b) = 1 - I_{1-x}(b,a)
        let l = betaInc(2.0, 3.0, 0.3)
        let r = 1.0 - betaInc(3.0, 2.0, 0.7)
        expectNear(l, r, 1e-12, "对称性")
        println("✓ 边界与对称性")
    }
}

@Test
class TDistTest {
    /**
     * **双侧 α=0.05 的临界值 —— 教科书 t 分位数表**
     *
     * 这是整个 p 值体系的锚点。表值取自任何统计教材附录。
     */
    @TestCase
    func testCriticalValuesMatchTable() {
        println("\n=== t 分位数表（双侧 α=0.05） ===")
        let table: Array<(Float64, Float64)> = [
            (1.0, 12.706), (2.0, 4.303), (3.0, 3.182), (4.0, 2.776),
            (5.0, 2.571), (10.0, 2.228), (15.0, 2.131), (20.0, 2.086),
            (30.0, 2.042), (60.0, 2.000), (120.0, 1.980)]
        for ((df, want) in table) {
            let got = tCritical(0.05, df)
            println("  df=${Int64(df)}: ${got}（表值 ${want}）")
            expectNear(got, want, 1e-3, "df=${Int64(df)}")
        }
        // 自由度趋于无穷时接近正态的 1.96
        let inf = tCritical(0.05, 1e7)
        expectNear(inf, 1.960, 1e-3, "大自由度趋近 1.96")
        println("✓ 11 个自由度全部与表值一致（容差 1e-3）")
    }

    /** CDF 的基本性质 */
    @TestCase
    func testCdfProperties() {
        println("\n=== CDF 性质 ===")
        // 中心对称
        expectNear(tCdf(0.0, 10.0), 0.5, 1e-12, "t=0 时 CDF=0.5")
        expectNear(tCdf(-2.0, 10.0) + tCdf(2.0, 10.0), 1.0, 1e-10, "对称性")
        // 单调递增
        if (tCdf(1.0, 10.0) >= tCdf(2.0, 10.0)) {
            @Fail("CDF 应单调递增")
        }
        // t 分布比正态厚尾：同样的 t 值，df 越小尾越厚
        if (!(tCdf(2.0, 5.0) < tCdf(2.0, 100.0))) {
            @Fail("df 越小尾应越厚：tCdf(2,5) 应小于 tCdf(2,100)")
        }
        println("✓ 对称、单调、厚尾性质都对")
    }

    /** 双侧 p 值 */
    @TestCase
    func testTwoSidedP() {
        println("\n=== 双侧 p 值 ===")
        // t=0 时 p=1
        expectNear(tTwoSidedP(0.0, 10.0), 1.0, 1e-12, "t=0 → p=1")
        // t 等于临界值时 p 等于 alpha
        let tc = tCritical(0.05, 10.0)
        expectNear(tTwoSidedP(tc, 10.0), 0.05, 1e-9, "临界值处 p=0.05")
        println("✓ p 值与临界值互相印证")
    }
}

@Test
class TTestTest {
    /**
     * 单样本检验：手工可算的例子
     *
     * `x = [1,2,3,4,5]`，`μ0 = 3`：均值 3、s = √2.5、n = 5
     * → `t = 0`，`p = 1`
     */
    @TestCase
    func testOneSampleHandComputed() {
        println("\n=== 单样本（手算） ===")
        let x: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0]
        let r = tTestOne(x, 3.0)
        let t = getF(r, "t")
        let p = getF(r, "p")
        expectNear(t, 0.0, 1e-12, "均值为 3 时 t=0")
        expectNear(p, 1.0, 1e-12, "p=1")
        // μ0 = 4：t = (3-4)/(√2.5/√5) = -1/√0.5 = -1.4142
        let r2 = tTestOne(x, 4.0)
        expectNear(getF(r2, "t"), -1.0 / sqrt(0.5), 1e-12, "μ0=4 时 t")
        println("✓ t 与 p 与手算一致")
    }

    /**
     * 双样本 Welch：两组明显不同时 p 应该很小
     */
    @TestCase
    func testTwoSampleClearDifference() {
        println("\n=== 双样本（明显差异） ===")
        let a: Array<Float64> = [10.0, 11.0, 12.0, 13.0, 14.0]
        let b: Array<Float64> = [20.0, 21.0, 22.0, 23.0, 24.0]
        let r = tTestTwo(a, b)
        let p = getF(r, "p")
        if (p > 1e-4) {
            @Fail("两组差 10、方差相同，p 应远小于 1e-4，实际 ${p}")
        }
        if (getF(r, "t") >= 0.0) {
            @Fail("a 的均值小，t 应为负")
        }
        println("✓ p = ${p}（远小于 0.05）")
    }

    /**
     * 双样本：两组几乎一样时 p 应该很大
     */
    @TestCase
    func testTwoSampleNoDifference() {
        println("\n=== 双样本（无差异） ===")
        let a: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0]
        let b: Array<Float64> = [1.1, 2.1, 3.1, 4.1, 5.1]
        let p = getF(tTestTwo(a, b), "p")
        if (p < 0.1) {
            @Fail("两组几乎相同，p 应该很大，实际 ${p}")
        }
        println("✓ p = ${p}（不显著）")
    }

    /** 样本太少要报错 */
    @TestCase
    func testTooFewSamples() {
        println("\n=== 样本过少 ===")
        var caught = false
        try {
            tTestOne([1.0], 0.0)
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("单样本应报错")
        }
        println("✓ 单样本报错")
    }

    /** 所有值相同时标准误为 0，要报错而不是给 inf */
    @TestCase
    func testZeroVariance() {
        println("\n=== 零方差 ===")
        var caught = false
        try {
            tTestOne([5.0, 5.0, 5.0], 3.0)
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("零方差应报错")
        }
        println("✓ 零方差报错（不返回 inf）")
    }
}

@Test
class ConfidenceIntervalTest {
    /**
     * 置信区间的宽度关系
     *
     * 95% 区间必须比 90% 宽 —— 这是置信水平定义最直接的体现。
     */
    @TestCase
    func testWidthOrdering() {
        println("\n=== 区间宽度 ===")
        let x: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
        let w90 = getF(confidenceInterval(x, 0.90), "hi") - getF(confidenceInterval(x, 0.90), "lo")
        let w95 = getF(confidenceInterval(x, 0.95), "hi") - getF(confidenceInterval(x, 0.95), "lo")
        let w99 = getF(confidenceInterval(x, 0.99), "hi") - getF(confidenceInterval(x, 0.99), "lo")
        if (!(w90 < w95 && w95 < w99)) {
            @Fail("区间宽度应随置信水平单调增加：90%=${w90}, 95%=${w95}, 99%=${w99}")
        }
        println("✓ 90% < 95% < 99%（${w90} < ${w95} < ${w99}）")
    }

    /** 区间必须包含样本均值 */
    @TestCase
    func testContainsMean() {
        println("\n=== 包含均值 ===")
        let x: Array<Float64> = [2.0, 4.0, 6.0, 8.0]
        let r = confidenceInterval(x, 0.95)
        let m = getF(r, "mean")
        let lo = getF(r, "lo")
        let hi = getF(r, "hi")
        if (!(lo < m && m < hi)) {
            @Fail("区间应包含均值：lo=${lo}, mean=${m}, hi=${hi}")
        }
        // 对称
        expectNear(m - lo, hi - m, 1e-12, "区间关于均值对称")
        println("✓ 区间包含均值且对称")
    }

    @TestCase
    func testInvalidLevel() {
        println("\n=== 非法置信水平 ===")
        for (lv in [0.0, 1.0, -0.5, 1.5]) {
            var caught = false
            try {
                confidenceInterval([1.0, 2.0, 3.0], lv)
            } catch (e: IllegalArgumentException) {
                caught = true
            }
            if (!caught) {
                @Fail("置信水平 ${lv} 应报错")
            }
        }
        println("✓ 0 / 1 / 负数 / 大于 1 都报错")
    }
}

/** 从检验结果的 HashMap 里取浮点字段 */
func getF(v: LispValue, key: String): Float64 {
    match (v) {
        case HashMap(m) =>
            match (m.get(key)) {
                case Some(Float(x)) => x
                case Some(Int(i)) => Float64(i)
                case _ => Float64.getNaN()
            }
        case _ => Float64.getNaN()
    }
}
