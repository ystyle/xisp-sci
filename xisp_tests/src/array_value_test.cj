package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*
// `BuiltinFunctions.presetFull()` 用于检查域名不与 core 预置域撞车
import ystyle::xisp.core.builtin.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList

/**
 * 数组能力（能力域 `array`）的契约测试
 *
 * 只用 public API（`withArray()` + Lisp 代码）验证**用户可见行为**；
 * 视图 / strides / 连续性这些仓颉层的语义在白盒测试
 * `xisp_array/src/ndarray_test.cj` 里测。
 */

/** 三个后端名 */
func arrayBackendNames(): Array<String> {
    ["AST", "BC", "JIT"]
}

/**
 * 在指定后端上求值一串表达式，返回最后一个值
 *
 * 遍历 `Parser.parseFromString` 而不是 `eval(String)`：后者会重建求值器，
 * 无法保留已装配的域。
 */
func evalArrayWithBackend(code: String, backend: String): LispValue {
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

func kindOfValue(v: LispValue): String {
    match (v) {
        case Error(err) => err.kind.name()
        case _ => ""
    }
}

/** 三后端结果必须一致 */
func assertArraySameAllBackends(code: String, expect: String): Unit {
    for (b in arrayBackendNames()) {
        let r = evalArrayWithBackend(code, b)
        let k = kindOfValue(r)
        if (k.size > 0) {
            @Fail("[${b}] 期望 `${expect}`，实际报错 ${k}：${r.toString()}（代码：${code}）")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] 期望 `${expect}`，实际 `${r.toString()}`（代码：${code}）")
        }
    }
}

/** 三后端都必须报同一种错误 */
func assertArrayErrorAllBackends(code: String, expectKind: String): Unit {
    for (b in arrayBackendNames()) {
        let r = evalArrayWithBackend(code, b)
        let k = kindOfValue(r)
        if (k.size == 0) {
            @Fail("[${b}] 期望错误 `${expectKind}`，实际正常值 ${r.toString()}（代码：${code}）")
        }
        if (k != expectKind) {
            @Fail("[${b}] 期望 `${expectKind}`，实际 `${k}`（代码：${code}）")
        }
    }
}

@Test
class ArrayValueTest {
    /**
     * 数组是外部值，`type-of` 得到 `ndarray`
     *
     * 这条钉住的是 `LispExternal.typeName` 与 core 的 `type-of` 之间的契约 ——
     * 改了 `typeName` 会让所有按类型分发的脚本失配。
     */
    @TestCase
    func testTypeOfIsNdarray() {
        println("\n=== type-of 得到 ndarray ===")
        // type-of 返回的是 Str，toString 会带引号
        assertArraySameAllBackends("(type-of (cangjie::array [1 2 3]))", "\"ndarray\"")
        assertArraySameAllBackends("(cangjie::ndarray? (cangjie::array [1 2]))", "true")
        assertArraySameAllBackends("(cangjie::ndarray? [1 2])", "false")
        println("✓ type-of = ndarray；ndarray? 只认 ndarray")
    }

    /**
     * 构造与 shape
     *
     * `(cangjie::shape a)` 返回列表，所以比较的是列表的 `toString`。
     */
    @TestCase
    func testConstructAndShape() {
        println("\n=== 构造与 shape ===")
        assertArraySameAllBackends("(cangjie::shape (cangjie::array [1 2 3 4 5]))", "(5)")
        assertArraySameAllBackends("(cangjie::shape (cangjie::array [[1 2] [3 4]]))", "(2 2)")
        // 变参形式与单参数形式等价
        assertArraySameAllBackends("(cangjie::shape (cangjie::array 1 2 3))", "(3)")
        // 嵌套两层的 3D
        assertArraySameAllBackends(
            "(cangjie::shape (cangjie::array [[[1 2] [3 4]] [[5 6] [7 8]]]))", "(2 2 2)")
        println("✓ 1D / 2D / 3D 与变参形式形状正确")
    }

    /**
     * `length` / `nth` 走 core 的通用内建，靠 `LispExternalIndexable` 分派
     *
     * 这是「数组获得一等公民观感」的关键证据：这两个符号**不在**数组域里注册，
     * 是 core 探测能力接口后分派的。如果哪天分派链路断了，这条先红。
     */
    @TestCase
    func testLengthAndNthDispatchThroughCore() {
        println("\n=== length / nth 走能力接口分派 ===")
        // 2x3 数组的 length 是 6（总元素数），不是 2
        assertArraySameAllBackends("(length (cangjie::array [[1 2 3] [4 5 6]]))", "6")
        assertArraySameAllBackends("(nth (cangjie::array [10 20 30]) 1)", "20")
        // 扁平语义：下标 3 是第 1 行第 0 列
        assertArraySameAllBackends("(nth (cangjie::array [[1 2 3] [4 5 6]]) 3)", "4")
        println("✓ length=总元素数，nth 按行优先扁平取值")
    }

