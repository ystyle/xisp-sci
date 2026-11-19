package ystyle::xisp_array

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList

/**
 * NDArray 的白盒测试
 *
 * 这里测的是**仓颉层的数据结构与视图语义**（buffer 共享、strides、offset、
 * 连续性判断），这些在 Lisp 层看不见也测不准 —— 契约测试放在 xisp_tests。
 */

func intsLv(vals: Array<Int64>): LispValue {
    var r: LispValue = Nil
    var i = vals.size - 1
    while (i >= 0) {
        r = consValue(LispValue.Int(vals[i]), r)
        i--
    }
    r
}

func floatsLv(vals: Array<Float64>): LispValue {
    var r: LispValue = Nil
    var i = vals.size - 1
    while (i >= 0) {
        r = consValue(LispValue.Float(vals[i]), r)
        i--
    }
    r
}

func listLv(items: Array<LispValue>): LispValue {
    var r: LispValue = Nil
    var i = items.size - 1
    while (i >= 0) {
        r = consValue(items[i], r)
        i--
    }
    r
}

func rowsLv(rows: Array<Array<Int64>>): LispValue {
    let items = ArrayList<LispValue>()
    for (r in rows) {
        items.add(intsLv(r))
    }
    listLv(items.toArray())
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

/** 断言某个操作抛 IllegalArgumentException */
func expectIllegal(body: () -> Unit, what: String): Unit {
    var caught = false
    try {
        body()
    } catch (e: IllegalArgumentException) {
        caught = true
    }
    if (!caught) {
        @Fail("${what}：应当报错，但没有")
    }
}

@Test
class NDArrayTest {
    // ===== 构造与 dtype =====

    @TestCase
    func testConstruct1D() {
        println("\n=== 1D 构造 ===")
        let a = arrayFromLisp(intsLv([1, 2, 3, 4, 5]))
        let sh = a.shape
        expectInt(sh.size, 1, "1D rank")
        expectInt(sh[0], 5, "1D shape[0]")
        expectInt(a.size(), 5, "元素总数")
        if (a.dtype != DType.Ints) {
            @Fail("dtype 应为 int64，实际 ${a.dtype.name()}")
        }
        expectStr(a.at(0).toString(), "1", "at(0)")
        expectStr(a.at(4).toString(), "5", "at(4)")
        println("✓ [1 2 3 4 5] → shape (5), int64")
    }

    @TestCase
    func testConstruct2D() {
        println("\n=== 2D 构造 ===")
        let a = arrayFromLisp(rowsLv([[1, 2], [3, 4]]))
        let sh = a.shape
        expectInt(sh.size, 2, "2D rank")
        expectInt(sh[0], 2, "shape[0]")
        expectInt(sh[1], 2, "shape[1]")
        expectInt(a.size(), 4, "元素总数")
        // 行优先：a[1][0] 是扁平下标 2
        expectStr(a.at(2).toString(), "3", "扁平下标 2 = 第 1 行第 0 列")
        println("✓ [[1 2] [3 4]] → shape (2 2)，行优先展开")
    }

    @TestCase
    func testFloatPromotion() {
        println("\n=== int 与 float 混排提升为 float64 ===")
        let inner = ArrayList<LispValue>()
        inner.add(intsLv([1, 2]))
        inner.add(floatsLv([3.5, 4.0]))
        let a = arrayFromLisp(listLv(inner.toArray()))
        if (a.dtype != DType.Floats) {
            @Fail("应为 float64，实际 ${a.dtype.name()}")
        }
        // 提升后每个元素都应是 Float（不是保留原 Int）
        let first = match (a.at(0)) {
            case Float(x) => x == 1.0
            case _ => false
        }
        if (!first) {
            @Fail("int 元素提升后应为 1.0 的 Float，实际 ${a.at(0).toString()}")
        }
        expectStr(a.display(), "#<ndarray float64 [[1.0 2.0] [3.5 4.0]]>", "提升后的显示")
        println("✓ [[1 2] [3.5 4.0]] → float64，int 元素也变成浮点")
    }

    @TestCase
    func testBoolDType() {
        println("\n=== bool 数组 ===")
        let items = ArrayList<LispValue>()
        items.add(LispValue.Boolean(true))
        items.add(LispValue.Boolean(false))
        let a = arrayFromLisp(listLv(items.toArray()))
        if (a.dtype != DType.Bools) {
            @Fail("应为 bool，实际 ${a.dtype.name()}")
        }
        expectStr(a.display(), "#<ndarray bool [true false]>", "bool 显示")
        println("✓ [true false] → bool")
    }

    @TestCase
    func testRaggedRejected() {
        println("\n=== 非规整嵌套报错 ===")
        let inner = ArrayList<LispValue>()
        inner.add(intsLv([1, 2]))
        inner.add(intsLv([3]))
        let ragged = listLv(inner.toArray())
        expectIllegal({ => arrayFromLisp(ragged) }, "[[1 2] [3]]")
        println("✓ 长度不一致的嵌套被拒绝")
    }

    @TestCase
    func testMixedBoolIntRejected() {
        println("\n=== bool 与 int 混排报错 ===")
        let items = ArrayList<LispValue>()
        items.add(LispValue.Boolean(true))
        items.add(LispValue.Int(1))
        let mixed = listLv(items.toArray())
        expectIllegal({ => arrayFromLisp(mixed) }, "[true 1]")
        println("✓ 不做隐式 bool→int 提升")
    }

    @TestCase
    func testUnsupportedElementType() {
        println("\n=== 字符串元素不支持 ===")
        let items = ArrayList<LispValue>()
        items.add(LispValue.Str("x"))
        expectIllegal({ => arrayFromLisp(listLv(items.toArray())) }, "[\"x\"]")
        println("✓ 非数值元素被拒绝")
    }

    @TestCase
    func testEmptyArray() {
        println("\n=== 空数组 ===")
        let a = arrayFromLisp(Nil)
        let sh = a.shape
        expectInt(sh.size, 1, "空列表是 1D")
        expectInt(sh[0], 0, "长度 0")
        expectInt(a.size(), 0, "元素总数 0")
        expectStr(a.display(), "#<ndarray float64 []>", "空数组显示")
        println("✓ [] → shape (0)，默认 float64")
    }

    // ===== 索引接口 =====

    @TestCase
    func testLengthAndNth() {
        println("\n=== length / nth 配对（扁平语义） ===")
        let a = arrayFromLisp(rowsLv([[1, 2, 3], [4, 5, 6]]))
        // length 是总元素数，不是首维长度
        expectInt(a.length(), 6, "length 为总元素数")
        expectStr(a.at(0).toString(), "1", "at(0)")
        expectStr(a.at(3).toString(), "4", "at(3) 是第 1 行第 0 列")
        expectStr(a.at(5).toString(), "6", "at(5)")
        println("✓ shape (2 3) 的 length=6，nth 按行优先扁平取值")
    }

    @TestCase
    func testOutOfRangeReturnsError() {
        println("\n=== 越界返回错误值 ===")
        let a = arrayFromLisp(intsLv([1, 2, 3]))
        for (bad in [-1, 3, 100]) {
            let r = a.at(bad)
            let isErr = match (r) {
                case Error(_) => true
                case _ => false
            }
            if (!isErr) {
                @Fail("at(${bad}) 应当返回错误，实际 ${r.toString()}")
            }
        }
        println("✓ -1 / 3 / 100 都返回错误值")
    }

    // ===== 形状操作与视图 =====

    @TestCase
    func testReshapeSharesBuffer() {
        println("\n=== reshape 连续数组零拷贝 ===")
        let a = arrayFromLisp(intsLv([1, 2, 3, 4, 5, 6]))
        let b = reshapeArray(a, [2, 3])
        let sh = b.shape
        expectInt(sh[0], 2, "新 shape[0]")
        expectInt(sh[1], 3, "新 shape[1]")
        // 共享判定：改 a 的底层缓冲，b 立刻看到
        let changed = match (a.buf) {
            case Ints(arr) =>
                arr[0] = 99
                true
            case _ => false
        }
        if (!changed) {
            @Fail("测试前提失败：a 应为 int64")
        }
        expectStr(b.at(0).toString(), "99", "改 a 的缓冲后 b 应看到")
        expectInt(b.offset, 0, "连续 reshape 的 offset 保持")
        println("✓ reshape 共享缓冲，不是拷贝")
    }

    @TestCase
    func testReshapeNonContiguousCopies() {
        println("\n=== 非连续数组 reshape 先连续化 ===")
        let a = arrayFromLisp(rowsLv([[1, 2, 3], [4, 5, 6]]))
        let t = transposeArray(a)
        if (t.isContiguous()) {
            @Fail("转置后不应连续")
        }
        let r = reshapeArray(t, [6])
        // 转置后是 [[1 4] [2 5] [3 6]]，行优先展开是 1 4 2 5 3 6
        expectStr(r.at(0).toString(), "1", "结果[0]")
        expectStr(r.at(1).toString(), "4", "结果[1] 应为 4")
        expectStr(r.at(2).toString(), "2", "结果[2] 应为 2")
        expectStr(r.at(3).toString(), "5", "结果[3] 应为 5")
        expectStr(r.at(4).toString(), "3", "结果[4] 应为 3")
        expectStr(r.at(5).toString(), "6", "结果[5] 应为 6")
        println("✓ 转置后 reshape 得到正确的行优先顺序")
    }

    @TestCase
    func testReshapeInferDim() {
        println("\n=== reshape 的 -1 推断 ===")
        let a = arrayFromLisp(intsLv([1, 2, 3, 4, 5, 6]))
        let b = reshapeArray(a, [-1, 2])
        let sh = b.shape
        expectInt(sh[0], 3, "-1 推断为 3")
        expectInt(sh[1], 2, "显式维 2")
        expectIllegal({ => reshapeArray(a, [-1, -1]) }, "两个 -1")
        expectIllegal({ => reshapeArray(a, [4, 2]) }, "总数 8 ≠ 6")
        println("✓ -1 推断正确，非法形状被拒绝")
    }

    @TestCase
    func testTransposeSwapsShapeAndStrides() {
        println("\n=== transpose 反转 shape 与 strides ===")
        let a = arrayFromLisp(rowsLv([[1, 2, 3], [4, 5, 6]]))
        let t = transposeArray(a)
        let sh = t.shape
        let st = t.strideList
        expectInt(sh[0], 3, "转置后 shape[0]")
        expectInt(sh[1], 2, "转置后 shape[1]")
        expectInt(st[0], 1, "转置后 strides[0]")
        expectInt(st[1], 3, "转置后 strides[1]")
        // [[1 2 3] [4 5 6]] 转置 → [[1 4] [2 5] [3 6]]
        expectStr(t.at(0).toString(), "1", "t(0,0)")
        expectStr(t.at(1).toString(), "4", "t(0,1)")
        expectStr(t.at(2).toString(), "2", "t(1,0)")
        expectStr(t.at(5).toString(), "6", "t(2,1)")
        println("✓ shape (2 3) → (3 2)，strides (3 1) → (1 3)")
    }

    @TestCase
    func testSliceSharesBufferAndOffsets() {
        println("\n=== slice 是共享缓冲的视图 ===")
        let a = arrayFromLisp(intsLv([10, 20, 30, 40, 50]))
        let s = sliceArray(a, 1, 4)
        expectInt(s.length(), 3, "切片长度")
        expectInt(s.offset, 1, "切片 offset = 原 offset + start")
        expectStr(s.at(0).toString(), "20", "切片[0]")
        expectStr(s.at(2).toString(), "40", "切片[2]")
        // 改原数组缓冲，切片立刻看到 —— 证明零拷贝
        match (a.buf) {
            case Ints(arr) => arr[2] = 999
            case _ => ()
        }
        expectStr(s.at(1).toString(), "999", "改原缓冲后切片应看到")
        println("✓ slice 零拷贝，offset 正确")
    }

    @TestCase
    func testSlice2DTakesRows() {
        println("\n=== 2D 的 slice 沿第 0 维取行 ===")
        let a = arrayFromLisp(rowsLv([[1, 2], [3, 4], [5, 6]]))
        let s = sliceArray(a, 0, 2)
        let sh = s.shape
        expectInt(sh[0], 2, "取两行")
        expectInt(sh[1], 2, "列数不变")
        expectStr(s.at(0).toString(), "1", "第 0 行第 0 列")
        expectStr(s.at(3).toString(), "4", "第 1 行第 1 列")
        expectIllegal({ => sliceArray(a, 0, 4) }, "end 越界")
        expectIllegal({ => sliceArray(a, 2, 1) }, "start > end")
        println("✓ 2D 切片取行；非法范围被拒绝")
    }

    @TestCase
    func testCopyIsIndependent() {
        println("\n=== copy 是独立副本 ===")
        let a = arrayFromLisp(intsLv([1, 2, 3]))
        let b = a.copy()
        match (a.buf) {
            case Ints(arr) => arr[0] = 77
            case _ => ()
        }
        expectStr(a.at(0).toString(), "77", "原数组被改")
        expectStr(b.at(0).toString(), "1", "副本不受影响")
        println("✓ copy 后两份互不影响")
    }

    @TestCase
    func testContiguity() {
        println("\n=== 连续性判断 ===")
        let a = arrayFromLisp(rowsLv([[1, 2], [3, 4]]))
        if (!a.isContiguous()) {
            @Fail("构造出来的数组应连续")
        }
        let t = transposeArray(a)
        if (t.isContiguous()) {
            @Fail("转置 2x2 后应在 strides 上表现为非连续")
        }
        // 1D 切片仍连续
        let s = sliceArray(arrayFromLisp(intsLv([1, 2, 3, 4, 5])), 1, 4)
        if (!s.isContiguous()) {
            @Fail("1D 切片应仍连续")
        }
        println("✓ 构造连续、转置非连续、1D 切片仍连续")
    }

    // ===== 构造辅助 =====

    @TestCase
    func testZerosOnes() {
        println("\n=== zeros / ones ===")
        let z = zerosArray([2, 3])
        expectInt(z.size(), 6, "zeros 元素数")
        if (z.dtype != DType.Floats) {
            @Fail("zeros 应为 float64")
        }
        expectStr(z.display(), "#<ndarray float64 [[0.0 0.0 0.0] [0.0 0.0 0.0]]>", "zeros 显示")
        let o = onesArray([3])
        expectStr(o.display(), "#<ndarray float64 [1.0 1.0 1.0]>", "ones 显示")
        expectIllegal({ => zerosArray([-1]) }, "负维度")
        println("✓ zeros / ones 为 float64，负维度被拒绝")
    }

    @TestCase
    func testArangeInts() {
        println("\n=== arange 整数版 ===")
        let a = arangeInts(0, 5, 1)
        expectInt(a.length(), 5, "0..5 步长 1")
        expectStr(a.display(), "#<ndarray int64 [0 1 2 3 4]>", "整数 arange")
        let b = arangeInts(0, 10, 3)
        expectStr(b.display(), "#<ndarray int64 [0 3 6 9]>", "步长 3")
        let c = arangeInts(5, 0, -1)
        expectStr(c.display(), "#<ndarray int64 [5 4 3 2 1]>", "负步长")
        let empty = arangeInts(0, 0, 1)
        expectInt(empty.length(), 0, "空范围")
        expectIllegal({ => arangeInts(0, 5, 0) }, "步长 0")
        println("✓ 正/负步长、空范围、步长 0 报错")
    }

    @TestCase
    func testArangeFloatCount() {
        println("\n=== arange 浮点计数不能因累加误差少一个 ===")
        // 这是经典的浮点坑：累加 0.1 一百次得到 9.99999999999998，
        // 若按 floor 计数会少一个元素。
        expectInt(arangeCount(0.0, 1.0, 0.1), 10, "0..1 步长 0.1")
        expectInt(arangeCount(0.0, 10.0, 0.1), 100, "0..10 步长 0.1")
        expectInt(arangeCount(0.0, 1.0, 0.25), 4, "0..1 步长 0.25")
        let a = arangeFloats(0.0, 1.0, 0.5)
        expectStr(a.display(), "#<ndarray float64 [0.0 0.5]>", "浮点 arange 显示")
        println("✓ 0..1 步长 0.1 得到 10 个元素，不是 9 个")
    }

    // ===== 显示 =====

    @TestCase
    func testDisplayFormat() {
        println("\n=== display 格式 ===")
        expectStr(arrayFromLisp(intsLv([1, 2, 3])).display(),
            "#<ndarray int64 [1 2 3]>", "1D int")
        expectStr(arrayFromLisp(rowsLv([[1, 2], [3, 4]])).display(),
            "#<ndarray int64 [[1 2] [3 4]]>", "2D int")
        expectStr(arrayFromLisp(floatsLv([1.0, 2.5])).display(),
            "#<ndarray float64 [1.0 2.5]>", "1D float 去尾 0")
        println("✓ 三种格式正确，浮点不留 6 位尾数")
    }

    @TestCase
    func testDisplayTruncates() {
        println("\n=== 大数组显示截断 ===")
        let big = arangeInts(0, 2000, 1)
        let text = big.display()
        if (text.indexOf("...").isNone()) {
            @Fail("2000 个元素的显示应包含省略号，实际长度 ${text.size}")
        }
        // 截断后不应把全部 2000 个都打出来
        if (text.size > 200) {
            @Fail("截断后仍太长：${text.size} 字符")
        }
        println("✓ 2000 元素显示被截断（长度 ${text.size}）")
    }

    @TestCase
    func testTypeNameIsNdarray() {
        println("\n=== typeName ===")
        let a = arrayFromLisp(intsLv([1]))
        expectStr(a.typeName, "ndarray", "typeName")
        println("✓ type-of 会得到 ndarray")
    }

    // ===== 布局工具函数 =====

    @TestCase
    func testContiguousStrides() {
        println("\n=== 行优先 strides 计算 ===")
        let s1 = contiguousStrides([3, 4])
        expectInt(s1[0], 4, "(3 4) strides[0]")
        expectInt(s1[1], 1, "(3 4) strides[1]")
        let s2 = contiguousStrides([2, 3, 4])
        expectInt(s2[0], 12, "(2 3 4) strides[0]")
        expectInt(s2[1], 4, "(2 3 4) strides[1]")
        expectInt(s2[2], 1, "(2 3 4) strides[2]")
        println("✓ 行优先：strides[i] = 后续维度之积")
    }
}
