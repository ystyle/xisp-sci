package ystyle::xisp_linalg

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * SVD / 特征分解 / 派生量的测试
 *
 * ## 为什么侧重「性质」而不是「数值对照」
 *
 * 数值对照只覆盖我恰好想到的那几个矩阵；而 SVD 的正确性有四条**恒等式**，
 * 它们对任意矩阵都必须成立：
 *
 * 1. `U Σ Vᵀ = A`（重构）
 * 2. `UᵀU = I`、`VᵀV = I`（正交）
 * 3. `Σ` 降序且非负
 * 4. `A v = λ v`（特征分解）
 *
 * 这几条比"某矩阵的奇异值是 5.46"强得多 —— 后者错了会立刻发现，
 * 而"符号取反""行列转置"这类错误只有在性质检验里才暴露。
 * 所以下面每个函数都先用 numpy 的数值钉一个锚点，再用恒等式扫一遍各种形状。
 */

/** 从二维数组构造行优先缓冲区 */
func flatOf(rows: Array<Array<Float64>>): (Int64, Int64, Array<Float64>) {
    let r = rows.size
    let c = rows[0].size
    let out = Array<Float64>(r * c, repeat: 0.0)
    var i: Int64 = 0
    while (i < r) {
        var j: Int64 = 0
        while (j < c) {
            out[i * c + j] = rows[i][j]
            j++
        }
        i++
    }
    (r, c, out)
}

/** 只要行优先缓冲区（不用元组成员访问，Cangjie 没这个语法） */
func dataOf(rows: Array<Array<Float64>>): Array<Float64> {
    let (_, _, d) = flatOf(rows)
    d
}

/** 从 SVD 的结果 HashMap 里取三个分量 */
func svdParts(res: LispValue): (Array<Float64>, Array<Float64>, Array<Float64>) {
    match (res) {
        case HashMap(m) =>
            (asFloatArr(mustGet(m, "u")), asFloatArr(mustGet(m, "s")),
                asFloatArr(mustGet(m, "vt")))
        case _ => (Array<Float64>(), Array<Float64>(), Array<Float64>())
    }
}

/** 断言 `M` 的列两两正交且单位长（`M` 是 `rows×cols` 行优先） */
func expectOrthonormalColumns(rows: Int64, cols: Int64, m: Array<Float64>, what: String): Unit {
    var p: Int64 = 0
    while (p < cols) {
        var q: Int64 = 0
        while (q < cols) {
            var acc = 0.0
            var i: Int64 = 0
            while (i < rows) {
                acc += m[i * cols + p] * m[i * cols + q]
                i++
            }
            let want = if (p == q) { 1.0 } else { 0.0 }
            if (abs(acc - want) > 1e-13) {
                @Fail("${what}：第 ${p},${q} 列内积为 ${acc}，期望 ${want}")
            }
            q++
        }
        p++
    }
}

