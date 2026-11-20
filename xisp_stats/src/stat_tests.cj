package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 假设检验（第二批）：相关、卡方、秩和、方差分析
 *
 * ## 这一批为什么现在才能做
 *
 * 它们每一个都是「算一个统计量 → 查对应分布的尾部概率」。在分布函数补齐之前，
 * 这个「查表」的动作根本没有入口 —— 能力全被封在 `t-test1` / `t-test2` 里。
 * 分布函数族落地之后，每个检验都只剩几十行。
 *
 * ## 共同约定
 *
 * - 返回 `HashMap`，字段具名（`stat` / `df` / `p` / …）—— 检验结果没有顺序语义
 * - `p` 一律是**双侧**（除非检验本身没有方向，如卡方与方差分析，那是单侧右尾）
 * - 样本里含 `NaN` 时**成对删除**（与 `corr` / `cov` 一致）
 *
 * ## 关于"精确"与"近似"
 *
 * 秩和检验（`wilcox-test`）在小样本时用**精确零分布**，大样本时退化成正态近似。
 * 这不是偷懒：精确分布的方案数随样本量组合爆炸，`30×30` 已经是三百多万种，
 * 而正态近似在 `n > 20` 时误差已经小于 1%。阈值取 `n1·n2 ≤ 1600`。
 */

/** 把值写进结果的辅助（与 `hypothesis.cj` 的 `putFloat` 同名同义） */
func putFloat2(m: HashMap<String, LispValue>, k: String, v: Float64): Unit {
    m.add(k, LispValue.Float(v))
}

func putInt2(m: HashMap<String, LispValue>, k: String, v: Int64): Unit {
    m.add(k, LispValue.Int(v))
}

// ───────────────────────── 相关检验 ─────────────────────────

/**
 * 相关系数的显著性检验：`H₀: ρ = 0`
 *
 * `t = r·√(n−2) / √(1−r²)`，服从自由度 `n−2` 的 t 分布。
 *
 * 为什么需要它：`corr` 给出一个 0 到 1 之间的数，但「0.35 算强还是弱」取决于样本量。
 * 20 个样本的 0.35 大概率是噪声，2000 个样本的 0.35 几乎一定是真的。
 */
func corTest(xs: Array<Float64>, ys: Array<Float64>): LispValue {
    let (x, y) = pairedFinite(xs, ys, "cangjie::cor-test")
    let n = x.size
    if (n < 3) {
        throw IllegalArgumentException(
            "cangjie::cor-test 至少需要 3 对有效观测，当前 ${n} 对")
    }
    let r = correlationOf(x, y)
    if (r >= 1.0 || r <= -1.0) {
        // 完全相关：t 发散，p = 0。这在数据里通常意味着两列是同一个变量
        let out = HashMap<String, LispValue>()
        putFloat2(out, "r", r)
        putFloat2(out, "t", Float64.getInf() * (if (r > 0.0) { 1.0 } else { -1.0 }))
        putFloat2(out, "df", Float64(n - 2))
        putFloat2(out, "p", 0.0)
        putInt2(out, "n", n)
        return LispValue.HashMap(out)
    }
    let df = Float64(n - 2)
    let t = r * sqrt(df) / sqrt(1.0 - r * r)
    let out = HashMap<String, LispValue>()
    putFloat2(out, "r", r)
    putFloat2(out, "t", t)
    putFloat2(out, "df", df)
    putFloat2(out, "p", tTwoSidedP(t, df))
    putInt2(out, "n", n)
    LispValue.HashMap(out)
}

/** 成对删除缺失值（两列必须等长） */
func pairedFinite(xs: Array<Float64>, ys: Array<Float64>, who: String):
    (Array<Float64>, Array<Float64>) {
    if (xs.size != ys.size) {
        throw IllegalArgumentException(
            "${who} 需要两个等长数组，得到 ${xs.size} 与 ${ys.size}")
    }
    let a = ArrayList<Float64>()
    let b = ArrayList<Float64>()
    var i: Int64 = 0
    while (i < xs.size) {
        let x = xs[i]
        let y = ys[i]
        // NaN 参与比较恒为 false，所以这里正好能筛掉
        if (x == x && y == y) {
            a.add(x)
            b.add(y)
        }
        i++
    }
    (a.toArray(), b.toArray())
}

