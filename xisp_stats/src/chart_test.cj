package ystyle::xisp_stats

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import std.math.*

/**
 * 图表数据的白盒测试
 *
 * 箱线图的**须**是「围栏内最远的实际数据点」而不是最小/最大值 —— 这是最容易记错的
 * 一个约定，测试直接钉住它。
 */

func expectNearC(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func getFieldC(v: LispValue, key: String): Float64 {
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

func outlierCount(v: LispValue): Int64 {
    match (v) {
        case HashMap(m) =>
            match (m.get("outliers")) {
                case Some(External(e)) =>
                    match (e) {
                        case a: NDArray => a.length()
                        case _ => -1
                    }
                case _ => -1
            }
        case _ => -1
    }
}

@Test
class FiveNumTest {
    /**
     * 五数概括的基本值（与 numpy 的 percentile 一致）
     */
    @TestCase
    func testBasic() {
        println("\n=== 五数概括 ===")
        // [1..9, 100]：Q1=3.25, med=5.5, Q3=7.75, IQR=4.5
        let x: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 100.0]
        let r = fiveNumSummary(x)
        expectNearC(getFieldC(r, "q1"), 3.25, 1e-12, "Q1")
        expectNearC(getFieldC(r, "median"), 5.5, 1e-12, "中位数")
        expectNearC(getFieldC(r, "q3"), 7.75, 1e-12, "Q3")
        expectNearC(getFieldC(r, "iqr"), 4.5, 1e-12, "IQR")
        expectNearC(getFieldC(r, "min"), 1.0, 1e-12, "min")
        expectNearC(getFieldC(r, "max"), 100.0, 1e-12, "max")
        println("✓ Q1=3.25 / med=5.5 / Q3=7.75 / IQR=4.5（与 numpy 一致）")
    }

    /**
     * **离群点与须**
     *
     * `[1..9, 100]`：上围栏 = 7.75 + 1.5×4.5 = 14.5，100 落在围栏外 →
     * 是离群点，而**须止于 9**（围栏内最远的实际点），不是 100。
     *
     * 若用 min/max 当须，100 会把整张图压扁到看不出箱体在哪 —— 这正是箱线图
     * 用围栏而不是极值的原因。
     */
    @TestCase
    func testOutlierAndWhisker() {
        println("\n=== 离群点与须 ===")
        let x: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 100.0]
        let r = fiveNumSummary(x)
        expectNearC(getFieldC(r, "upper_fence"), 14.5, 1e-12, "上围栏")
        expectNearC(getFieldC(r, "high_whisker"), 9.0, 1e-12, "上须止于 9（不是 100）")
        if (outlierCount(r) != 1) {
            @Fail("应有 1 个离群点（100），实际 ${outlierCount(r)} 个")
        }
        println("✓ 100 是离群点，须止于 9")
    }

    /** 无离群点时，须等于 min / max */
    @TestCase
    func testNoOutliers() {
        println("\n=== 无离群点 ===")
        let x: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0]
        let r = fiveNumSummary(x)
        if (outlierCount(r) != 0) {
            @Fail("均匀数据不该有离群点")
        }
        expectNearC(getFieldC(r, "low_whisker"), 1.0, 1e-12, "下须 = min")
        expectNearC(getFieldC(r, "high_whisker"), 5.0, 1e-12, "上须 = max")
        println("✓ 无离群点时须等于极值")
    }

    /** 两端都有离群点 */
    @TestCase
    func testBothEnds() {
        println("\n=== 两端离群 ===")
        let x: Array<Float64> = [-100.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 1000.0]
        let r = fiveNumSummary(x)
        if (outlierCount(r) != 2) {
            @Fail("应有 2 个离群点，实际 ${outlierCount(r)}")
        }
        println("✓ 两端各 1 个离群点")
    }

    @TestCase
    func testTooFew() {
        println("\n=== 样本过少 ===")
        var caught = false
        try {
            fiveNumSummary([1.0, 2.0, 3.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("3 个样本应报错")
        }
        println("✓ 少于 4 个样本报错")
    }
}

@Test
class CorrMatrixTest {
    /** 对角线为 1，且矩阵对称 */
    @TestCase
    func testDiagonalAndSymmetry() {
        println("\n=== 相关矩阵性质 ===")
        // 三列：x1=[1,2,3,4], x2=[2,4,6,8]（与 x1 完全相关）, x3=[4,3,2,1]（与 x1 完全负相关）
        let rows: Array<Array<Float64>> = [
            [1.0, 2.0, 4.0],
            [2.0, 4.0, 3.0],
            [3.0, 6.0, 2.0],
            [4.0, 8.0, 1.0]]
        let m = correlationMatrix(rows, 3)
        let vals = match (m) {
            case External(e) => match (e) {
                case a: NDArray =>
                    let out = ArrayList<Float64>()
                    var i: Int64 = 0
                    while (i < 9) {
                        out.add(match (a.at(i)) { case Float(x) => x; case _ => Float64.getNaN() })
                        i++
                    }
                    out.toArray()
                case _ => Array<Float64>()
            }
            case _ => Array<Float64>()
        }
        // 对角线
        var i: Int64 = 0
        while (i < 3) {
            expectNearC(vals[i * 3 + i], 1.0, 1e-12, "对角线 ${i}")
            i++
        }
        // 对称
        i = 0
        while (i < 3) {
            var j: Int64 = 0
            while (j < 3) {
                expectNearC(vals[i * 3 + j], vals[j * 3 + i], 1e-12, "对称 (${i},${j})")
                j++
            }
            i++
        }
        // x1 与 x2 完全正相关 → 1；x1 与 x3 完全负相关 → -1
        expectNearC(vals[0 * 3 + 1], 1.0, 1e-12, "x1~x2")
        expectNearC(vals[0 * 3 + 2], -1.0, 1e-12, "x1~x3")
        println("✓ 对角线 1、对称、完全相关处 ±1")
    }

    /**
     * **成对删除缺失**：某行在某列缺失，只影响涉及该列的格子
     */
    @TestCase
    func testPairwiseDeletion() {
        println("\n=== 成对删除缺失 ===")
        let nan = Float64.getNaN()
        let rows: Array<Array<Float64>> = [
            [1.0, 1.0],
            [2.0, 2.0],
            [3.0, nan],      // 第 2 列缺失
            [4.0, 4.0],
            [5.0, 5.0]]
        let m = correlationMatrix(rows, 2)
        let offDiag = match (m) {
            case External(e) => match (e) {
                case a: NDArray =>
                    match (a.at(1)) { case Float(x) => x; case _ => Float64.getNaN() }
                case _ => Float64.getNaN()
            }
            case _ => Float64.getNaN()
        }
        // 剩 4 对有效样本，且完全线性 → 相关系数 1
        expectNearC(offDiag, 1.0, 1e-12, "成对删除后仍完全相关")
        println("✓ 缺失只影响相关的那一格，其余样本仍可用")
    }
}
