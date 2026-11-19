package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import std.collection.ArrayList

/**
 * 分布函数族的 Lisp 接口
 *
 * ## 为什么单开一个文件
 *
 * `stats.cj` 里的 18 个符号都是「拿一列数据算一个数」；这一组是「给一个数算一个概率」。
 * 输入输出形状完全不同（前者吃数组、后者吃标量），混在一个文件里会让 `registerStats`
 * 长到没法读。数学实现在 `distributions.cj`，这里只做**参数校验 + 装箱**。
 *
 * ## 参数校验放在接口层，不放在数学层
 *
 * `distributions.cj` 里的函数对非法参数返回 `NaN` —— 那是数值代码的惯例（NaN 可以继续传播，
 * 让调用方自己决定怎么处理）。但 Lisp 层不一样：用户敲 `(cangjie::norm-cdf 1 0 0)` 得到的
 * 如果是一个 `nan`，它会一路飘到结果里，最后只看到「算出来是 NaN」，根本不知道
 * 是 `sigma=0` 引起的。
 *
 * 所以**接口层严格校验并抛错**，数学层保持宽容。分界线就在这里。
 */

/**
 * 包一层 NaN 检查
 *
 * 数学层对越界参数返回 `NaN`（数值代码的惯例：NaN 可以继续传播，让调用方决定），
 * 但 Lisp 层拿到 `nan` 只会一路飘到最终结果，用户看到的只是「算出来是 NaN」，
 * 根本不知道是哪个参数越界。这里统一转成明确的 `TypeError`。
 *
 * 显式校验（`positiveArg` / `probOpenArg` 等）覆盖常见错误并给出**具体到参数名**的消息；
 * 这一层只兜住剩下的边界（如 `x < 0`、`k > n`），消息不必那么细。
 */
func guardedDist(who: String, action: () -> LispValue): LispValue {
    let r = guardedStats(action)
    match (r) {
        case Float(x) => if (x != x) {
            LispValue.Error(XispError(ErrorType.TypeError,
                "${who}：参数超出分布的定义域（结果是 NaN）"))
        } else {
            r
        }
        case _ => r
    }
}

/** 参数个数校验 */
func requireArity(args: ArrayList<LispValue>, n: Int64, who: String): Unit {
    if (args.size != n) {
        throw IllegalArgumentException("${who} 需要 ${n} 个参数，得到 ${args.size}")
    }
}

/** 严格取整数参数：`Int` 才行，`5.0` 这种浮点不悄悄截断 */
func intArg(v: LispValue, who: String, name: String): Int64 {
    match (v) {
        case Int(i) => i
        case _ => throw IllegalArgumentException(
            "${who} 的 ${name} 需要整数，得到 ${v.toString()}")
    }
}

/** 必须为正的连续参数（`sigma` / `df` / `lambda` 的 `lambda` 可为 0，另走一条） */
func positiveArg(v: LispValue, who: String, name: String): Float64 {
    let x = numOf(v, who)
    if (x <= 0.0) {
        throw IllegalArgumentException("${who} 的 ${name} 必须 > 0，得到 ${x}")
    }
    x
}

/** 概率参数，必须落在开区间 `(0,1)`（`q*` 函数在端点无定义） */
func probOpenArg(v: LispValue, who: String, name: String): Float64 {
    let x = numOf(v, who)
    if (x <= 0.0 || x >= 1.0) {
        throw IllegalArgumentException("${who} 的 ${name} 必须在 (0,1) 开区间内，得到 ${x}")
    }
    x
}

/** 必须非负的参数（泊松的 `lambda` 可以是 0 —— 退化成「全压 0」） */
func nonNegativeArg(v: LispValue, who: String, name: String): Float64 {
    let x = numOf(v, who)
    if (x < 0.0) {
        throw IllegalArgumentException("${who} 的 ${name} 必须 ≥ 0，得到 ${x}")
    }
    x
}

/** 概率参数，允许端点 `[0,1]`（二项的 `p` 可以取 0 或 1） */
func probClosedArg(v: LispValue, who: String, name: String): Float64 {
    let x = numOf(v, who)
    if (x < 0.0 || x > 1.0) {
        throw IllegalArgumentException("${who} 的 ${name} 必须在 [0,1] 内，得到 ${x}")
    }
    x
}

