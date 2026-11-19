package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList

/**
 * 数组的算术 / 归约 / 逐元素数学 —— 契约测试（Lisp 层，三后端差分）
 *
 * 这些能力**不在数组域里注册符号**：`+ - * /` 是 core 的算术内建，`sin` / `sum`
 * 是 core 的标量数学与归约，它们遇到 `LispValue.External(NDArray)` 时按能力接口
 * 分派到本仓。所以这一组测试的真正对象是**跨仓的分派链路**。
 */

func opsBackendNames(): Array<String> {
    ["AST", "BC", "JIT"]
}

func evalOpsWithBackend(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    if (backend != "AST") {
        opts.add(withBytecodeCompiler())
    }
    if (backend == "JIT") {
        opts.add(withJit())
    }
    let it = LispInterpreter(opts.toArray())
    var result: LispValue = Nil
    for (expr in Parser.parseFromString(code)) {
        result = it.evalExpr(expr)
    }
    result
}

func opsKindOf(v: LispValue): String {
    match (v) {
        case Error(err) => err.kind.name()
        case _ => ""
    }
}

func assertOpsAll(code: String, expect: String): Unit {
    for (b in opsBackendNames()) {
        let r = evalOpsWithBackend(code, b)
        let k = opsKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] 期望 `${expect}`，实际报错 ${k}：${r.toString()}（代码：${code}）")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] 期望 `${expect}`，实际 `${r.toString()}`（代码：${code}）")
        }
    }
}

func assertOpsError(code: String, expectKind: String): Unit {
    for (b in opsBackendNames()) {
        let r = evalOpsWithBackend(code, b)
        let k = opsKindOf(r)
        if (k.size == 0) {
            @Fail("[${b}] 期望错误 `${expectKind}`，实际正常值 ${r.toString()}（代码：${code}）")
        }
        if (k != expectKind) {
            @Fail("[${b}] 期望 `${expectKind}`，实际 `${k}`（代码：${code}）")
        }
    }
}

@Test
class ArrayArithTest {
    /**
     * 同形与标量：`(+ arr arr)` / `(+ arr 10)` / `(+ 10 arr)`
     *
     * 这条链路是 `+`（core）→ `LispExternalArithmetic`（本仓）。它通了，
     * "数组拿到一等公民待遇"才成立。
     */
    @TestCase
    func testBasicArith() {
        println("\n=== 基本算术 ===")
        assertOpsAll("(+ (cangjie::array [1 2 3]) (cangjie::array [10 20 30]))",
            "#<ndarray int64 [11 22 33]>")
        assertOpsAll("(+ (cangjie::array [1 2 3]) 10)", "#<ndarray int64 [11 12 13]>")
        assertOpsAll("(+ 10 (cangjie::array [1 2 3]))", "#<ndarray int64 [11 12 13]>")
        assertOpsAll("(* (cangjie::array [1 2 3]) 2)", "#<ndarray int64 [2 4 6]>")
        println("✓ 同形与两个方向的标量")
    }

    /**
     * 减法 / 除法的方向
     *
     * `(- 10 arr)` 必须是 `10 - arr`。断言里的值故意不对称，方向反了立刻能看出。
     */
    @TestCase
    func testDirection() {
        println("\n=== 方向 ===")
        assertOpsAll("(- (cangjie::array [1 2 3]) 10)", "#<ndarray int64 [-9 -8 -7]>")
        assertOpsAll("(- 10 (cangjie::array [1 2 3]))", "#<ndarray int64 [9 8 7]>")
        assertOpsAll("(/ (cangjie::array [2 4 8]) 2)", "#<ndarray float64 [1.0 2.0 4.0]>")
        assertOpsAll("(/ 8 (cangjie::array [2 4 8]))", "#<ndarray float64 [4.0 2.0 1.0]>")
        println("✓ 10-arr = [9 8 7]，arr-10 = [-9 -8 -7]")
    }

    /** 一元取负 */
    @TestCase
    func testUnaryMinus() {
        println("\n=== 一元取负 ===")
        assertOpsAll("(- (cangjie::array [1 -2 3]))", "#<ndarray int64 [-1 2 -3]>")
        println("✓ (- arr) 取负")
    }

