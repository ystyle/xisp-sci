package ystyle::xisp_tests

import ystyle::xisp.*
import ystyle::xisp_array.*
import ystyle::xisp_stats.*
import ystyle::xisp_bc.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 分组聚合的契约测试（Lisp 层，三后端差分）
 *
 * `group-agg` 要**回调 Lisp 函数**（`cangjie::mean` 或用户写的 lambda），
 * 与 `fmin` / `rk4` 走同一条 `ctx.invoke` 路径 —— 三后端都必须通。
 */

func evalGroup(code: String, backend: String): LispValue {
    let opts = ArrayList<InterpreterOption>()
    opts.add(withQuietMode())
    opts.add(withStdLib())
    opts.add(withArray())
    opts.add(withStats())
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

func kindOfG(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

func assertAllBackends(code: String, expect: String, what: String): Unit {
    for (b in ["AST", "BC", "JIT"]) {
        let r = evalGroup(code, b)
        let k = kindOfG(r)
        if (k.size > 0) {
            @Fail("[${b}] ${what}：报错 ${k} — ${r.toString()}")
        }
        if (r.toString() != expect) {
            @Fail("[${b}] ${what}：期望 `${expect}`，实际 `${r.toString()}`")
        }
    }
}

@Test
class GroupContractTest {
    /**
     * `group-by` 返回 alist：`[[key, ndarray] …]`，按首次出现顺序
     */
    @TestCase
    func testGroupBy() {
        println("\n=== group-by ===")
        // 用 (list "a" "b" "a") 作键，(cangjie::array [1 2 3]) 作值
        let code = "(cangjie::group-by (list \"a\" \"b\" \"a\") (cangjie::array [1.0 2.0 3.0]))"
        // 结构是 [[a, ndarray[1,3]], [b, ndarray[2]]]
        assertAllBackends(code,
            "((\"a\" #<ndarray float64 [1.0 3.0]>) (\"b\" #<ndarray float64 [2.0]>))",
            "两组，按首次出现顺序")
        println("✓ 两组，顺序 a → b")
    }

    /**
     * `group-agg` 一行出聚合结果
     */
    @TestCase
    func testGroupAggWithNativeFunc() {
        println("\n=== group-agg + 内建函数 ===")
        let code = "(cangjie::group-agg (list \"a\" \"b\" \"a\") " +
            "(cangjie::array [1.0 2.0 3.0]) cangjie::mean)"
        // a 组 (1+3)/2 = 2, b 组 2
        assertAllBackends(code, "((\"a\" 2.000000) (\"b\" 2.000000))",
            "按组求均值")
        println("✓ a 组均值 2，b 组均值 2")
    }

    /**
     * `group-agg` 也能接用户写的 lambda
     *
     * 这是"回调 Lisp 函数"的关键路径：内建函数是宿主代码，lambda 是解释器里的闭包，
     * 两者在 `ctx.invoke` 里走不同分支。
     */
    @TestCase
    func testGroupAggWithLambda() {
        println("\n=== group-agg + lambda ===")
        let code = "(cangjie::group-agg (list \"a\" \"a\" \"b\") " +
            "(cangjie::array [1.0 3.0 10.0]) (lambda (v) (* 2 (cangjie::max v))))"
        // a 组 max = 3 → 6；b 组 max = 10 → 20
        assertAllBackends(code, "((\"a\" 6.000000) (\"b\" 20.000000))",
            "lambda 聚合")
        println("✓ 用 lambda 求「组内最大值 × 2」")
    }

    /**
     * 与 `map` 配合：手工拼聚合结果
     *
     * `group-by` 返回 alist 的价值就在这里 —— 可以直接喂给 `map`。
     */
    @TestCase
    func testComposeWithMap() {
        println("\n=== 与 map 组合 ===")
        let code = "(map (lambda (kv) (list (car kv) (cangjie::mean (cadr kv)))) " +
            "(cangjie::group-by (list \"a\" \"b\" \"a\") (cangjie::array [1.0 2.0 3.0])))"
        assertAllBackends(code, "((\"a\" 2.000000) (\"b\" 2.000000))",
            "group-by + map")
        println("✓ alist 可直接被 map 处理")
    }

    /**
     * 数值键也能分组（比如按年份分组）
     */
    @TestCase
    func testNumericKeys() {
        println("\n=== 数值键 ===")
        let code = "(cangjie::group-agg (cangjie::array [1 2 1]) " +
            "(cangjie::array [10.0 20.0 30.0]) cangjie::mean)"
        assertAllBackends(code, "((\"1\" 20.000000) (\"2\" 20.000000))",
            "按整数键分组")
        println("✓ 整数键（转成十进制字符串）")
    }

    @TestCase
    func testErrors() {
        println("\n=== 错误路径 ===")
        // 长度不匹配
        let r = evalGroup(
            "(cangjie::group-by (list \"a\" \"b\") (cangjie::array [1.0]))", "AST")
        if (kindOfG(r) != "TypeError") {
            @Fail("长度不匹配应报 TypeError，实际 ${r.toString()}")
        }
        // 参数个数不对
        let r2 = evalGroup("(cangjie::group-by (list \"a\"))", "AST")
        if (kindOfG(r2) != "TypeError") {
            @Fail("参数不足应报 TypeError，实际 ${r2.toString()}")
        }
        println("✓ 长度不匹配与参数不足都报 TypeError")
    }
}
