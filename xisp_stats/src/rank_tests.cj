package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 基于秩的假设检验：Kruskal-Wallis、Friedman、Wilcoxon 符号秩
 *
 * ## 为什么这几个一起做
 *
 * 它们是同一个思路的三种用法：**不看原始值，只看排名**。
 *
 * | 设计 | 问题 | 检验 |
 * |---|---|---|
 * | 完全随机（各组独立） | 多组位置是否相同 | Kruskal-Wallis |
 * | 随机区组（同一对象多次测量） | 多处理是否相同 | Friedman |
 * | 配对（前后对比） | 两组差值是否有方向 | Wilcoxon 符号秩 |
 *
 * 共同优点是**不假设正态**。共同代价是**丢失了量级信息** ——
 * 「A 比 B 高 1」和「A 比 B 高 1000」在秩检验里是同一件事。
 * 数据接近正态时，t 检验 / ANOVA 的效能更高；偏离正态或含离群点时，秩检验更稳。
 */

/**
 * Wilcoxon 符号秩检验的精确零分布
 *
 * `C(w)` = `W⁺` 取值为 `w` 的方案数。递推：第 `i` 个秩可以给正号（`w += i`）
 * 或负号（`w` 不变）：
 *
 *     Cᵢ(w) = Cᵢ₋₁(w) + Cᵢ₋₁(w − i)
 *
 * 一维滚动，空间 `O(n²)`、时间 `O(n³)`（`n` 是秩个数）。`n = 50` 时约 6 万格子。
 */
func signedRankCounts(n: Int64): Array<Float64> {
    let maxW = n * (n + 1) / 2
    var prev = Array<Float64>(maxW + 1, repeat: 0.0)
    prev[0] = 1.0
    var i: Int64 = 1
    while (i <= n) {
        let cur = Array<Float64>(maxW + 1, repeat: 0.0)
        var w: Int64 = 0
        while (w <= maxW) {
            var v = prev[w]
            if (w >= i) {
                v = v + prev[w - i]
            }
            cur[w] = v
            w++
        }
        prev = cur
        i++
    }
    prev
}

/** 秩里有没有并列（出现非整数秩说明有） */
func hasTieInRanks(ranks: Array<Float64>): Bool {
    var i: Int64 = 0
    while (i < ranks.size) {
        let r = ranks[i]
        if (r == r && abs(r - Float64(Int64(r))) > 1e-9) {
            return true
        }
        i++
    }
    false
}

/**
 * Wilcoxon 符号秩检验（**配对**样本）：`H₀: 差值中位数 = 0`
 *
 * 与 `wilcox-test`（两独立样本）不是一回事：那个比的是「两组的分布是否相同」，
 * 这个比的是「同一对象的两次测量之差有没有系统性偏向」。配对设计下它比独立样本
 * 检验**效能高得多**，因为个体差异被差值消掉了。
 *
 * 差值为 0 的观测被丢弃（R 的默认行为 `zero.method = "wilcoxon"`），样本量相应减少。
 */
func signedRankTest(xs: Array<Float64>, ys: Array<Float64>): LispValue {
    let (x, y) = pairedFinite(xs, ys, "cangjie::signed-rank-test")
    if (x.size < 1) {
        throw IllegalArgumentException("cangjie::signed-rank-test 没有有效的配对观测")
    }
    // 只留非零差值
    let diffs = ArrayList<Float64>()
    var i: Int64 = 0
    while (i < x.size) {
        let d = x[i] - y[i]
        if (d != 0.0) {
            diffs.add(d)
        }
        i++
    }
    let n = diffs.size
    if (n < 1) {
        throw IllegalArgumentException(
            "cangjie::signed-rank-test 所有差值都是 0，没有可检验的信息")
    }
    let absDev = Array<Float64>(n, repeat: 0.0)
    i = 0
    while (i < n) {
        absDev[i] = abs(diffs[i])
        i++
    }
    let ranks = ranksRaw(absDev)
    var wPlus = 0.0
    var wMinus = 0.0
    i = 0
    while (i < n) {
        if (diffs[i] > 0.0) {
            wPlus += ranks[i]
        } else {
            wMinus += ranks[i]
        }
        i++
    }
    let totalW = Float64(n * (n + 1)) / 2.0
    let tied = hasTieInRanks(ranks)

    let out = HashMap<String, LispValue>()
    putFloat2(out, "w", wPlus)
    putFloat2(out, "w2", wMinus)
    putInt2(out, "n", n)

    if (!tied && n <= 50) {
        // 精确：W⁺ + W⁻ = n(n+1)/2 对称，双侧只需看较小那侧
        let counts = signedRankCounts(n)
        var total = 0.0
        for (c in counts) {
            total += c
        }
        let wObs = Float64(Int64(if (wPlus < wMinus) { wPlus } else { wMinus }))
        var lower = 0.0
        var w: Int64 = 0
        let lim = Int64(wObs)
        while (w <= lim) {
            lower += counts[w]
            w++
        }
        var p = 2.0 * lower / total
        if (p > 1.0) {
            p = 1.0
        }
        putFloat2(out, "p", p)
        out.add("method", LispValue.Str("exact"))
    } else {
        // 正态近似（带并列校正）
        let mu = Float64(n * (n + 1)) / 4.0
        var sigma2 = Float64(n * (n + 1) * (2 * n + 1)) / 24.0
        if (tied) {
            // 并列统计必须基于**排序后**的 |d| —— 相邻比较才等价于「相同的值归为一组」。
            // 用原始顺序的 `absDev` 会漏掉所有不相邻的重复值（而重复值本来就不相邻），
            // 结果校正项恒为 0，σ 偏大、z 偏小、p 偏大。
            let sortedAbs = sortRaw(absDev, false)
            var tieSum = 0.0
            var k: Int64 = 0
            while (k < n) {
                var m = k
                while (m + 1 < n && abs(sortedAbs[m + 1] - sortedAbs[k]) < 1e-9) {
                    m++
                }
                let t = Float64(m - k + 1)
                if (t > 1.0) {
                    tieSum += t * t * t - t
                }
                k = m + 1
            }
            sigma2 = sigma2 - tieSum / 48.0
        }
        let sigma = sqrt(sigma2)
        if (sigma == 0.0) {
            throw IllegalArgumentException(
                "cangjie::signed-rank-test：差值全相同，无法计算检验统计量的方差")
        }
        let diff = wPlus - mu
        let corr = if (diff > 0.0) { 0.5 } else if (diff < 0.0) { -0.5 } else { 0.0 }
        let z = (diff - corr) / sigma
        var p = 2.0 * (1.0 - normCdf(abs(z), 0.0, 1.0))
        if (p > 1.0) {
            p = 1.0
        }
        putFloat2(out, "p", p)
        putFloat2(out, "z", z)
        out.add("method", LispValue.Str(if (tied) { "normal-approx-ties" } else { "normal-approx" }))
    }
    LispValue.HashMap(out)
}