// ───────────────────────── 卡方检验 ─────────────────────────

/**
 * 卡方拟合优度检验：观测频数 vs 期望频数
 *
 * `χ² = Σ (Oᵢ − Eᵢ)² / Eᵢ`，自由度 `k − 1`。
 *
 * 期望频数可以不传 —— 不传就假设**均匀分布**（每个类别期望相同），
 * 那是「这批数据是不是均匀分布」这个最常见问题的直接形式。
 */
func chisqGof(obs: Array<Float64>, exp: Array<Float64>): LispValue {
    if (obs.size != exp.size) {
        throw IllegalArgumentException(
            "cangjie::chisq-test 的观测与期望频数必须等长，得到 ${obs.size} 与 ${exp.size}")
    }
    if (obs.size < 2) {
        throw IllegalArgumentException("cangjie::chisq-test 至少需要 2 个类别")
    }
    var stat = 0.0
    var i: Int64 = 0
    while (i < obs.size) {
        if (exp[i] <= 0.0) {
            throw IllegalArgumentException(
                "cangjie::chisq-test 的期望频数必须 > 0，第 ${i} 个是 ${exp[i]}")
        }
        let d = obs[i] - exp[i]
        stat += d * d / exp[i]
        i++
    }
    let df = Float64(obs.size - 1)
    let out = HashMap<String, LispValue>()
    putFloat2(out, "stat", stat)
    putFloat2(out, "df", df)
    putFloat2(out, "p", 1.0 - chisqCdf(stat, df))
    putInt2(out, "k", obs.size)
    LispValue.HashMap(out)
}

/** 不传期望时按均匀分布构造 */
func chisqGofUniform(obs: Array<Float64>): LispValue {
    var total = 0.0
    for (o in obs) {
        total += o
    }
    if (total <= 0.0) {
        throw IllegalArgumentException("cangjie::chisq-test 的观测总数必须 > 0")
    }
    let e = total / Float64(obs.size)
    let exp = Array<Float64>(obs.size, repeat: e)
    chisqGof(obs, exp)
}

/**
 * 卡方独立性检验：`r × c` 列联表
 *
 * `χ² = Σ (Oᵢⱼ − Eᵢⱼ)² / Eᵢⱼ`，其中 `Eᵢⱼ = 行和·列和 / 总和`，
 * 自由度 `(r−1)(c−1)`。
 *
 * 检验的是「两个分类变量是否独立」—— 例如「性别」与「是否通过」有没有关联。
 */
func chisqIndep(table: Array<Array<Float64>>): LispValue {
    let r = table.size
    if (r < 2) {
        throw IllegalArgumentException("cangjie::chisq-test 的列联表至少需要 2 行")
    }
    let c = table[0].size
    if (c < 2) {
        throw IllegalArgumentException("cangjie::chisq-test 的列联表至少需要 2 列")
    }
    let rowSum = Array<Float64>(r, repeat: 0.0)
    let colSum = Array<Float64>(c, repeat: 0.0)
    var total = 0.0
    var i: Int64 = 0
    while (i < r) {
        if (table[i].size != c) {
            throw IllegalArgumentException("cangjie::chisq-test 的列联表每一行长度必须相同")
        }
        var j: Int64 = 0
        while (j < c) {
            let v = table[i][j]
            if (v < 0.0) {
                throw IllegalArgumentException("cangjie::chisq-test 的频数不能为负")
            }
            rowSum[i] += v
            colSum[j] += v
            total += v
            j++
        }
        i++
    }
    if (total <= 0.0) {
        throw IllegalArgumentException("cangjie::chisq-test 的列联表总频数必须 > 0")
    }
    var stat = 0.0
    i = 0
    while (i < r) {
        var j: Int64 = 0
        while (j < c) {
            let e = rowSum[i] * colSum[j] / total
            if (e > 0.0) {
                let d = table[i][j] - e
                stat += d * d / e
            }
            j++
        }
        i++
    }
    let df = Float64((r - 1) * (c - 1))
    let out = HashMap<String, LispValue>()
    putFloat2(out, "stat", stat)
    putFloat2(out, "df", df)
    putFloat2(out, "p", 1.0 - chisqCdf(stat, df))
    putInt2(out, "rows", r)
    putInt2(out, "cols", c)
    LispValue.HashMap(out)
}

