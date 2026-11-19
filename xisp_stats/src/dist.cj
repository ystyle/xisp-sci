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
