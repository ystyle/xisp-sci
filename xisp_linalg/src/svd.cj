package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 奇异值分解与对称特征值分解
 *
 * ## 为什么现在才做
 *
 * 路线图阶段 4 写的是「`eig` / `svd` 视难度单独排」—— 这一排就排到了现在。
 * 缺它们的代价是具体的：
 *
 * - **PCA 做不了**（它是 SVD 的直接应用）
 * - **没有 `rank` / `cond`**，判断奇异只能拿 `det` 当代理，而 `det` 在维度稍大时
 *   既会上溢又可能下溢，是个不可靠的指示器
 * - **`lstsq` 只能走 QR**，对病态矩阵 SVD 才是更稳的路线
 * - **没有 `ginv`**，非满秩最小二乘只能报错
 *
 * ## 算法：为什么是 Jacobi
 *
 * SVD 用的是**单边 Jacobi（Hestenes）**，不是 Golub-Kahan-Reinsch。
 *
 * GKR 更快（O(n²m) → O(nm²) 的常数更小），但要 Householder 双对角化 + 隐式 QR
 * 带 Wilkinson 位移，几百行且每一步都得仔细验。Jacobi 赢在**精度**：
 * 它给出的每个奇异值都有高**相对**精度，而 QR 路线的小奇异值相对误差会退化。
 * 而 `cond`（σmax/σmin）和 `rank`（数有几个 σ 显著大于 0）恰恰完全依赖小奇异值 ——
 * 用 GKR 的结果去算条件数，会在最需要它的时候给出不准的数。
 *
 * 代价是慢一点。数据分析的矩阵（n < 1000）用不上那点速度差：800×800 的 SVD
 * 在 Jacobi 下约 1 秒量级，而这个规模本来就该考虑稀疏或降维了。
 *
 * 对称特征值同理用**循环 Jacobi**（cyclic Jacobi）—— 对称矩阵的经典方法，
 * 全局收敛、精度高、代码短。
 *
 * ## 只支持对称矩阵的 `eigen`
 *
 * 非对称矩阵的特征值可以是复数，而本仓的 dtype 只有 `Int64` / `Float64` / `Bool`
 * （路线图 §4.3 明确决定不做复数）。硬做非对称就得返回「实部数组 + 虚部数组」，
 * 那等于在没有复数类型的前提下发明一套半吊子的表示。
 *
 * 所以 `eigen` 对非对称矩阵**报错并提示用 `svd`** —— 后者对任意矩阵都有定义，
 * 且统计场景里真正需要的（协方差矩阵、相关矩阵、PCA）全都是对称的。
 *
 * ## 约定
 *
 * 所有矩阵参数都是**行优先**的 `Array<Float64>`，`i` 行 `j` 列在 `i * cols + j`。
 */

/** 单位阵（行优先） */
func identityRaw(n: Int64): Array<Float64> {
    let v = Array<Float64>(n * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        v[i * n + i] = 1.0
        i++
    }
    v
}

/** 转置：输入 `rows×cols`，输出 `cols×rows` */
func transposeRaw(rows: Int64, cols: Int64, a: Array<Float64>): Array<Float64> {
    let out = Array<Float64>(rows * cols, repeat: 0.0)
    var i: Int64 = 0
    while (i < rows) {
        var j: Int64 = 0
        while (j < cols) {
            out[j * rows + i] = a[i * cols + j]
            j++
        }
        i++
    }
    out
}

/**
 * 给零奇异值补一个与其余列正交的单位向量
 *
 * 秩亏时 `U` 的零列在数学上是任意的（任何与其余列正交的单位向量都成立），
 * 但**必须正交** —— 否则 `UᵀU = I` 不成立，基于它算出来的 `ginv` 也是错的。
 * 直接从标准基取 `e_0` 会导致多个零列撞在一起，所以这里挑「与已有列最不相关」
 * 的那个基向量，再做一遍 Gram-Schmidt。
 */
