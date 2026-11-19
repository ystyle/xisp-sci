package ystyle::xisp_array

import ystyle::xisp.types.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList

/**
 * 算术 / 归约 / 逐元素的仓颉层测试
 *
 * 用 `arrayFromLisp` 构造（复用已有的 helper），重点钉三件事：
 * 广播的形状规则、`stride = 0` 视图取值是否正确、以及 dtype 提升。
 */

func expectShape(a: NDArray, want: Array<Int64>, what: String): Unit {
    let got = a.shape
    if (got.size != want.size) {
        @Fail("${what}：维数期望 ${want.size}，实际 ${got.size}（${got}）")
    }
    var i: Int64 = 0
    while (i < want.size) {
        if (got[i] != want[i]) {
            @Fail("${what}：第 ${i} 维期望 ${want[i]}，实际 ${got[i]}")
        }
        i++
    }
}

func expectNDDisplay(v: LispValue, want: String, what: String): Unit {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    if (a.display() != want) {
                        @Fail("${what}：期望 `${want}`，实际 `${a.display()}`")
                    }
                case _ => @Fail("${what}：不是 ndarray")
            }
        case _ => @Fail("${what}：期望 ndarray，实际 ${v.toString()}")
    }
}

/** 把 int 数组构造成 NDArray */
func iArr(vals: Array<Int64>): NDArray {
    match (arrayFromLisp(intsLv(vals))) {
        case a: NDArray => a
        case _ => NDArray(Ints(Array<Int64>(0, repeat: 0)), 0, [0], [1])
    }
}

func fArr(vals: Array<Float64>): NDArray {
    match (arrayFromLisp(floatsLv(vals))) {
        case a: NDArray => a
        case _ => NDArray(Floats(Array<Float64>(0, repeat: 0.0)), 0, [0], [1])
    }
}

@Test
class BroadcastShapeTest {
    @TestCase
    func testSameShape() {
        println("\n=== 同形 ===")
        expectStr(broadcastShape([3], [3]).toString(), "Some([3])", "[3]+[3]")
        expectStr(broadcastShape([2, 3], [2, 3]).toString(), "Some([2, 3])", "[2,3]+[2,3]")
        println("✓ 同形直接取原形")
    }

    /**
     * 从**尾部**对齐，不是从头
     *
     * `[2,3]` 与 `[3]` 兼容（列对齐）；如果从头对齐就会变成"2 与 3 不兼容"。
     * 这条错了，所有"矩阵 + 向量"的写法都会报错。
     */
    @TestCase
    func testTrailingAlignment() {
        println("\n=== 尾部对齐 ===")
        expectStr(broadcastShape([2, 3], [3]).toString(), "Some([2, 3])", "[2,3]+[3]")
        expectStr(broadcastShape([3], [2, 3]).toString(), "Some([2, 3])", "[3]+[2,3]")
        println("✓ [2,3] 与 [3] 兼容（尾部对齐）")
    }

    @TestCase
    func testExpandUnitDims() {
        println("\n=== 长度为 1 的维可扩张 ===")
        expectStr(broadcastShape([3, 1], [1, 4]).toString(), "Some([3, 4])", "[3,1]+[1,4]")
        expectStr(broadcastShape([1], [4]).toString(), "Some([4])", "[1]+[4]")
        expectStr(broadcastShape([2, 1, 3], [1, 4, 1]).toString(),
            "Some([2, 4, 3])", "[2,1,3]+[1,4,1]")
        println("✓ 单位维扩张")
    }

    @TestCase
    func testIncompatible() {
        println("\n=== 不兼容 ===")
        // 3 与 2 都无法对齐
        expectStr(broadcastShape([2, 3], [2]).toString(), "None", "[2,3]+[2]")
        expectStr(broadcastShape([2, 3], [4]).toString(), "None", "[2,3]+[4]")
        println("✓ 不兼容返回 None")
    }