// ───────────────────────── 秩和检验 ─────────────────────────

/**
 * Mann-Whitney U 的**精确**零分布
 *
 * 递推：把秩从大到小依次分配给两组。若当前元素给第一组，它比第二组已有的 `j` 个
 * 都大，所以 U 增加 `j`；给第二组则 U 不变。于是
 *
 *     C(i, j, u) = C(i−1, j, u−j) + C(i, j−1, u)
 *
 * 只保留两行（`i−1` 与 `i`），内存是 `O(n2 · n1n2)` 而不是 `O(n1 · n2 · n1n2)`。
 */
func mannWhitneyCounts(n1: Int64, n2: Int64): Array<Float64> {
    let maxU = n1 * n2
    let w = maxU + 1
    // prev[j * w + u] = C(i-1, j, u)
    var prev = Array<Float64>((n2 + 1) * w, repeat: 0.0)
    // i = 0 行：一个元素都不给第一组，U 恒为 0
    var j: Int64 = 0
    while (j <= n2) {
        prev[j * w + 0] = 1.0
        j++
    }
    var i: Int64 = 1
    while (i <= n1) {
        let cur = Array<Float64>((n2 + 1) * w, repeat: 0.0)
        // j = 0：全给第一组，U 增加 0，只有 u = 0 一种方案
        cur[0 * w + 0] = 1.0
        j = 1
        while (j <= n2) {
            var u: Int64 = 0
            while (u <= maxU) {
                var v = cur[(j - 1) * w + u]
                if (u >= j) {
                    v += prev[j * w + (u - j)]
                }
                cur[j * w + u] = v
                u++
            }
            j++
        }
        var t: Int64 = 0
        while (t < cur.size) {
            prev[t] = cur[t]
            t++
        }
        i++
    }
    let out = Array<Float64>(w, repeat: 0.0)
    var u: Int64 = 0
    while (u <= maxU) {
        out[u] = prev[n2 * w + u]
        u++
    }
    out
}

/**
 * Wilcoxon 秩和 / Mann-Whitney U 检验（两独立样本）
 *
 * 与 t 检验的区别是它**不假设正态**：只看两组混在一起后谁排在前面。
 * 对偏态数据、序数数据、含离群点的数据，它比 t 检验可靠得多。
 *
 * 小样本（`n1·n2 ≤ 1600`）用精确零分布；否则用正态近似（带并列校正）。
 * 有并列（ties）时精确分布不再适用 —— 用近似 + 校正。
 */
