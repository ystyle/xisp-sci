package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 精确检验：Fisher 列联表、Kolmogorov-Smirnov
 *
 * 这两个的共同点是**不依赖大样本近似**（至少 Fisher 不依赖）。
 * 小样本、稀疏列联表、分布形状未知的场景下，近似检验会给出不可信的 p 值，
 * 而精确检验在任何样本量下都成立。
 */

/**
 * 超几何分布的 log 概率质量：`P(X = x) = C(r₁,x)·C(r₂,c₁−x) / C(n,c₁)`
 *
 * 用 `lgamma` 算而不是直接算组合数 —— 20 行的表 `C(40,20)` 已经到 1.4e11，
 * 再乘几个就溢出 float64 了。取对数之后只剩加减。
 */
func hypergeomLogPmf(x: Int64, r1: Int64, r2: Int64, c1: Int64, n: Int64): Float64 {
    // 边界外概率为 0（返回一个很小的对数，避免 -inf 参与运算）
    if (x < 0 || x > r1 || c1 - x < 0 || c1 - x > r2) {
        return -1.0e300
    }
    let logC1 = lgammaOf(Float64(r1) + 1.0) - lgammaOf(Float64(x) + 1.0) -
        lgammaOf(Float64(r1 - x) + 1.0)
    let logC2 = lgammaOf(Float64(r2) + 1.0) - lgammaOf(Float64(c1 - x) + 1.0) -
        lgammaOf(Float64(r2 - (c1 - x)) + 1.0)
    let logC3 = lgammaOf(Float64(n) + 1.0) - lgammaOf(Float64(c1) + 1.0) -
        lgammaOf(Float64(n - c1) + 1.0)
    logC1 + logC2 - logC3
}

/**
 * Fisher 精确检验（2×2 列联表）
 *
 * 输入是 `[[a, b], [c, d]]` 四个计数。`H₀: 行变量与列变量独立`。
 *
 * 双侧 p 值的定义沿用 R：**所有「概率不大于观测表概率」的表之和**。
 * 这跟「2 倍单侧」不是一回事 —— 超几何分布是离散且不对称的，
 * 2 倍单侧的写法会给出大于 1 的数或系统性偏差。
 *
 * 什么时候必须用它而不是 `chisq-test`：**任何一格期望频数 < 5** 时。
 * 卡方近似在稀疏表上完全不可信，而 Fisher 检验没有这个限制。
 */
func fisherTest(table: Array<Array<Float64>>): LispValue {
    if (table.size != 2 || table[0].size != 2 || table[1].size != 2) {
        throw IllegalArgumentException(
            "cangjie::fisher-test 需要 2×2 表（[[a b] [c d]]），" +
            "更大的表请用 cangjie::chisq-test")
    }
    let a = Int64(table[0][0])
    let b = Int64(table[0][1])
    let c = Int64(table[1][0])
    let d = Int64(table[1][1])
    if (Float64(a) != table[0][0] || Float64(b) != table[0][1]
        || Float64(c) != table[1][0] || Float64(d) != table[1][1]) {
        throw IllegalArgumentException("cangjie::fisher-test 的四个格都必须是整数计数")
    }
    if (a < 0 || b < 0 || c < 0 || d < 0) {
        throw IllegalArgumentException("cangjie::fisher-test 的计数不能为负")
    }
    let r1 = a + b
    let r2 = c + d
    let c1 = a + c
    let n = a + b + c + d
    if (n == 0) {
        throw IllegalArgumentException("cangjie::fisher-test 的表格总数为 0")
    }
    if (r1 == 0 || r2 == 0 || c1 == 0 || c1 == n) {
        throw IllegalArgumentException("cangjie::fisher-test 表里有全零的行或列，无法检验")
    }
    let obsLogP = hypergeomLogPmf(a, r1, r2, c1, n)
    // 枚举所有可能的 a 值（超几何的支撑集），累加「不比观测更可能」的那些
    var lo: Int64 = 0
    if (c1 - r2 > lo) {
        lo = c1 - r2
    }
    var hi = r1
    if (c1 < hi) {
        hi = c1
    }
    var p = 0.0
    // 浮点比较留一点余量：理论上相等的概率可能算出差 1e-16
    let tol = obsLogP + 1.0e-9
    var x = lo
    while (x <= hi) {
        let lp = hypergeomLogPmf(x, r1, r2, c1, n)
        if (lp <= tol) {
            p += exp(lp)
        }
        x++
    }
    if (p > 1.0) {
        p = 1.0
    }
    // 单侧 p：观测值及更极端的一侧
    var pLess = 0.0
    x = lo
    while (x <= a) {
        pLess += exp(hypergeomLogPmf(x, r1, r2, c1, n))
        x++
    }
    var pGreater = 0.0
    x = a
    while (x <= hi) {
        pGreater += exp(hypergeomLogPmf(x, r1, r2, c1, n))
        x++
    }
    // 优势比 a·d / (b·c)（b 或 c 为 0 时是 inf / 0）
    var odds = 0.0
    if (b > 0 && c > 0) {
        odds = Float64(a) * Float64(d) / (Float64(b) * Float64(c))
    } else if (a > 0 && d > 0) {
        odds = Float64.getInf()
    }
    let out = HashMap<String, LispValue>()
    putFloat2(out, "p", p)
    putFloat2(out, "p-less", pLess)
    putFloat2(out, "p-greater", pGreater)
    putFloat2(out, "odds-ratio", odds)
    putInt2(out, "n", n)
    out.add("method", LispValue.Str("exact"))
    LispValue.HashMap(out)
}

