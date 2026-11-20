package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.math.*

/**
 * 多元正态抽样 `N(μ, Σ)`
 *
 * ## 它不只是「跑 p 次 rnorm」
 *
 * 独立地跑 p 次 `rnorm` 得到的是 `Σ = diag(σ₁², …, σ_p²)` 的样本 —— 对角矩阵意味着
 * 各维**互不相关**。但真实数据里维度之间几乎总是相关的（身高与体重、温度与销量）。
 * 要让样本具备目标协方差结构，必须做线性变换。
 *
 * 算法是标准的：把 `Σ` 分解成 `Σ = L·Lᵀ`（Cholesky，`L` 下三角），
 * 对每个 `z ~ N(0, I_p)` 取 `x = μ + L·z`。这样 `E[x] = μ`、
 * `Cov[x] = L·Cov[z]·Lᵀ = L·Lᵀ = Σ`。
 *
 * ## 为什么这里自带一份 Cholesky
 *
 * `xisp_linalg` 里已经有 `cangjie::cholesky`，但族内模块**不许互依**（路线图 §2.2）：
 * 让「只想做多元抽样」的宿主被迫拖进整个线性代数模块，正是这条依赖规则要防的事。
 *
 * 这里只需要 `Σ = L·Lᵀ` 这一种分解，30 行。重复的是**算法**而不是**接口** ——
 * 比起改依赖规则，这个代价小得多，而且不会随时间漂移（Cholesky 是闭式算法，
 * 不存在「实现演进导致两份不一致」的问题）。
 *
 * ## 一个容易写错的地方
 *
 * 生成 `n×p` 个标准正态时，**必须一次性生成 `n·p` 个**。
 * 如果按「每一维用一个种子各生成 `n` 个」，各维拿到的是**同一条随机序列**，
 * 样本会全部落在一条直线上（样本相关系数恒为 1）—— 而且数据看起来完全正常，
 * 只有算一下相关矩阵才会发现。
 */

/** 下三角 Cholesky：`a` 是行优先的 `n×n`，返回行优先的 `n×n` 下三角 `L`（`a = L·Lᵀ`） */
func choleskyLowerRaw(n: Int64, a: Array<Float64>): Array<Float64> {
    let l = Array<Float64>(n * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        var j: Int64 = 0
        while (j <= i) {
            var s = a[i * n + j]
            var k: Int64 = 0
            while (k < j) {
                s = s - l[i * n + k] * l[j * n + k]
                k++
            }
            if (i == j) {
                if (s <= 0.0) {
                    throw IllegalArgumentException(
                        "cangjie::rand-mvnorm：协方差矩阵不是正定矩阵" +
                        "（第 ${i} 个对角元消元后为 ${s}）。协方差矩阵必须对称正定 —— " +
                        "常见原因是某两列完全共线，或某个方差为 0")
                }
                l[i * n + j] = sqrt(s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j++
        }
        i++
    }
    l
}

/** 生成 `n` 个 `N(μ, Σ)` 样本，返回行优先的 `n×p`（每行一个样本） */
func mvnormSamples(n: Int64, mu: Array<Float64>, sigma: Array<Float64>, seed: Int64):
    Array<Float64> {
    let p = mu.size
    let l = choleskyLowerRaw(p, sigma)
    // 一次生成 n·p 个独立标准正态，按行优先排成矩阵。
    // 不能按维度各生成 n 个（见文件头注释）。
    let z = normalSamples(n * p, 0.0, 1.0, seed)
    let out = Array<Float64>(n * p, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        var j: Int64 = 0
        while (j < p) {
            // L 是下三角：第 j 行只有 k ≤ j 的元素非零
            var s = mu[j]
            var k: Int64 = 0
            while (k <= j) {
                s = s + l[j * p + k] * z[i * p + k]
                k++
            }
            out[i * p + j] = s
            j++
        }
        i++
    }
    out
}

/** 从 Lisp 侧取二维方阵 */
func squareMatrixArg(v: LispValue, who: String): (Int64, Array<Float64>) {
    let table = toTable(v, who)
    let p = table.size
    if (p == 0) {
        throw IllegalArgumentException("${who} 的协方差矩阵不能为空")
    }
    let flat = Array<Float64>(p * p, repeat: 0.0)
    var i: Int64 = 0
    while (i < p) {
        if (table[i].size != p) {
            throw IllegalArgumentException(
                "${who} 的协方差矩阵必须是方阵，第 ${i} 行有 ${table[i].size} 个元素，应为 ${p}")
        }
        var j: Int64 = 0
        while (j < p) {
            flat[i * p + j] = table[i][j]
            j++
        }
        i++
    }
    // 对称性检查：协方差矩阵不对称说明调用方拿错了矩阵，
    // 而 Cholesky 只读下三角，会**默默用错的那一半**算出一个看着正常的结果
    i = 0
    while (i < p) {
        var j = i + 1
        while (j < p) {
            let a = flat[i * p + j]
            let b = flat[j * p + i]
            if (abs(a - b) > 1e-9 * (1.0 + abs(a) + abs(b))) {
                throw IllegalArgumentException(
                    "${who} 的协方差矩阵不对称：第 ${i},${j} 个是 ${a}，" +
                    "第 ${j},${i} 个是 ${b}。协方差矩阵必然对称，这里拿错了矩阵")
            }
            j++
        }
        i++
    }
    (p, flat)
}

func registerMvnorm(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::rand-mvnorm n mu sigma seed) —— 多元正态抽样
    env.define("cangjie::rand-mvnorm", NativeFunc({ args =>
        guardedDist("cangjie::rand-mvnorm", { =>
            requireArity(args, 4, "cangjie::rand-mvnorm")
            let who = "cangjie::rand-mvnorm"
            let n = intArg(args[0], who, "n")
            if (n < 0) {
                throw IllegalArgumentException("${who} 的 n 必须 ≥ 0，得到 ${n}")
            }
            let mu = asFloatValues(args[1], who)
            if (mu.size == 0) {
                throw IllegalArgumentException("${who} 的均值向量不能为空")
            }
            let (p, flat) = squareMatrixArg(args[2], who)
            if (p != mu.size) {
                throw IllegalArgumentException(
                    "${who} 的均值向量长度 ${mu.size} 与协方差矩阵阶数 ${p} 不一致")
            }
            let seed = intArg(args[3], who, "seed")
            if (n == 0) {
                // 0 个样本：返回形状 [0, p] 的矩阵在 reshape 时容易踩空，
                // 直接给一维空数组 —— 调用方拿到的都是"长度 0"，
                // 而不是一个形状正确但没法再运算的东西
                LispValue.External(ndarrayFromFloats(Array<Float64>(0, repeat: 0.0)))
            } else {
                let data = mvnormSamples(n, mu, flat, seed)
                LispValue.External(reshapeArray(ndarrayFromFloats(data), [n, p]))
            }
        })
    }))
}