    @TestCase
    func testScalarZeroDim() {
        println("\n=== 0 维（标量）与任意形状兼容 ===")
        expectStr(broadcastShape([2, 3], Array<Int64>()).toString(), "Some([2, 3])", "[2,3]+[]")
        expectStr(broadcastShape(Array<Int64>(), [5]).toString(), "Some([5])", "[]+[5]")
        println("✓ 0 维可广播到任意形状")
    }
}

@Test
class ArithTest {
    /** stride = 0 的广播视图取值必须正确 */
    @TestCase
    func testBroadcastValueCorrectness() {
        println("\n=== 广播后的取值 ===")
        // [[1],[2]] + [[3,4]] = [[4,5],[5,6]]
        let a = match (arrayFromLisp(rowsLv([[1], [2]]))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        let b = match (arrayFromLisp(rowsLv([[3, 4]]))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        let r = binopWith("+", a, LispValue.External(b), false)
        match (r) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [[4 5] [5 6]]>", "[[1],[2]] + [[3,4]]")
            case None => @Fail("应当成功广播")
        }
        println("✓ stride=0 视图逐元素取值正确")
    }

    @TestCase
    func testSameShapeAdd() {
        println("\n=== 同形相加 ===")
        let r = binopWith("+", iArr([1, 2, 3]), LispValue.External(iArr([10, 20, 30])), false)
        match (r) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [11 22 33]>", "同形相加")
            case None => @Fail("应当成功")
        }
        println("✓ [1 2 3] + [10 20 30] = [11 22 33]")
    }

    /** 标量在右（arithLeft）与在左（arithRight） */
    @TestCase
    func testScalarBothSides() {
        println("\n=== 标量在两边的方向 ===")
        let right = binopWith("-", iArr([1, 2, 3]), LispValue.Int(10), false)
        match (right) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [-9 -8 -7]>", "arr - 10")
            case None => @Fail("arr - 10 应当成功")
        }
        let left = binopWith("-", iArr([1, 2, 4]), LispValue.Int(10), true)
        match (left) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [9 8 6]>", "10 - arr")
            case None => @Fail("10 - arr 应当成功")
        }
        println("✓ arr-10 = [-9 -8 -7]；10-arr = [9 8 6]")
    }

    /**
     * dtype 提升
     *
     * `int 数组 + float 标量` → float 数组；两边读值都按结果 dtype 转，
     * 不做整数组预拷贝。
     */
    @TestCase
    func testDTypePromotion() {
        println("\n=== dtype 提升 ===")
        let r = binopWith("+", iArr([1, 2]), LispValue.Float(0.5), false)
        match (r) {
            case Some(v) => expectNDDisplay(v, "#<ndarray float64 [1.5 2.5]>", "int arr + float")
            case None => @Fail("应当成功")
        }
        // 除法恒浮点
        let d = binopWith("/", iArr([1, 2]), LispValue.Int(2), false)
        match (d) {
            case Some(v) => expectNDDisplay(v, "#<ndarray float64 [0.5 1.0]>", "int arr / 2")
            case None => @Fail("除法应当成功")
        }
        println("✓ int+float→float；除法恒 float")
    }

    @TestCase
    func testBoolRejected() {
        println("\n=== bool 不参与算术 ===")
        let items = ArrayList<LispValue>()
        items.add(LispValue.Boolean(true))
        items.add(LispValue.Boolean(false))
        let b = match (arrayFromLisp(listLv(items.toArray()))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        let r = binopWith("+", b, LispValue.Int(1), false)
        match (r) {
            case Some(_) => @Fail("bool 数组相加应当不支持")
            case None => ()
        }
        println("✓ bool 数组返回 None")
    }

    @TestCase
    func testIncompatibleIsNone() {
        println("\n=== 形状不兼容返回 None ===")
        let a = match (arrayFromLisp(rowsLv([[1, 2, 3], [4, 5, 6]]))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        let r = binopWith("+", a, LispValue.External(iArr([1, 2])), false)
        match (r) {
            case Some(_) => @Fail("[2,3] + [2] 应当不兼容")
            case None => ()
        }
        println("✓ 不兼容返回 None（由 core 报 TypeError）")
    }

    /**
     * 视图参与运算
     *
     * `slice` 出来的视图 offset 非 0、`transpose` 出来的非连续 —— 两者都必须
     * 按逻辑顺序正确取值。
     */
    @TestCase
    func testViewsInArith() {
        println("\n=== 视图参与运算 ===")
        let base = iArr([10, 20, 30, 40, 50])
        let s = sliceArray(base, 1, 4)     // [20 30 40]
        let r = binopWith("+", s, LispValue.Int(1), false)
        match (r) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [21 31 41]>", "切片 + 1")
            case None => @Fail("切片相加应当成功")
        }
        let m = match (arrayFromLisp(rowsLv([[1, 2], [3, 4]]))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        let t = transposeArray(m)          // [[1 3] [2 4]]
        let r2 = binopWith("*", t, LispValue.Int(2), false)
        match (r2) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [[2 6] [4 8]]>", "转置 * 2")
            case None => @Fail("转置相乘应当成功")
        }
        println("✓ 切片与非连续视图都按逻辑顺序取值")
    }
}