/**
 * Kolmogorov 分布的 CDF `P(√n·D ≤ x)`（渐近）
 *
 * `Q(λ) = 2·Σ_{j≥1} (−1)^{j−1} e^{−2j²λ²}`
 *
 * 级数在 λ 大时收敛极快（一两项就够），λ 小时需要很多项 —— 但那时
 * `Q(λ)` 已经接近 1，所以按「项小到可以丢」截断即可。
 */
func kolmogorovQ(lambda: Float64): Float64 {
    if (lambda <= 0.0) {
        return 1.0
    }
    var sum = 0.0
    var j: Int64 = 1
    while (j <= 200) {
        let term = exp(-2.0 * Float64(j) * Float64(j) * lambda * lambda)
        if (j % 2 == 1) {
            sum += term
        } else {
            sum -= term
        }
        // 前一项已经小到无关紧要就收手（交替级数，余项不超过被丢掉的那项）
        if (term < 1e-18) {
            break
        }
        j++
    }
    var p = 2.0 * sum
    if (p < 0.0) {
        p = 0.0
    }
    if (p > 1.0) {
        p = 1.0
    }
    p
}

/**
 * 两样本 Kolmogorov-Smirnov 检验：`H₀: 两组来自同一分布`
 *
 * 与秩检验的区别：它比较的是**整条分布曲线**（任何位置的差异都能察觉），
 * 而 Mann-Whitney 只对「一组整体偏大」这一类差异敏感。比如两组的中位数相同、
 * 但一组的尾部厚得多，KS 能查出来、Wilcoxon 查不出来。
 *
 * p 值用渐近公式 `Q(D·√(n₁n₂/(n₁+n₂)))`。**小样本时它偏保守**（p 值偏大），
 * 不会给出假阳性；需要精确 p 值请查 KS 临界值表。
 */
func ksTwoSample(xs: Array<Float64>, ys: Array<Float64>): LispValue {
    let x = sortRaw(finiteOf(xs), false)
    let y = sortRaw(finiteOf(ys), false)
    if (x.size < 1 || y.size < 1) {
        throw IllegalArgumentException("cangjie::ks-test 两组都需要至少 1 个有效观测")
    }
    let n1 = x.size
    let n2 = y.size
    // 双指针走两条经验 CDF，取 |F₁ − F₂| 的最大值
    var i: Int64 = 0
    var j: Int64 = 0
    var dMax = 0.0
    var dPlus = 0.0
    var dMinus = 0.0
    while (i < n1 || j < n2) {
        // 下一个最小的观测值，把两边所有等于它的都吃掉
        var v = 0.0
        if (i >= n1) {
            v = y[j]
        } else if (j >= n2) {
            v = x[i]
        } else {
            v = if (x[i] < y[j]) { x[i] } else { y[j] }
        }
        while (i < n1 && x[i] <= v) {
            i++
        }
        while (j < n2 && y[j] <= v) {
            j++
        }
        let f1 = Float64(i) / Float64(n1)
        let f2 = Float64(j) / Float64(n2)
        let d = f1 - f2
        if (abs(d) > dMax) {
            dMax = abs(d)
        }
        if (d > dPlus) {
            dPlus = d
        }
        if (-d > dMinus) {
            dMinus = -d
        }
    }
    let en = sqrt(Float64(n1 * n2) / Float64(n1 + n2))
    let lambda = dMax * en
    let out = HashMap<String, LispValue>()
    putFloat2(out, "d", dMax)
    putFloat2(out, "d-plus", dPlus)
    putFloat2(out, "d-minus", dMinus)
    putFloat2(out, "p", kolmogorovQ(lambda))
    putInt2(out, "n1", n1)
    putInt2(out, "n2", n2)
    out.add("method", LispValue.Str("asymptotic"))
    LispValue.HashMap(out)
}

func registerExactTests(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::fisher-test table) —— 2×2 精确列联表检验
    env.define("cangjie::fisher-test", NativeFunc({ args =>
        guardedDist("cangjie::fisher-test", { =>
            requireArity(args, 1, "cangjie::fisher-test")
            fisherTest(toTable(args[0], "cangjie::fisher-test"))
        })
    }))

    // (cangjie::ks-test x y) —— 两样本 K-S 检验
    env.define("cangjie::ks-test", NativeFunc({ args =>
        guardedDist("cangjie::ks-test", { =>
            requireArity(args, 2, "cangjie::ks-test")
            ksTwoSample(asFloatValues(args[0], "cangjie::ks-test"),
                asFloatValues(args[1], "cangjie::ks-test"))
        })
    }))
}