/** 分布函数族占用的 18 个符号 */
let DIST_SYMBOLS: Array<String> = [
    "cangjie::norm-pdf", "cangjie::norm-cdf", "cangjie::norm-quantile",
    "cangjie::t-pdf", "cangjie::t-cdf", "cangjie::t-quantile",
    "cangjie::chisq-pdf", "cangjie::chisq-cdf", "cangjie::chisq-quantile",
    "cangjie::f-pdf", "cangjie::f-cdf", "cangjie::f-quantile",
    "cangjie::pois-pmf", "cangjie::pois-cdf", "cangjie::pois-quantile",
    "cangjie::binom-pmf", "cangjie::binom-cdf", "cangjie::binom-quantile"]

func registerDistributions(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // ───────────── 正态 N(μ, σ²) ─────────────

    // (cangjie::norm-pdf x mu sigma)
    env.define("cangjie::norm-pdf", NativeFunc({ args =>
        guardedDist("cangjie::norm-pdf", { =>
            requireArity(args, 3, "cangjie::norm-pdf")
            let who = "cangjie::norm-pdf"
            LispValue.Float(normPdf(numOf(args[0], who), numOf(args[1], who),
                positiveArg(args[2], who, "sigma")))
        })
    }))

    // (cangjie::norm-cdf x mu sigma)
    env.define("cangjie::norm-cdf", NativeFunc({ args =>
        guardedDist("cangjie::norm-cdf", { =>
            requireArity(args, 3, "cangjie::norm-cdf")
            let who = "cangjie::norm-cdf"
            LispValue.Float(normCdf(numOf(args[0], who), numOf(args[1], who),
                positiveArg(args[2], who, "sigma")))
        })
    }))

    // (cangjie::norm-quantile p mu sigma)
    env.define("cangjie::norm-quantile", NativeFunc({ args =>
        guardedDist("cangjie::norm-quantile", { =>
            requireArity(args, 3, "cangjie::norm-quantile")
            let who = "cangjie::norm-quantile"
            LispValue.Float(normQuantile(probOpenArg(args[0], who, "p"),
                numOf(args[1], who), positiveArg(args[2], who, "sigma")))
        })
    }))

    // ───────────── Student t(df) ─────────────

    // (cangjie::t-pdf t df)
    env.define("cangjie::t-pdf", NativeFunc({ args =>
        guardedDist("cangjie::t-pdf", { =>
            requireArity(args, 2, "cangjie::t-pdf")
            let who = "cangjie::t-pdf"
            LispValue.Float(tDistPdf(numOf(args[0], who), positiveArg(args[1], who, "df")))
        })
    }))

    // (cangjie::t-cdf t df)
    env.define("cangjie::t-cdf", NativeFunc({ args =>
        guardedDist("cangjie::t-cdf", { =>
            requireArity(args, 2, "cangjie::t-cdf")
            let who = "cangjie::t-cdf"
            LispValue.Float(tDistCdf(numOf(args[0], who), positiveArg(args[1], who, "df")))
        })
    }))

    // (cangjie::t-quantile p df)
    env.define("cangjie::t-quantile", NativeFunc({ args =>
        guardedDist("cangjie::t-quantile", { =>
            requireArity(args, 2, "cangjie::t-quantile")
            let who = "cangjie::t-quantile"
            LispValue.Float(tDistQuantile(probOpenArg(args[0], who, "p"),
                positiveArg(args[1], who, "df")))
        })
    }))

    // ───────────── 卡方 χ²(df) ─────────────

    // (cangjie::chisq-pdf x df)
    env.define("cangjie::chisq-pdf", NativeFunc({ args =>
        guardedDist("cangjie::chisq-pdf", { =>
            requireArity(args, 2, "cangjie::chisq-pdf")
            let who = "cangjie::chisq-pdf"
            LispValue.Float(chisqPdf(numOf(args[0], who), positiveArg(args[1], who, "df")))
        })
    }))

    // (cangjie::chisq-cdf x df)
    env.define("cangjie::chisq-cdf", NativeFunc({ args =>
        guardedDist("cangjie::chisq-cdf", { =>
            requireArity(args, 2, "cangjie::chisq-cdf")
            let who = "cangjie::chisq-cdf"
            LispValue.Float(chisqCdf(numOf(args[0], who), positiveArg(args[1], who, "df")))
        })
    }))

    // (cangjie::chisq-quantile p df)
    env.define("cangjie::chisq-quantile", NativeFunc({ args =>
        guardedDist("cangjie::chisq-quantile", { =>
            requireArity(args, 2, "cangjie::chisq-quantile")
            let who = "cangjie::chisq-quantile"
            LispValue.Float(chisqQuantile(probOpenArg(args[0], who, "p"),
                positiveArg(args[1], who, "df")))
        })
    }))

    // ───────────── F(d1, d2) ─────────────

    // (cangjie::f-pdf x d1 d2)
    env.define("cangjie::f-pdf", NativeFunc({ args =>
        guardedDist("cangjie::f-pdf", { =>
            requireArity(args, 3, "cangjie::f-pdf")
            let who = "cangjie::f-pdf"
            LispValue.Float(fDistPdf(numOf(args[0], who),
                positiveArg(args[1], who, "d1"), positiveArg(args[2], who, "d2")))
        })
    }))

    // (cangjie::f-cdf x d1 d2)
    env.define("cangjie::f-cdf", NativeFunc({ args =>
        guardedDist("cangjie::f-cdf", { =>
            requireArity(args, 3, "cangjie::f-cdf")
            let who = "cangjie::f-cdf"
            LispValue.Float(fDistCdf(numOf(args[0], who),
                positiveArg(args[1], who, "d1"), positiveArg(args[2], who, "d2")))
        })
    }))

    // (cangjie::f-quantile p d1 d2)
    env.define("cangjie::f-quantile", NativeFunc({ args =>
        guardedDist("cangjie::f-quantile", { =>
            requireArity(args, 3, "cangjie::f-quantile")
            let who = "cangjie::f-quantile"
            LispValue.Float(fDistQuantile(probOpenArg(args[0], who, "p"),
                positiveArg(args[1], who, "d1"), positiveArg(args[2], who, "d2")))
        })
    }))

    // ───────────── 泊松 Poisson(λ) ─────────────

    // (cangjie::pois-pmf k lambda)
    env.define("cangjie::pois-pmf", NativeFunc({ args =>
        guardedDist("cangjie::pois-pmf", { =>
            requireArity(args, 2, "cangjie::pois-pmf")
            let who = "cangjie::pois-pmf"
            let k = intArg(args[0], who, "k")
            if (k < 0) {
                throw IllegalArgumentException("${who} 的 k 必须 ≥ 0，得到 ${k}")
            }
            LispValue.Float(poisPmf(k, nonNegativeArg(args[1], who, "lambda")))
        })
    }))

    // (cangjie::pois-cdf k lambda)
    env.define("cangjie::pois-cdf", NativeFunc({ args =>
        guardedDist("cangjie::pois-cdf", { =>
            requireArity(args, 2, "cangjie::pois-cdf")
            let who = "cangjie::pois-cdf"
            LispValue.Float(poisCdf(intArg(args[0], who, "k"),
                nonNegativeArg(args[1], who, "lambda")))
        })
    }))

    // (cangjie::pois-quantile p lambda)
    env.define("cangjie::pois-quantile", NativeFunc({ args =>
        guardedDist("cangjie::pois-quantile", { =>
            requireArity(args, 2, "cangjie::pois-quantile")
            let who = "cangjie::pois-quantile"
            LispValue.Int(poisQuantile(probOpenArg(args[0], who, "p"),
                nonNegativeArg(args[1], who, "lambda")))
        })
    }))

    // ───────────── 二项 Binomial(n, p) ─────────────

    // (cangjie::binom-pmf k n p)
    env.define("cangjie::binom-pmf", NativeFunc({ args =>
        guardedDist("cangjie::binom-pmf", { =>
            requireArity(args, 3, "cangjie::binom-pmf")
            let who = "cangjie::binom-pmf"
            LispValue.Float(binomPmf(intArg(args[0], who, "k"), intArg(args[1], who, "n"),
                probClosedArg(args[2], who, "p")))
        })
    }))

    // (cangjie::binom-cdf k n p)
    env.define("cangjie::binom-cdf", NativeFunc({ args =>
        guardedDist("cangjie::binom-cdf", { =>
            requireArity(args, 3, "cangjie::binom-cdf")
            let who = "cangjie::binom-cdf"
            LispValue.Float(binomCdf(intArg(args[0], who, "k"), intArg(args[1], who, "n"),
                probClosedArg(args[2], who, "p")))
        })
    }))

    // (cangjie::binom-quantile q n p)
    env.define("cangjie::binom-quantile", NativeFunc({ args =>
        guardedDist("cangjie::binom-quantile", { =>
            requireArity(args, 3, "cangjie::binom-quantile")
            let who = "cangjie::binom-quantile"
            LispValue.Int(binomQuantile(probOpenArg(args[0], who, "q"),
                intArg(args[1], who, "n"), probClosedArg(args[2], who, "p")))
        })
    }))
}