func fillZeroColumn(u: Array<Float64>, rows: Int64, cols: Int64, j: Int64): Unit {
    var best: Int64 = 0
    var bestScore = Float64.getInf()
    var cand: Int64 = 0
    while (cand < rows) {
        var score = 0.0
        var k: Int64 = 0
        while (k < cols) {
            if (k != j) {
                score += abs(u[cand * cols + k])
            }
            k++
        }
        if (score < bestScore) {
            bestScore = score
            best = cand
        }
        cand++
    }
    let tmp = Array<Float64>(rows, repeat: 0.0)
    tmp[best] = 1.0
    var k: Int64 = 0
    while (k < cols) {
        if (k != j) {
            var dot = 0.0
            var i: Int64 = 0
            while (i < rows) {
                dot += tmp[i] * u[i * cols + k]
                i++
            }
            i = 0
            while (i < rows) {
                tmp[i] = tmp[i] - dot * u[i * cols + k]
                i++
            }
        }
        k++
    }
    var norm = 0.0
    var i: Int64 = 0
    while (i < rows) {
        norm += tmp[i] * tmp[i]
        i++
    }
    norm = sqrt(norm)
    if (norm > 0.0) {
        i = 0
        while (i < rows) {
            u[i * cols + j] = tmp[i] / norm
            i++
        }
    }
}

/**
 * 单边 Jacobi 分解（要求 `rows >= cols`）
 *
 * 反复把 U 的**列**两两正交化（旋转同时作用在 U 与 V 上，所以 `U Vᵀ` 不变）。
 * 收敛后每列的长度就是奇异值。
 */
func jacobiSvdTall(rows: Int64, cols: Int64, a: Array<Float64>):
    (Array<Float64>, Array<Float64>, Array<Float64>) {
    let u = a.clone()
    let v = identityRaw(cols)
    let eps = 1.0e-15
    // 用初始矩阵的 Frobenius 范数当收敛判据的尺度 —— 绝对值阈值对量级敏感的
    // 矩阵（如全部元素 1e-10）会误判成"已收敛"
    var scale = 0.0
    var t: Int64 = 0
    while (t < rows * cols) {
        scale += u[t] * u[t]
        t++
    }
    scale = sqrt(scale)
    if (scale == 0.0) {
        return (u, Array<Float64>(cols, repeat: 0.0), identityRaw(cols))
    }

    var sweep: Int64 = 0
    while (sweep < 60) {
        var offNorm = 0.0
        var p: Int64 = 0
        while (p < cols - 1) {
            var q = p + 1
            while (q < cols) {
                var alpha = 0.0
                var beta = 0.0
                var gamma = 0.0
                var i: Int64 = 0
                while (i < rows) {
                    let up = u[i * cols + p]
                    let uq = u[i * cols + q]
                    alpha += up * up
                    beta += uq * uq
                    gamma += up * uq
                    i++
                }
                if (abs(gamma) > eps * sqrt(alpha * beta)) {
                    offNorm += gamma * gamma
                    let zeta = (beta - alpha) / (2.0 * gamma)
                    // 取绝对值较小的那个根，避免 zeta 很大时的相消误差
                    var tau = 0.0
                    if (zeta >= 0.0) {
                        tau = 1.0 / (zeta + sqrt(1.0 + zeta * zeta))
                    } else {
                        tau = -1.0 / (-zeta + sqrt(1.0 + zeta * zeta))
                    }
                    let c = 1.0 / sqrt(1.0 + tau * tau)
                    let s = c * tau
                    i = 0
                    while (i < rows) {
                        let up = u[i * cols + p]
                        let uq = u[i * cols + q]
                        u[i * cols + p] = c * up - s * uq
                        u[i * cols + q] = s * up + c * uq
                        i++
                    }
                    i = 0
                    while (i < cols) {
                        let vp = v[i * cols + p]
                        let vq = v[i * cols + q]
                        v[i * cols + p] = c * vp - s * vq
                        v[i * cols + q] = s * vp + c * vq
                        i++
                    }
                }
                q++
            }
            p++
        }
        if (sqrt(offNorm) <= eps * scale) {
            break
        }
        sweep++
    }

    // 列长度 = 奇异值；顺便把 U 归一化成单位列
    let sv = Array<Float64>(cols, repeat: 0.0)
    var j: Int64 = 0
    while (j < cols) {
        var norm = 0.0
        var i: Int64 = 0
        while (i < rows) {
            let x = u[i * cols + j]
            norm += x * x
            i++
        }
        sv[j] = sqrt(norm)
        j++
    }
    // 判零用**相对**阈值：秩亏时残列不会是精确 0，而是 1e-17 量级。
    // 若按 `> 0` 判断就会把一个纯噪声方向归一化成"奇异向量"，U 立刻失去正交性
    var sMax = 0.0
    j = 0
    while (j < cols) {
        if (sv[j] > sMax) {
            sMax = sv[j]
        }
        j++
    }
    let zeroTol = eps * scale
    // **两遍**：先归一化所有非零列，再补零列。
    // 合成一遍会踩坑：Jacobi 收敛后零列可能排在前（[[1,1],[1,1]] 的最优列序就是「零列在前」），
    // 而零列的 Gram-Schmidt 需要其余列**已经是单位向量**，否则补出来的向量不正交。
    j = 0
    while (j < cols) {
        if (sv[j] > zeroTol) {
            var i: Int64 = 0
            while (i < rows) {
                u[i * cols + j] = u[i * cols + j] / sv[j]
                i++
            }
        } else {
            sv[j] = 0.0
        }
        j++
    }
    j = 0
    while (j < cols) {
        if (sv[j] == 0.0) {
            fillZeroColumn(u, rows, cols, j)
        }
        j++
    }
    (u, sv, v)
}