/**
 * Kruskal-Wallis 检验（多组独立样本）：`H₀: 各组位置相同`
 *
 * ANOVA 的非参数版本：把全部数据混在一起排秩，看「各组秩和」是否差异过大。
 * 公式 `H = 12/(N(N+1))·Σ Rᵢ²/nᵢ − 3(N+1)`，无并列时服从 `χ²(k−1)`。
 *
 * 有并列时必须除以校正因子 `1 − Σ(t³−t)/(N³−N)`：并列让秩的方差变小，
 * 不校正会让 H 系统性偏小、p 值偏大，**该显著的检验不出来**。
 */
func kruskalTest(groups: Array<Array<Float64>>): LispValue {
    let k = groups.size
    if (k < 2) {
        throw IllegalArgumentException("cangjie::kruskal-test 至少需要 2 组")
    }
    let clean = ArrayList<Array<Float64>>()
    var bigN: Int64 = 0
    for (g in groups) {
        let f = finiteOf(g)
        if (f.size < 1) {
            throw IllegalArgumentException("cangjie::kruskal-test：有一组没有有效观测")
        }
        clean.add(f)
        bigN += f.size
    }
    if (bigN < k + 1) {
        throw IllegalArgumentException("cangjie::kruskal-test 总观测数必须大于组数")
    }
    // 混合成一个向量，记下每段属于哪组
    let all = Array<Float64>(bigN, repeat: 0.0)
    var pos: Int64 = 0
    for (g in clean) {
        var i: Int64 = 0
        while (i < g.size) {
            all[pos] = g[i]
            pos++
            i++
        }
    }
    let ranks = ranksRaw(all)
    // 各组秩和
    let rankSums = Array<Float64>(k, repeat: 0.0)
    pos = 0
    var gi: Int64 = 0
    for (g in clean) {
        var i: Int64 = 0
        while (i < g.size) {
            rankSums[gi] += ranks[pos]
            pos++
            i++
        }
        gi++
    }
    var h = 0.0
    gi = 0
    for (g in clean) {
        h += rankSums[gi] * rankSums[gi] / Float64(g.size)
        gi++
    }
    let nF = Float64(bigN)
    h = 12.0 / (nF * (nF + 1.0)) * h - 3.0 * (nF + 1.0)

    // 并列校正：同样要先把混合后的整个向量排好序再找并列组。
    // Kruskal 的输入是「一组接一组」拼起来的，相同值天然分散在不连续的位置上，
    // 用原始顺序去扫相邻元素，几乎永远扫不到并列。
    let sortedAll = sortRaw(all, false)
    var tieSum = 0.0
    var hasTie = false
    pos = 0
    while (pos < bigN) {
        var m = pos
        while (m + 1 < bigN && sortedAll[m + 1] == sortedAll[pos]) {
            m++
        }
        let t = Float64(m - pos + 1)
        if (t > 1.0) {
            tieSum += t * t * t - t
            hasTie = true
        }
        pos = m + 1
    }
    var hAdj = h
    if (hasTie) {
        let c = 1.0 - tieSum / (nF * nF * nF - nF)
        if (c > 0.0) {
            hAdj = h / c
        }
    }
    let df = Float64(k - 1)
    let out = HashMap<String, LispValue>()
    putFloat2(out, "h", hAdj)
    putFloat2(out, "df", df)
    putFloat2(out, "p", 1.0 - chisqCdf(hAdj, df))
    putInt2(out, "k", k)
    putInt2(out, "n", bigN)
    out.add("method", LispValue.Str(if (hasTie) { "chisq-approx-ties" } else { "chisq-approx" }))
    LispValue.HashMap(out)
}

