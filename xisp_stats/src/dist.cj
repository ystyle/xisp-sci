package ystyle::xisp_stats

import std.math.*

/**
 * 统计分布：Gamma 函数、不完全 Beta、Student t
 *
 * 仓颉的 `std.math` **没有** `lgamma` / `tgamma`（探测过：`undeclared identifier`），
 * 所以这里自己实现。这不算"重复造轮子"—— 没有它就没法算 t 分布的 p 值，
 * 而 p 值是假设检验的全部意义所在。
 *
 * 数值方法：
 * - `lgamma` 用 **Lanczos 近似**（g=7，9 项系数），双精度下相对误差 ~1e-15；
 *   负数走反射公式 `Γ(x)Γ(1−x) = π/sin(πx)`
 * - 不完全 Beta 用 **连分式 + Lentz 算法**（Numerical Recipes 的 betacf），
 *   `I_x(a,b)` 按 `x < (a+1)/(a+b+2)` 选前向还是后向展开以保证收敛
 * - t 分布分位数用**二分反解** CDF —— 比牛顿法简单，且 t 的 CDF 单调，二分必然收敛
 */

let LANCZOS_G: Float64 = 7.0

let LANCZOS_C: Array<Float64> = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7]

/**
 * `log Γ(x)`
 *
 * 负半轴走反射公式。注意反射只在 `x < 0.5` 时用 —— 靠近 1 时反射会引入相消误差。
 */
func lgammaOf(x: Float64): Float64 {
    if (x < 0.5) {
        // Γ(x)Γ(1−x) = π / sin(πx)
        return log(Float64.getPI() / abs(sin(Float64.getPI() * x))) - lgammaOf(1.0 - x)
    }
    let z = x - 1.0
    var a = LANCZOS_C[0]
    var i: Int64 = 1
    while (i <= 8) {
        a = a + LANCZOS_C[i] / (z + Float64(i))
        i++
    }
    let t = z + LANCZOS_G + 0.5
    0.5 * log(2.0 * Float64.getPI()) + (z + 0.5) * log(t) - t + log(a)
}

/** 不完全 Beta 的连分式（Lentz 算法） */
func betaCF(a: Float64, b: Float64, x: Float64): Float64 {
    let maxIter: Int64 = 300
    let eps = 3.0e-16
    let fpMin = 1.0e-300
    let qab = a + b
    let qap = a + 1.0
    let qam = a - 1.0
    var c = 1.0
    var d = 1.0 - qab * x / qap
    if (abs(d) < fpMin) {
        d = fpMin
    }
    d = 1.0 / d
    var h = d
    var m: Int64 = 1
    while (m <= maxIter) {
        let m2 = Float64(2 * m)
        var aa = Float64(m) * (b - Float64(m)) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if (abs(d) < fpMin) {
            d = fpMin
        }
        c = 1.0 + aa / c
        if (abs(c) < fpMin) {
            c = fpMin
        }
        d = 1.0 / d
        h = h * d * c
        aa = -(a + Float64(m)) * (qab + Float64(m)) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if (abs(d) < fpMin) {
            d = fpMin
        }
        c = 1.0 + aa / c
        if (abs(c) < fpMin) {
            c = fpMin
        }
        d = 1.0 / d
        let del = d * c
        h = h * del
        if (abs(del - 1.0) < eps) {
            break
        }
        m++
    }
    h
}

/** 正则化不完全 Beta `I_x(a,b)` */
func betaInc(a: Float64, b: Float64, x: Float64): Float64 {
    if (x <= 0.0) {
        return 0.0
    }
    if (x >= 1.0) {
        return 1.0
    }
    let bt = exp(lgammaOf(a + b) - lgammaOf(a) - lgammaOf(b)
        + a * log(x) + b * log(1.0 - x))
    // 按 x 的位置选展开方向：连分式在对应一侧收敛更快
    if (x < (a + 1.0) / (a + b + 2.0)) {
        bt * betaCF(a, b, x) / a
    } else {
        1.0 - bt * betaCF(b, a, 1.0 - x) / b
    }
}

/**
 * Student t 分布的 CDF：`P(T ≤ t)`，`df` 是自由度
 *
 * 用 `I_x(df/2, 1/2)` 表示：`x = df/(df+t²)`，然后按 `t` 的正负取两侧。
 */
