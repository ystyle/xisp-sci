package ystyle::xisp_stats

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * 多元正态抽样的测试
 *
 * ## 验证思路
 *
 * 随机数没法逐值对照（换个 PRNG 结果就全变），所以验的是**分布性质**：
 * 大样本的样本均值要收敛到 `μ`、样本协方差要收敛到 `Σ`。
 *
 * 这两条恰好也是最容易写错的地方 —— 比如「按维度各生成 n 个」的错误会让
 * 样本协方差的非对角元恒等于对角元（完全相关），而样本看起来毫无异常。
 *
 * ## 一条单独的白盒检查
 *
 * Cholesky 必须满足 `L·Lᵀ = Σ`。这条不依赖随机数，能单独定位「分解写错」还是
 * 「变换写错」—— 否则两种错误在样本矩检验里表现一样（协方差不等于目标值）。
 */

func sampleMean(data: Array<Float64>, n: Int64, p: Int64, col: Int64): Float64 {
    var s = 0.0
    var i: Int64 = 0
    while (i < n) {
        s += data[i * p + col]
        i++
    }
    s / Float64(n)
}

func sampleCov(data: Array<Float64>, n: Int64, p: Int64, ci: Int64, cj: Int64): Float64 {
    let mi = sampleMean(data, n, p, ci)
    let mj = sampleMean(data, n, p, cj)
    var s = 0.0
    var i: Int64 = 0
    while (i < n) {
        s += (data[i * p + ci] - mi) * (data[i * p + cj] - mj)
        i++
    }
    s / Float64(n - 1)
}

/** 相对容差断言（协方差量级不同，绝对容差不好定） */
func nearRel(actual: Float64, want: Float64, rel: Float64, what: String): Unit {
    let tol = abs(want) * rel
    if (!(abs(actual - want) <= tol)) {
        @Fail("${what}：期望 ${want}（±${rel*100.0}%），实际 ${actual}")
    }
}

@Test
class MvnormTest {
    /**
     * `L·Lᵀ = Σ`
     *
     * 不涉及随机数，能单独定位「分解写错」还是「变换写错」。
     */
    @TestCase
    func testCholeskyReconstructs() {
        println("\n=== Cholesky 重构 ===")
        let cases: Array<Array<Float64>> = [
            [4.0, 2.0, 1.0, 2.0, 5.0, 3.0, 1.0, 3.0, 6.0],
            [1.0],
            [2.0, 0.0, 0.0, 3.0],           // 对角
            [1.0, 0.99, 0.99, 1.0]           // 接近奇异但正定
        ]
        for (sigma in cases) {
            // 从扁平数组推阶数
            var p: Int64 = 1
            while (p * p < sigma.size) {
                p++
            }
            let l = choleskyLowerRaw(p, sigma)
            var i: Int64 = 0
            while (i < p) {
                var j: Int64 = 0
                while (j < p) {
                    // (L·Lᵀ)[i][j] = Σ_k L[i][k]·L[j][k]
                    var s = 0.0
                    var k: Int64 = 0
                    while (k < p) {
                        s += l[i * p + k] * l[j * p + k]
                        k++
                    }
                    if (abs(s - sigma[i * p + j]) > 1e-10) {
                        @Fail("${p}×${p}：L·Lᵀ 的第 (${i},${j}) 项为 ${s}，应为 ${sigma[i * p + j]}")
                    }
                    j++
                }
                i++
            }
            // L 必须是下三角
            i = 0
            while (i < p) {
                var j = i + 1
                while (j < p) {
                    if (l[i * p + j] != 0.0) {
                        @Fail("${p}×${p}：L 不是下三角，(${i},${j}) = ${l[i * p + j]}")
                    }
                    j++
                }
                i++
            }
        }
    }

