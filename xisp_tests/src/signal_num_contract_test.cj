package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_signal.*
import ystyle::xisp_num.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 阶段 5 的契约测试：信号处理与数值方法
 *
 * 三后端差分是重点中的重点 —— `fmin` / `rk4` 要**回调 Lisp 函数**，
 * 这条路径在 0.9.x 之前于字节码后端下根本不通（见 core 的 `ctx.invoke` 修复）。
 */

func sciBackendNames(): Array<String> {
    ["AST", "BC", "JIT"]
}

func evalSci(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    opts.add(withSignal())
    opts.add(withNum())
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

func sciKindOf(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

func assertSciSame(code: String, expect: String, what: String): Unit {
    for (b in sciBackendNames()) {
        let r = evalSci(code, b)
        let k = sciKindOf(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] ${what}：期望 `${expect}`，实际 `${r.toString()}`")
        }
    }
}

func assertSciNum(code: String, want: Float64, tol: Float64, what: String): Unit {
    for (b in sciBackendNames()) {
        let r = evalSci(code, b)
        let k = sciKindOf(r)
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

/** 取 HashMap 里的第 k 个元素并转成 Float64 数组 */
func arrOfField(v: LispValue, field: String, idx: Int64): Float64 {
    match (v) {
        case HashMap(m) =>
            match (m.get(field)) {
                case Some(External(e)) =>
                    match (e) {
                        case a: NDArray =>
                            match (a.at(idx)) {
                                case Float(x) => x
                                case Int(i) => Float64(i)
                                case _ => Float64.getNaN()
                            }
                        case _ => Float64.getNaN()
                    }
                case _ => Float64.getNaN()
            }
        case _ => Float64.getNaN()
    }
}

@Test
class SignalContractTest {
    /**
     * FFT 的复数表示：`{"re": …, "im": …}`
     *
     * 常数信号的直流分量是 n，其余为 0。
     */
    @TestCase
    func testFftRepresentation() {
        println("\n=== FFT 复数表示 ===")
        let r = evalSci("(cangjie::fft (cangjie::array [1.0 1.0 1.0 1.0]))", "AST")
        let k = sciKindOf(r)
        if (k.size > 0) {
            @Fail("FFT 报错：${k}")
        }
        if (abs(arrOfField(r, "re", 0) - 4.0) > 1e-9) {
            @Fail("直流分量应为 4，实际 ${arrOfField(r, "re", 0)}")
        }
        if (abs(arrOfField(r, "im", 0)) > 1e-9) {
            @Fail("直流分量虚部应为 0")
        }
        if (abs(arrOfField(r, "re", 1)) > 1e-9) {
            @Fail("k=1 实部应为 0")
        }
        println("✓ 返回 {re, im}，直流分量为 n")
    }

    /** 幅度谱 */
    @TestCase
    func testMagnitude() {
        println("\n=== 幅度谱 ===")
        // 冲激信号的幅度谱全 1
        assertSciSame("(cangjie::fft-magnitude (cangjie::array [1.0 0.0 0.0 0.0]))",
            "#<ndarray float64 [1.0 1.0 1.0 1.0]>", "冲激的幅度谱")
        println("✓ 冲激 → 全 1")
    }

    /** 往返：IFFT(FFT(x)) 在 Lisp 层也应恒等 */
    @TestCase
    func testRoundTrip() {
        println("\n=== Lisp 层往返 ===")
        let code = "(define f (cangjie::fft (cangjie::array [1.0 2.0 3.0 4.0 5.0])))\n" +
            "(cangjie::ifft f)"
        let r = evalSci(code, "AST")
        let k = sciKindOf(r)
        if (k.size > 0) {
            @Fail("往返报错：${k}")
        }
        expectCloseVal(arrOfField(r, "re", 0), 1.0, 1e-9, "x[0]")
        expectCloseVal(arrOfField(r, "re", 2), 3.0, 1e-9, "x[2]")
        expectCloseVal(arrOfField(r, "re", 4), 5.0, 1e-9, "x[4]")
        println("✓ IFFT(FFT(x)) = x（5 点，走 Bluestein）")
    }

    /** 卷积与冲激 */
    @TestCase
    func testConv() {
        println("\n=== 卷积 ===")
        assertSciSame("(cangjie::conv (cangjie::array [1.0 0.0 0.0]) (cangjie::array [2.0 -1.0 0.5]))",
            "#<ndarray float64 [2.0 -1.0 0.5 0.0 0.0]>", "冲激卷积")
        println("✓ 冲激卷积 = 恒等（补零到 full 长度）")
    }

    /** IIR 滤波 */
    @TestCase
    func testFilter() {
        println("\n=== IIR 滤波 ===")
        // 两抽头移动平均
        assertSciSame(
            "(cangjie::filter (cangjie::array [0.5 0.5]) (cangjie::array [1.0]) " +
            "(cangjie::array [1.0 2.0 3.0 4.0]))",
            "#<ndarray float64 [0.5 1.5 2.5 3.5]>", "移动平均")
        println("✓ 两抽头移动平均")
    }

    /** 窗函数 */
    @TestCase
    func testWindow() {
        println("\n=== 窗函数 ===")
        assertSciSame("(cangjie::window \"hann\" 5)",
            "#<ndarray float64 [0.0 0.5 1.0 0.5 0.0]>", "Hann 窗")
        assertSciSame("(cangjie::window \"rect\" 3)",
            "#<ndarray float64 [1.0 1.0 1.0]>", "矩形窗")
        println("✓ Hann / 矩形窗")
    }
}

func expectCloseVal(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (abs(actual - want) > tol) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

@Test
class NumContractTest {
    @TestCase
    func testInterp() {
        println("\n=== 线性插值 ===")
        assertSciSame(
            "(cangjie::interp1 (cangjie::array [0.0 1.0 2.0]) (cangjie::array [0.0 10.0 20.0]) " +
            "(cangjie::array [0.5 1.5]))",
            "#<ndarray float64 [5.0 15.0]>", "中点插值")
        println("✓ 中点线性插值")
    }

    /**
     * 多项式拟合 + 求值
     *
     * `y = 2x² + 3x + 1` 采样后拟合，再用 `polyval` 回代。
     */
    @TestCase
    func testPolyfitPolyval() {
        println("\n=== 拟合与求值 ===")
        let code = "(define c (cangjie::polyfit " +
            "(cangjie::array [-2.0 -1.0 0.0 1.0 2.0]) " +
            "(cangjie::array [3.0 0.0 1.0 6.0 15.0]) 2))\n" +
            "(cangjie::polyval c 3.0)"
        // 3 处应为 2*9+3*3+1 = 28
        assertSciNum(code, 28.0, 1e-6, "polyfit + polyval")
        println("✓ 拟合还原后求值得 28")
    }

    @TestCase
    func testIntegral() {
        println("\n=== 数值积分 ===")
        // y = x 在 [0,1] 上 = 0.5
        assertSciNum(
            "(cangjie::trapz (cangjie::array [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]) 0.1)",
            0.5, 1e-12, "梯形积分")
        // Simpson 对二次函数精确：y = x² 积分 = 1/3
        let ys = ArrayList<String>()
        var i: Int64 = 0
        while (i < 11) {
            let t = Float64(i) / 10.0
            ys.add("${t * t}")
            i++
        }
        let arr = ys.toArray().toString()   // 形如 ["0.0", "0.01", ...]
        // 直接用固定串，避免依赖数组 toString 的格式
        let code = "(cangjie::simpson (cangjie::array [0.0 0.01 0.04 0.09 0.16 0.25 0.36 0.49 0.64 0.81 1.0]) 0.1)"
        assertSciNum(code, 1.0 / 3.0, 1e-12, "Simpson 对二次函数")
        println("✓ 梯形与 Simpson")
    }

    /**
     * **优化回调 Lisp 函数**
     *
     * `(cangjie::fmin (lambda (x) (* (- x 2) (- x 2))) 0 5)` → 2
     *
     * 这条在字节码后端下曾经不通（`ctx.invoke` 的配置快照问题）。
     */
    @TestCase
    func testFminCallback() {
        println("\n=== 优化回调 ===")
        assertSciNum("(cangjie::fmin (lambda (x) (* (- x 2) (- x 2))) 0 5)", 2.0, 1e-5, "fmin")
        println("✓ fmin 找到 x = 2（三后端都通）")
    }

    /**
     * **ODE 回调 Lisp 函数**
     *
     * `dy/dt = y` 的解是 `eᵗ`。
     */
    @TestCase
    func testRk4Callback() {
        println("\n=== ODE 回调 ===")
        let code = "(define r (cangjie::rk4 (lambda (t y) y) 1.0 0.0 1.0 0.05))\n" +
            "(nth (hashmap-get r \"y\") 20)"
        assertSciNum(code, 2.718281828459045, 1e-5, "rk4 解指数增长")
        println("✓ rk4 解 dy/dt = y 得 e（三后端都通）")
    }

    // ===== 错误路径 =====

    @TestCase
    func testErrors() {
        println("\n=== 错误路径 ===")
        // 插值 x 非升序
        let bad = evalSci("(cangjie::interp1 (cangjie::array [1.0 0.0]) " +
            "(cangjie::array [0.0 1.0]) (cangjie::array [0.5]))", "AST")
        if (sciKindOf(bad) != "TypeError") {
            @Fail("x 非升序应报 TypeError，实际 ${bad.toString()}")
        }
        // Simpson 偶数个点
        let bad2 = evalSci("(cangjie::simpson (cangjie::array [1.0 2.0 3.0 4.0]) 0.1)", "AST")
        if (sciKindOf(bad2) != "TypeError") {
            @Fail("偶数点 Simpson 应报 TypeError，实际 ${bad2.toString()}")
        }
        // rk4 步长为 0
        let bad3 = evalSci("(cangjie::rk4 (lambda (t y) y) 1.0 0.0 1.0 0.0)", "AST")
        if (sciKindOf(bad3) != "TypeError") {
            @Fail("步长 0 应报 TypeError，实际 ${bad3.toString()}")
        }
        println("✓ 三类参数错误报 TypeError")
    }
}