@Test
class SvdTest {
    /**
     * 奇异值对照 numpy
     *
     * 奇异值是**唯一**的（与 U / V 的符号选择无关），所以可以逐值比。
     * `A = [[1,2],[3,4]]` 的奇异值是 `(√884 ± 30)/2` 开根，numpy 给 5.4649857 / 0.3659662。
     */
    @TestCase
    func testSingularValuesAgainstNumpy() {
        println("\n=== 奇异值（对照 numpy）===")
        let (_, s2, _) = svdParts(svdLispOf(matOf([[1.0, 2.0], [3.0, 4.0]])))
        expectArrClose(s2, [5.4649857042190426, 0.3659661906262574], 1e-12, "A=[[1,2],[3,4]] 的 σ")

        // 对角矩阵的奇异值就是绝对对角元（且降序）
        let (_, s3, _) = svdParts(svdLispOf(matOf([[3.0, 0.0], [0.0, 1.0]])))
        expectArrClose(s3, [3.0, 1.0], 1e-12, "diag(3,1) 的 σ")

        // 3×2 长方形
        let (_, s4, _) = svdParts(svdLispOf(matOf([
            [1.0, 2.0], [3.0, 4.0], [5.0, 7.0]])))
        expectArrClose(s4, [10.191428257097224, 0.36713768594389934], 1e-12, "3×2 的 σ")

        // 2×3 矮胖（走转置分支）
        let (_, s5, _) = svdParts(svdLispOf(matOf([
            [1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])))
        expectArrClose(s5, [9.508032000695723, 0.7728696356734851], 1e-12, "2×3 的 σ")
    }

    /**
     * 重构与正交性 —— 对多种形状扫一遍
     *
     * 这两条是 SVD 的定义性质，任何矩阵都必须满足。它们能抓住数值对照抓不到的错误：
     * U 的某一列符号取反、V 的行列弄混、矮胖矩阵的转置分支写错 —— 这些都会让
     * 「某个矩阵的 σ 等于多少」看着对，而重构直接崩掉。
     */
    @TestCase
    func testReconstructionAndOrthonormality() {
        println("\n=== 重构 U·Σ·Vᵀ = A 与正交性 ===")
        let cases: Array<Array<Array<Float64>>> = [
            [[1.0, 2.0], [3.0, 4.0]],
            [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],
            [[1.0, 2.0], [3.0, 4.0], [5.0, 7.0]],
            [[4.0, 1.0, 1.0], [1.0, 3.0, 0.0], [1.0, 0.0, 2.0]],
            [[2.0, 0.0, 0.0, 0.0], [0.0, -3.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]],
            [[1.0, 1.0], [1.0, 1.0]],
            [[5.0]]]
        for (rows in cases) {
            let (m, n, a) = flatOf(rows)
            let k = if (m < n) { m } else { n }
            let (u, s, vt) = svdRaw(m, n, a)
            // U 是 m×k、Vᵀ 是 k×n → U·diag(S)·Vᵀ 是 m×n
            // 先算 U·diag(S)（m×k），再乘 Vᵀ（k×n）
            let us = Array<Float64>(m * k, repeat: 0.0)
            var i: Int64 = 0
            while (i < m) {
                var t: Int64 = 0
                while (t < k) {
                    us[i * k + t] = u[i * k + t] * s[t]
                    t++
                }
                i++
            }
            let rec = matmulRaw(m, k, n, us, vt)
            expectArrClose(rec, a, 1e-11, "${m}×${n} 重构")
            expectOrthonormalColumns(m, k, u, "${m}×${n} 的 U")
            // Vᵀ 是 k×n，列正交等价于 V 的列正交 —— 转成 V 再验
            let v = transposeRaw(k, n, vt)
            expectOrthonormalColumns(n, k, v, "${m}×${n} 的 V")
            // 奇异值非负且降序
            var t: Int64 = 0
            while (t < k) {
                if (s[t] < 0.0) {
                    @Fail("${m}×${n}：第 ${t} 个奇异值为负 ${s[t]}")
                }
                if (t > 0 && s[t] > s[t - 1] + 1e-14) {
                    @Fail("${m}×${n}：奇异值未降序（${s[t - 1]} 后跟 ${s[t]}）")
                }
                t++
            }
        }
    }

    /** 秩亏矩阵：第二个奇异值应当接近 0，而不是"看起来还行的小数" */
    @TestCase
    func testRankDeficient() {
        println("\n=== 秩亏矩阵的奇异值 ===")
        let (_, s, _) = svdParts(svdLispOf(matOf([[1.0, 2.0], [2.0, 4.0]])))
        expectClose(s[0], 5.0, 1e-12, "σmax")
        // numpy 给 1.99e-16，严格的 0 反而说明算法没走完
        if (s[1] > 1e-12) {
            @Fail("秩 1 矩阵的 σmin 应接近 0，实际 ${s[1]}")
        }
    }
}

@Test
class EigenTest {
    /** 特征值对照 numpy（对称矩阵的特征值也是唯一的） */
    @TestCase
    func testEigenValuesAgainstNumpy() {
        println("\n=== 对称特征值（对照 numpy）===")
        let r = eigenLispOf(matOf([[2.0, 1.0], [1.0, 2.0]]))
        match (r) {
            case HashMap(m) =>
                expectArrClose(asFloatArr(mustGet(m, "values")), [3.0, 1.0], 1e-12,
                    "[[2,1],[1,2]] 的特征值")
            case _ => @Fail("eigen 应返回 HashMap")
        }
        let r2 = eigenLispOf(matOf([[4.0, 1.0, 1.0], [1.0, 3.0, 0.0], [1.0, 0.0, 2.0]]))
        match (r2) {
            case HashMap(m) => expectArrClose(asFloatArr(mustGet(m, "values")),
                [4.879385241571816, 2.6527036446661385, 1.4679111137620429], 1e-12,
                "3×3 对称矩阵的特征值")
            case _ => @Fail("eigen 应返回 HashMap")
        }
    }