func wilcoxTest(xs: Array<Float64>, ys: Array<Float64>): LispValue {
    let x = finiteOf(xs)
    let y = finiteOf(ys)
    let n1 = x.size
    let n2 = y.size
    if (n1 < 1 || n2 < 1) {
        throw IllegalArgumentException("cangjie::wilcox-test 两组都需要至少 1 个有效观测")
    }
    let all = Array<Float64>(n1 + n2, repeat: 0.0)
    var i: Int64 = 0
    while (i < n1) {
        all[i] = x[i]
        i++
    }
    i = 0
    while (i < n2) {
        all[n1 + i] = y[i]
        i++
    }
    let ranks = ranksRaw(all)
    // 第一组的秩和
    var w = 0.0
    i = 0
    while (i < n1) {
        w += ranks[i]
        i++
    }
    let u1 = w - Float64(n1 * (n1 + 1)) / 2.0
    let u2 = Float64(n1 * n2) - u1

    // 有没有并列：秩里出现非整数说明有
    var hasTies = false
    i = 0
    while (i < ranks.size) {
        let r = ranks[i]
        if (r == r && abs(r - Float64(Int64(r))) > 1e-9) {
            hasTies = true
            break
        }
        i++
    }

    var p = 0.0
    var method = ""
    let out = HashMap<String, LispValue>()
    if (!hasTies && n1 * n2 <= 1600) {
        // 精确：把 U 的零分布累起来
        let counts = mannWhitneyCounts(n1, n2)
        var total = 0.0
        for (c in counts) {
            total += c
        }
        let u = Int64(if (u1 < u2) { u1 } else { u2 })
        var lower = 0.0
        var k: Int64 = 0
        while (k <= u) {
            lower += counts[k]
            k++
        }
        p = 2.0 * lower / total
        if (p > 1.0) {
            p = 1.0
        }
        method = "exact"
        putFloat2(out, "u", u1)
        putFloat2(out, "u2", u2)
    } else {
        // 正态近似：μ = n1n2/2，σ² = n1n2(n1+n2+1)/12，有并列时减校正项
        let mu = Float64(n1 * n2) / 2.0
        var sigma2 = Float64(n1 * n2 * (n1 + n2 + 1)) / 12.0
        if (hasTies) {
            // 并列校正：σ² ← σ² · (1 − Σ(t³−t) / (N³−N))
            let bigN = Float64(n1 + n2)
            var tieSum = 0.0
            var k: Int64 = 0
            while (k < ranks.size) {
                var m = k
                while (m + 1 < ranks.size && abs(ranks[m + 1] - ranks[k]) < 1e-9) {
                    m++
                }
                let t = Float64(m - k + 1)
                if (t > 1.0) {
                    tieSum += t * t * t - t
                }
                k = m + 1
            }
            sigma2 = sigma2 * (1.0 - tieSum / (bigN * bigN * bigN - bigN))
        }
        let sigma = sqrt(sigma2)
        if (sigma == 0.0) {
            throw IllegalArgumentException("cangjie::wilcox-test：两组完全重合，无法计算方差")
        }
        // 连续性校正：向均值方向收 0.5
        var diff = u1 - mu
        if (diff > 0.0) {
            diff = diff - 0.5
        } else if (diff < 0.0) {
            diff = diff + 0.5
        }
        let z = diff / sigma
        p = 2.0 * (1.0 - normCdf(abs(z), 0.0, 1.0))
        method = if (hasTies) { "normal-approx-ties" } else { "normal-approx" }
        putFloat2(out, "u", u1)
        putFloat2(out, "u2", u2)
        putFloat2(out, "z", z)
    }
    putFloat2(out, "w", w)
    putFloat2(out, "p", p)
    putInt2(out, "n1", n1)
    putInt2(out, "n2", n2)
    out.add("method", LispValue.Str(method))
    LispValue.HashMap(out)
}

// ───────────────────────── 单因素方差分析 ─────────────────────────

/**
 * 单因素方差分析：`H₀: 各组均值相等`
 *
 * `F = MSB / MSW`，其中 `MSB = SSB/(k−1)`、`MSW = SSW/(N−k)`。
 *
 * 为什么不两两跑 t 检验：k 组两两比较有 `k(k−1)/2` 对，每对都有 5% 的假阳性率，
 * 6 组就是 15 对 —— 「至少有一对碰巧显著」的概率约 54%。ANOVA 用一个 F 值
 * 一次回答「这些组的均值是不是都一样」，把整体错误率控制在设定水平。
 */
