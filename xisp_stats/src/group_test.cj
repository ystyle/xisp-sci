package ystyle::xisp_stats

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 分组聚合的白盒测试
 *
 * 重点验证两件容易写错的事：
 * 1. **顺序稳定**（按首次出现），而不是 HashMap 的任意顺序；
 * 2. **一次遍历**，不是"对每个类别扫一遍全表"。
 */

func expectStrEq(actual: String, want: String, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 `${want}`，实际 `${actual}`")
    }
}

@Test
class GroupByTest {
    /**
     * 基本分组：三组、顺序按首次出现
     *
     * 注意 `b` 在 `a` 之后出现，所以输出顺序是 a, b, c —— 不是字典序，
     * 也不是 HashMap 的哈希顺序。报告和图表都依赖这个稳定性。
     */
    @TestCase
    func testBasicGrouping() {
        println("\n=== 基本分组 ===")
        let labels = ["a", "b", "a", "c", "b", "a"]
        let values: Array<Float64> = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        let g = groupValues(labels, values)
        expectInt(g.keys.size, 3, "组数")
        expectStrEq(g.keys[0], "a", "第 0 组")
        expectStrEq(g.keys[1], "b", "第 1 组")
        expectStrEq(g.keys[2], "c", "第 2 组")
        // a 组有 1, 3, 6
        expectInt(g.groups[0].size, 3, "a 组元素数")
        if (g.groups[0][0] != 1.0 || g.groups[0][2] != 6.0) {
            @Fail("a 组元素不对：${g.groups[0]}")
        }
        // b 组有 2, 5
        expectInt(g.groups[1].size, 2, "b 组元素数")
        println("✓ 3 组，按首次出现顺序 a → b → c")
    }

    /** 单组：所有键相同 */
    @TestCase
    func testSingleGroup() {
        println("\n=== 单组 ===")
        let g = groupValues(["x", "x", "x"], [1.0, 2.0, 3.0])
        expectInt(g.keys.size, 1, "组数")
        expectInt(g.groups[0].size, 3, "元素数")
        println("✓ 全部同键 → 一组")
    }

    /** 每组一个元素 */
    @TestCase
    func testAllDistinct() {
        println("\n=== 全不同 ===")
        let g = groupValues(["a", "b", "c"], [1.0, 2.0, 3.0])
        expectInt(g.keys.size, 3, "组数")
        var i: Int64 = 0
        while (i < 3) {
            expectInt(g.groups[i].size, 1, "第 ${i} 组")
            i++
        }
        println("✓ 3 个键各一组")
    }

    @TestCase
    func testEmpty() {
        println("\n=== 空输入 ===")
        let g = groupValues(Array<String>(), Array<Float64>())
        expectInt(g.keys.size, 0, "组数")
        println("✓ 空输入给空结果")
    }

    /** 长度不匹配必须报错 —— 静默截断会让两个数组错位，算出的分组是错的 */
    @TestCase
    func testLengthMismatch() {
        println("\n=== 长度不匹配 ===")
        var caught = false
        try {
            groupValues(["a", "b"], [1.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("长度不匹配应当报错")
        }
        println("✓ 长度不匹配报错（不静默截断）")
    }

    /** 组内保持原始顺序（不排序）—— 这对时间序列类数据很重要 */
    @TestCase
    func testPreservesOrderWithinGroup() {
        println("\n=== 组内顺序 ===")
        let g = groupValues(["a", "a", "a"], [3.0, 1.0, 2.0])
        let vals = g.groups[0]
        if (vals[0] != 3.0 || vals[1] != 1.0 || vals[2] != 2.0) {
            @Fail("组内应保持原始顺序，实际 ${vals}")
        }
        println("✓ 组内保持原始顺序（不排序）")
    }

    /** 数值键：转成字符串 */
    @TestCase
    func testNumericKeys() {
        println("\n=== 数值键 ===")
        expectStrEq(keyOf(LispValue.Int(42)), "42", "整数键")
        expectStrEq(keyOf(LispValue.Str("s")), "s", "字符串键")
        println("✓ 整数键转成十进制字符串")
    }
}