    /**
     * 五条恒等式
     *
     * - `A·v_j = λ_j·v_j` —— 特征向量的定义
     * - `Σλ = trace(A)`
     * - `Πλ = det(A)`
     * - `VᵀV = I` —— 对称矩阵的特征向量正交
     * - 特征值降序
     *
     * 前三条互相独立（分别走特征向量、迹、行列式三条路），一起对上才说明分解是对的。
     */
    @TestCase
    func testEigenIdentities() {
        println("\n=== 特征分解的恒等式 ===")
        let cases: Array<Array<Array<Float64>>> = [
            [[2.0, 1.0], [1.0, 2.0]],
            [[4.0, 1.0, 1.0], [1.0, 3.0, 0.0], [1.0, 0.0, 2.0]],
            [[1.0, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 3.0]],
            [[2.0, -1.0, 0.0], [-1.0, 2.0, -1.0], [0.0, -1.0, 2.0]]]
        for (rows in cases) {
            let (n, cols, a) = flatOf(rows)
            let (vals, vecs) = eigenSymRaw(n, a)
            // 1) A·v = λ·v
            var j: Int64 = 0
            while (j < n) {
                var i: Int64 = 0
                while (i < n) {
                    var acc = 0.0
                    var t: Int64 = 0
                    while (t < n) {
                        acc += a[i * n + t] * vecs[t * n + j]
                        t++
                    }
                    let want = vals[j] * vecs[i * n + j]
                    if (abs(acc - want) > 1e-11) {
                        @Fail("A·v = λ·v 不成立：第 ${i} 行第 ${j} 个特征向量，" +
                            "实际 ${acc}，期望 ${want}")
                    }
                    i++
                }
                j++
            }
            // 2) Σλ = trace
            var sum = 0.0
            var tr = 0.0
            var i: Int64 = 0
            while (i < n) {
                sum += vals[i]
                tr += a[i * n + i]
                i++
            }
            expectClose(sum, tr, 1e-10, "${n}×${n}：Σλ = trace")
            // 3) Πλ = det（用已有的 detOf）
            var prod = 1.0
            i = 0
            while (i < n) {
                prod *= vals[i]
                i++
            }
            expectClose(prod, detOf(matOf(rows)), 1e-9, "${n}×${n}：Πλ = det")
            // 4) 特征向量正交
            expectOrthonormalColumns(n, n, vecs, "${n}×${n} 的特征向量")
            // 5) 降序
            i = 1
            while (i < n) {
                if (vals[i] > vals[i - 1] + 1e-12) {
                    @Fail("特征值未降序：${vals[i - 1]} 后跟 ${vals[i]}")
                }
                i++
            }
        }
    }

    /**
     * 非对称矩阵必须报错
     *
     * 这是本仓边界决策的直接体现：非对称矩阵的特征值可以是复数，而 dtype 里没有复数。
     * **不检查才是危险的** —— 非对称矩阵被当成对称矩阵算，会给出一个看起来正常、
     * 实际毫无意义的结果。
     */
    @TestCase
    func testNonSymmetricRejected() {
        println("\n=== 非对称矩阵报错 ===")
        expectErr({ => eigenLispOf(matOf([[1.0, 2.0], [3.0, 4.0]])) }, "非对称矩阵")
    }
}

@Test
class DerivedLinearAlgebraTest {
    /** `rank`：满秩、秩亏、零矩阵 */
    @TestCase
    func testRank() {
        println("\n=== 数值秩 ===")
        expectClose(Float64(rankRaw(2, 2, dataOf([[1.0, 2.0], [3.0, 4.0]]))), 2.0, 0.0, "满秩 2×2")
        expectClose(Float64(rankRaw(2, 2, dataOf([[1.0, 2.0], [2.0, 4.0]]))), 1.0, 0.0, "秩 1")
        expectClose(Float64(rankRaw(3, 3, dataOf([[1.0, 2.0, 3.0], [2.0, 4.0, 6.0], [3.0, 6.0, 9.0]]))), 1.0, 0.0, "秩 1 的 3×3")
        expectClose(Float64(rankRaw(2, 2, [0.0, 0.0, 0.0, 0.0])), 0.0, 0.0, "零矩阵")
        // 单位阵乘一个很小的全局尺度：秩不变（相对判据的作用）。
        // 注意不能取 1e-200 —— 它的平方下溢成 0，任何基于平方的算法都会把矩阵看成全零
        let tiny = Array<Float64>(4, repeat: 0.0)
        tiny[0] = 1e-10
        tiny[3] = 1e-10
        expectClose(Float64(rankRaw(2, 2, tiny)), 2.0, 0.0, "1e-10·I 的秩仍为 2")
    }

    /** `cond`：单位阵为 1、对角缩放、奇异为 inf */
    @TestCase
    func testCond() {
        println("\n=== 条件数 ===")
        expectClose(condRaw(2, 2, dataOf([[1.0, 0.0], [0.0, 1.0]])), 1.0, 1e-12, "I 的条件数")
        expectClose(condRaw(2, 2, dataOf([[1.0, 0.0], [0.0, 1e-3]])), 1000.0, 1e-9,
            "diag(1,1e-3) 的条件数")
        expectClose(condRaw(2, 2, dataOf([[3.0, 0.0], [0.0, 1.0]])), 3.0, 1e-12,
            "diag(3,1) 的条件数")
        // 奇异矩阵：σmin = 0 → inf
        let c = condRaw(2, 2, dataOf([[1.0, 2.0], [2.0, 4.0]]))
        if (!(c > 1e15)) {
            @Fail("奇异矩阵的条件数应为 inf（或极大），实际 ${c}")
        }
    }

