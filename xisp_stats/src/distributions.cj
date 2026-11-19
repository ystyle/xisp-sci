package ystyle::xisp_stats

import std.math.*

/**
 * 分布函数族：密度 / 累积 / 分位数
 *
 * ## 为什么要有一组「分布函数」
 *
 * 统计推断的全部出口都是 p 值，而 p 值永远是「某个统计量落在某个分布尾部的概率」。
 * 只有打包好的 `t-test1` / `t-test2`，意味着**除了这两个检验，其余一律算不出 p 值** ——
 * 想算个卡方统计量对应的 p、想找一个 95% 分位点、想自己搭一个检验，都没有入口。
 *
 * R 用 `d/p/q/r` 四个前缀覆盖这件事（density / probability / quantile / random）。
 * 本仓不抄那套缩写，用**描述性后缀** `-pdf` / `-pmf` / `-cdf` / `-quantile`：
 * 与已有的 `std` 对 `std-pop` 同一个思路（靠后缀区分语义，不靠单字母）。
 *
 * ## 命名里的两个约定
 *
 * 1. **分布名在前**（`norm-` / `t-` / `chisq-` / `f-` / `pois-` / `binom-`）——
 *    排序时同族挨在一起，文档生成也是按前缀分组的。
 * 2. **连续用 `-pdf`，离散用 `-pmf`**。R 的 `d` 前缀不分这个，但那是它的历史包袱：
 *    「概率密度」与「概率质量」是不同量纲的东西，混叫会让「为什么 pmf 之和可以不等于 1」
 *    这类问题永远说不清。
 *
 * ## 数值上依赖什么
 *
 * - 连续分布的 CDF 全部归到 `dist.cj` 的两个不完全 Gamma / Beta（正态还多一层 erf）
 * - 分位数全部用 `bisectQuantile` 反解 —— 不用牛顿，因为 t / F / 卡方的 PDF
 *   在端点会溢出或除零，导数法反而更难写稳
 * - 离散分布的分位数按定义取**下侧**：最小的 `k` 使 `CDF(k) ≥ p`
 *
 * ## 一个刻意的取舍：不做随机数
 *
 * `rnorm` / `rt` 这类抽样需要**状态**（种子），而本仓所有域都声明为纯函数。
 * 种子放哪、可复现性怎么保证、`escapable` 怎么标 —— 这是架构决策，不是实现难度问题。
 * 见 [`docs/plans/2026-11-19-r-parity-audit.md`](../../docs/plans/2026-11-19-r-parity-audit.md) §3.10。
 */

// ───────────────────────── 常量与小工具 ─────────────────────────
//
// Cangjie 要求顶层 `let` 先定义后使用，所以常量放在函数之前，不能像某些语言那样甩到文件末尾。

let SQRT_2: Float64 = sqrt(2.0)

let SQRT_2PI: Float64 = sqrt(2.0 * Float64.getPI())

let LOG_2: Float64 = log(2.0)

/** 两个 `Int64` 取大 */
func maxOf(a: Int64, b: Int64): Int64 {
    if (a > b) {
        a
    } else {
        b
    }
}

// ───────────────────────── 正态 ─────────────────────────

/** 正态分布密度 `N(μ, σ²)`；`σ ≤ 0` 返回 NaN */
func normPdf(x: Float64, mu: Float64, sigma: Float64): Float64 {
    if (sigma <= 0.0) {
        return Float64.getNaN()
    }
    let z = (x - mu) / sigma
    exp(-0.5 * z * z) / (sigma * SQRT_2PI)
}

/** 正态分布 CDF；`σ ≤ 0` 返回 NaN */
func normCdf(x: Float64, mu: Float64, sigma: Float64): Float64 {
    if (sigma <= 0.0) {
        return Float64.getNaN()
    }
    let z = (x - mu) / sigma
    // 左半轴走 erfc 保尾概率精度：Φ(−8) ≈ 6e-16，用 1−Φ(8) 会直接算成 0
    if (z <= 0.0) {
        0.5 * erfcOf(-z / SQRT_2)
    } else {
        1.0 - 0.5 * erfcOf(z / SQRT_2)
    }
}