func anovaOf(groups: Array<Array<Float64>>): LispValue {
    let k = groups.size
    if (k < 2) {
        throw IllegalArgumentException("cangjie::anova 至少需要 2 组")
    }
    let means = Array<Float64>(k, repeat: 0.0)
    let ns = Array<Int64>(k, repeat: 0)
    var total = 0.0
    var bigN: Int64 = 0
    var i: Int64 = 0
    while (i < k) {
        let g = finiteOf(groups[i])
        if (g.size < 1) {
            throw IllegalArgumentException("cangjie::anova 第 ${i} 组没有有效观测")
        }
        var s = 0.0
        for (v in g) {
            s += v
        }
        means[i] = s / Float64(g.size)
        ns[i] = g.size
        total += s
        bigN += g.size
        i++
    }
    if (bigN <= k) {
        throw IllegalArgumentException("cangjie::anova 总观测数必须大于组数")
    }
    let grand = total / Float64(bigN)
    var ssb = 0.0
    var ssw = 0.0
    i = 0
    while (i < k) {
        let d = means[i] - grand
        ssb += Float64(ns[i]) * d * d
        let g = finiteOf(groups[i])
        for (v in g) {
            let e = v - means[i]
            ssw += e * e
        }
        i++
    }
    let df1 = Float64(k - 1)
    let df2 = Float64(bigN - k)
    if (ssw == 0.0) {
        throw IllegalArgumentException("cangjie::anova：组内方差为 0（每组内所有值相同），F 无定义")
    }
    let f = (ssb / df1) / (ssw / df2)
    let out = HashMap<String, LispValue>()
    putFloat2(out, "f", f)
    putFloat2(out, "df1", df1)
    putFloat2(out, "df2", df2)
    putFloat2(out, "p", 1.0 - fDistCdf(f, df1, df2))
    putFloat2(out, "ss-between", ssb)
    putFloat2(out, "ss-within", ssw)
    putInt2(out, "k", k)
    putInt2(out, "n", bigN)
    LispValue.HashMap(out)
}

// ───────────────────────── 两个便宜但常用的统计量 ─────────────────────────

/**
 * 中位数绝对偏差 `MAD = median(|xᵢ − median(x)|)`
 *
 * 它是**稳健版的方差**：标准差用平方，一个离群点就能把它拉爆；MAD 用中位数，
 * 一半数据变动才会有明显反应。R 的 `mad()` 默认还乘 1.4826 让它与正态下的 σ 可比，
 * 这里**不乘** —— 乘了以后它就既不是 MAD 也不是 σ，只是那个系数的产品。
 * 需要与 σ 比较时自己乘。
 */
func madOf(values: Array<Float64>): Float64 {
    let f = finiteOf(values)
    if (f.size == 0) {
        return Float64.getNaN()
    }
    let med = quantileOf(sortedCopy(f), 0.5)
    let dev = Array<Float64>(f.size, repeat: 0.0)
    var i: Int64 = 0
    while (i < f.size) {
        dev[i] = abs(f[i] - med)
        i++
    }
    quantileOf(sortedCopy(dev), 0.5)
}

/** 极差 `max − min`（跳过 NaN） */
func rangeOf(values: Array<Float64>): Float64 {
    let f = finiteOf(values)
    if (f.size == 0) {
        return Float64.getNaN()
    }
    var lo = f[0]
    var hi = f[0]
    for (x in f) {
        if (x < lo) {
            lo = x
        }
        if (x > hi) {
            hi = x
        }
    }
    hi - lo
}

// ───────────────────────── Lisp 接口 ─────────────────────────