func tCdf(t: Float64, df: Float64): Float64 {
    if (df <= 0.0) {
        return Float64.getNaN()
    }
    let x = df / (df + t * t)
    let ib = betaInc(df / 2.0, 0.5, x)
    if (t > 0.0) {
        1.0 - 0.5 * ib
    } else {
        0.5 * ib
    }
}

/**
 * t 分布的**双侧**临界值：找 `t` 使 `P(|T| > t) = alpha`
 *
 * 二分反解。t 的 CDF 单调，二分必然收敛，不用管初始值。
 */
func tCritical(alpha: Float64, df: Float64): Float64 {
    if (df <= 0.0) {
        return Float64.getNaN()
    }
    if (alpha <= 0.0 || alpha >= 1.0) {
        return Float64.getNaN()
    }
    let target = 1.0 - alpha / 2.0
    var lo = 0.0
    var hi = 1.0
    // 找一个足够大的上界（df 大时临界值接近正态的 1.96，df=1 时约 12.7，
    // 但极端 alpha 会更大，所以动态放大）
    while (tCdf(hi, df) < target && hi < 1e12) {
        hi = hi * 2.0
    }
    var iter: Int64 = 0
    while (iter < 300) {
        let mid = (lo + hi) / 2.0
        if (tCdf(mid, df) < target) {
            lo = mid
        } else {
            hi = mid
        }
        if (hi - lo < 1e-14 * (1.0 + abs(mid))) {
            break
        }
        iter++
    }
    (lo + hi) / 2.0
}

/** 双侧 p 值：`P(|T| > |t|)` */
func tTwoSidedP(t: Float64, df: Float64): Float64 {
    let c = tCdf(abs(t), df)
    2.0 * (1.0 - c)
}

// ───────────────────────── 不完全 Gamma ─────────────────────────
//
// 卡方、泊松、正态（经 erf）三个分布族的 CDF 都归到这一个函数上。
// 这是整片分布函数的地基：补上它，正态 / 卡方 / 泊松的 `cdf` 都只剩几行。
//
// 两个展开方向按 `x` 与 `a` 的大小关系选（与 `betaInc` 同一个思路）：
// `x < a+1` 时级数收敛快，否则连分式收敛快。选错方向不是算不准，是**根本不收敛**。

/**
 * 正则化下不完全 Gamma `P(a,x)` 的级数展开
 *
 * `P(a,x) = e^{-x} x^a / Γ(a) · Σ_{n≥0} x^n / (a(a+1)…(a+n))`
 */
func gammaSeries(a: Float64, x: Float64): Float64 {
    var ap = a
    var del = 1.0 / a
    var sum = del
    var n: Int64 = 0
    while (n < 1000) {
        ap = ap + 1.0
        del = del * x / ap
        sum = sum + del
        if (abs(del) < abs(sum) * 1.0e-17) {
            break
        }
        n++
    }
    sum * exp(-x + a * log(x) - lgammaOf(a))
}

/**
 * 正则化上不完全 Gamma `Q(a,x)` 的连分式（Lentz 算法）
 *
 * `Q(a,x) = e^{-x} x^a / Γ(a) · 1/(x+1−a − 1·(1−a)/(x+3−a − 2·(2−a)/(…)))`
 */
func gammaCF(a: Float64, x: Float64): Float64 {
    let fpMin = 1.0e-300
    var b = x + 1.0 - a
    var c = 1.0 / fpMin
    var d = 1.0 / b
    var h = d
    var i: Int64 = 1
    while (i <= 1000) {
        let an = -Float64(i) * (Float64(i) - a)
        b = b + 2.0
        d = an * d + b
        if (abs(d) < fpMin) {
            d = fpMin
        }
        c = b + an / c
        if (abs(c) < fpMin) {
            c = fpMin
        }
        d = 1.0 / d
        let del = d * c
        h = h * del
        if (abs(del - 1.0) < 1.0e-17) {
            break
        }
        i++
    }
    exp(-x + a * log(x) - lgammaOf(a)) * h
}

