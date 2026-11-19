package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 基于 SVD / 特征分解的派生量：`rank` / `cond` / `ginv` / `pca`
 *
 * 这四个都是「`svd` 算完之后再走一步」，所以放在 `svd.cj` 之后单开一个文件 ——
 * 它们共享同一套分解结果，不该各自再实现一遍。
 *
 * ## 阈值判据
 *
 * `rank` 与 `ginv` 都要判断「这个奇异值算不算 0」。绝对阈值没有意义：
 * 把整个矩阵乘 1e-6 后，所有奇异值都小于 1e-3，但秩没变。
 * 所以用**相对判据** `σ > max(m,n) · ε · σmax`（ε 是 float64 机器精度 2.22e-16），
 * 与 NumPy `matrix_rank` 的默认约定一致。这个式子的含义是：
 * 「相对最大奇异值而言，这个 σ 已经小到了舍入误差的量级」。
 */

/** float64 机器精度 */
let MACHINE_EPS: Float64 = 2.220446049250313e-16

/** 相对秩判据的阈值：`max(rows, cols) · ε · σmax` */
func svdTolerance(rows: Int64, cols: Int64, sMax: Float64): Float64 {
    let mx = if (rows > cols) { rows } else { cols }
    Float64(mx) * MACHINE_EPS * sMax
}

/** 数值秩 */
func rankRaw(rows: Int64, cols: Int64, a: Array<Float64>): Int64 {
    let (_, s, _) = svdRaw(rows, cols, a)
    if (s.size == 0 || s[0] <= 0.0) {
        return 0
    }
    let tol = svdTolerance(rows, cols, s[0])
    var cnt: Int64 = 0
    var i: Int64 = 0
    while (i < s.size) {
        if (s[i] > tol) {
            cnt++
        }
        i++
    }
    cnt
}

/**
 * 2-范数条件数 `σmax / σmin`
 *
 * 全零矩阵返回 `0`（秩 0，谈不上病态）；有零奇异值时返回 `inf`（严格奇异）。
 */
func condRaw(rows: Int64, cols: Int64, a: Array<Float64>): Float64 {
    let (_, s, _) = svdRaw(rows, cols, a)
    if (s.size == 0 || s[0] <= 0.0) {
        return 0.0
    }
    let tol = svdTolerance(rows, cols, s[0])
    let sMin = s[s.size - 1]
    if (sMin <= tol) {
        return Float64.getInf()
    }
    s[0] / sMin
}

/**
 * Moore-Penrose 伪逆 `A⁺ = V Σ⁺ Uᵀ`（返回 `cols×rows`）
 *
 * 与 `inv` 的区别在于**它永远有定义**：奇异矩阵、长方阵都有伪逆，
 * 而 `inv` 对它们只能报错。最小二乘 `x = A⁺y` 就是 `lstsq` 的手工版。
 */
func pinvRaw(rows: Int64, cols: Int64, a: Array<Float64>): Array<Float64> {
    let (u, s, vt) = svdRaw(rows, cols, a)
    let k = s.size
    var sMax = 0.0
    if (k > 0) {
        sMax = s[0]
    }
    let tol = svdTolerance(rows, cols, sMax)
    // out 是 cols×rows
    let out = Array<Float64>(rows * cols, repeat: 0.0)
    var i: Int64 = 0
    while (i < cols) {
        var j: Int64 = 0
        while (j < rows) {
            var acc = 0.0
            var t: Int64 = 0
            while (t < k) {
                if (s[t] > tol) {
                    // v[i][t] = vt[t * cols + i]；u[j][t] = u[j * k + t]
                    acc += (vt[t * cols + i] / s[t]) * u[j * k + t]
                }
                t++
            }
            out[i * rows + j] = acc
            j++
        }
        i++
    }
    out
}