/** 把 Lisp 侧的二维矩阵转成 `Array<Array<Float64>>` */
func toTable(v: LispValue, who: String): Array<Array<Float64>> {
    let a = match (v) {
        case External(e) => match (e) {
            case x: NDArray => x
            case _ => throw IllegalArgumentException("${who} 需要二维矩阵，得到其它外部值")
        }
        case _ => throw IllegalArgumentException("${who} 需要二维矩阵（ndarray）")
    }
    let dims = a.shape
    if (dims.size != 2) {
        throw IllegalArgumentException(
            "${who} 需要二维矩阵，得到 ${dims.size} 维")
    }
    let r = dims[0]
    let c = dims[1]
    let rows = ArrayList<Array<Float64>>()
    var i: Int64 = 0
    while (i < r) {
        let row = Array<Float64>(c, repeat: 0.0)
        var j: Int64 = 0
        while (j < c) {
            row[j] = match (a.at(i * c + j)) {
                case Float(x) => x
                case Int(x) => Float64(x)
                case _ => Float64.getNaN()
            }
            j++
        }
        rows.add(row)
        i++
    }
    rows.toArray()
}

func registerStatTests(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::cor-test x y) —— 相关显著性
    env.define("cangjie::cor-test", NativeFunc({ args =>
        guardedDist("cangjie::cor-test", { =>
            requireArity(args, 2, "cangjie::cor-test")
            corTest(asFloatValues(args[0], "cangjie::cor-test"),
                asFloatValues(args[1], "cangjie::cor-test"))
        })
    }))

    // (cangjie::chisq-test table) —— 列联表独立性
    // (cangjie::chisq-test observed) —— 拟合优度，期望按均匀分布
    // (cangjie::chisq-test observed expected) —— 拟合优度，指定期望
    env.define("cangjie::chisq-test", NativeFunc({ args =>
        guardedDist("cangjie::chisq-test", { =>
            let who = "cangjie::chisq-test"
            if (args.size == 1) {
                match (args[0]) {
                    case External(e) => match (e) {
                        case a: NDArray =>
                            if (a.shape.size == 2) {
                                chisqIndep(toTable(args[0], who))
                            } else {
                                chisqGofUniform(asFloatValues(args[0], who))
                            }
                        case _ => chisqGofUniform(asFloatValues(args[0], who))
                    }
                    case _ => chisqGofUniform(asFloatValues(args[0], who))
                }
            } else if (args.size == 2) {
                chisqGof(asFloatValues(args[0], who), asFloatValues(args[1], who))
            } else {
                throw IllegalArgumentException(
                    "${who} 需要 1 个参数（列联表 / 观测频数）或 2 个参数（观测 + 期望），" +
                    "得到 ${args.size} 个")
            }
        })
    }))

    // (cangjie::wilcox-test x y) —— 秩和检验
    env.define("cangjie::wilcox-test", NativeFunc({ args =>
        guardedDist("cangjie::wilcox-test", { =>
            requireArity(args, 2, "cangjie::wilcox-test")
            wilcoxTest(asFloatValues(args[0], "cangjie::wilcox-test"),
                asFloatValues(args[1], "cangjie::wilcox-test"))
        })
    }))

    // (cangjie::anova g1 g2 ...) —— 单因素方差分析
    env.define("cangjie::anova", NativeFunc({ args =>
        guardedDist("cangjie::anova", { =>
            if (args.size < 2) {
                throw IllegalArgumentException(
                    "cangjie::anova 至少需要 2 组，得到 ${args.size} 组")
            }
            let groups = ArrayList<Array<Float64>>()
            for (a in args) {
                groups.add(asFloatValues(a, "cangjie::anova"))
            }
            anovaOf(groups.toArray())
        })
    }))

    // (cangjie::mad x) —— 中位数绝对偏差
    env.define("cangjie::mad", NativeFunc({ args =>
        guardedDist("cangjie::mad", { =>
            requireArity(args, 1, "cangjie::mad")
            LispValue.Float(madOf(asFloatValues(args[0], "cangjie::mad")))
        })
    }))

    // (cangjie::range x) —— 极差
    env.define("cangjie::range", NativeFunc({ args =>
        guardedDist("cangjie::range", { =>
            requireArity(args, 1, "cangjie::range")
            LispValue.Float(rangeOf(asFloatValues(args[0], "cangjie::range")))
        })
    }))
}
