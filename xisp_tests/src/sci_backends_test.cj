package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_sci.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*
import ystyle::xisp_bc.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList

/**
 * 门面装配在三后端下的一致性
 *
 * 现有契约测试都是**单独装配**某一族（`withArray()` / `withStats()` / …）。
 * 这一组验证 `withSci()`（一次装齐六族）在 AST / 字节码 / JIT 下行为一致。
 *
 * ## 为什么要单独验
 *
 * 三处路径会因装配方式不同而出问题：
 *
 * 1. **算术快速路径**：`+ - * / < > =` 被求值器提升成特殊形式，字节码还把它们编译成
 *    `OP_ADD` 等指令（VM 里内联实现）。外部值要走 `binNumFallback` 才能到
 *    `LispExternalArithmetic` —— 0.9.0 就是因为 VM 的 12 处内联实现漏了这个，
 *    在 BC 后端报 `+: expected a number`。
 * 2. **域里回调 Lisp 函数**：`group-agg` / `fmin` / `rk4` 走 `ctx.invoke`。`invoke`
 *    用宿主配置快照去调 `applyFunction`，快照里没有 `decompiler` 就调不动编译闭包
 *    （0.9.1 前 BC/JIT 报 `closure without bytecode backend`）。
 * 3. **域装配顺序**：上面那个快照问题在 0.9.2 修成「每次调用前刷新」，所以装配顺序
 *    才不再是隐式依赖。
 *
 * 这三条都只有**真的装齐六族并切到 BC/JIT** 才能一起验到。
 */

func backends(): Array<String> {
    ["AST", "BC", "JIT"]
}

/** 用门面装配跑一段代码 */
func evalSciBackend(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withSci())
    if (backend != "AST") {
        opts.add(withBytecodeCompiler())
    }
    if (backend == "JIT") {
        opts.add(withJit())
    }
    let it = LispInterpreter(opts.toArray())
    var r: LispValue = Nil
    for (e in Parser.parseFromString(code)) {
        r = it.evalExpr(e)
    }
    r
}

func kindOfS(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

/** 三后端结果字符串必须一致 */
func assertSame(code: String, expect: String, what: String): Unit {
    for (b in backends()) {
        let r = evalSciBackend(code, b)
        let k = kindOfS(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] ${what}：期望 `${expect}`，实际 `${r.toString()}`")
        }
    }
}

@Test
class SciBackendsTest {
    /**
     * 数组算术走快速路径
     *
     * `+` 在 AST 里是特殊形式、在 BC 里是 `OP_ADD`、在 JIT 里是另一种内联 ——
     * 三条路径都必须回落到 `LispExternalArithmetic`。
     */
    @TestCase
    func testArrayArithmetic() {
        println("\n=== 数组算术（快速路径）===")
        assertSame("(+ (cangjie::array [1 2 3]) 10)",
            "#<ndarray int64 [11 12 13]>", "数组 + 标量")
        assertSame("(* (cangjie::array [1 2 3]) (cangjie::array [2 2 2]))",
            "#<ndarray int64 [2 4 6]>", "数组 × 数组")
        assertSame("(sum (cangjie::array [1 2 3 4]))", "10", "归约")
        println("✓ + × sum 三后端一致")
    }

    /**
     * 六个族各取一个代表符号
     */
    @TestCase
    func testAllSixFamilies() {
        println("\n=== 六族代表符号 ===")
        // stats
        assertSame("(cangjie::mean (cangjie::array [1.0 2.0 3.0]))", "2.000000", "stats")
        // linalg
        assertSame("(cangjie::det (cangjie::array [[1 2] [3 4]]))", "-2.000000", "linalg")
        // signal
        assertSame("(cangjie::fft-magnitude (cangjie::array [1.0 0.0 0.0 0.0]))",
            "#<ndarray float64 [1.0 1.0 1.0 1.0]>", "signal")
        // num
        assertSame("(cangjie::polyval (cangjie::array [2.0 3.0 1.0]) 2.0)", "15.000000", "num")
        // io
        assertSame("(hashmap-get (cangjie::csv-parse \"a,b\\n1,2\\n\") \"b\")",
            "#<ndarray int64 [2]>", "io")
        println("✓ stats / linalg / signal / num / io 三后端一致")
    }

