package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_linalg.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 线性代数的契约测试（Lisp 层，三后端差分）
 *
 * 浮点运算在所有后端跑的是同一份仓颉代码，理论上结果逐位相同 —— 这条要验，
 * 因为一旦某个后端把 `matmul` 之类当成可优化的纯函数做了常量折叠，
 * 差异会以"某个后端结果略不同"的形式出现，极难排查。
 */

func linBackendNames(): Array<String> {
    ["AST", "BC", "JIT"]
}

func evalLin(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    opts.add(withLinalg())
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

func linKindOf(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

/** 三后端结果字符串必须完全一致 */
func assertLinSame(code: String, expect: String, what: String): Unit {
    for (b in linBackendNames()) {
        let r = evalLin(code, b)
        let k = linKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] ${what}：期望 `${expect}`，实际 `${r.toString()}`")
        }
    }
}

/** 三后端都报 TypeError */
func assertLinError(code: String, what: String): Unit {
    for (b in linBackendNames()) {
        let r = evalLin(code, b)
        let k = linKindOf(r)
        if (k != "TypeError") {
            let shown = if (k.size > 0) { k } else { r.toString() }
            @Fail("[${b}] ${what}：期望 TypeError，实际 ${shown}")
        }
    }
}

/** 三后端结果数值都接近期望 */
func assertLinNum(code: String, want: Float64, tol: Float64, what: String): Unit {
    for (b in linBackendNames()) {
        let r = evalLin(code, b)
        let k = linKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}")
        }
        let got = match (r) {
            case Float(x) => x
            case Int(i) => Float64(i)
            case _ => Float64.getNaN()
        }
        if (abs(got - want) > tol) {
            @Fail("[${b}] ${what}：期望 ${want}，实际 ${got}")
        }
    }
}

@Test
class LinalgContractTest {
    /**
     * 矩阵乘法：`(cangjie::matmul A B)`
     *
     * `[[1,2],[3,4]] × [[5,6],[7,8]] = [[19,22],[43,50]]`
     */
    @TestCase
    func testMatmul() {
        println("\n=== 矩阵乘法 ===")
        assertLinSame(
            "(cangjie::matmul (cangjie::array [[1 2] [3 4]]) (cangjie::array [[5 6] [7 8]]))",
            "#<ndarray float64 [[19.0 22.0] [43.0 50.0]]>", "2x2 乘法")
        // 点积返回标量
        assertLinNum("(cangjie::matmul (cangjie::array [1 2 3]) (cangjie::array [4 5 6]))",
            32.0, 1e-12, "点积")
        println("✓ 2×2 与点积")
    }

    /**
     * 行列式与迹
     */
    @TestCase
    func testDetTrace() {
        println("\n=== 行列式 / 迹 ===")
        assertLinNum("(cangjie::det (cangjie::array [[1 2] [3 4]]))", -2.0, 1e-12, "det")
        assertLinNum("(cangjie::trace (cangjie::array [[1 2] [3 4]]))", 5.0, 1e-12, "trace")
        println("✓ det = -2，trace = 5")
    }

    /**
     * 解方程与求逆
     *
     * 逆矩阵用**定义性质**验：`A × A⁻¹` 应是单位阵。
     */
    @TestCase
    func testSolveInv() {
        println("\n=== 解方程 / 求逆 ===")
        assertLinSame(
            "(cangjie::solve (cangjie::array [[2 1] [1 3]]) (cangjie::array [5 10]))",
            "#<ndarray float64 [1.0 3.0]>", "solve")
        // A × A⁻¹ = I
        assertLinSame(
            "(cangjie::matmul (cangjie::array [[4 7] [2 6]]) (cangjie::inv (cangjie::array [[4 7] [2 6]])))",
            "#<ndarray float64 [[1.0 0.0] [0.0 1.0]]>", "A × A⁻¹")
        println("✓ solve 与 inv（用定义性质验）")
    }

    /**
     * Cholesky：`L Lᵀ = A`
     */
    @TestCase
    func testCholesky() {
        println("\n=== Cholesky ===")
        assertLinSame(
            "(cangjie::cholesky (cangjie::array [[4 12 -16] [12 37 -43] [-16 -43 98]]))",
            "#<ndarray float64 [[2.0 0.0 0.0] [6.0 1.0 0.0] [-8.0 5.0 3.0]]>",
            "Cholesky L")
        println("✓ 下三角 L 正确")
    }

