package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 矩阵分解与线性方程组
 *
 * 全部基于**带部分主元的 LU 分解**（`solve` / `det` / `inv` 共用一份分解），
 * 另加 Cholesky（对称正定，比 LU 快一倍且更稳）与 Householder QR。
 *
 * 奇异 / 非正定**一律报错**：悄悄返回一个"看起来像逆矩阵"的垃圾值，
 * 比一次明确的报错危险得多。
 */

/**
 * LU 分解（部分主元，Doolittle）
 *
 * 返回 `(lu, piv, 主元符号, 是否奇异)`。`lu` 原地存放：下三角（不含对角线）是 L，
 * 上三角含对角线是 U，L 的对角线隐含为 1。`piv[i]` 是第 i 步选中的行。
 *
 * 部分主元不是可选项：不选主元时，`[[0,1],[1,0]]` 这种矩阵在第一步就会除零，
 * 而 `[[1e-20,1],[1,1]]` 会得到灾难性的误差放大。
 */
func luDecompose(n: Int64, a: Array<Float64>): (Array<Float64>, Array<Int64>, Float64, Bool) {
    let lu = a.clone()
    let piv = Array<Int64>(n, repeat: 0)
    let eps = linalgEps(a)
    var sign = 1.0
    var singular = false
    var k: Int64 = 0
    while (k < n) {
        // 选绝对值最大的主元
        var p = k
        var maxV = abs(lu[k * n + k])
        var i = k + 1
        while (i < n) {
            let v = abs(lu[i * n + k])
            if (v > maxV) {
                maxV = v
                p = i
            }
            i++
        }
        piv[k] = p
        if (maxV <= eps) {
            singular = true
        }
        if (p != k) {
            var j: Int64 = 0
            while (j < n) {
                let t = lu[k * n + j]
                lu[k * n + j] = lu[p * n + j]
                lu[p * n + j] = t
                j++
            }
            sign = -sign
        }
        let pivot = lu[k * n + k]
        if (pivot != 0.0) {
            i = k + 1
            while (i < n) {
                let factor = lu[i * n + k] / pivot
                lu[i * n + k] = factor
                var j = k + 1
                while (j < n) {
                    lu[i * n + j] = lu[i * n + j] - factor * lu[k * n + j]
                    j++
                }
                i++
            }
        }
        k++
    }
    (lu, piv, sign, singular)
}

/** 用已分解的 LU 解 `A x = b`（`b` 会被当作工作区） */
func luSolve(n: Int64, lu: Array<Float64>, piv: Array<Int64>, b: Array<Float64>): Array<Float64> {
    let x = b.clone()
    // 应用行置换
    var k: Int64 = 0
    while (k < n) {
        let p = piv[k]
        if (p != k) {
            let t = x[k]
            x[k] = x[p]
            x[p] = t
        }
        k++
    }
    // 前代 L y = Pb（L 对角线为 1）
    k = 0
    while (k < n) {
        var s = x[k]
        var j: Int64 = 0
        while (j < k) {
            s = s - lu[k * n + j] * x[j]
            j++
        }
        x[k] = s
        k++
    }
    // 回代 U x = y
    k = n - 1
    while (k >= 0) {
        var s = x[k]
        var j = k + 1
        while (j < n) {
            s = s - lu[k * n + j] * x[j]
            j++
        }
        x[k] = s / lu[k * n + k]
        k--
    }
    x
}

func requireSquare(rows: Int64, cols: Int64, who: String): Unit {
    if (rows != cols) {
        throw IllegalArgumentException("${who} 需要方阵，得到 ${rows}×${cols}")
    }
}

/** `(cangjie::det A)` —— 行列式 */
func detOf(av: LispValue): Float64 {
    let (rows, cols, data) = toMatrix(av, "cangjie::det")
    requireSquare(rows, cols, "cangjie::det")
    if (rows == 0) {
        return 1.0
    }
    let (lu, _, sign, singular) = luDecompose(rows, data)
    var d = sign
    var i: Int64 = 0
    while (i < rows) {
        d = d * lu[i * rows + i]
        i++
    }
    if (singular) {
        // 精确奇异时对角线会出现 0，乘积自然是 0；这里只把极小值归零，避免
        // 1e-300 这种"看起来有值"的残渣被当成可逆
        let eps = linalgEps(data)
        if (abs(d) <= eps * eps) {
            return 0.0
        }
    }
    d
}