/**
 * Friedman 检验（随机区组）：`H₀: 各处理效应相同`
 *
 * 输入是 `n` 行 × `k` 列的矩阵：每行一个**区组**（同一个受试者 / 同一批实验条件），
 * 每列一个处理。**秩在每一行内部单独排** —— 这正是它与 Kruskal-Wallis 的区别：
 * 区组内的差异被排名消掉了，只留下处理之间的系统性差异。
 *
 * `Q = 12/(nk(k+1))·Σ Rⱼ² − 3n(k+1)`，无并列时服从 `χ²(k−1)`。
 */
func friedmanTest(table: Array<Array<Float64>>): LispValue {
    let n = table.size
    if (n < 2) {
        throw IllegalArgumentException("cangjie::friedman-test 至少需要 2 个区组")
    }
    let k = table[0].size
    if (k < 3) {
        throw IllegalArgumentException(
            "cangjie::friedman-test 至少需要 3 个处理（2 个处理时等价于符号检验）")
    }
    var i: Int64 = 0
    while (i < n) {
        if (table[i].size != k) {
            throw IllegalArgumentException(
                "cangjie::friedman-test 每一行（区组）的长度必须相同")
        }
        i++
    }
    let rankSums = Array<Float64>(k, repeat: 0.0)
    var tieSum = 0.0
    var hasTie = false
    i = 0
    while (i < n) {
        // 每行内单独排秩
        let row = Array<Float64>(k, repeat: 0.0)
        var j: Int64 = 0
        while (j < k) {
            row[j] = table[i][j]
            j++
        }
        let r = ranksRaw(row)
        j = 0
        while (j < k) {
            rankSums[j] += r[j]
            j++
        }
        // 区组内的并列：影响 χ² 的自由度校正
        j = 0
        while (j < k) {
            var m = j
            while (m + 1 < k && abs(row[m + 1] - row[j]) < 1e-12) {
                m++
            }
            let t = Float64(m - j + 1)
            if (t > 1.0) {
                tieSum += t * t * t - t
                hasTie = true
            }
            j = m + 1
        }
        i++
    }
    let nF = Float64(n)
    let kF = Float64(k)
    var q = 0.0
    var j: Int64 = 0
    while (j < k) {
        q += rankSums[j] * rankSums[j]
        j++
    }
    q = 12.0 / (nF * kF * (kF + 1.0)) * q - 3.0 * nF * (kF + 1.0)
    var qAdj = q
    if (hasTie) {
        let denom = nF * (kF * kF * kF - kF)
        if (denom > 0.0) {
            let c = 1.0 - tieSum / denom
            if (c > 0.0) {
                qAdj = q / c
            }
        }
    }
    let df = kF - 1.0
    let out = HashMap<String, LispValue>()
    putFloat2(out, "q", qAdj)
    putFloat2(out, "df", df)
    putFloat2(out, "p", 1.0 - chisqCdf(qAdj, df))
    putInt2(out, "n", n)
    putInt2(out, "k", k)
    out.add("method", LispValue.Str(if (hasTie) { "chisq-approx-ties" } else { "chisq-approx" }))
    LispValue.HashMap(out)
}

func registerRankTests(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::signed-rank-test x y) —— 配对符号秩检验
    env.define("cangjie::signed-rank-test", NativeFunc({ args =>
        guardedDist("cangjie::signed-rank-test", { =>
            requireArity(args, 2, "cangjie::signed-rank-test")
            signedRankTest(asFloatValues(args[0], "cangjie::signed-rank-test"),
                asFloatValues(args[1], "cangjie::signed-rank-test"))
        })
    }))

    // (cangjie::kruskal-test g1 g2 ...) —— 多组秩和检验
    env.define("cangjie::kruskal-test", NativeFunc({ args =>
        guardedDist("cangjie::kruskal-test", { =>
            if (args.size < 2) {
                throw IllegalArgumentException(
                    "cangjie::kruskal-test 至少需要 2 组，得到 ${args.size} 组")
            }
            let groups = ArrayList<Array<Float64>>()
            for (a in args) {
                groups.add(asFloatValues(a, "cangjie::kruskal-test"))
            }
            kruskalTest(groups.toArray())
        })
    }))

    // (cangjie::friedman-test table) —— 随机区组检验
    env.define("cangjie::friedman-test", NativeFunc({ args =>
        guardedDist("cangjie::friedman-test", { =>
            requireArity(args, 1, "cangjie::friedman-test")
            friedmanTest(toTable(args[0], "cangjie::friedman-test"))
        })
    }))
}
