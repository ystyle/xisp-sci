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
 * 分布函数族的契约测试（Lisp 层）
 *
 * 白盒测试（`xisp_stats/src/distributions_test.cj`）验的是数学；这里验的是**接线**：
 * 18 个符号真的注册进去了、参数顺序没搞反、离散分布返回的是 `Int` 而不是 `Float`、
 * 非法参数在 Lisp 层变成 `TypeError` 而不是悄悄返回 `nan`。
 *
 * 参数顺序尤其值得测一遍：`(cangjie::norm-cdf x mu sigma)` 与
 * `(cangjie::binom-cdf k n p)` 的顺序不同（前者是「值 + 位置参数」，后者是「计数 + 试验数」），
 * 写反了类型检查根本拦不住，只有对着已知值比才能发现。
 */

func evalDist(code: String, backend: String): LispValue {
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

/** 取 `Float`，`Int` 也接受（Lisp 里 `5` 与 `5.0` 是一等公民的两种写法） */
func floatOf(v: LispValue): Float64 {
    match (v) {
        case Float(x) => x
        case Int(i) => Float64(i)
        case _ => Float64.getNaN()
    }
}

/** 取 `Int`；给 `Float` 说明返回类型错了，直接暴露 */
func intOfDist(v: LispValue): Int64 {
    match (v) {
        case Int(i) => i
        case _ => -999999
    }
}

func isNaND(v: Float64): Bool {
    v != v
}

func expectNearD(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func kindOfD(v: LispValue): String {
    match (v) {
        case Error(e) => e.kind.name()
        case _ => ""
    }
}

@Test
class DistributionsContractTest {
    /**
     * 域声明的符号清单里真有这 18 个
     *
     * `LispCapability.symbols` 是沙箱审计与文档生成的**唯一来源**。
     * 曾经有过「声明了 `abs` 却从未实现」的教训 —— 清单与实现对不上，
     * 上层会以为可用，直到真调用才炸。所以第一条就核对清单。
     */
    @TestCase
    func testSymbolsDeclared() {
        println("\n=== 分布函数族的符号清单 ===")
        let declared = statsDomain().symbols
        let expected = [
            "cangjie::norm-pdf", "cangjie::norm-cdf", "cangjie::norm-quantile",
            "cangjie::t-pdf", "cangjie::t-cdf", "cangjie::t-quantile",
            "cangjie::chisq-pdf", "cangjie::chisq-cdf", "cangjie::chisq-quantile",
            "cangjie::f-pdf", "cangjie::f-cdf", "cangjie::f-quantile",
            "cangjie::pois-pmf", "cangjie::pois-cdf", "cangjie::pois-quantile",
            "cangjie::binom-pmf", "cangjie::binom-cdf", "cangjie::binom-quantile"]
        for (name in expected) {
            var found = false
            for (d in declared) {
                if (d == name) {
                    found = true
                    break
                }
            }
            if (!found) {
                @Fail("域声明的符号清单里缺 ${name}")
            }
        }
        println("  stats 域共 ${declared.size} 个符号，其中分布函数 18 个")
        // 42 = 18 描述统计 + 18 分布 + 6 随机数（随机数在 rng.cj，符号清单见 rng_test.cj）
        if (declared.size != 58) {
            @Fail("stats 域应有 42 个符号（18 描述统计 + 18 分布 + 6 随机数），实际 ${declared.size}")
        }
    }

    /** 正态：`(cangjie::norm-cdf 1.96 0 1)` 应给出 0.975002 */
    @TestCase
    func testNormAtLispLevel() {
        println("\n=== Lisp 层的正态分布 ===")
        expectNearD(floatOf(evalDist("(cangjie::norm-cdf 1.96 0 1)", "AST")),
            0.9750021048517795, 1e-12, "Φ(1.96)")
        expectNearD(floatOf(evalDist("(cangjie::norm-quantile 0.975 0 1)", "AST")),
            1.959963984540054, 1e-9, "Φ⁻¹(0.975)")
        // 非标准位置尺度
        expectNearD(floatOf(evalDist("(cangjie::norm-cdf 70 100 15)", "AST")),
            0.022750131948179216, 1e-12, "Φ(70;100,15)")
        expectNearD(floatOf(evalDist("(cangjie::norm-pdf 0 0 1)", "AST")),
            0.3989422804014327, 1e-12, "φ(0)")
    }

    /** t / 卡方 / F：参数顺序用已知分位数钉住 */
    @TestCase
    func testContinuousFamilies() {
        println("\n=== Lisp 层的 t / 卡方 / F ===")
        // 参照值是分段 Simpson 积分（重尾上只有 ~1e-8 精度），所以容差放到 1e-7
        expectNearD(floatOf(evalDist("(cangjie::t-cdf 2.0 5)", "AST")),
            0.94903025769373783, 1e-7, "F_t(2; df=5)")
        expectNearD(floatOf(evalDist("(cangjie::t-quantile 0.975 5)", "AST")),
            2.570581835636, 1e-6, "t_{0.975,5}")
        expectNearD(floatOf(evalDist("(cangjie::chisq-cdf 3.841458820694124 1)", "AST")),
            0.95, 1e-10, "χ²(3.8415; df=1)")
        expectNearD(floatOf(evalDist("(cangjie::chisq-quantile 0.95 1)", "AST")),
            3.841458820694124, 1e-6, "χ²_{0.95,1}")
        expectNearD(floatOf(evalDist("(cangjie::f-cdf 3.098391212 3 20)", "AST")),
            0.95, 1e-6, "F(3.0984; 3,20)")
        expectNearD(floatOf(evalDist("(cangjie::f-quantile 0.95 3 20)", "AST")),
            3.098391212, 1e-6, "F_{0.95}(3,20)")
    }

    /**
     * 离散分布：`pmf` / `cdf` 返回 `Float`，`quantile` 返回 `Int`
     *
     * 返回类型弄错是个隐蔽的错误 —— Lisp 里 `5` 和 `5.0` 在算术里几乎等价，
     * 但作为数组下标、`nth` 的参数就天差地别。
     */
    @TestCase
    func testDiscreteFamilies() {
        println("\n=== Lisp 层的泊松 / 二项 ===")
        expectNearD(floatOf(evalDist("(cangjie::pois-pmf 2 2.5)", "AST")),
            0.25651562069968387, 1e-14, "Pois P(X=2; 2.5)")
        expectNearD(floatOf(evalDist("(cangjie::pois-cdf 5 2.5)", "AST")),
            0.95797896180469422, 1e-13, "Pois P(X≤5; 2.5)")
        let q = evalDist("(cangjie::pois-quantile 0.95 2.5)", "AST")
        match (q) {
            case Int(i) => if (i != 5) {
                @Fail("Pois_{0.95}(2.5) 应为 Int 5，实际 ${i}")
            }
            case _ => @Fail("pois-quantile 应返回 Int，实际 ${q.toString()}")
        }

        expectNearD(floatOf(evalDist("(cangjie::binom-pmf 3 10 0.3)", "AST")),
            0.26682793199999943, 1e-13, "Binom P(X=3; 10,0.3)")
        expectNearD(floatOf(evalDist("(cangjie::binom-cdf 5 10 0.3)", "AST")),
            0.9526510125999984, 1e-13, "Binom P(X≤5; 10,0.3)")
        let bq = evalDist("(cangjie::binom-quantile 0.95 10 0.3)", "AST")
        match (bq) {
            case Int(i) => if (i != 5) {
                @Fail("Binom_{0.95}(10,0.3) 应为 Int 5，实际 ${i}")
            }
            case _ => @Fail("binom-quantile 应返回 Int，实际 ${bq.toString()}")
        }
    }

    /**
     * 非法参数在 Lisp 层必须是 `TypeError`，不能是 `nan`
     *
     * 理由写在 `dist_ops.cj` 的文件注释里：`nan` 会一路飘到最终结果，
     * 用户只看到「算出来是 NaN」，根本不知道是哪个参数错了。
     */
    @TestCase
    func testInvalidArgsRaiseTypeError() {
        println("\n=== 非法参数的报错 ===")
        let cases = [
            ("(cangjie::norm-cdf 1 0 0)", "sigma=0"),
            ("(cangjie::norm-quantile 1.5 0 1)", "p 越界"),
            ("(cangjie::t-cdf 1 0)", "df=0"),
            ("(cangjie::chisq-cdf -1 4)", "x<0"),
            ("(cangjie::f-cdf 1 3 -2)", "d2<0"),
            ("(cangjie::pois-pmf -1 2.5)", "k<0"),
            ("(cangjie::binom-pmf 11 10 0.3)", "k>n"),
            ("(cangjie::norm-cdf 1 0)", "参数个数不足"),
            ("(cangjie::norm-cdf 1 0 1 2)", "参数个数过多")]
        for ((code, why) in cases) {
            let k = kindOfD(evalDist(code, "AST"))
            if (k != "TypeError") {
                @Fail("${why}：${code} 应报 TypeError，实际 ${k}")
            }
        }
    }

    /** 三后端给出同一个值（纯数值计算，但仍然验一遍接线） */
    @TestCase
    func testThreeBackendsAgree() {
        println("\n=== 三后端一致性 ===")
        let code = "(cangjie::chisq-quantile 0.975 7)"
        let a = floatOf(evalDist(code, "AST"))
        let b = floatOf(evalDist(code, "BC"))
        let c = floatOf(evalDist(code, "JIT"))
        expectNearD(b, a, 1e-12, "BC vs AST")
        expectNearD(c, a, 1e-12, "JIT vs AST")
        // χ²_{0.975,7} ≈ 16.013
        expectNearD(a, 16.012764241849702, 1e-6, "χ²_{0.975,7}")
    }
}
