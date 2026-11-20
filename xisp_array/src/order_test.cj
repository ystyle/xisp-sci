package ystyle::xisp_array

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.math.*

/**
 * 排序 / 排序索引 / 累积归约 / 秩 的白盒测试
 *
 * 重点在两处容易错的：
 *
 * 1. **稳定性** —— 「相等元素保持原顺序」不是可选项。`order` 的全部意义就在于
 *    拿到索引后按它重排**别的列**，索引不稳定会让行与行的对应关系错位，
 *    而错位后的数据看起来完全正常。
 * 2. **NaN 的位置** —— NaN 在浮点比较里既不小于也不大于任何数，直接用默认比较器
 *    排序会得到依赖实现的不确定顺序。这里靠「先把 NaN 挑出去、排完拼回末尾」保证确定。
 */

func expectArrEq(actual: Array<Float64>, want: Array<Float64>, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度期望 ${want.size}，实际 ${actual.size}")
    }
    var i: Int64 = 0
    while (i < want.size) {
        let a = actual[i]
        let w = want[i]
        // 两者都是 NaN 也算相等（NaN != NaN，要单独判）
        let bothNaN = (a != a) && (w != w)
        if (!bothNaN && abs(a - w) > 1e-14) {
            @Fail("${what}：第 ${i} 个元素期望 ${w}，实际 ${a}")
        }
        i++
    }
}

func expectIdxEq(actual: Array<Int64>, want: Array<Int64>, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度期望 ${want.size}，实际 ${actual.size}")
    }
    var i: Int64 = 0
    while (i < want.size) {
        if (actual[i] != want[i]) {
            @Fail("${what}：第 ${i} 个期望 ${want[i]}，实际 ${actual[i]}")
        }
        i++
    }
}

@Test
class SortTest {
    /** 升序 / 降序 */
    @TestCase
    func testSort() {
        println("\n=== 排序 ===")
        let v = [3.0, 1.0, 4.0, 1.0, 5.0]
        expectArrEq(sortRaw(v, false), [1.0, 1.0, 3.0, 4.0, 5.0], "升序")
        expectArrEq(sortRaw(v, true), [5.0, 4.0, 3.0, 1.0, 1.0], "降序")
        // 单元素与空数组
        expectArrEq(sortRaw([7.0], false), [7.0], "单元素")
        expectArrEq(sortRaw(Array<Float64>(0, repeat: 0.0), false), Array<Float64>(0, repeat: 0.0), "空数组")
    }

    /** NaN 必须排在最后，且不参与比较 */
    @TestCase
    func testSortNaNLast() {
        println("\n=== NaN 排最后 ===")
        let v = [3.0, Float64.getNaN(), 1.0, Float64.getNaN(), 2.0]
        let s = sortRaw(v, false)
        expectArrEq(s, [1.0, 2.0, 3.0, Float64.getNaN(), Float64.getNaN()], "升序带 NaN")
        let d = sortRaw(v, true)
        expectArrEq(d, [3.0, 2.0, 1.0, Float64.getNaN(), Float64.getNaN()], "降序带 NaN")
    }
}

@Test
class OrderTest {
    /**
     * 排序索引：`order(x)[i]` 是「排序后第 i 个元素在原数组里的下标」
     *
     * 这条必须**稳定**：两个 1.0 分别在下标 1 和 3，排序后它们的相对顺序不能反。
     */
    @TestCase
    func testOrder() {
        println("\n=== 排序索引 ===")
        let v = [3.0, 1.0, 4.0, 1.0, 5.0]
        // 值 1.0 在下标 1、3；稳定 → 先 1 后 3
        expectIdxEq(orderRaw(v, false), [1, 3, 0, 2, 4], "升序索引")
        expectIdxEq(orderRaw(v, true), [4, 2, 0, 1, 3], "降序索引")
        // 索引能真正重排原数组 —— 这是它唯一的用途
        let idx = orderRaw(v, false)
        let rebuilt = Array<Float64>(v.size, repeat: 0.0)
        var i: Int64 = 0
        while (i < v.size) {
            rebuilt[i] = v[idx[i]]
            i++
        }
        expectArrEq(rebuilt, sortRaw(v, false), "按索引重排 == 直接排序")
    }