@Test
class ReduceArrayTest {
    @TestCase
    func testBasicReductions() {
        println("\n=== 四个归约 ===")
        let a = iArr([1, 2, 3, 4])
        expectStr(reduceArray(a, "sum").toString(), "Some(10)", "sum")
        expectStr(reduceArray(a, "product").toString(), "Some(24)", "product")
        expectStr(reduceArray(a, "max").toString(), "Some(4)", "max")
        expectStr(reduceArray(a, "min").toString(), "Some(1)", "min")
        println("✓ sum / product / max / min")
    }

    @TestCase
    func testFloatReduction() {
        println("\n=== 浮点归约 ===")
        let a = fArr([1.5, 2.5])
        expectStr(reduceArray(a, "sum").toString(), "Some(4.000000)", "浮点 sum")
        let m = reduceArray(a, "max")
        match (m) {
            case Some(Float(x)) => if (x != 2.5) { @Fail("max 应为 2.5，实际 ${x}") }
            case _ => @Fail("max 应返回浮点")
        }
        println("✓ 浮点归约返回浮点")
    }

    /**
     * 空数组一律拒绝
     *
     * `sum` 空数组给 0 会让"文件读空了"伪装成一个正常结果；`max` 更是没有单位元。
     */
    @TestCase
    func testEmptyRejected() {
        println("\n=== 空数组 ===")
        let e = iArr([])
        for (rn in ["sum", "product", "max", "min"]) {
            match (reduceArray(e, rn)) {
                case Some(_) => @Fail("空数组 ${rn} 应当返回 None")
                case None => ()
            }
        }
        println("✓ 空数组四个归约都返回 None")
    }

    @TestCase
    func testBoolReduction() {
        println("\n=== bool 归约 ===")
        let items = ArrayList<LispValue>()
        items.add(LispValue.Boolean(false))
        items.add(LispValue.Boolean(true))
        let b = match (arrayFromLisp(listLv(items.toArray()))) {
            case x: NDArray => x
            case _ => iArr([0])
        }
        expectStr(reduceArray(b, "max").toString(), "Some(true)", "bool max")
        expectStr(reduceArray(b, "min").toString(), "Some(false)", "bool min")
        match (reduceArray(b, "sum")) {
            case Some(_) => @Fail("bool 数组 sum 应当不支持")
            case None => ()
        }
        println("✓ bool 的 max/min 可用，sum/product 拒绝")
    }

    /** 视图归约按逻辑顺序 */
    @TestCase
    func testReductionOnView() {
        println("\n=== 视图归约 ===")
        let base = iArr([10, 20, 30, 40])
        let s = sliceArray(base, 1, 3)
        expectStr(reduceArray(s, "sum").toString(), "Some(50)", "切片 sum")
        println("✓ 切片视图归约正确")
    }
}