/**
 * 主成分分析
 *
 * 对**中心化后**的矩阵做 SVD：`Xc = U Σ Vᵀ`，于是
 * - `scores = U Σ`（把原数据投影到主成分上）
 * - `loadings = V`（每个原始变量在各主成分上的权重）
 * - `sdev = Σ / √(n−1)`（各主成分的标准差）
 * - `varExplained = Σ² / Σσ²`（解释方差比例）
 *
 * 用 SVD 而不是对协方差矩阵做 `eigen`：后者要先算 `XcᵀXc`，
 * 而这一步会把条件数**平方** —— 数据本身条件数 1e8 时，协方差矩阵就是 1e16，
 * 已经在 float64 的精度之外了。SVD 直接作用在 `Xc` 上，避开了这个问题。
 */
func pcaRaw(rows: Int64, cols: Int64, a: Array<Float64>, keep: Int64):
    HashMap<String, LispValue> {
    // 列均值
    let center = Array<Float64>(cols, repeat: 0.0)
    var j: Int64 = 0
    while (j < cols) {
        var sum = 0.0
        var i: Int64 = 0
        while (i < rows) {
            sum += a[i * cols + j]
            i++
        }
        center[j] = sum / Float64(rows)
        j++
    }
    // 中心化
    let xc = Array<Float64>(rows * cols, repeat: 0.0)
    var i: Int64 = 0
    while (i < rows) {
        j = 0
        while (j < cols) {
            xc[i * cols + j] = a[i * cols + j] - center[j]
            j++
        }
        i++
    }
    let (u, s, vt) = svdRaw(rows, cols, xc)
    let k0 = s.size
    var k = keep
    if (k <= 0 || k > k0) {
        k = k0
    }
    // scores: rows×k = U Σ
    let scores = Array<Float64>(rows * k, repeat: 0.0)
    i = 0
    while (i < rows) {
        var t: Int64 = 0
        while (t < k) {
            scores[i * k + t] = u[i * k0 + t] * s[t]
            t++
        }
        i++
    }
    // loadings: cols×k = V（即 vt 的转置）
    let loadings = Array<Float64>(cols * k, repeat: 0.0)
    i = 0
    while (i < cols) {
        var t: Int64 = 0
        while (t < k) {
            loadings[i * k + t] = vt[t * cols + i]
            t++
        }
        i++
    }
    // sdev 与解释方差
    let sdev = Array<Float64>(k, repeat: 0.0)
    let varExplained = Array<Float64>(k, repeat: 0.0)
    var total = 0.0
    var t: Int64 = 0
    while (t < k0) {
        total += s[t] * s[t]
        t++
    }
    let denom = if (rows > 1) { sqrt(Float64(rows - 1)) } else { 1.0 }
    t = 0
    while (t < k) {
        sdev[t] = s[t] / denom
        varExplained[t] = if (total > 0.0) { s[t] * s[t] / total } else { 0.0 }
        t++
    }
    let result = HashMap<String, LispValue>()
    result.add("scores", LispValue.External(matrixToArray(rows, k, scores)))
    result.add("loadings", LispValue.External(matrixToArray(cols, k, loadings)))
    result.add("sdev", LispValue.External(ndarrayFromFloats(sdev)))
    result.add("var-explained", LispValue.External(ndarrayFromFloats(varExplained)))
    result.add("center", LispValue.External(ndarrayFromFloats(center)))
    result
}

// ───────────────────────── Lisp 接口 ─────────────────────────

/** 把行优先矩阵打成 ndarray */
func matrixOf(rows: Int64, cols: Int64, data: Array<Float64>): LispValue {
    LispValue.External(matrixToArray(rows, cols, data))
}

/** 取整型参数（保留主成分个数这类） */
func intArgL(v: LispValue, who: String, name: String): Int64 {
    match (v) {
        case Int(i) => i
        case _ => throw IllegalArgumentException(
            "${who} 的 ${name} 需要整数，得到 ${v.toString()}")
    }
}