/** 正则化下不完全 Gamma `P(a,x)`；`x = 0` 时取 0（`a·log x` 会算成 NaN，要拦在前头） */
func gammaIncLower(a: Float64, x: Float64): Float64 {
    if (a <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    if (x == 0.0) {
        return 0.0
    }
    if (x < a + 1.0) {
        gammaSeries(a, x)
    } else {
        1.0 - gammaCF(a, x)
    }
}

/** 正则化上不完全 Gamma `Q(a,x) = 1 − P(a,x)`；大 `x` 时比 `1 − gammaIncLower` 保精度 */
func gammaIncUpper(a: Float64, x: Float64): Float64 {
    if (a <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    if (x == 0.0) {
        return 1.0
    }
    if (x < a + 1.0) {
        1.0 - gammaSeries(a, x)
    } else {
        gammaCF(a, x)
    }
}

// ───────────────────────── 误差函数 ─────────────────────────
//
// 仓颉的 `std.math` 没有 `erf` / `erfc`（与没有 `lgamma` 同理）。
// 但不完全 Gamma 正好能给出它们：`erf(x) = P(1/2, x²)`、`erfc(x) = Q(1/2, x²)`（`x ≥ 0`）。
// 所以这两个函数只是上面两个的换名，没有新的数值方法。

/** 误差函数 `erf(x) = (2/√π)·∫₀ˣ e^{−t²}dt` */
func erfOf(x: Float64): Float64 {
    if (x == 0.0) {
        return 0.0
    }
    let p = gammaIncLower(0.5, x * x)
    if (x > 0.0) {
        p
    } else {
        -p
    }
}

/**
 * 互补误差函数 `erfc(x) = 1 − erf(x)`
 *
 * 左尾要单独算：`Φ(z)` 在 `z` 很负时是 `0.5·erfc(−z/√2)`，
 * 而 `1 − erf(y)` 在 `y ≈ 6` 处会因相消丢光有效位。所以用 `Q` 而不是 `1 − P`。
 */
func erfcOf(x: Float64): Float64 {
    if (x == 0.0) {
        return 1.0
    }
    let q = gammaIncUpper(0.5, x * x)
    if (x > 0.0) {
        q
    } else {
        2.0 - q
    }
}

// ───────────────────────── 分位数反解 ─────────────────────────

/**
 * 二分反解一个单调递增的 CDF：找 `x` 使 `cdf(x) = p`
 *
 * 用二分不用牛顿，理由与 `tCritical` 相同：CDF 单调保证收敛，且不需要导数
 * （t / F / 卡方的 PDF 在端点会溢出或除零，导数法反而难写稳）。
 *
 * 上界从 `hi0` 起倍增，下界从 `lo0` 起减半 —— 这样不同尺度的分布（卡方 df=1 与 df=1000）
 * 都能自己找到合适的区间，不用为每个分布手调。
 */
func bisectQuantile(p: Float64, cdf: (Float64) -> Float64, lo0: Float64, hi0: Float64): Float64 {
    var lo = lo0
    var hi = hi0
    var guard: Int64 = 0
    while (cdf(hi) < p && guard < 200) {
        hi = hi * 2.0 + 1.0
        guard++
    }
    guard = 0
    while (cdf(lo) > p && guard < 200) {
        lo = lo * 2.0 - 1.0
        guard++
    }
    var iter: Int64 = 0
    while (iter < 300) {
        let mid = (lo + hi) / 2.0
        if (cdf(mid) < p) {
            lo = mid
        } else {
            hi = mid
        }
        if (hi - lo < 1.0e-15 * (1.0 + abs(mid))) {
            break
        }
        iter++
    }
    (lo + hi) / 2.0
}

/** 整数版二分：找最小的 `k` 使 `cdf(k) ≥ p`（离散分布的分位数按定义取下侧） */
func bisectQuantileInt(p: Float64, cdf: (Int64) -> Float64, lo0: Int64, hi0: Int64): Int64 {
    var lo = lo0
    var hi = hi0
    var guard: Int64 = 0
    while (cdf(hi) < p && guard < 200) {
        hi = hi * 2 + 1
        guard++
    }
    // 不变式：cdf(lo) < p <= cdf(hi)
    while (lo < hi) {
        let mid = lo + (hi - lo) / 2
        if (cdf(mid) < p) {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    lo
}
