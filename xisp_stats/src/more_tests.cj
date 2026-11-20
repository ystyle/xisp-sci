package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 假设检验（第三批）：方差比、比例
 *
 * 这三个的数学都很直接 —— 统计量是闭式的，p 值靠第二批的分布函数查表。
 * 之所以还没做，纯粹是因为之前没有 `chisq-cdf` / `f-cdf` / `binom-cdf`。
 *
 * ## 两条容易搞反的
 *
 * **F 检验的双侧 p 不是 `2·P(F > f)`。** F 分布不对称（一端顶到 0、另一端拖长尾），
 * 双侧要按「比当前值更极端」定义：分别看左右两尾，取小的那侧乘 2。
 *
 * **比例的精确检验与近似检验要分开。** `binom-test` 给的是**精确**二项概率，
 * `prop-test` 是**正态近似**（还带连续性校正）。样本小的时候两者能差出好几倍，
 * 不能混着用。
 */

/** 双侧 F 检验的 p：`2·min(P(F ≤ f), P(F ≥ f))`，上限 1 */
func fTwoSidedP2(f: Float64, d1: Float64, d2: Float64): Float64 {
    let lower = fDistCdf(f, d1, d2)
    let upper = 1.0 - lower
    var p = 2.0 * (if (lower < upper) { lower } else { upper })
    if (p > 1.0) {
        p = 1.0
    }
    p
}

/**
 * 两样本方差比检验（F 检验）：`H₀: σ₁² = σ₂²`
 *
 * `F = s₁²/s₂²`，自由度 `(n₁−1, n₂−1)`。
 *
 * ⚠️ **它对正态假设极其敏感**。两个分布只要稍微偏离正态，F 检验给出的 p 值就不可信 ——
 * 这是它最常被误用的地方。方差齐性检验更稳的选择是 Levene / Brown-Forsythe
 * （基于绝对偏差的 ANOVA），但那需要 ANOVA 的框架，这里先给最基础的这个，
 * 并在文档里写清楚它的前提。
 */
func varTest(xs: Array<Float64>, ys: Array<Float64>): LispValue {
    let x = finiteOf(xs)
    let y = finiteOf(ys)
    if (x.size < 2 || y.size < 2) {
        throw IllegalArgumentException("cangjie::var-test 两组都至少需要 2 个有效观测")
    }
    let v1 = varianceOf(x, 1)
    let v2 = varianceOf(y, 1)
    if (v2 == 0.0) {
        throw IllegalArgumentException("cangjie::var-test 第二组方差为 0，方差比无定义")
    }
    let f = v1 / v2
    let d1 = Float64(x.size - 1)
    let d2 = Float64(y.size - 1)
    let out = HashMap<String, LispValue>()
    putFloat2(out, "f", f)
    putFloat2(out, "df1", d1)
    putFloat2(out, "df2", d2)
    putFloat2(out, "p", fTwoSidedP2(f, d1, d2))
    putFloat2(out, "var1", v1)
    putFloat2(out, "var2", v2)
    LispValue.HashMap(out)
}

/**
 * 单样本比例检验（**精确**二项检验）：`H₀: p = p₀`
 *
 * `k` 次成功 / `n` 次试验。p 值按「至少和观测结果一样极端」的**精确**二项概率算：
 * `2·min(P(X ≤ k), P(X ≥ k))`，上限 1。
 *
 * 为什么不用正态近似：`n` 小或 `p₀` 靠近 0/1 时，正态近似会给出明显偏离的 p 值，
 * 甚至出现负数。精确二项概率在任何 `n` 下都对。
 */
func binomTest(k: Int64, n: Int64, p0: Float64): LispValue {
    if (n <= 0) {
        throw IllegalArgumentException("cangjie::binom-test 的 n 必须 > 0")
    }
    if (k < 0 || k > n) {
        throw IllegalArgumentException(
            "cangjie::binom-test 的 k 必须落在 [0, n]，得到 k=${k} n=${n}")
    }
    if (p0 <= 0.0 || p0 >= 1.0) {
        throw IllegalArgumentException(
            "cangjie::binom-test 的 p0 必须在 (0,1) 开区间内，得到 ${p0}")
    }
    let lower = binomCdf(k, n, p0)
    let upper = 1.0 - binomCdf(k - 1, n, p0)
    var p = 2.0 * (if (lower < upper) { lower } else { upper })
    if (p > 1.0) {
        p = 1.0
    }
    let out = HashMap<String, LispValue>()
    putFloat2(out, "p", p)
    putFloat2(out, "estimate", Float64(k) / Float64(n))
    putFloat2(out, "null", p0)
    putInt2(out, "k", k)
    putInt2(out, "n", n)
    out.add("method", LispValue.Str("exact"))
    LispValue.HashMap(out)
}