    /**
     * 广播
     *
     * `(+ [[1] [2]] [[3 4]])` => `[[4 5] [5 6]]` —— 与 NumPy 一致。
     * 这条同时验证了 `stride = 0` 的广播视图取值正确。
     */
    @TestCase
    func testBroadcast() {
        println("\n=== 广播 ===")
        assertOpsAll("(+ (cangjie::array [[1] [2]]) (cangjie::array [[3 4]]))",
            "#<ndarray int64 [[4 5] [5 6]]>")
        // 矩阵 + 行向量
        assertOpsAll("(+ (cangjie::array [[1 2] [3 4]]) (cangjie::array [10 20]))",
            "#<ndarray int64 [[11 22] [13 24]]>")
        assertOpsAll("(* (cangjie::array [[1] [2] [3]]) 10)",
            "#<ndarray int64 [[10] [20] [30]]>")
        println("✓ 单位维扩张与尾部对齐")
    }

    /** dtype 提升与除法的浮点结果 */
    @TestCase
    func testDType() {
        println("\n=== dtype ===")
        assertOpsAll("(+ (cangjie::array [1 2]) 0.5)", "#<ndarray float64 [1.5 2.5]>")
        // 除法恒浮点：与 core 的 (/ 1 2) => 0.5 一致
        assertOpsAll("(/ (cangjie::array [1 2]) 2)", "#<ndarray float64 [0.5 1.0]>")
        println("✓ int+float→float；除法恒 float")
    }

    /** N 元折叠：`(+ a b c)` 是 `(a+b)+c` */
    @TestCase
    func testNaryFold() {
        println("\n=== N 元折叠 ===")
        assertOpsAll("(+ (cangjie::array [1 2]) (cangjie::array [10 20]) (cangjie::array [100 200]))",
            "#<ndarray int64 [111 222]>")
        println("✓ 三参相加按左结合折叠")
    }

    // ===== 错误路径 =====

    @TestCase
    func testIncompatibleShapes() {
        println("\n=== 形状不兼容 ===")
        // [2,3] + [2] —— 3 与 2 无法对齐
        assertOpsError("(+ (cangjie::array [[1 2 3] [4 5 6]]) (cangjie::array [1 2]))",
            "TypeError")
        println("✓ 不兼容返回 TypeError")
    }

    @TestCase
    func testBoolArithRejected() {
        println("\n=== bool 不参与算术 ===")
        assertOpsError("(+ (cangjie::array [#t #f]) 1)", "TypeError")
        println("✓ bool 数组算术报 TypeError")
    }
}

@Test
class ArrayReduceTest {
    /**
     * 归约：`(sum arr)` / `(max arr)` 等
     *
     * core 的 `sum` / `max` 此前**只认 Cons 链**，数组传进去会静默得到 0。
     * 这条钉住 `LispExternalReducible` 分派已接通。
     */
    @TestCase
    func testReductions() {
        println("\n=== 归约 ===")
        assertOpsAll("(sum (cangjie::array [1 2 3 4]))", "10")
        assertOpsAll("(product (cangjie::array [1 2 3 4]))", "24")
        assertOpsAll("(max (cangjie::array [3 1 4 1 5]))", "5")
        assertOpsAll("(min (cangjie::array [3 1 4 1 5]))", "1")
        println("✓ sum / product / max / min 走外部值归约")
    }

    @TestCase
    func testFloatReduction() {
        println("\n=== 浮点归约 ===")
        assertOpsAll("(sum (cangjie::array [1.5 2.5]))", "4.000000")
        println("✓ 浮点归约返回浮点")
    }

    /** 2D 数组的归约作用于全部元素（不按轴） */
    @TestCase
    func test2DReduction() {
        println("\n=== 2D 归约 ===")
        assertOpsAll("(sum (cangjie::array [[1 2] [3 4]]))", "10")
        assertOpsAll("(max (cangjie::array [[1 9] [3 4]]))", "9")
        println("✓ 2D 归约取全元素")
    }

    /**
     * 空数组归约必须报错
     *
     * 若返回 0 或 nil，"读文件读空了"就会伪装成一个正常结果。
     */
    @TestCase
    func testEmptyReduction() {
        println("\n=== 空数组归约 ===")
        assertOpsError("(sum (cangjie::array []))", "TypeError")
        assertOpsError("(max (cangjie::array []))", "TypeError")
        println("✓ 空数组归约报 TypeError")
    }

