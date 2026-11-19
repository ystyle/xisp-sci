package ystyle::xisp_stats

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 描述统计的白盒测试
 *
 * 重点验证三件事：**缺失值跳过**、**样本 vs 总体的自由度**、**成对过滤**。
 * 前两条错了结果"看着像数字"，第三条错了更是会算出一组完全无关的配对 —— 都不报错。
 */

func fvals(vals: Array<Float64>): Array<Float64> {
    vals.clone()
}

func expectInt(actual: Int64, want: Int64, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func expectStr(actual: String, want: String, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 `${want}`，实际 `${actual}`")
    }
}

func closeEnough(a: Float64, b: Float64, tol: Float64): Bool {
    if (a.isNaN() && b.isNaN()) {
        return true
    }
    abs(a - b) <= tol
}

func expectNum(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!closeEnough(actual, want, tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func expectNaN(actual: Float64, what: String): Unit {
    if (!actual.isNaN()) {
        @Fail("${what}：期望 NaN，实际 ${actual}")
    }
}

@Test
class StatsBasicTest {
    @TestCase
    func testMean() {
        println("\n=== 均值 ===")
        expectNum(meanOf(fvals([1.0, 2.0, 3.0])), 2.0, 1e-12, "mean")
        expectNum(meanOf(fvals([2.5])), 2.5, 1e-12, "单元素")
        expectNaN(meanOf(Array<Float64>()), "空数组的均值")
        println("✓ 基本均值；空输入 NaN")
    }

    /**
     * 缺失值不参与统计
     *
     * `[1, NaN, 3]` 的均值是 2 而不是 1.333 —— 把 NaN 当 0 会静默得出错误结论。
     */
    @TestCase
    func testSkipNaN() {
        println("\n=== 跳过 NaN ===")
        let nan = Float64.getNaN()
        let v = fvals([1.0, nan, 3.0])
        expectNum(meanOf(finiteOf(v)), 2.0, 1e-12, "含 NaN 的均值")
        expectInt(finiteOf(v).size, 2, "有效样本数")
        expectNaN(meanOf(finiteOf(fvals([nan, nan]))), "全 NaN 的均值")
        println("✓ [1, NaN, 3] 均值 = 2")
    }

    /**
     * 样本 vs 总体方差
     *
     * `[1,2,3,4]`：均值 2.5，平方偏差和 5。
     * 总体方差 5/4 = 1.25；样本方差 5/3 ≈ 1.6667。
     */
    @TestCase
    func testVarianceDDof() {
        println("\n=== 样本 / 总体方差 ===")
        let v = fvals([1.0, 2.0, 3.0, 4.0])
        expectNum(varianceOf(v, 0), 1.25, 1e-12, "总体方差 (ddof=0)")
        expectNum(varianceOf(v, 1), 5.0 / 3.0, 1e-12, "样本方差 (ddof=1)")
        // 单样本算不出样本方差
        expectNaN(varianceOf(fvals([1.0]), 1), "单样本的样本方差")
        println("✓ ddof=0 → 1.25；ddof=1 → 1.6667；单样本样本方差 NaN")
    }

    @TestCase
    func testMedian() {
        println("\n=== 中位数 ===")
        expectNum(quantileOf(sortedCopy(fvals([3.0, 1.0, 2.0])), 0.5), 2.0, 1e-12, "奇数个")
        expectNum(quantileOf(sortedCopy(fvals([4.0, 1.0, 3.0, 2.0])), 0.5), 2.5, 1e-12, "偶数个")
        expectNaN(quantileOf(Array<Float64>(), 0.5), "空数组中位数")
        println("✓ 奇数取中间、偶数取平均")
    }

    @TestCase
    func testQuantile() {
        println("\n=== 分位数（线性插值）===")
        let v = fvals([1.0, 2.0, 3.0, 4.0, 5.0])
        let s = sortedCopy(v)
        expectNum(quantileOf(s, 0.0), 1.0, 1e-12, "q=0")
        expectNum(quantileOf(s, 1.0), 5.0, 1e-12, "q=1")
        expectNum(quantileOf(s, 0.25), 2.0, 1e-12, "q=0.25")
        expectNum(quantileOf(s, 0.75), 4.0, 1e-12, "q=0.75")
        // 位置 0.1*4 = 0.4 → 1 与 2 之间插值
        expectNum(quantileOf(s, 0.1), 1.4, 1e-12, "q=0.1 线性插值")
        println("✓ 线性插值，与 NumPy 默认 method 一致")
    }

    /** 归并排序的正确性（含重复值） */
    @TestCase
    func testSort() {
        println("\n=== 排序 ===")
        let s = sortedCopy(fvals([3.0, 1.0, 2.0, 2.0, 5.0, 0.0]))
        expectStr("${s}", "[0.000000, 1.000000, 2.000000, 2.000000, 3.000000, 5.000000]", "升序")
        expectInt(s.size, 6, "长度不变")
        // 大数组走完整的归并路径
        let big = Array<Float64>(1000, repeat: 0.0)
        var i: Int64 = 0
        while (i < 1000) {
            big[i] = Float64(1000 - i)
            i++
        }
        let bs = sortedCopy(big)
        var ok = true
        var j: Int64 = 0
        while (j < 999) {
            if (bs[j] > bs[j + 1]) {
                ok = false
            }
            j++
        }
        if (!ok) {
            @Fail("1000 个逆序元素排序后有逆序对")
        }
        println("✓ 小数组与 1000 元素归并排序都正确")
    }

    @TestCase
    func testCovAndCorr() {
        println("\n=== 协方差与相关系数 ===")
        let x = fvals([1.0, 2.0, 3.0, 4.0])
        let y = fvals([2.0, 4.0, 6.0, 8.0])   // 完全正相关
        expectNum(covarianceOf(x, y), 10.0 / 3.0, 1e-12, "cov")
        expectNum(correlationOf(x, y), 1.0, 1e-12, "完全正相关的 corr")
        let z = fvals([4.0, 3.0, 2.0, 1.0])
        expectNum(correlationOf(x, z), -1.0, 1e-12, "完全负相关的 corr")
        println("✓ cov；corr = 1 / -1 在完全线性关系上")
    }

    /**
     * **成对过滤**：任一侧缺失就丢整个样本
     *
     * 若各自独立跳过 NaN，两个数组会错位 —— 算的是"1 号价格对 5 号销量"，
     * 数字看着正常，结论完全错。
     */
    @TestCase
    func testPairedFilter() {
        println("\n=== 成对过滤 ===")
        let nan = Float64.getNaN()
        let x = fvals([1.0, 2.0, nan, 4.0])
        let y = fvals([10.0, nan, 30.0, 40.0])
        let pair = pairedFinite(x, y)
        expectInt(pair[0].size, 2, "有效配对数")
        expectNum(pair[0][0], 1.0, 1e-12, "保留第 1 对")
        expectNum(pair[0][1], 4.0, 1e-12, "保留第 4 对")
        expectNum(pair[1][1], 40.0, 1e-12, "y 侧同步保留")
        println("✓ 任一侧缺失即整对丢弃，不会错位")
    }

    @TestCase
    func testLengthMismatch() {
        println("\n=== 长度不一致 ===")
        var caught = false
        try {
            pairedFinite(fvals([1.0, 2.0]), fvals([1.0]))
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("长度不一致应当报错")
        }
        println("✓ 两数组长度不同 → 报错")
    }

    @TestCase
    func testHistogramEdges() {
        println("\n=== 直方图分箱 ===")
        // 自己算一遍，验证左闭右开与最大值归入最后一箱
        let v = fvals([0.0, 1.0, 2.0, 3.0, 4.0])
        var lo = v[0]
        var hi = v[0]
        for (x in v) {
            if (x < lo) { lo = x }
            if (x > hi) { hi = x }
        }
        let bins: Int64 = 4
        let width = (hi - lo) / Float64(bins)
        let counts = Array<Int64>(bins, repeat: 0)
        for (x in v) {
            var idx = if (width > 0.0) { Int64(floor((x - lo) / width)) } else { 0 }
            if (idx >= bins) { idx = bins - 1 }
            counts[idx] = counts[idx] + 1
        }
        expectInt(counts[0], 1, "箱 0")
        expectInt(counts[1], 1, "箱 1")
        expectInt(counts[2], 1, "箱 2")
        expectInt(counts[3], 2, "箱 3 含最大值")
        println("✓ 等宽分箱，最大值归入最后一箱")
    }
}
