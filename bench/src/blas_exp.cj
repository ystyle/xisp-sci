package ystyle::bench

import ystyle::xisp.*
import ystyle::xisp_sci.*
import ystyle::xisp_linalg.*
import ystyle::xisp_linalg_blas.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*
import std.collection.ArrayList
import std.time.*
import std.math.*

/**
 * BLAS 加速后端：端到端验证
 *
 * 走**真实使用路径** —— 用 `withSci()` 装配、在 Lisp 层调 `cangjie::matmul`，
 * 只是启动时多一行 `enableBlas()`。
 */
func blasExperiment(): Unit {
    log("\n## 十二、可选 BLAS 加速后端")
    log("")
    log("新成员 `xisp_linalg_blas`，零 C 代码 —— 只有一句 `foreign` 声明。")
    log("启动时调 `enableBlas()` 就切换后端，不调就是纯仓颉。")
    log("")

    let n: Int64 = 800
    let code = "(define A (cangjie::reshape (cangjie::arange 0 ${n * n}) [${n} ${n}]))\n" +
        "(cangjie::matmul A A)"

    // 纯仓颉
    clearMatmulBackend()
    let it1 = LispInterpreter([withQuietMode(), withStdLib(), withSci()])
    let e1 = Parser.parseFromString(code)
    for (e in e1) { it1.evalExpr(e) }
    let t0 = MonoTime.now()
    var r1: LispValue = Nil
    for (e in Parser.parseFromString("(cangjie::matmul A A)")) { r1 = it1.evalExpr(e) }
    let naiveMs = Float64((MonoTime.now() - t0).toNanoseconds()) / 1000000.0

    // BLAS
    enableBlas()
    let it2 = LispInterpreter([withQuietMode(), withStdLib(), withSci()])
    let e2 = Parser.parseFromString(code)
    for (e in e2) { it2.evalExpr(e) }
    let t1 = MonoTime.now()
    var r2: LispValue = Nil
    for (e in Parser.parseFromString("(cangjie::matmul A A)")) { r2 = it2.evalExpr(e) }
    let blasMs = Float64((MonoTime.now() - t1).toNanoseconds()) / 1000000.0

    let flops = 2.0 * Float64(n) * Float64(n) * Float64(n)
    log("| 后端 | 耗时 | GFLOPS | 相对 |")
    log("|---|---|---|---|")
    log("| 纯仓颉（默认） | ${formatMs(naiveMs)} | ${cut((flops/(naiveMs/1000.0)/1e9).toString(), 4)} | 1× |")
    log("| BLAS（`enableBlas()` 后） | ${formatMs(blasMs)} | ${cut((flops/(blasMs/1000.0)/1e9).toString(), 4)} | **${cut((naiveMs/blasMs).toString(), 4)}×** |")
    log("")
    // 结果一致性：两边都是 ndarray，比较 toString（截断显示不够，比数值）
    let same = r1.toString() == r2.toString()
    log("结果一致性：${if (same) { "✅ 两侧输出一致" } else { "⚠️ 输出不一致，需检查" }}")
    log("")
    log("### 跨平台")
    log("")
    log("**BLAS 不属于 libc**，是独立的数学库。CBLAS 接口的符号名跨平台一致，")
    log("差别只在链接参数：")
    log("")
    log("| 平台 | `link-option` | 库从哪来 |")
    log("|---|---|---|")
    log("| Linux | `-lblas` | 发行版包（Debian `libblas3`，要快装 `libopenblas0`） |")
    log("| macOS | `-framework Accelerate` | **系统自带**，Apple 优化过 |")
    log("| Windows | OpenBLAS 的库路径 | 需要自己装 |")
    log("")
    log("Linux 上「看起来像自带」通常是因为装了 numpy / scipy 顺带装上 —— fresh 系统其实没有。")
}