    /**
     * QR：`Q R = A`
     */
    @TestCase
    func testQr() {
        println("\n=== QR ===")
        // 3x2 矩阵，Q 是 3x3、R 是 3x2
        let code = "(define qr (cangjie::qr (cangjie::array [[1 2] [3 4] [5 6]])))\n" +
            "(cangjie::matmul (hashmap-get qr \"q\") (hashmap-get qr \"r\"))"
        assertLinSame(code, "#<ndarray float64 [[1.0 2.0] [3.0 4.0] [5.0 6.0]]>", "Q R = A")
        println("✓ Q R = A")
    }

    /**
     * LU：`P A = L U`
     */
    @TestCase
    func testLu() {
        println("\n=== LU ===")
        // 不换行的情形：L U 直接等于 A
        let code = "(define lu (cangjie::lu (cangjie::array [[4 3] [2 1]])))\n" +
            "(cangjie::matmul (hashmap-get lu \"l\") (hashmap-get lu \"u\"))"
        assertLinSame(code, "#<ndarray float64 [[4.0 3.0] [2.0 1.0]]>", "L U = A")
        println("✓ L U = A")
    }

    // ===== 错误路径 =====

    /**
     * 奇异矩阵、非正定、非对称、维度不匹配 —— 全部要报 TypeError
     *
     * 这些情形返回"看起来像答案"的垃圾值是最危险的：下游会拿着它继续算。
     */
    @TestCase
    func testErrors() {
        println("\n=== 错误路径 ===")
        // 奇异矩阵求逆
        assertLinError("(cangjie::inv (cangjie::array [[1 2] [2 4]]))", "奇异矩阵 inv")
        // 奇异矩阵解方程
        assertLinError("(cangjie::solve (cangjie::array [[1 2] [2 4]]) (cangjie::array [1 2]))",
            "奇异矩阵 solve")
        // 非正定
        assertLinError("(cangjie::cholesky (cangjie::array [[1 2] [2 1]]))", "非正定 cholesky")
        // 非对称
        assertLinError("(cangjie::cholesky (cangjie::array [[1 2] [3 4]]))", "非对称 cholesky")
        // matmul 维度不匹配
        assertLinError("(cangjie::matmul (cangjie::array [[1 2]]) (cangjie::array [[1 2]]))",
            "matmul 维度不匹配")
        // det 非方阵
        assertLinError("(cangjie::det (cangjie::array [[1 2 3]]))", "非方阵 det")
        // 非 ndarray 参数
        assertLinError("(cangjie::det 42)", "标量 det")
        println("✓ 六类错误都报 TypeError")
    }

    /**
     * 选择主元不是可选项
     *
     * `[[0,1],[1,0]]` 第一步主元就是 0，不选主元会直接除零。
     */
    @TestCase
    func testPivotingNeeded() {
        println("\n=== 需要选主元 ===")
        assertLinSame(
            "(cangjie::solve (cangjie::array [[0 1] [1 0]]) (cangjie::array [2 3]))",
            "#<ndarray float64 [3.0 2.0]>", "零主元矩阵求解")
        println("✓ 零主元矩阵也能解")
    }

    /**
     * 病态矩阵仍能反演出接近单位阵
     *
     * Hilbert 3×3 条件数约 7.5e2，误差会被放大但仍在可控范围。
     */
    @TestCase
    func testIllConditioned() {
        println("\n=== 病态矩阵 ===")
        let code = "(define h (cangjie::array [[1.0 0.5 0.3333333333333333] " +
            "[0.5 0.3333333333333333 0.25] [0.3333333333333333 0.25 0.2]]))\n" +
            "(cangjie::matmul h (cangjie::inv h))"
        let r = evalLin(code, "AST")
        let k = linKindOf(r)
        if (k.size > 0) {
            @Fail("Hilbert 求逆失败：${k} ${r.toString()}")
        }
        match (r) {
            case External(e) => match (e) {
                case a: NDArray =>
                    // 对角线应接近 1，非对角线接近 0
                    let d0 = match (a.at(0)) { case Float(x) => x; case _ => 0.0 }
                    let off = match (a.at(1)) { case Float(x) => x; case _ => 0.0 }
                    if (abs(d0 - 1.0) > 1e-6) {
                        @Fail("Hilbert 求逆后对角元素偏离 1：${d0}")
                    }
                    if (abs(off) > 1e-6) {
                        @Fail("Hilbert 求逆后非对角元素不为 0：${off}")
                    }
                case _ => @Fail("应返回 ndarray")
            }
            case _ => @Fail("应返回 ndarray")
        }
        println("✓ 病态矩阵求逆后接近单位阵（容差 1e-6）")
    }
}