/**
 * 奇异值分解 `A = U · diag(S) · Vᵀ`（thin 形式）
 *
 * 返回 `(u, s, vt)`：`k = min(rows, cols)`，`u` 是 `rows×k`，`s` 长度 `k`（**降序**），
 * `vt` 是 `k×cols`。三者都是行优先。
 */
func svdRaw(rows: Int64, cols: Int64, a: Array<Float64>):
    (Array<Float64>, Array<Float64>, Array<Float64>) {
    if (rows >= cols) {
        let (u, s, v) = jacobiSvdTall(rows, cols, a)
        let (u2, s2, v2) = sortSvd(u, s, v, rows, cols)
        (u2, s2, transposeRaw(cols, cols, v2))
    } else {
        // A 是矮胖的：先分解 Aᵀ（n×m，n>m），再换回来。
        // Aᵀ = U' S V'ᵀ  ⟹  A = V' S U'ᵀ，所以 A 的 U 是 V'，Vᵀ 是 U'ᵀ
        let at = transposeRaw(rows, cols, a)
        let (ut, st, vt2) = jacobiSvdTall(cols, rows, at)
        let (ut2, st2, vt3) = sortSvd(ut, st, vt2, cols, rows)
        // ut2: cols×rows（Aᵀ 的 U），vt3: rows×rows（Aᵀ 的 V）
        // A 的 U = vt3（rows×rows），A 的 Vᵀ = ut2ᵀ（rows×cols）
        (vt3, st2, transposeRaw(cols, rows, ut2))
    }
}

/** 把奇异值按降序重排，同时置换 U 与 V 的列 */
func sortSvd(u: Array<Float64>, s: Array<Float64>, v: Array<Float64>,
    rows: Int64, cols: Int64): (Array<Float64>, Array<Float64>, Array<Float64>) {
    let order = Array<Int64>(cols, repeat: 0)
    var i: Int64 = 0
    while (i < cols) {
        order[i] = i
        i++
    }
    // 选择排序（列数不大，稳定且不引入额外依赖）
    var p: Int64 = 0
    while (p < cols - 1) {
        var best = p
        var q = p + 1
        while (q < cols) {
            if (s[order[q]] > s[order[best]]) {
                best = q
            }
            q++
        }
        if (best != p) {
            let tmp = order[p]
            order[p] = order[best]
            order[best] = tmp
        }
        p++
    }
    let uo = Array<Float64>(rows * cols, repeat: 0.0)
    let vo = Array<Float64>(cols * cols, repeat: 0.0)
    let so = Array<Float64>(cols, repeat: 0.0)
    var j: Int64 = 0
    while (j < cols) {
        let src = order[j]
        so[j] = s[src]
        i = 0
        while (i < rows) {
            uo[i * cols + j] = u[i * cols + src]
            i++
        }
        i = 0
        while (i < cols) {
            vo[i * cols + j] = v[i * cols + src]
            i++
        }
        j++
    }
    (uo, so, vo)
}