    /**
     * 伪逆 `A A⁺ A = A`
     *
     * 这是伪逆的**定义性质**，对满秩、秩亏、长方阵统一成立。
     * 另有三个 Penrose 条件，但这一条最能抓住转置写反（伪逆是 `cols×rows`，
     * 方向搞反的话乘法维度直接不匹配）。
     */
    @TestCase
    func testPinv() {
        println("\n=== 伪逆 A·A⁺·A = A ===")
        let cases: Array<Array<Array<Float64>>> = [
            [[1.0, 2.0], [3.0, 4.0]],
            [[1.0, 2.0], [2.0, 4.0]],
            [[1.0, 2.0], [3.0, 4.0], [5.0, 7.0]],
            [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]]
        for (rows in cases) {
            let (m, n, a) = flatOf(rows)
            let p = pinvRaw(m, n, a)
            // A( m×n ) · P( n×m ) = m×m
            let ap = matmulRaw(m, n, m, a, p)
            // (A·P)( m×m ) · A( m×n ) = m×n
            let apa = matmulRaw(m, m, n, ap, a)
            expectArrClose(apa, a, 1e-10, "${m}×${n} 的 A·A⁺·A = A")
        }
        // 满秩方阵：伪逆就是逆
        let sq = dataOf([[1.0, 2.0], [3.0, 4.0]])
        let p2 = pinvRaw(2, 2, sq)
        expectArrClose(p2, [-2.0, 1.0, 1.5, -0.5], 1e-9, "2×2 满秩的伪逆 = 逆")
    }

    /**
     * PCA：解释方差、中心化、得分与载荷
     *
     * 参照 numpy 对同一份数据的 SVD 结果。这份数据是 PCA 教科书上的标准例子
     * （二维、10 个点、第一主成分解释 96.3% 的方差）。
     */
    @TestCase
    func testPca() {
        println("\n=== PCA ===")
        let (n, p, x) = flatOf([
            [2.5, 2.4], [0.5, 0.7], [2.2, 2.9], [1.9, 2.2], [3.1, 3.0],
            [2.3, 2.7], [2.0, 1.6], [1.0, 1.1], [1.5, 1.6], [1.1, 0.9]])
        let res = pcaRaw(n, p, x, 0)
        match (res.get("sdev")) {
            case Some(v) => expectArrClose(asFloatArr(v),
                [1.1331494659455936, 0.22154773512344314], 1e-12, "sdev")
            case None => @Fail("pca 结果缺 sdev")
        }
        match (res.get("var-explained")) {
            case Some(v) => expectArrClose(asFloatArr(v),
                [0.96318131434864596, 0.036818685651354044], 1e-12, "var-explained")
            case None => @Fail("pca 结果缺 var-explained")
        }
        match (res.get("center")) {
            case Some(v) => expectArrClose(asFloatArr(v),
                [1.8100000000000001, 1.9099999999999997], 1e-14, "center")
            case None => @Fail("pca 结果缺 center")
        }
        // 得分矩阵的列方差 = sdev²（这是 sdev 的定义，也是与 scores 的交叉验证）
        match (res.get("scores")) {
            case Some(v) =>
                let sc = asFloatArr(v)
                var t: Int64 = 0
                while (t < 2) {
                    var mean = 0.0
                    var i: Int64 = 0
                    while (i < n) {
                        mean += sc[i * 2 + t]
                        i++
                    }
                    mean = mean / Float64(n)
                    var acc = 0.0
                    i = 0
                    while (i < n) {
                        let d = sc[i * 2 + t] - mean
                        acc += d * d
                        i++
                    }
                    let sd = sqrt(acc / Float64(n - 1))
                    let want = 1.1331494659455936
                    if (t == 0) {
                        expectClose(sd, want, 1e-10, "第 0 个得分的标准差")
                    }
                    // 中心化后每个主成分的得分均值为 0
                    expectClose(mean, 0.0, 1e-12, "第 ${t} 个得分的均值")
                    t++
                }
            case None => @Fail("pca 结果缺 scores")
        }
        // 只取第一个主成分
        let res1 = pcaRaw(n, p, x, 1)
        match (res1.get("sdev")) {
            case Some(v) =>
                let sd = asFloatArr(v)
                if (sd.size != 1) {
                    @Fail("k=1 时 sdev 应只有 1 个元素，实际 ${sd.size}")
                }
            case None => @Fail("pca 结果缺 sdev")
        }
    }
}