    /** NaN 的索引排在最后 */
    @TestCase
    func testOrderNaNLast() {
        println("\n=== 索引里 NaN 排最后 ===")
        let v = [2.0, Float64.getNaN(), 1.0]
        expectIdxEq(orderRaw(v, false), [2, 0, 1], "含 NaN 的索引")
    }
}

@Test
class CumulativeTest {
    /** 累积和与累积积 */
    @TestCase
    func testCumsumCumprod() {
        println("\n=== 累积和 / 累积积 ===")
        let v = [1.0, 2.0, 3.0, 4.0]
        expectArrEq(cumsumRaw(v), [1.0, 3.0, 6.0, 10.0], "累积和")
        expectArrEq(cumprodRaw(v), [1.0, 2.0, 6.0, 24.0], "累积积")
        // 空数组
        expectArrEq(cumsumRaw(Array<Float64>(0, repeat: 0.0)), Array<Float64>(0, repeat: 0.0), "空累积和")
        // 含负数：累积和要正确穿越 0
        expectArrEq(cumsumRaw([5.0, -3.0, -4.0, 2.0]), [5.0, 2.0, -2.0, 0.0], "含负数累积和")
    }
}

@Test
class RanksTest {
    /**
     * 秩：并列取**平均秩**
     *
     * `[3, 1, 4, 1, 5]` 里两个 1 占第 1、2 名，各拿 (1+2)/2 = 1.5。
     * 并列处理选错（比如「谁先出现谁拿前面的名次」），秩和检验会系统性地偏。
     */
    @TestCase
    func testRanks() {
        println("\n=== 秩（并列取平均）===")
        expectArrEq(ranksRaw([3.0, 1.0, 4.0, 1.0, 5.0]),
            [3.0, 1.5, 4.0, 1.5, 5.0], "两个并列")
        // 三个并列：占第 2、3、4 名，各拿 3
        expectArrEq(ranksRaw([1.0, 5.0, 5.0, 5.0, 9.0]),
            [1.0, 3.0, 3.0, 3.0, 5.0], "三个并列")
        // 全相等：都拿 (1+n)/2
        expectArrEq(ranksRaw([7.0, 7.0, 7.0, 7.0]),
            [2.5, 2.5, 2.5, 2.5], "全相等")
        // 无并列时就是 1..n
        expectArrEq(ranksRaw([10.0, 20.0, 30.0]), [1.0, 2.0, 3.0], "无并列")
    }

    /** 秩的和恒等于 n(n+1)/2 —— 这条对任何数据都必须成立 */
    @TestCase
    func testRankSumInvariant() {
        println("\n=== 秩和的恒等式 ===")
        let cases: Array<Array<Float64>> = [
            [3.0, 1.0, 4.0, 1.0, 5.0],
            [1.0, 5.0, 5.0, 5.0, 9.0],
            [7.0, 7.0, 7.0],
            [2.0, 4.0, 6.0, 8.0, 10.0]]
        for (v in cases) {
            let r = ranksRaw(v)
            var sum = 0.0
            for (x in r) {
                sum += x
            }
            let want = Float64(v.size * (v.size + 1)) / 2.0
            if (abs(sum - want) > 1e-12) {
                @Fail("${v.size} 个元素的秩和为 ${sum}，应为 ${want}")
            }
        }
    }

    /** NaN 位置的秩是 NaN（R 的 na.last 语义） */
    @TestCase
    func testRanksNaN() {
        println("\n=== 秩里的 NaN ===")
        let r = ranksRaw([2.0, Float64.getNaN(), 1.0])
        expectArrEq([r[2]], [1.0], "最小值拿第 1 名")
        expectArrEq([r[0]], [2.0], "次小值拿第 2 名")
        if (!(r[1] != r[1])) {
            @Fail("NaN 位置的秩应为 NaN，实际 ${r[1]}")
        }
    }
}