/**
 * 对称矩阵的特征值分解（循环 Jacobi）
 *
 * 返回 `(values 降序, vectors)`，`vectors` 是 `n×n` 行优先，**第 j 列**是 `values[j]`
 * 对应的单位特征向量（与 R 的 `eigen()` 一致）。
 *
 * 只接受对称矩阵：非对称的特征值可以是复数，而本仓没有复数类型。
 */
func eigenSymRaw(n: Int64, a: Array<Float64>): (Array<Float64>, Array<Float64>) {
    let m = a.clone()
    let v = identityRaw(n)
    var scale = 0.0
    var t: Int64 = 0
    while (t < n * n) {
        scale += m[t] * m[t]
        t++
    }
    scale = sqrt(scale)
    let eps = 1.0e-15
    if (scale == 0.0) {
        return (Array<Float64>(n, repeat: 0.0), v)
    }

    var sweep: Int64 = 0
    while (sweep < 100) {
        var off = 0.0
        var p: Int64 = 0
        while (p < n - 1) {
            var q = p + 1
            while (q < n) {
                let apq = m[p * n + q]
                off += apq * apq
                if (abs(apq) > eps * scale) {
                    let theta = (m[q * n + q] - m[p * n + p]) / (2.0 * apq)
                    var tau = 0.0
                    if (theta >= 0.0) {
                        tau = 1.0 / (theta + sqrt(1.0 + theta * theta))
                    } else {
                        tau = -1.0 / (-theta + sqrt(1.0 + theta * theta))
                    }
                    let c = 1.0 / sqrt(1.0 + tau * tau)
                    let s = c * tau
                    // A ← A·J（旋转列）
                    var i: Int64 = 0
                    while (i < n) {
                        let aip = m[i * n + p]
                        let aiq = m[i * n + q]
                        m[i * n + p] = c * aip - s * aiq
                        m[i * n + q] = s * aip + c * aiq
                        i++
                    }
                    // A ← Jᵀ·A（旋转行）
                    i = 0
                    while (i < n) {
                        let api = m[p * n + i]
                        let aqi = m[q * n + i]
                        m[p * n + i] = c * api - s * aqi
                        m[q * n + i] = s * api + c * aqi
                        i++
                    }
                    // V ← V·J
                    i = 0
                    while (i < n) {
                        let vip = v[i * n + p]
                        let viq = v[i * n + q]
                        v[i * n + p] = c * vip - s * viq
                        v[i * n + q] = s * vip + c * viq
                        i++
                    }
                }
                q++
            }
            p++
        }
        if (sqrt(off) <= eps * scale) {
            break
        }
        sweep++
    }

    // 特征值在对角线上；排序降序并同步置换 V 的列
    let order = Array<Int64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        order[i] = i
        i++
    }
    var p: Int64 = 0
    while (p < n - 1) {
        var best = p
        var q = p + 1
        while (q < n) {
            if (m[order[q] * n + order[q]] > m[order[best] * n + order[best]]) {
                best = q
            }
            q++
        }
        if (best != p) {
            let tmp = order[p]
            order[p] = order[best]
            order[best] = tmp
        }
        p++
    }
    let vals = Array<Float64>(n, repeat: 0.0)
    let vecs = Array<Float64>(n * n, repeat: 0.0)
    var j: Int64 = 0
    while (j < n) {
        let src = order[j]
        vals[j] = m[src * n + src]
        i = 0
        while (i < n) {
            vecs[i * n + j] = v[i * n + src]
            i++
        }
        j++
    }
    (vals, vecs)
}
