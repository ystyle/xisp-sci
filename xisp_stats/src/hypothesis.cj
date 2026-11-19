package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 假设检验：t 检验与置信区间
 *
 * ## 为什么 p 值值得算
 *
 * 「A 组均值比 B 组高 2 分」本身没有信息量 —— 两组各只有 3 个样本时，这 2 分可能
 * 纯属偶然；各有 3000 个样本时，它几乎一定是真的。**p 值回答的是「这个差异有多可能
 * 是偶然」**，没有它就没法判断一个差异值不值得当回事。
 *
 * ## 返回什么
 *
 * 返回 `HashMap`，字段都是具名的（`t` / `df` / `p` / …）。这里用 HashMap 不用 alist，
 * 因为检验结果**没有顺序语义**，按名字取值比按位置取更不容易错。
 */

/** 均值与样本标准差（跳过 NaN） */
func moments(v: Array<Float64>): (Float64, Float64, Int64) {
    let f = finiteOf(v)
    let n = f.size
    if (n < 2) {
        throw IllegalArgumentException(
            "t 检验至少需要 2 个有效样本，当前 ${n} 个")
    }
    var s = 0.0
    for (x in f) {
        s = s + x
    }
    let m = s / Float64(n)
    var ss = 0.0
    for (x in f) {
        let d = x - m
        ss = ss + d * d
    }
    (m, sqrt(ss / Float64(n - 1)), n)
}

func putFloat(m: HashMap<String, LispValue>, k: String, v: Float64): Unit {
    m.add(k, LispValue.Float(v))
}

/**
 * 单样本 t 检验：`H₀: μ = mu0`
 *
 * 返回 `{t, df, p, mean, se, n}`。`p` 是**双侧** p 值。
 */
func tTestOne(x: Array<Float64>, mu0: Float64): LispValue {
    let (m, sd, n) = moments(x)
    let se = sd / sqrt(Float64(n))
    if (se == 0.0) {
        throw IllegalArgumentException(
            "t 检验：样本标准差为 0（所有值相同），无法计算标准误")
    }
    let t = (m - mu0) / se
    let df = Float64(n - 1)
    let out = HashMap<String, LispValue>()
    putFloat(out, "t", t)
    putFloat(out, "df", df)
    putFloat(out, "p", tTwoSidedP(t, df))
    putFloat(out, "mean", m)
    putFloat(out, "se", se)
    out.add("n", LispValue.Int(n))
    LispValue.HashMap(out)
}

/**
 * 双样本 t 检验（**Welch**，不假设方差相等）
 *
 * 用 Welch 而不是合并方差（Student's）版本，因为**方差相等这个前提在真实数据里
 * 几乎从不成立**：两组样本量差很多时，合并方差会把大方差那组的信息过度加权，
 * 让 p 值系统性地偏小。
 *
 * 自由度用 Welch–Satterthwaite 近似（不是整数）。
 *
 * 返回 `{t, df, p, mean1, mean2, se}`。
 */
func tTestTwo(x: Array<Float64>, y: Array<Float64>): LispValue {
    let (m1, s1, n1) = moments(x)
    let (m2, s2, n2) = moments(y)
    let v1 = s1 * s1 / Float64(n1)
    let v2 = s2 * s2 / Float64(n2)
    let se = sqrt(v1 + v2)
    if (se == 0.0) {
        throw IllegalArgumentException("t 检验：两组的标准误都是 0，无法比较")
    }
    let t = (m1 - m2) / se
    // Welch–Satterthwaite 自由度
    let denom = v1 * v1 / Float64(n1 - 1) + v2 * v2 / Float64(n2 - 1)
    if (denom == 0.0) {
        throw IllegalArgumentException("t 检验：自由度计算分母为 0")
    }
    let df = (v1 + v2) * (v1 + v2) / denom
    let out = HashMap<String, LispValue>()
    putFloat(out, "t", t)
    putFloat(out, "df", df)
    putFloat(out, "p", tTwoSidedP(t, df))
    putFloat(out, "mean1", m1)
    putFloat(out, "mean2", m2)
    putFloat(out, "se", se)
    out.add("n1", LispValue.Int(n1))
    out.add("n2", LispValue.Int(n2))
    LispValue.HashMap(out)
}

/**
 * 均值的置信区间：`mean ± t_{α/2, n−1} · s/√n`
 *
 * `level` 是置信水平（如 `0.95`），不是显著性水平。
 */
func confidenceInterval(x: Array<Float64>, level: Float64): LispValue {
    if (level <= 0.0 || level >= 1.0) {
        throw IllegalArgumentException(
            "置信水平必须在 (0,1) 之间，当前 ${level}")
    }
    let (m, sd, n) = moments(x)
    let df = Float64(n - 1)
    let tc = tCritical(1.0 - level, df)
    let se = sd / sqrt(Float64(n))
    let half = tc * se
    let out = HashMap<String, LispValue>()
    putFloat(out, "lo", m - half)
    putFloat(out, "hi", m + half)
    putFloat(out, "mean", m)
    putFloat(out, "se", se)
    putFloat(out, "df", df)
    putFloat(out, "tcrit", tc)
    out.add("n", LispValue.Int(n))
    LispValue.HashMap(out)
}