@Test
class ElementwiseTest {
    @TestCase
    func testFloatFns() {
        println("\n=== 恒浮点的一组 ===")
        let a = fArr([0.0, 1.5707963267948966])   // [0, pi/2]
        let r = applyElementwiseArray(a, "sin")
        match (r) {
            case Some(v) => expectNDDisplay(v, "#<ndarray float64 [0.0 1.0]>", "sin arr")
            case None => @Fail("sin 应当支持")
        }
        // int 数组经过恒浮点函数后变成 float
        let i = iArr([4, 9])
        let s = applyElementwiseArray(i, "sqrt")
        match (s) {
            case Some(v) => expectNDDisplay(v, "#<ndarray float64 [2.0 3.0]>", "sqrt int arr")
            case None => @Fail("sqrt 应当支持")
        }
        println("✓ sin / sqrt，int 数组结果为 float")
    }

    /**
     * `floor` / `ceil` 转整数
     *
     * 与 core 的标量行为一致：`(floor 3.7)` 是 `3`（整数），
     * `(nth arr (floor 3.7))` 才能直接用。
     */
    @TestCase
    func testFloorCeilToInt() {
        println("\n=== floor / ceil 转整数 ===")
        let a = fArr([3.7, -3.2, 2.0])
        let f = applyElementwiseArray(a, "floor")
        match (f) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [3 -4 2]>", "floor")
            case None => @Fail("floor 应当支持")
        }
        let c = applyElementwiseArray(a, "ceil")
        match (c) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [4 -3 2]>", "ceil")
            case None => @Fail("ceil 应当支持")
        }
        println("✓ floor / ceil 结果为 int64")
    }

    @TestCase
    func testPreservingDtype() {
        println("\n=== abs / sign 保留量纲 ===")
        let i = iArr([-3, 0, 4])
        match (applyElementwiseArray(i, "abs")) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [3 0 4]>", "int abs")
            case None => @Fail("abs 应当支持")
        }
        match (applyElementwiseArray(i, "sign")) {
            case Some(v) => expectNDDisplay(v, "#<ndarray int64 [-1 0 1]>", "int sign")
            case None => @Fail("sign 应当支持")
        }
        let f = fArr([-2.5, 0.0])
        match (applyElementwiseArray(f, "abs")) {
            case Some(v) => expectNDDisplay(v, "#<ndarray float64 [2.5 0.0]>", "float abs")
            case None => @Fail("abs 应当支持")
        }
        println("✓ abs / sign 入参 int 得 int、入参 float 得 float")
    }

    @TestCase
    func testUnknownFnIsNone() {
        println("\n=== 不认识的函数 ===")
        match (applyElementwiseArray(iArr([1]), "nosuchfn")) {
            case Some(_) => @Fail("不认识的函数应当返回 None")
            case None => ()
        }
        println("✓ 未知函数返回 None")
    }

    /** 定义域外返回 nan / -inf 而不是抛异常 */
    @TestCase
    func testDomainOutside() {
        println("\n=== 定义域外 ===")
        let a = fArr([-1.0, 0.0, 1.0])
        let r = applyElementwiseArray(a, "log")
        match (r) {
            case Some(v) =>
                match (v) {
                    case External(e) =>
                        match (e) {
                            case nd: NDArray =>
                                let v0 = match (nd.at(0)) { case Float(x) => x; case _ => 0.0 }
                                let v1 = match (nd.at(1)) { case Float(x) => x; case _ => 0.0 }
                                let v2 = match (nd.at(2)) { case Float(x) => x; case _ => 0.0 }
                                if (!v0.isNaN()) { @Fail("log(-1) 应为 nan，实际 ${v0}") }
                                if (!v1.isInf() || v1 > 0.0) { @Fail("log(0) 应为 -inf，实际 ${v1}") }
                                if (v2 != 0.0) { @Fail("log(1) 应为 0，实际 ${v2}") }
                            case _ => @Fail("应返回 ndarray")
                        }
                    case _ => @Fail("应返回 ndarray")
                }
            case None => @Fail("log 应当支持")
        }
        println("✓ log：-1→nan、0→-inf、1→0")
    }
}