/** `(cangjie::svd A)` → `{u, s, vt}` */
func svdLispOf(av: LispValue): LispValue {
    let (rows, cols, data) = toMatrix(av, "cangjie::svd")
    let k = if (rows < cols) { rows } else { cols }
    let (u, s, vt) = svdRaw(rows, cols, data)
    let result = HashMap<String, LispValue>()
    result.add("u", matrixOf(rows, k, u))
    result.add("s", LispValue.External(ndarrayFromFloats(s)))
    result.add("vt", matrixOf(k, cols, vt))
    LispValue.HashMap(result)
}

/** `(cangjie::eigen A)` → `{values, vectors}`；只接受对称矩阵 */
func eigenLispOf(av: LispValue): LispValue {
    let (rows, cols, data) = toMatrix(av, "cangjie::eigen")
    requireSquare(rows, cols, "cangjie::eigen")
    // 对称性检查：不查的话，非对称矩阵会被当成对称矩阵算，给出**看起来正常**的错结果
    var scale = 0.0
    var i: Int64 = 0
    while (i < rows * cols) {
        scale += abs(data[i])
        i++
    }
    let tol = (if (scale > 0.0) { scale } else { 1.0 }) * 1.0e-12
    i = 0
    while (i < rows) {
        var j = i + 1
        while (j < cols) {
            if (abs(data[i * cols + j] - data[j * cols + i]) > tol) {
                throw IllegalArgumentException(
                    "cangjie::eigen 只接受对称矩阵：第 ${i} 行 ${j} 列为 " +
                    "${data[i * cols + j]}，第 ${j} 行 ${i} 列为 ${data[j * cols + i]}。\n" +
                    "非对称矩阵的特征值可能是复数，而本仓的 dtype 没有复数。" +
                    "任意矩阵请用 cangjie::svd（它对所有矩阵都有定义）。")
            }
            j++
        }
        i++
    }
    let (vals, vecs) = eigenSymRaw(rows, data)
    let result = HashMap<String, LispValue>()
    result.add("values", LispValue.External(ndarrayFromFloats(vals)))
    result.add("vectors", matrixOf(rows, rows, vecs))
    LispValue.HashMap(result)
}

/** `(cangjie::rank A)` → 整数 */
func rankLispOf(av: LispValue): LispValue {
    let (rows, cols, data) = toMatrix(av, "cangjie::rank")
    LispValue.Int(rankRaw(rows, cols, data))
}

/** `(cangjie::cond A)` → 浮点 */
func condLispOf(av: LispValue): LispValue {
    let (rows, cols, data) = toMatrix(av, "cangjie::cond")
    LispValue.Float(condRaw(rows, cols, data))
}

/** `(cangjie::ginv A)` → 伪逆 ndarray（`cols×rows`） */
func pinvLispOf(av: LispValue): LispValue {
    let (rows, cols, data) = toMatrix(av, "cangjie::ginv")
    matrixOf(cols, rows, pinvRaw(rows, cols, data))
}

/** `(cangjie::pca X)` 或 `(cangjie::pca X k)` */
func pcaLispOf(args: ArrayList<LispValue>): LispValue {
    if (args.size != 1 && args.size != 2) {
        throw IllegalArgumentException(
            "cangjie::pca 需要 (X) 或 (X k) 两种形式，得到 ${args.size} 个参数")
    }
    let (rows, cols, data) = toMatrix(args[0], "cangjie::pca")
    var keep: Int64 = 0
    if (args.size == 2) {
        keep = intArgL(args[1], "cangjie::pca", "k")
        if (keep <= 0) {
            throw IllegalArgumentException("cangjie::pca 的 k 必须 > 0，得到 ${keep}")
        }
        let kMax = if (rows < cols) { rows } else { cols }
        if (keep > kMax) {
            throw IllegalArgumentException(
                "cangjie::pca 的 k 不能超过 min(行数, 列数) = ${kMax}，得到 ${keep}")
        }
    }
    LispValue.HashMap(pcaRaw(rows, cols, data, keep))
}
