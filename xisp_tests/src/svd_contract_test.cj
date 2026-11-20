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
 * SVD / 特征分解 / 派生量的契约测试（Lisp 层）
 *
 * 白盒测试（`xisp_linalg/src/svd_test.cj`）验的是算法；这里验的是**接线**：
 * 六个符号真的注册进去了、返回的 HashMap 键名对得上、`rank` 返回 `Int` 而不是
 * `Float`、非对称矩阵在 Lisp 层变成 `TypeError`。
 *
 * 另一个重点是**三后端一致** —— 这些函数本身是纯数值，但结果要经过 `HashMap`
 * 与 `External` 两条路径回到 Lisp，与 `t-test` 遇到的是同一类接线问题。
 */

@Test
class SvdContractTest {
    /**
     * 域声明的符号清单里真有这 6 个
     *
     * `LispCapability.symbols` 是沙箱审计与文档生成的唯一来源，清单与实现对不上
     * 会让上层以为可用 —— 本仓有过这类教训。
     */
    @TestCase
    func testSymbolsDeclared() {
        println("\n=== linalg 域符号清单 ===")
        let declared = linalgDomain().symbols
        for (name in ["cangjie::svd", "cangjie::eigen", "cangjie::rank",
            "cangjie::cond", "cangjie::ginv", "cangjie::pca"]) {
            var found = false
            for (d in declared) {
                if (d == name) {
                    found = true
                    break
                }
            }
            if (!found) {
                @Fail("linalg 域符号清单缺 ${name}")
            }
        }
        println("  linalg 域共 ${declared.size} 个符号")
        if (declared.size != 15) {
            @Fail("linalg 域应有 15 个符号（9 分解求解 + 6 派生量），实际 ${declared.size}")
        }
    }

    /** `rank` / `cond`：Lisp 层能拿到正确的数 */
    @TestCase
    func testRankAndCond() {
        println("\n=== Lisp 层的 rank / cond ===")
        assertLinNum("(cangjie::rank (cangjie::array [[1.0 2.0] [3.0 4.0]]))",
            2.0, 0.0, "满秩 2×2")
        assertLinNum("(cangjie::rank (cangjie::array [[1.0 2.0] [2.0 4.0]]))",
            1.0, 0.0, "秩 1")
        assertLinNum("(cangjie::cond (cangjie::array [[1.0 0.0] [0.0 1.0]]))",
            1.0, 1e-10, "单位阵条件数")
        // 用 `1e-3` 而不是 `0.001`：这一行同时是**科学计数法的回归测试** ——
        // xisp 0.9.3 之前词法器没有指数分支，`1e-3` 会被切成 `Int(1)` + 符号 `e-3`，
        // 报 `Undefined variable`。写成科学计数法让这条测试顺带守住那个缺口。
        assertLinNum("(cangjie::cond (cangjie::array [[1.0 0.0] [0.0 1e-3]]))",
            1000.0, 1e-6, "diag(1,1e-3) 条件数")
    }

    /**
     * `svd`：返回 `{u, s, vt}`，奇异值从 Lisp 层取得到
     *
     * `A = [[1,2],[3,4]]` 的奇异值是 `5.4649857` / `0.3659662`。
     */
    @TestCase
    func testSvdAtLispLevel() {
        println("\n=== Lisp 层的 svd ===")
        let code = "(define a (cangjie::array [[1.0 2.0] [3.0 4.0]]))\n" +
            "(define r (cangjie::svd a))\n" +
            "(nth (hashmap-get r \"s\") 0)"
        assertLinNum(code, 5.4649857042190426, 1e-9, "σmax")
        let code2 = "(define a (cangjie::array [[1.0 2.0] [3.0 4.0]]))\n" +
            "(define r (cangjie::svd a))\n" +
            "(nth (hashmap-get r \"s\") 1)"
        assertLinNum(code2, 0.3659661906262574, 1e-9, "σmin")
    }

    /**
     * `eigen`：对称矩阵给 {values, vectors}；非对称报 TypeError
     */
    @TestCase
    func testEigenAtLispLevel() {
        println("\n=== Lisp 层的 eigen ===")
        let code = "(define a (cangjie::array [[2.0 1.0] [1.0 2.0]]))\n" +
            "(define r (cangjie::eigen a))\n" +
            "(nth (hashmap-get r \"values\") 0)"
        assertLinNum(code, 3.0, 1e-10, "最大特征值")
        // 非对称：必须报 TypeError，不能悄悄给出「看起来正常」的结果
        assertLinError("(cangjie::eigen (cangjie::array [[1.0 2.0] [3.0 4.0]]))",
            "非对称矩阵报错")
    }

    /** `ginv`：`A·A⁺·A = A` 在 Lisp 层也成立 */
    @TestCase
    func testPinvAtLispLevel() {
        println("\n=== Lisp 层的 ginv ===")
        // 秩 1 的 2×2，inv 会报错，ginv 有定义
        let code = "(define a (cangjie::array [[1.0 2.0] [2.0 4.0]]))\n" +
            "(define p (cangjie::ginv a))\n" +
            "(define apa (cangjie::matmul (cangjie::matmul a p) a))\n" +
            "(nth (nth apa 0) 1)"
        assertLinNum(code, 2.0, 1e-9, "A·A⁺·A 的 (0,1) 元素")
        // 对照：inv 对同一个矩阵必须报错
        assertLinError("(cangjie::inv (cangjie::array [[1.0 2.0] [2.0 4.0]]))",
            "奇异矩阵的 inv 报错")
    }

    /** `pca`：解释方差之和为 1 */
    @TestCase
    func testPcaAtLispLevel() {
        println("\n=== Lisp 层的 pca ===")
        let code = "(define x (cangjie::array [[2.5 2.4] [0.5 0.7] [2.2 2.9] [1.9 2.2] " +
            "[3.1 3.0] [2.3 2.7] [2.0 1.6] [1.0 1.1] [1.5 1.6] [1.1 0.9]]))\n" +
            "(define p (cangjie::pca x))\n" +
            "(define ve (hashmap-get p \"var-explained\"))\n" +
            "(+ (nth ve 0) (nth ve 1))"
        assertLinNum(code, 1.0, 1e-12, "var-explained 之和")
        let code2 = "(define x (cangjie::array [[2.5 2.4] [0.5 0.7] [2.2 2.9] [1.9 2.2] " +
            "[3.1 3.0] [2.3 2.7] [2.0 1.6] [1.0 1.1] [1.5 1.6] [1.1 0.9]]))\n" +
            "(define p (cangjie::pca x))\n" +
            "(nth (hashmap-get p \"sdev\") 0)"
        assertLinNum(code2, 1.1331494659455936, 1e-9, "第一主成分的 sdev")
    }

    /**
     * 三后端一致性
     *
     * `assertLinNum` 本身就对 AST / BC / JIT 各跑一遍并比同一个数，
     * 所以这两条同时也验证了后端无关性。
     */
    @TestCase
    func testThreeBackendsAgree() {
        println("\n=== 三后端一致性 ===")
        // 对称正定的条件数 = λmax/λmin = 4.8794/1.4679
        assertLinNum("(cangjie::cond (cangjie::array [[4.0 1.0 1.0] [1.0 3.0 0.0] [1.0 0.0 2.0]]))",
            3.324028, 1e-5, "3×3 的条件数")
        assertLinNum("(cangjie::rank (cangjie::array [[1.0 2.0 3.0] [4.0 5.0 6.0] [7.0 8.0 9.0]]))",
            2.0, 0.0, "3×3 秩亏矩阵的秩")
    }
}
