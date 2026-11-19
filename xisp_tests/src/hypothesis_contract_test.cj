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
 * 假设检验的契约测试（Lisp 层，三后端差分）
 *
 * t 检验全是纯数值计算，但结果要通过 `HashMap` 返回 —— 这条路径在三后端上都得通。
 */

func evalHyp(code: String, backend: String): LispValue {
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

func kindOfH(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

/** 从 HashMap 取浮点字段 */
func fieldOf(v: LispValue, key: String): Float64 {
    match (v) {
        case HashMap(m) =>
            match (m.get(key)) {
                case Some(Float(x)) => x
                case Some(Int(i)) => Float64(i)
                case _ => Float64.getNaN()
            }
        case _ => Float64.getNaN()
    }
}

@Test
class HypothesisContractTest {
    /**
     * 单样本 t 检验：三后端给出同一个 p 值
     */
    @TestCase
    func testOneSample() {
        println("\n=== 单样本 t 检验 ===")
        // [1,2,3,4,5] 对 μ0=4：t = -1.4142，p 约 0.2291
        let code = "(cangjie::t-test1 (cangjie::array [1.0 2.0 3.0 4.0 5.0]) 4.0)"
        var firstP = Float64.getNaN()
        for (b in ["AST", "BC", "JIT"]) {
            let r = evalHyp(code, b)
            let k = kindOfH(r)
            if (k.size > 0) {
                @Fail("[${b}] 报错 ${k} — ${r.toString()}")
            }
            let p = fieldOf(r, "p")
            if (p.isNaN()) {
                @Fail("[${b}] 没拿到 p 值")
            }
            if (firstP.isNaN()) {
                firstP = p
            } else if (abs(firstP - p) > 1e-12) {
                @Fail("[${b}] p 值与 AST 不一致：${p} vs ${firstP}")
            }
        }
        // p 应大于 0.05（5 个样本、差 1，不显著）
        if (firstP < 0.05) {
            @Fail("这个例子不该显著，p = ${firstP}")
        }
        println("✓ 三后端 p 值一致（${firstP}），不显著")
    }

    /**
     * 双样本 Welch：明显差异时 p 很小
     */
    @TestCase
    func testTwoSample() {
        println("\n=== 双样本 t 检验 ===")
        let code = "(cangjie::t-test2 (cangjie::array [10.0 11.0 12.0 13.0 14.0]) " +
            "(cangjie::array [20.0 21.0 22.0 23.0 24.0]))"
        var firstP = Float64.getNaN()
        for (b in ["AST", "BC", "JIT"]) {
            let r = evalHyp(code, b)
            let k = kindOfH(r)
            if (k.size > 0) {
                @Fail("[${b}] 报错 ${k}")
            }
            let p = fieldOf(r, "p")
            if (firstP.isNaN()) {
                firstP = p
            } else if (abs(firstP - p) > 1e-12) {
                @Fail("[${b}] p 不一致")
            }
        }
        if (firstP > 1e-4) {
            @Fail("两组差 10，p 应远小于 1e-4，实际 ${firstP}")
        }
        println("✓ 三后端 p 值一致（${firstP}）")
    }

    /**
     * 置信区间：三后端一致，且区间包含均值
     */
    @TestCase
    func testConfidenceInterval() {
        println("\n=== 置信区间 ===")
        let code = "(cangjie::ci (cangjie::array [2.0 4.0 6.0 8.0]) 0.95)"
        var lo = Float64.getNaN()
        var hi = Float64.getNaN()
        var m = Float64.getNaN()
        for (b in ["AST", "BC", "JIT"]) {
            let r = evalHyp(code, b)
            let k = kindOfH(r)
            if (k.size > 0) {
                @Fail("[${b}] 报错 ${k}")
            }
            let l = fieldOf(r, "lo")
            let h = fieldOf(r, "hi")
            let mv = fieldOf(r, "mean")
            if (lo.isNaN()) {
                lo = l
                hi = h
                m = mv
            } else if (abs(lo - l) > 1e-12 || abs(hi - h) > 1e-12) {
                @Fail("[${b}] 区间不一致")
            }
        }
        if (!(lo < m && m < hi)) {
            @Fail("区间应包含均值：[${lo}, ${hi}] 不含 ${m}")
        }
        println("✓ 三后端一致，区间 [${lo}, ${hi}] 包含均值 ${m}")
    }

    @TestCase
    func testErrors() {
        println("\n=== 错误路径 ===")
        // 单样本只给 1 个数
        let r = evalHyp("(cangjie::t-test1 (cangjie::array [1.0]) 0.0)", "AST")
        if (kindOfH(r) != "TypeError") {
            @Fail("单样本 1 个数应报 TypeError，实际 ${r.toString()}")
        }
        // 置信水平非法
        let r2 = evalHyp("(cangjie::ci (cangjie::array [1.0 2.0]) 1.5)", "AST")
        if (kindOfH(r2) != "TypeError") {
            @Fail("置信水平 1.5 应报 TypeError，实际 ${r2.toString()}")
        }
        // 零方差
        let r3 = evalHyp("(cangjie::t-test1 (cangjie::array [5.0 5.0 5.0]) 3.0)", "AST")
        if (kindOfH(r3) != "TypeError") {
            @Fail("零方差应报 TypeError，实际 ${r3.toString()}")
        }
        println("✓ 三类错误都报 TypeError")
    }
}