/** 正态分布分位数（CDF 的反函数） */
func normQuantile(p: Float64, mu: Float64, sigma: Float64): Float64 {
    if (sigma <= 0.0 || p <= 0.0 || p >= 1.0) {
        return Float64.getNaN()
    }
    let z = bisectQuantile(p, { x => normCdf(x, 0.0, 1.0) }, 0.0, 1.0)
    mu + sigma * z
}

// ───────────────────────── Student t ─────────────────────────

/** t 分布密度；`df ≤ 0` 返回 NaN */
func tDistPdf(t: Float64, df: Float64): Float64 {
    if (df <= 0.0) {
        return Float64.getNaN()
    }
    let logC = lgammaOf((df + 1.0) / 2.0) - lgammaOf(df / 2.0) - 0.5 * log(df * Float64.getPI())
    exp(logC - ((df + 1.0) / 2.0) * log(1.0 + t * t / df))
}

/** t 分布 CDF（复用 `dist.cj` 的实现，同时收口参数校验） */
func tDistCdf(t: Float64, df: Float64): Float64 {
    tCdf(t, df)
}

/** t 分布分位数 */
func tDistQuantile(p: Float64, df: Float64): Float64 {
    if (df <= 0.0 || p <= 0.0 || p >= 1.0) {
        return Float64.getNaN()
    }
    bisectQuantile(p, { x => tCdf(x, df) }, 0.0, 1.0)
}

// ───────────────────────── 卡方 ─────────────────────────