    /**
     * **域里回调 Lisp 函数** —— 这条最容易在 BC/JIT 断
     *
     * 三个符号都走 `ctx.invoke`，而 `invoke` 需要宿主配置里有 `decompiler`
     * 才能调用编译后的闭包。
     */
    @TestCase
    func testCallbacksIntoDomain() {
        println("\n=== 域回调 Lisp 函数 ===")
        // group-agg 回调内建函数
        assertSame(
            "(cangjie::group-agg (list \"a\" \"b\" \"a\") (cangjie::array [1.0 2.0 3.0]) cangjie::mean)",
            "((\"a\" 2.000000) (\"b\" 2.000000))", "group-agg + 内建")
        // group-agg 回调用户 lambda
        let g = "(cangjie::group-agg (list \"a\" \"a\") (cangjie::array [1.0 5.0]) " +
            "(lambda (v) (cangjie::max v)))"
        for (b in backends()) {
            let r = evalSciBackend(g, b)
            if (kindOfS(r).size > 0) {
                @Fail("[${b}] group-agg + lambda 报错：${r.toString()}")
            }
        }
        // fmin 回调
        for (b in backends()) {
            let r = evalSciBackend("(cangjie::fmin (lambda (x) (* (- x 2) (- x 2))) 0 5)", b)
            if (kindOfS(r).size > 0) {
                @Fail("[${b}] fmin 报错：${r.toString()}")
            }
        }
        // rk4 回调
        for (b in backends()) {
            let r = evalSciBackend("(length (hashmap-get (cangjie::rk4 (lambda (t y) y) 1.0 0.0 1.0 0.25) \"y\"))", b)
            if (kindOfS(r).size > 0) {
                @Fail("[${b}] rk4 报错：${r.toString()}")
            }
        }
        println("✓ group-agg / fmin / rk4 的回调在 BC 与 JIT 下都通")
    }

    /**
     * 装配顺序无关
     *
     * `withSci()` 内部按 `after` 约束重排域。把它放在 `withBytecodeCompiler()`
     * **之前**（正确做法）和**之后**（顺序反了）运行结果必须相同 —— 0.9.2 的
     * `ctx.invoke` 修复保证后者也能工作。
     */
    @TestCase
    func testAssemblyOrderIndependent() {
        println("\n=== 装配顺序无关 ===")
        let code = "(cangjie::group-agg (list \"a\" \"b\" \"a\") " +
            "(cangjie::array [1.0 2.0 3.0]) cangjie::mean)"
        // 正常顺序：域在前
        let o1 = ArrayList<InterpreterOption>()
        o1.add(withQuietMode())
        o1.add(withStdLib())
        o1.add(withSci())
        o1.add(withBytecodeCompiler())
        let it1 = LispInterpreter(o1.toArray())
        let r1 = it1.evalExpr(Parser.parseFromString(code)[0])

        // 反序：编译器在前
        let o2 = ArrayList<InterpreterOption>()
        o2.add(withQuietMode())
        o2.add(withStdLib())
        o2.add(withBytecodeCompiler())
        o2.add(withSci())
        let it2 = LispInterpreter(o2.toArray())
        let r2 = it2.evalExpr(Parser.parseFromString(code)[0])

        if (kindOfS(r1).size > 0 || kindOfS(r2).size > 0) {
            @Fail("其中一种顺序报错：${r1.toString()} / ${r2.toString()}")
        }
        if (r1.toString() != r2.toString()) {
            @Fail("装配顺序影响结果：\n  域在前: ${r1.toString()}\n  编译器在前: ${r2.toString()}")
        }
        println("✓ 两种装配顺序结果相同（0.9.2 的 ctx.invoke 修复生效）")
    }
}