    @TestCase
    func testDisplay() {
        println("\n=== 显示 ===")
        assertArraySameAllBackends("(cangjie::array [1 2 3])", "#<ndarray int64 [1 2 3]>")
        assertArraySameAllBackends(
            "(cangjie::array [[1 2] [3 4]])", "#<ndarray int64 [[1 2] [3 4]]>")
        assertArraySameAllBackends(
            "(cangjie::array [1.0 2.5])", "#<ndarray float64 [1.0 2.5]>")
        println("✓ 三种 dtype 的显示格式一致")
    }

    /**
     * 构造辅助函数
     */
    @TestCase
    func testConstructors() {
        println("\n=== zeros / ones / arange ===")
        assertArraySameAllBackends(
            "(cangjie::zeros 2 3)", "#<ndarray float64 [[0.0 0.0 0.0] [0.0 0.0 0.0]]>")
        assertArraySameAllBackends(
            "(cangjie::zeros [2 2])", "#<ndarray float64 [[0.0 0.0] [0.0 0.0]]>")
        assertArraySameAllBackends("(cangjie::ones 3)", "#<ndarray float64 [1.0 1.0 1.0]>")
        assertArraySameAllBackends("(cangjie::arange 0 5)", "#<ndarray int64 [0 1 2 3 4]>")
        assertArraySameAllBackends(
            "(cangjie::arange 0 1 0.25)", "#<ndarray float64 [0.0 0.25 0.5 0.75]>")
        println("✓ zeros / ones / arange（含浮点步长）")
    }

    /**
     * 形状操作与视图
     *
     * 视图语义在 Lisp 层只能观察到"形状变了、值对得上"，零拷贝由白盒测试钉。
     */
    @TestCase
    func testShapeOperations() {
        println("\n=== reshape / transpose / slice ===")
        assertArraySameAllBackends(
            "(cangjie::reshape (cangjie::arange 0 6) [2 3])",
            "#<ndarray int64 [[0 1 2] [3 4 5]]>")
        assertArraySameAllBackends(
            "(cangjie::reshape (cangjie::arange 0 6) [-1 3])",
            "#<ndarray int64 [[0 1 2] [3 4 5]]>")
        assertArraySameAllBackends(
            "(cangjie::transpose (cangjie::array [[1 2 3] [4 5 6]]))",
            "#<ndarray int64 [[1 4] [2 5] [3 6]]>")
        assertArraySameAllBackends(
            "(cangjie::slice (cangjie::arange 0 10) 2 5)",
            "#<ndarray int64 [2 3 4]>")
        // 2D 沿第 0 维取行
        assertArraySameAllBackends(
            "(cangjie::slice (cangjie::array [[1 2] [3 4] [5 6]]) 1 3)",
            "#<ndarray int64 [[3 4] [5 6]]>")
        println("✓ reshape（含 -1）/ transpose / slice")
    }

    /**
     * 视图与转置后 reshape 的顺序
     *
     * 转置出来的是**非连续**视图，`reshape` 必须先连续化；顺序错了会得到
     * 看似合理但完全错位的数据 —— 这条是那个坑的回归测试。
     */
    @TestCase
    func testTransposedReshapeOrder() {
        println("\n=== 转置后 reshape 的元素顺序 ===")
        // [[1 2 3] [4 5 6]] 转置 → [[1 4] [2 5] [3 6]] → 展平 → 1 4 2 5 3 6
        assertArraySameAllBackends(
            "(cangjie::reshape (cangjie::transpose (cangjie::array [[1 2 3] [4 5 6]])) [6])",
            "#<ndarray int64 [1 4 2 5 3 6]>")
        println("✓ 转置后展平顺序为 1 4 2 5 3 6（不是原始的 1 2 3 4 5 6）")
    }

    // ===== 错误路径 =====
    // 错误必须分类正确：TypeError 表示"参数类型不对"，RuntimeError 表示"值不对"。
    // 分错会让宿主的错误处理走错分支。

    @TestCase
    func testErrors() {
        println("\n=== 错误路径 ===")
        // 非规整嵌套
        assertArrayErrorAllBackends("(cangjie::array [[1 2] [3]])", "TypeError")
        // 不支持的元素类型
        assertArrayErrorAllBackends("(cangjie::array [1 \"x\"])", "TypeError")
        // bool 与 int 混排（xisp 的布尔字面量是 #t / #f，不是 true / false）
        assertArrayErrorAllBackends("(cangjie::array [#t 1])", "TypeError")
        // reshape 总数不符
        assertArrayErrorAllBackends(
            "(cangjie::reshape (cangjie::array [1 2 3]) [2 2])", "TypeError")
        // shape 传入非数组
        assertArrayErrorAllBackends("(cangjie::shape 42)", "TypeError")
        // arange 步长 0
        assertArrayErrorAllBackends("(cangjie::arange 0 5 0)", "TypeError")
        println("✓ 六类错误都归为 TypeError")
    }

    /**
     * 数组下标越界不是错误，而是错误值 —— 但 `nth` 的越界由 core 处理，
     * 这里验证它不会崩，且三后端一致。
     */
    @TestCase
    func testOutOfRangeNth() {
        println("\n=== nth 越界 ===")
        assertArrayErrorAllBackends("(nth (cangjie::array [1 2 3]) 99)", "RuntimeError")
        println("✓ 越界返回 RuntimeError，三后端一致")
    }
}