/**
 * 两样本比例检验（正态近似 + 连续性校正）：`H₀: p₁ = p₂`
 *
 * 合并比例 `p̂ = (k₁+k₂)/(n₁+n₂)`，统计量
 * `z = (p̂₁ − p̂₂ − 校正) / √(p̂(1−p̂)(1/n₁ + 1/n₂))`。
 *
 * 连续性校正在 `n` 小时不能省：`k` 是整数，`p̂₁ − p̂₂` 的分布是格点上的，
 * 不校正会让 p 值系统性偏小。
 */
func propTest(k1: Int64, n1: Int64, k2: Int64, n2: Int64): LispValue {
    if (n1 <= 0 || n2 <= 0) {
        throw IllegalArgumentException("cangjie::prop-test 的 n1 / n2 都必须 > 0")
    }
    if (k1 < 0 || k1 > n1 || k2 < 0 || k2 > n2) {
        throw IllegalArgumentException("cangjie::prop-test 的 k1 / k2 必须落在 [0, n] 内")
    }
    let p1 = Float64(k1) / Float64(n1)
    let p2 = Float64(k2) / Float64(n2)
    let pooled = Float64(k1 + k2) / Float64(n1 + n2)
    let se = sqrt(pooled * (1.0 - pooled) * (1.0 / Float64(n1) + 1.0 / Float64(n2)))
    if (se == 0.0) {
        throw IllegalArgumentException(
            "cangjie::prop-test 的标准误为 0（两组的成功数都是 0 或都等于样本量）")
    }
    // 连续性校正：向 0 收 0.5/n 的等效量
    let diff = p1 - p2
    let corr = 0.5 * (1.0 / Float64(n1) + 1.0 / Float64(n2))
    var adj = 0.0
    if (diff > 0.0) {
        adj = diff - corr
    } else if (diff < 0.0) {
        adj = diff + corr
    }
    let z = adj / se
    let p = 2.0 * (1.0 - normCdf(abs(z), 0.0, 1.0))
    let out = HashMap<String, LispValue>()
    putFloat2(out, "p", p)
    putFloat2(out, "p1", p1)
    putFloat2(out, "p2", p2)
    putFloat2(out, "pooled", pooled)
    putFloat2(out, "z", z)
    putInt2(out, "k1", k1)
    putInt2(out, "n1", n1)
    putInt2(out, "k2", k2)
    putInt2(out, "n2", n2)
    out.add("method", LispValue.Str("normal-approx-corrected"))
    LispValue.HashMap(out)
}

func registerMoreTests(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::var-test x y) —— 方差比F检验
    env.define("cangjie::var-test", NativeFunc({ args =>
        guardedDist("cangjie::var-test", { =>
            requireArity(args, 2, "cangjie::var-test")
            varTest(asFloatValues(args[0], "cangjie::var-test"),
                asFloatValues(args[1], "cangjie::var-test"))
        })
    }))

    // (cangjie::binom-test k n p0) —— 精确二项检验
    env.define("cangjie::binom-test", NativeFunc({ args =>
        guardedDist("cangjie::binom-test", { =>
            requireArity(args, 3, "cangjie::binom-test")
            let who = "cangjie::binom-test"
            binomTest(intArg(args[0], who, "k"), intArg(args[1], who, "n"),
                numOf(args[2], who))
        })
    }))

    // (cangjie::prop-test k1 n1 k2 n2) —— 两样本比例检验
    env.define("cangjie::prop-test", NativeFunc({ args =>
        guardedDist("cangjie::prop-test", { =>
            requireArity(args, 4, "cangjie::prop-test")
            let who = "cangjie::prop-test"
            propTest(intArg(args[0], who, "k1"), intArg(args[1], who, "n1"),
                intArg(args[2], who, "k2"), intArg(args[3], who, "n2"))
        })
    }))
}
