package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.HashMap
import std.math.*

/**
 * 正态性检验
 *
 * ## 为什么是 D'Agostino-Pearson 而不是 Shapiro-Wilk
 *
 * R 的 `shapiro.test` 用的是 Shapiro-Wilk 的 `W` 统计量，它的计算需要一组
 * **依赖样本量的系数 `aᵢ`**。小样本查表、大样本用 Royston 的多项式近似 ——
 * 那套系数表本身就有几百个数，抄错一个不会有任何提示，只会让 p 值悄悄偏掉。
 *
 * 这里用 **D'Agostino-Pearson 综合检验**（1990）：它同时看**偏度**和**峰度**，
 * 把两个标准化统计量平方和成 `K²`，服从 `χ²(2)`。只需要两个闭式公式，
 * 没有一个需要外挂的系数表，**可以实现得逐项可核对**。
 *
 * 代价是与 R 的结论不逐位一致。但两种检验的判别力相当（对中等样本，
 * D'Agostino-Pearson 在很多情形下还略强），而且这里给出的 p 值是可以解释的：
 * 「偏度和峰度联合偏离正态的程度有多极端」。
 *
 * ## 它能查出什么、查不出什么
 *
 * 偏度和峰度只描述分布的**前四阶矩**。双峰分布可以有和正态一样的偏度与峰度
 * （比如一半数据在 −1 一半在 +1，与 `N(0,1)` 的这两个矩接近），这种形状它查不出来。
 * 想看形状请直接画直方图。
 */

/** `asinh(x) = ln(x + √(x²+1))` —— 仓颉 `std.math` 没有 */
func asinhOf(x: Float64): Float64 {
    // x 很负时 x + sqrt(x²+1) 会相消，用 -asinh(-x) 绕开
    if (x < 0.0) {
        return -asinhOf(-x)
    }
    log(x + sqrt(x * x + 1.0))
}

/** `x^y`（`std.math` 没有 pow，用 exp/log 组合；底数必须为正） */
func powOf(x: Float64, y: Float64): Float64 {
    if (x <= 0.0) {
        return 0.0
    }
    exp(y * log(x))
}

/**
 * 实三次根（**负数也要给负数**）
 *
 * 不能用 `powOf(x, 1.0/3.0)` —— `exp(log(x)/3)` 对负底数无定义，会退化成 0，
 * 而正态性检验的峰度分支里那个底数**确实可能是负数**。写成 0 会得到一个
 * 巨大的 Z2（实测能把 p 值从 0.28 压到 1e-104），而且不报任何错。
 */
func cbrtOf(x: Float64): Float64 {
    if (x >= 0.0) {
        exp(log(x) / 3.0)
    } else {
        -exp(log(-x) / 3.0)
    }
}

/**
 * D'Agostino-Pearson 综合正态性检验：`H₀: 数据来自正态分布`
 *
 * 返回 `{k2, z-skew, z-kurt, p, n}`。`k2 = z-skew² + z-kurt²` 服从 `χ²(2)`。
 *
 * 至少需要 8 个观测：偏度/峰度的标准化公式里有 `(n−3)` 作分母，再小就发散了。
 */
func normalityTest(values: Array<Float64>): LispValue {
    let v = finiteOf(values)
    let n = v.size
    if (n < 8) {
        throw IllegalArgumentException(
            "cangjie::normality-test 至少需要 8 个有效观测（偏度/峰度的标准化公式" +
            "在 n < 8 时无定义），当前 ${n} 个")
    }
    let nF = Float64(n)
    // 中心矩
    var mean = 0.0
    for (x in v) {
        mean += x
    }
    mean = mean / nF
    var m2 = 0.0
    var m3 = 0.0
    var m4 = 0.0
    for (x in v) {
        let d = x - mean
        let d2 = d * d
        m2 += d2
        m3 += d2 * d
        m4 += d2 * d2
    }
    m2 = m2 / nF
    m3 = m3 / nF
    m4 = m4 / nF
    if (m2 <= 0.0) {
        throw IllegalArgumentException(
            "cangjie::normality-test：所有观测相同，方差为 0，无法检验正态性")
    }
    let g1 = m3 / powOf(m2, 1.5)          // 样本偏度
    let g2 = m4 / (m2 * m2) - 3.0          // 超额峰度

    // ── 偏度的标准化（D'Agostino 1990）──
    let y = g1 * sqrt((nF + 1.0) * (nF + 3.0) / (6.0 * (nF - 2.0)))
    let beta2 = 3.0 * (nF * nF + 27.0 * nF - 70.0) * (nF + 1.0) * (nF + 3.0) /
        ((nF - 2.0) * (nF + 5.0) * (nF + 7.0) * (nF + 9.0))
    let w2 = -1.0 + sqrt(2.0 * (beta2 - 1.0))
    let delta = 1.0 / sqrt(log(sqrt(w2)))
    let alpha = sqrt(2.0 / (w2 - 1.0))
    let zSkew = delta * asinhOf(y / alpha)

    // ── 峰度的标准化（D'Agostino 1990）──
    // 超额峰度 g2 = b2 − 3 的期望是 −6/(n+1)。
    // 写成 3(n−1)/(n+1) 是**未减 3 的 b2** 的期望，用在这里会系统性高估峰度偏离，
    // 正态数据也会被判成严重非正态。
    let e = -6.0 / (nF + 1.0)
    let varG2 = 24.0 * nF * (nF - 2.0) * (nF - 3.0) /
        ((nF + 1.0) * (nF + 1.0) * (nF + 3.0) * (nF + 5.0))
    let xx = (g2 - e) / sqrt(varG2)
    let sb1 = 6.0 * (nF * nF - 5.0 * nF + 2.0) / ((nF + 7.0) * (nF + 9.0)) *
        sqrt(6.0 * (nF + 3.0) * (nF + 5.0) / (nF * (nF - 2.0) * (nF - 3.0)))
    let aCoef = 6.0 + (8.0 / sb1) * (2.0 / sb1 + sqrt(1.0 + 4.0 / (sb1 * sb1)))
    let inner = (1.0 - 2.0 / aCoef) / (1.0 + xx * sqrt(2.0 / (aCoef - 4.0)))
    let zKurt = ((1.0 - 2.0 / (9.0 * aCoef)) - cbrtOf(inner)) /
        sqrt(2.0 / (9.0 * aCoef))

    let k2 = zSkew * zSkew + zKurt * zKurt
    let out = HashMap<String, LispValue>()
    putFloat2(out, "k2", k2)
    putFloat2(out, "z-skew", zSkew)
    putFloat2(out, "z-kurt", zKurt)
    putFloat2(out, "skew", g1)
    putFloat2(out, "kurtosis", g2)
    putFloat2(out, "p", 1.0 - chisqCdf(k2, 2.0))
    putInt2(out, "n", n)
    out.add("method", LispValue.Str("dagostino-pearson"))
    LispValue.HashMap(out)
}

func registerNormality(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::normality-test x) —— D'Agostino-Pearson 正态性检验
    env.define("cangjie::normality-test", NativeFunc({ args =>
        guardedDist("cangjie::normality-test", { =>
            requireArity(args, 1, "cangjie::normality-test")
            normalityTest(asFloatValues(args[0], "cangjie::normality-test"))
        })
    }))
}