/**
 * `(cangjie::solve A b)` —— 解 `A x = b`
 *
 * `b` 可以是 `(n,)` 向量或 `(n, m)` 多列右端项（一次解多个方程组，共用同一份 LU）。
 */
func solveLisp(av: LispValue, bv: LispValue): LispValue {
    let (n, cols, a) = toMatrix(av, "cangjie::solve")
    requireSquare(n, cols, "cangjie::solve")
    let bArr = match (bv) {
        case External(e) => match (e) {
            case x: NDArray => x
            case _ => throw IllegalArgumentException("cangjie::solve 的 b 需要 ndarray")
        }
        case _ => throw IllegalArgumentException("cangjie::solve 的 b 需要 ndarray")
    }
    let bd = bArr.shape
    let bIsVec = bd.size == 1
    let (bn, bm, bData) = toMatrix(bv, "cangjie::solve")
    if (bn != n) {
        throw IllegalArgumentException(
            "solve 维度不匹配：A 是 ${n}×${n}，b 有 ${bn} 行")
    }
    let (lu, piv, _, singular) = luDecompose(n, a)
    if (singular) {
        throw IllegalArgumentException(
            "solve：矩阵奇异或接近奇异，无法求解（det ≈ 0）")
    }
    if (bIsVec) {
        return LispValue.External(ndarrayFromFloats(luSolve(n, lu, piv, bData)))
    }
    // 多列：逐个右端项求解
    let out = Array<Float64>(n * bm, repeat: 0.0)
    var c: Int64 = 0
    while (c < bm) {
        let col = Array<Float64>(n, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            col[i] = bData[i * bm + c]
            i++
        }
        let sol = luSolve(n, lu, piv, col)
        i = 0
        while (i < n) {
            out[i * bm + c] = sol[i]
            i++
        }
        c++
    }
    LispValue.External(matrixToArray(n, bm, out))
}

/** `(cangjie::inv A)` —— 逆矩阵 */
func invOf(av: LispValue): LispValue {
    let (n, cols, a) = toMatrix(av, "cangjie::inv")
    requireSquare(n, cols, "cangjie::inv")
    if (n == 0) {
        throw IllegalArgumentException("inv：空矩阵没有逆")
    }
    let (lu, piv, _, singular) = luDecompose(n, a)
    if (singular) {
        throw IllegalArgumentException(
            "inv：矩阵奇异或接近奇异，没有逆（det ≈ 0）")
    }
    let out = Array<Float64>(n * n, repeat: 0.0)
    var c: Int64 = 0
    while (c < n) {
        let e = Array<Float64>(n, repeat: 0.0)
        e[c] = 1.0
        let col = luSolve(n, lu, piv, e)
        var i: Int64 = 0
        while (i < n) {
            out[i * n + c] = col[i]
            i++
        }
        c++
    }
    LispValue.External(matrixToArray(n, n, out))
}

/**
 * `(cangjie::cholesky A)` —— 对称正定矩阵的 `A = L Lᵀ`
 *
 * 只做下三角 L。Cholesky 比 LU 快一倍且不需要选主元 —— 对称正定保证了主元恒正。
 * 非正定时**报错**：返回一个"看起来像分解"的垃圾值会让后续求解全部错。
 */
func choleskyOf(av: LispValue): LispValue {
    let (n, cols, a) = toMatrix(av, "cangjie::cholesky")
    requireSquare(n, cols, "cangjie::cholesky")
    // 先检查对称性（相对容差）
    let eps = linalgEps(a)
    var i: Int64 = 0
    while (i < n) {
        var j: Int64 = i + 1
        while (j < n) {
            if (abs(a[i * n + j] - a[j * n + i]) > eps) {
                throw IllegalArgumentException(
                    "cholesky 需要对称矩阵：A[${i},${j}]=${a[i * n + j]} 与 A[${j},${i}]=${a[j * n + i]} 不相等")
            }
            j++
        }
        i++
    }
    let l = Array<Float64>(n * n, repeat: 0.0)
    i = 0
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
                        "cholesky：矩阵不是正定的（第 ${i} 个主元为 ${s}）")
                }
                l[i * n + i] = sqrt(s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j++
        }
        i++
    }
    LispValue.External(matrixToArray(n, n, l))
}