    /** 旧行为不能破坏：列表归约仍然可用 */
    @TestCase
    func testListReductionStillWorks() {
        println("\n=== 列表归约不受影响 ===")
        assertOpsAll("(sum '(1 2 3))", "6")
        assertOpsAll("(max '(1 5 3))", "5")
        println("✓ 列表与变参形式不变")
    }
}

@Test
class ArrayElementwiseTest {
    /**
     * `(sin arr)` 与 `(sin 1.0)` 同一个符号
     *
     * 这是"不搞两套名字"的落地验证：`sin` 是 core 的标量函数，
     * 遇到数组时按 `LispExternalElementwise` 分派成逐元素。
     */
    @TestCase
    func testElementwiseMath() {
        println("\n=== 逐元素数学 ===")
        assertOpsAll("(sin (cangjie::array [0.0]))", "#<ndarray float64 [0.0]>")
        assertOpsAll("(sqrt (cangjie::array [4.0 9.0]))", "#<ndarray float64 [2.0 3.0]>")
        // int 数组经恒浮点函数得到 float 数组
        assertOpsAll("(sqrt (cangjie::array [4 9]))", "#<ndarray float64 [2.0 3.0]>")
        assertOpsAll("(exp (cangjie::array [0.0]))", "#<ndarray float64 [1.0]>")
        println("✓ sin / sqrt / exp 逐元素生效")
    }

    /** `floor` / `ceil` 转整数，与标量行为一致 */
    @TestCase
    func testFloorCeil() {
        println("\n=== floor / ceil ===")
        assertOpsAll("(floor (cangjie::array [3.7 -3.2]))", "#<ndarray int64 [3 -4]>")
        assertOpsAll("(ceil (cangjie::array [3.2 -3.7]))", "#<ndarray int64 [4 -3]>")
        println("✓ floor / ceil 结果为 int64")
    }

    /** `abs` / `sign` 保留量纲 */
    @TestCase
    func testAbsSign() {
        println("\n=== abs / sign ===")
        assertOpsAll("(abs (cangjie::array [-3 0 4]))", "#<ndarray int64 [3 0 4]>")
        assertOpsAll("(sign (cangjie::array [-3 0 4]))", "#<ndarray int64 [-1 0 1]>")
        assertOpsAll("(abs (cangjie::array [-2.5 1.5]))", "#<ndarray float64 [2.5 1.5]>")
        println("✓ abs / sign 保留入参 dtype")
    }

    /** 定义域外不报错，nan / -inf 沿数组传播 */
    @TestCase
    func testDomainOutside() {
        println("\n=== 定义域外 ===")
        let r = evalOpsWithBackend("(sqrt (cangjie::array [-1.0]))", "AST")
        let text = r.toString()
        if (text.indexOf("nan").isNone()) {
            @Fail("(sqrt [-1.0]) 结果应为 nan，实际 ${text}")
        }
        let l = evalOpsWithBackend("(log (cangjie::array [0.0]))", "AST")
        if (l.toString().indexOf("inf").isNone()) {
            @Fail("(log [0.0]) 结果应为 -inf，实际 ${l.toString()}")
        }
        println("✓ sqrt(-1)→nan、log(0)→-inf")
    }

    /**
     * 视图上的逐元素运算
     *
     * `slice` 出来的视图 offset 非 0，逐元素运算必须按逻辑下标取值，
     * 不能直接遍历 buffer 从头开始。
     */
    @TestCase
    func testOnView() {
        println("\n=== 视图上运算 ===")
        assertOpsAll("(sqrt (cangjie::slice (cangjie::array [1 4 9 16]) 1 3))",
            "#<ndarray float64 [2.0 3.0]>")
        println("✓ 切片视图逐元素正确")
    }

    /** 标量路径不受影响 */
    @TestCase
    func testScalarStillWorks() {
        println("\n=== 标量不受影响 ===")
        assertOpsAll("(sqrt 4)", "2.000000")
        assertOpsAll("(sin 0)", "0.000000")
        println("✓ 同一个符号对数字仍走数值路径")
    }
}