    /**
     * 大样本的样本均值与协方差必须收敛到目标值
     *
     * 这是整条链路的验收：Cholesky 对了但变换写错（比如该用列却用了行），
     * 或者各维用了同一条随机序列，都会在这里暴露。
     */
    @TestCase
    func testSampleMoments() {
        println("\n=== 样本矩收敛 ===")
        let mu = [10.0, 20.0, -5.0]
        let sigma = [
            4.0, 2.0, 1.0,
            2.0, 5.0, 3.0,
            1.0, 3.0, 6.0]
        let n: Int64 = 40000
        let p: Int64 = 3
        let data = mvnormSamples(n, mu, sigma, 20261120)

        // 均值：标准误 = σ/√n ≈ 2.4/200 = 0.012，取 0.05 的绝对容差很宽松
        var j: Int64 = 0
        while (j < p) {
            let m = sampleMean(data, n, p, j)
            if (abs(m - mu[j]) > 0.05) {
                @Fail("第 ${j} 维均值为 ${m}，应为 ${mu[j]}")
            }
            j++
        }
        // 协方差：n=40000 时相对标准误约 0.7%，取 5%
        j = 0
        while (j < p) {
            var k: Int64 = 0
            while (k < p) {
                nearRel(sampleCov(data, n, p, j, k), sigma[j * p + k], 0.05,
                    "Cov[${j}][${k}]")
                k++
            }
            j++
        }
        // 样本相关矩阵的对角必须是 1（自洽性检查）
        j = 0
        while (j < p) {
            let v = sampleCov(data, n, p, j, j)
            nearRel(sampleCov(data, n, p, j, j) / v, 1.0, 1e-12, "对角协方差比")
            j++
        }
    }

    /**
     * 对角协方差 → 各维独立
     *
     * 这条专门抓「各维用了同一条随机序列」这个错误：那种情况下非对角元会
     * **恒等于**对角元（相关系数 1），而不是接近 0。
     */
    @TestCase
    func testIndependentDimensions() {
        println("\n=== 对角协方差意味着独立 ===")
        let mu = [0.0, 0.0]
        let sigma = [4.0, 0.0, 0.0, 9.0]
        let n: Int64 = 20000
        let p: Int64 = 2
        let data = mvnormSamples(n, mu, sigma, 42)
        let cov = sampleCov(data, n, p, 0, 1)
        // 独立时协方差标准误 ≈ σ1σ2/√n = 6/141 = 0.042，取 0.15 很宽松
        if (abs(cov) > 0.15) {
            @Fail("独立维度的样本协方差应接近 0，实际 ${cov}")
        }
        // 方差要分别对
        nearRel(sampleCov(data, n, p, 0, 0), 4.0, 0.05, "Var[X₁]")
        nearRel(sampleCov(data, n, p, 1, 1), 9.0, 0.05, "Var[X₂]")
    }

    /** 同种子必须给同一批样本；不同种子必须不同 */
    @TestCase
    func testDeterministic() {
        println("\n=== 可复现 ===")
        let mu = [1.0, 2.0]
        let sigma = [1.0, 0.5, 0.5, 1.0]
        let a = mvnormSamples(50, mu, sigma, 7)
        let b = mvnormSamples(50, mu, sigma, 7)
        var i: Int64 = 0
        while (i < a.size) {
            if (a[i] != b[i]) {
                @Fail("同种子第 ${i} 个样本不同：${a[i]} vs ${b[i]}")
            }
            i++
        }
        let c = mvnormSamples(50, mu, sigma, 8)
        var same = 0
        i = 0
        while (i < a.size) {
            if (a[i] == c[i]) {
                same++
            }
            i++
        }
        if (same > 2) {
            @Fail("不同种子却给出 ${same} 个相同样本")
        }
    }

    /** 非正定 / 非对称 / 维度不匹配都要报错 */
    @TestCase
    func testErrors() {
        println("\n=== 错误输入 ===")
        // 完全共线：Σ = [[1,1],[1,1]]，行列式为 0
        var caught = false
        try {
            mvnormSamples(10, [0.0, 0.0], [1.0, 1.0, 1.0, 1.0], 1)
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("奇异协方差矩阵应报错")
        }
        // 非对称
        caught = false
        try {
            squareMatrixArg(LispValue.External(reshapeArray(
                ndarrayFromFloats([1.0, 2.0, 3.0, 4.0]), [2, 2])), "test")
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("非对称矩阵应报错")
        }
        // 非方阵
        caught = false
        try {
            squareMatrixArg(LispValue.External(reshapeArray(
                ndarrayFromFloats([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]), [2, 3])), "test")
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("非方阵应报错")
        }
    }
}