/**
 * `(cangjie::lu A)` —— 返回 `{"l": …, "u": …, "p": …}`
 *
 * `p` 是**累积后的最终置换**（1-based：`p[i]` 表示 `PA` 的第 i 行来自原矩阵的第 `p[i]` 行），
 * 满足 `P A = L U`。注意它不是「每步与谁交换」的中间量。
 */
func luLispOf(av: LispValue): LispValue {
    let (n, cols, a) = toMatrix(av, "cangjie::lu")
    requireSquare(n, cols, "cangjie::lu")
    let (lu, piv, _, singular) = luDecompose(n, a)
    if (singular) {
        throw IllegalArgumentException("lu：矩阵奇异或接近奇异")
    }
    let l = Array<Float64>(n * n, repeat: 0.0)
    let u = Array<Float64>(n * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        var j: Int64 = 0
        while (j < n) {
            if (j < i) {
                l[i * n + j] = lu[i * n + j]
            } else if (j == i) {
                l[i * n + j] = 1.0
                u[i * n + j] = lu[i * n + j]
            } else {
                u[i * n + j] = lu[i * n + j]
            }
            j++
        }
        i++
    }
    // 把「逐步交换」累积成**最终置换**：`piv[k]` 只说明第 k 步与哪一行交换，
    // 直接拿它当置换会得到非法矩阵（`[[1,2],[3,4]]` 的 piv 是 [1,1]，两行都指向
    // 同一行）。累积后的 perm[i] 才表示 PA 的第 i 行来自原矩阵的哪一行。
    let perm = Array<Int64>(n, repeat: 0)
    i = 0
    while (i < n) {
        perm[i] = i
        i++
    }
    var kk: Int64 = 0
    while (kk < n) {
        let pv = piv[kk]
        if (pv != kk) {
            let t = perm[kk]
            perm[kk] = perm[pv]
            perm[pv] = t
        }
        kk++
    }
    let pData = Array<Float64>(n, repeat: 0.0)
    i = 0
    while (i < n) {
        pData[i] = Float64(perm[i] + 1)      // 1-based，方便在 Lisp 里读
        i++
    }
    let out = HashMap<String, LispValue>()
    out.add("l", LispValue.External(matrixToArray(n, n, l)))
    out.add("u", LispValue.External(matrixToArray(n, n, u)))
    out.add("p", LispValue.External(ndarrayFromFloats(pData)))
    LispValue.HashMap(out)
}

/**
 * `(cangjie::qr A)` —— Householder QR，返回 `{"q": …, "r": …}`
 *
 * `Q` 是 `m×m` 正交矩阵，`R` 是 `m×n` 上三角。用 Householder 反射而不是
 * Gram-Schmidt：古典 Gram-Schmidt 在近乎线性相关的列上会严重丢正交性。
 */
/**
 * Householder QR 分解：返回 `(Q, R)`
 *
 * `Q` 是 `m×m` 正交矩阵，`R` 是 `m×n` 上三角。用 Householder 反射而不是
 * Gram-Schmidt：古典 Gram-Schmidt 在近乎线性相关的列上会严重丢正交性。
 */