/** 卡方分布密度；`df ≤ 0` 或 `x < 0` 返回 NaN，`x = 0` 按 `df` 取极限 */
func chisqPdf(x: Float64, df: Float64): Float64 {
    if (df <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    let half = df / 2.0
    if (x == 0.0) {
        // `x^(df/2−1)` 在 0 处的极限：df < 2 发散、df = 2 取 1、df > 2 取 0
        if (half < 1.0) {
            return Float64.getInf()
        }
        if (half == 1.0) {
            return 0.5
        }
        return 0.0
    }
    exp((half - 1.0) * log(x) - x / 2.0 - half * LOG_2 - lgammaOf(half))
}

/** 卡方分布 CDF `P(χ² ≤ x)` */
func chisqCdf(x: Float64, df: Float64): Float64 {
    if (df <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    gammaIncLower(df / 2.0, x / 2.0)
}

/** 卡方分布分位数 */
func chisqQuantile(p: Float64, df: Float64): Float64 {
    if (df <= 0.0 || p <= 0.0 || p >= 1.0) {
        return Float64.getNaN()
    }
    bisectQuantile(p, { x => chisqCdf(x, df) }, 0.0, 1.0)
}

// ───────────────────────── F ─────────────────────────

/** F 分布密度；`d1 ≤ 0` / `d2 ≤ 0` / `x < 0` 返回 NaN */
func fDistPdf(x: Float64, d1: Float64, d2: Float64): Float64 {
    if (d1 <= 0.0 || d2 <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    if (x == 0.0) {
        // d1 < 2 时在 0 处发散；d1 = 2 时取 d2/2 处的有限值；d1 > 2 时取 0
        if (d1 < 2.0) {
            return Float64.getInf()
        }
        if (d1 == 2.0) {
            return 1.0
        }
        return 0.0
    }
    let logB = lgammaOf(d1 / 2.0) + lgammaOf(d2 / 2.0) - lgammaOf((d1 + d2) / 2.0)
    let s = (d1 / 2.0) * log(d1) + (d2 / 2.0) * log(d2) + (d1 / 2.0 - 1.0) * log(x) -
        ((d1 + d2) / 2.0) * log(d1 * x + d2) - logB
    exp(s)
}

/**
 * F 分布 CDF
 *
 * 换元到 Beta：`I_{d1x/(d1x+d2)}(d1/2, d2/2)`。
 * 用 `betaInc` 而不是新写一套 —— F 与 Beta 本来就是同一个东西的两种参数化。
 */
func fDistCdf(x: Float64, d1: Float64, d2: Float64): Float64 {
    if (d1 <= 0.0 || d2 <= 0.0 || x < 0.0) {
        return Float64.getNaN()
    }
    betaInc(d1 / 2.0, d2 / 2.0, d1 * x / (d1 * x + d2))
}

/** F 分布分位数 */
func fDistQuantile(p: Float64, d1: Float64, d2: Float64): Float64 {
    if (d1 <= 0.0 || d2 <= 0.0 || p <= 0.0 || p >= 1.0) {
        return Float64.getNaN()
    }
    bisectQuantile(p, { x => fDistCdf(x, d1, d2) }, 0.0, 1.0)
}

// ───────────────────────── 泊松 ─────────────────────────

/** 泊松分布概率质量 `P(X = k)`；`λ < 0` 返回 NaN */
func poisPmf(k: Int64, lambda: Float64): Float64 {
    if (lambda < 0.0 || k < 0) {
        return Float64.getNaN()
    }
    if (lambda == 0.0) {
        if (k == 0) {
            return 1.0
        }
        return 0.0
    }
    exp(-lambda + Float64(k) * log(lambda) - lgammaOf(Float64(k) + 1.0))
}

/**
 * 泊松分布 CDF `P(X ≤ k)`
 *
 * 恒等式 `P(X ≤ k) = Q(k+1, λ)`（上不完全 Gamma）。用 `Q` 不用 `1 − P` 的理由与
 * `erfcOf` 相同：`λ` 很大时 `P(X ≤ k)` 落在深尾部，`1 − P` 会把有效位丢光。
 */
func poisCdf(k: Int64, lambda: Float64): Float64 {
    if (lambda < 0.0) {
        return Float64.getNaN()
    }
    if (k < 0) {
        return 0.0
    }
    if (lambda == 0.0) {
        return 1.0
    }
    gammaIncUpper(Float64(k) + 1.0, lambda)
}

/** 泊松分布分位数：最小的 `k` 使 `CDF(k) ≥ p` */
func poisQuantile(p: Float64, lambda: Float64): Int64 {
    if (lambda < 0.0 || p <= 0.0 || p >= 1.0) {
        return -1
    }
    if (lambda == 0.0) {
        return 0
    }
    bisectQuantileInt(p, { k => poisCdf(k, lambda) }, 0, maxOf(1, Int64(lambda) + 1))
}

// ───────────────────────── 二项 ─────────────────────────

/** 二项分布概率质量 `P(X = k)`；`n < 0` / `p ∉ [0,1]` 返回 NaN */
func binomPmf(k: Int64, n: Int64, p: Float64): Float64 {
    if (n < 0 || p < 0.0 || p > 1.0 || k < 0 || k > n) {
        return Float64.getNaN()
    }
    if (p == 0.0) {
        if (k == 0) {
            return 1.0
        }
        return 0.0
    }
    if (p == 1.0) {
        if (k == n) {
            return 1.0
        }
        return 0.0
    }
    // ln C(n,k) 用 lgamma 算，避免 n 稍大时阶乘溢出
    let logC = lgammaOf(Float64(n) + 1.0) - lgammaOf(Float64(k) + 1.0) -
        lgammaOf(Float64(n - k) + 1.0)
    exp(logC + Float64(k) * log(p) + Float64(n - k) * log(1.0 - p))
}

/**
 * 二项分布 CDF `P(X ≤ k)`
 *
 * 恒等式 `P(X ≤ k) = I_{1−p}(n−k, k+1)`（正则化不完全 Beta）。
 * `k < 0` 与 `k ≥ n` 两个端点直接给 0 / 1，不让 `betaInc` 去吃非法参数。
 */
func binomCdf(k: Int64, n: Int64, p: Float64): Float64 {
    if (n < 0 || p < 0.0 || p > 1.0) {
        return Float64.getNaN()
    }
    if (k < 0) {
        return 0.0
    }
    if (k >= n) {
        return 1.0
    }
    betaInc(Float64(n - k), Float64(k) + 1.0, 1.0 - p)
}

/** 二项分布分位数：最小的 `k` 使 `CDF(k) ≥ p` */
func binomQuantile(p: Float64, n: Int64, prob: Float64): Int64 {
    if (n < 0 || prob < 0.0 || prob > 1.0 || p <= 0.0 || p >= 1.0) {
        return -1
    }
    if (n == 0) {
        return 0
    }
    bisectQuantileInt(p, { k => binomCdf(k, n, prob) }, 0, n)
}