func qrRaw(m: Int64, n: Int64, a: Array<Float64>): (Array<Float64>, Array<Float64>) {
    let r = a.clone()
    let q = Array<Float64>(m * m, repeat: 0.0)
    var i: Int64 = 0
    while (i < m) {
        q[i * m + i] = 1.0
        i++
    }
    var k: Int64 = 0
    let steps = if (m < n) { m } else { n }
    while (k < steps) {
        var norm = 0.0
        i = k
        while (i < m) {
            let v = r[i * n + k]
            norm = norm + v * v
            i++
        }
        norm = sqrt(norm)
        if (norm == 0.0) {
            k++
            continue
        }
        let alpha = if (r[k * n + k] >= 0.0) { -norm } else { norm }
        let v = Array<Float64>(m, repeat: 0.0)
        i = k
        while (i < m) {
            v[i] = r[i * n + k]
            i++
        }
        v[k] = v[k] - alpha
        var vnorm2 = 0.0
        i = k
        while (i < m) {
            vnorm2 = vnorm2 + v[i] * v[i]
            i++
        }
        if (vnorm2 == 0.0) {
            k++
            continue
        }
        var j: Int64 = k
        while (j < n) {
            var dot = 0.0
            i = k
            while (i < m) {
                dot = dot + v[i] * r[i * n + j]
                i++
            }
            let factor = 2.0 * dot / vnorm2
            i = k
            while (i < m) {
                r[i * n + j] = r[i * n + j] - factor * v[i]
                i++
            }
            j++
        }
        j = 0
        while (j < m) {
            var dot = 0.0
            i = k
            while (i < m) {
                dot = dot + q[j * m + i] * v[i]
                i++
            }
            let factor = 2.0 * dot / vnorm2
            i = k
            while (i < m) {
                q[j * m + i] = q[j * m + i] - factor * v[i]
                i++
            }
            j++
        }
        k++
    }
    // 把 R 的严格下三角清零（浮点残渣）
    i = 0
    while (i < m) {
        var j: Int64 = 0
        while (j < n) {
            if (i > j) {
                r[i * n + j] = 0.0
            }
            j++
        }
        i++
    }
    (q, r)
}

/**
 * `(cangjie::lstsq X y)` —— 最小二乘
 *
 * 解 `min ‖X b − y‖`。用 QR：`X = QR` 时 `b = R⁻¹ Qᵀ y`，
 * 只取 `Qᵀy` 的前 n 个分量回代 —— 不显式求 `XᵀX` 的逆。
 *
 * **这是相对正规方程的关键优势**：正规方程把条件数平方（`cond(XᵀX) = cond(X)²`），
 * 一个条件数 1e6 的设计矩阵直接变成 1e12，多精度就全丢了。
 *
 * `X` 是 `(m, n)`，`y` 是 `(m,)`，返回 `b`（`n` 维）。
 */
func lstsqLisp(xv: LispValue, yv: LispValue): LispValue {
    let (m, n, x) = toMatrix(xv, "cangjie::lstsq")
    if (m < n) {
        throw IllegalArgumentException(
            "lstsq：样本数 ${m} 少于特征数 ${n}，方程欠定")
    }
    let y = match (yv) {
        case External(e) => match (e) {
            case a: NDArray =>
                let arr = a.copy()
                if (arr.shape.size == 2 && arr.shape[1] != 1) {
                    throw IllegalArgumentException("lstsq：y 必须是向量或单列矩阵")
                }
                flattenFloats(arr, "cangjie::lstsq")
            case _ => throw IllegalArgumentException("lstsq 的 y 需要 ndarray")
        }
        case _ => throw IllegalArgumentException("lstsq 的 y 需要 ndarray")
    }
    if (y.size != m) {
        throw IllegalArgumentException(
            "lstsq：X 有 ${m} 行但 y 有 ${y.size} 个元素")
    }
    let (q, r) = qrRaw(m, n, x)
    // Qᵀ y（取前 n 个）
    let qty = Array<Float64>(n, repeat: 0.0)
    var j: Int64 = 0
    while (j < n) {
        var s = 0.0
        var i: Int64 = 0
        while (i < m) {
            s = s + q[i * m + j] * y[i]
            i++
        }
        qty[j] = s
        j++
    }
    // 回代解 R[0..n, 0..n] b = qty
    let b = Array<Float64>(n, repeat: 0.0)
    var k = n - 1
    while (k >= 0) {
        let diag = r[k * n + k]
        if (abs(diag) <= linalgEps(x)) {
            throw IllegalArgumentException(
                "lstsq：设计矩阵秩亏（第 ${k} 个对角元为 ${diag}），特征之间线性相关")
        }
        var s = qty[k]
        var j2 = k + 1
        while (j2 < n) {
            s = s - r[k * n + j2] * b[j2]
            j2++
        }
        b[k] = s / diag
        k--
    }
    LispValue.External(ndarrayFromFloats(b))
}

func qrLispOf(av: LispValue): LispValue {
    let (m, n, a) = toMatrix(av, "cangjie::qr")
    let (q, r) = qrRaw(m, n, a)
    let out = HashMap<String, LispValue>()
    out.add("q", LispValue.External(matrixToArray(m, m, q)))
    out.add("r", LispValue.External(matrixToArray(m, n, r)))
    LispValue.HashMap(out)
}
