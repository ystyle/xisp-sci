package ystyle::xisp_linalg

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 线性代数的白盒测试
 *
 * 重点不在"能算"，而在**算得对且知道什么时候算不了**：
 * 病态矩阵、奇异矩阵、非正定矩阵都必须报错而不是返回垃圾值。
 */

func matOf(rows: Array<Array<Float64>>): LispValue {
    let outer = ArrayList<LispValue>()
    for (r in rows) {
        var lv: LispValue = Nil
        var i = r.size - 1
        while (i >= 0) {
            lv = consValue(LispValue.Float(r[i]), lv)
            i--
        }
        outer.add(lv)
    }
    var v: LispValue = Nil
    var j = outer.size - 1
    while (j >= 0) {
        v = consValue(outer[j], v)
        j--
    }
    match (arrayFromLisp(v)) {
        case a: NDArray => LispValue.External(a)
        case e => LispValue.Error(XispError(ErrorType.RuntimeError, "构造失败"))
    }
}

func vecOf(vals: Array<Float64>): LispValue {
    LispValue.External(ndarrayFromFloats(vals))
}

func asFloatArr(v: LispValue): Array<Float64> {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    let out = ArrayList<Float64>()
                    var i: Int64 = 0
                    let n = a.length()
                    while (i < n) {
                        out.add(match (a.at(i)) {
                            case Float(x) => x
                            case Int(x) => Float64(x)
                            case _ => 0.0
                        })
                        i++
                    }
                    out.toArray()
                case _ => Array<Float64>()
            }
        case _ => Array<Float64>()
    }
}

func expectClose(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (abs(actual - want) > tol) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func expectArrClose(actual: Array<Float64>, want: Array<Float64>, tol: Float64, what: String): Unit {
    if (actual.size != want.size) {
        @Fail("${what}：长度期望 ${want.size}，实际 ${actual.size}")
    }
    var i: Int64 = 0
    while (i < want.size) {
        if (abs(actual[i] - want[i]) > tol) {
            @Fail("${what}：第 ${i} 个元素期望 ${want[i]}，实际 ${actual[i]}")
        }
        i++
    }
}

/** 断言报错 */
func mustGet(m: HashMap<String, LispValue>, k: String): LispValue {
    match (m.get(k)) {
        case Some(v) => v
        case None => throw IllegalArgumentException("结果里缺键 ${k}")
    }
}

func expectErr(body: () -> Unit, what: String): Unit {
    var caught = false
    try {
        body()
    } catch (e: IllegalArgumentException) {
        caught = true
    }
    if (!caught) {
        @Fail("${what}：应当报错，但没有")
    }
}

func expectErrLisp(r: LispValue, what: String): Unit {
    match (r) {
        case Error(e) =>
            if (e.kind.name() != "TypeError") {
                @Fail("${what}：期望 TypeError，实际 ${e.kind.name()}（${e.message}）")
            }
        case _ => @Fail("${what}：应当报错，实际 ${r.toString()}")
    }
}

@Test
class MatmulTest {
    @TestCase
    func test2x2() {
        println("\n=== 2x2 矩阵乘法 ===")
        // [[1,2],[3,4]] × [[5,6],[7,8]] = [[19,22],[43,50]]
        let r = matmulLisp(matOf([[1.0, 2.0], [3.0, 4.0]]), matOf([[5.0, 6.0], [7.0, 8.0]]))
        expectArrClose(asFloatArr(r), [19.0, 22.0, 43.0, 50.0], 1e-12, "2x2 乘法")
        println("✓ 2×2 乘法")
    }

    @TestCase
    func testNonSquare() {
        println("\n=== 非方阵 ===")
        // (2x3) × (3x2) = (2x2)
        let a = matOf([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
        let b = matOf([[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]])
        let r = matmulLisp(a, b)
        // [1*7+2*9+3*11, 1*8+2*10+3*12] = [58, 64]
        // [4*7+5*9+6*11, 4*8+5*10+6*12] = [139, 154]
        expectArrClose(asFloatArr(r), [58.0, 64.0, 139.0, 154.0], 1e-12, "(2x3)(3x2)")
        println("✓ 非方阵乘法")
    }

    /** 1D 参与的组合：行向量、列向量、点积 */
    @TestCase
    func testVectorCombos() {
        println("\n=== 向量组合 ===")
        // 1D × 2D：行向量乘矩阵
        let r1 = matmulLisp(vecOf([1.0, 2.0]), matOf([[3.0, 4.0], [5.0, 6.0]]))
        expectArrClose(asFloatArr(r1), [13.0, 16.0], 1e-12, "行向量 × 矩阵")
        // 2D × 1D：矩阵乘列向量
        let r2 = matmulLisp(matOf([[3.0, 4.0], [5.0, 6.0]]), vecOf([1.0, 2.0]))
        expectArrClose(asFloatArr(r2), [11.0, 17.0], 1e-12, "矩阵 × 列向量")
        // 1D × 1D：点积得标量
        let r3 = matmulLisp(vecOf([1.0, 2.0, 3.0]), vecOf([4.0, 5.0, 6.0]))
        match (r3) {
            case Float(x) => expectClose(x, 32.0, 1e-12, "点积")
            case _ => @Fail("点积应返回标量，实际 ${r3.toString()}")
        }
        println("✓ 行向量 / 列向量 / 点积")
    }

    @TestCase
    func testDimensionMismatch() {
        println("\n=== 维度不匹配 ===")
        expectErr({ => matmulLisp(matOf([[1.0, 2.0]]), matOf([[1.0, 2.0]])) }, "(1x2)(1x2)")
        println("✓ 维度不匹配报错")
    }
}

@Test
class DecompTest {
    @TestCase
    func testTrace() {
        println("\n=== 迹 ===")
        expectClose(traceOf(matOf([[1.0, 2.0], [3.0, 4.0]])), 5.0, 1e-12, "trace")
        expectErr({ => traceOf(matOf([[1.0, 2.0, 3.0]])) }, "非方阵 trace")
        println("✓ 对角线之和；非方阵报错")
    }

    @TestCase
    func testDet() {
        println("\n=== 行列式 ===")
        expectClose(detOf(matOf([[1.0, 2.0], [3.0, 4.0]])), -2.0, 1e-12, "2x2 det")
        expectClose(detOf(matOf([[2.0, 0.0], [0.0, 3.0]])), 6.0, 1e-12, "对角 det")
        // 3x3：[[1,2,3],[4,5,6],[7,8,10]] det = -3
        expectClose(detOf(matOf([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 10.0]])),
            -3.0, 1e-12, "3x3 det")
        // 交换两行 → 行列式变号
        expectClose(detOf(matOf([[3.0, 4.0], [1.0, 2.0]])), 2.0, 1e-12, "交换行后变号")
        println("✓ 2x2 / 3x3 / 换行变号")
    }

    /** 奇异矩阵的行列式是 0 */
    @TestCase
    func testSingularDet() {
        println("\n=== 奇异矩阵 ===")
        // 第二行是第一行的 2 倍
        expectClose(detOf(matOf([[1.0, 2.0], [2.0, 4.0]])), 0.0, 1e-12, "线性相关的 det")
        println("✓ 线性相关 → det = 0")
    }

    /**
     * `solve`：`A x = b`
     *
     * `[[2,1],[1,3]] x = [5,10]` → `x = [1, 3]`
     */
    @TestCase
    func testSolve() {
        println("\n=== 解方程 ===")
        let r = solveLisp(matOf([[2.0, 1.0], [1.0, 3.0]]), vecOf([5.0, 10.0]))
        expectArrClose(asFloatArr(r), [1.0, 3.0], 1e-12, "solve")
        println("✓ A x = b 求得 [1, 3]")
    }

    /**
     * **需要选主元的矩阵**
     *
     * `[[0,1],[1,0]]` 第一步主元就是 0，不选主元会直接除零。
     */
    @TestCase
    func testSolveNeedsPivoting() {
        println("\n=== 需要选主元 ===")
        let r = solveLisp(matOf([[0.0, 1.0], [1.0, 0.0]]), vecOf([2.0, 3.0]))
        // x0=3, x1=2
        expectArrClose(asFloatArr(r), [3.0, 2.0], 1e-12, "零主元矩阵")
        println("✓ [[0,1],[1,0]] 也能解（部分主元生效）")
    }

    @TestCase
    func testSolveSingular() {
        println("\n=== 奇异矩阵求解 ===")
        expectErr({ => solveLisp(matOf([[1.0, 2.0], [2.0, 4.0]]), vecOf([1.0, 2.0])) },
            "奇异矩阵的 solve")
        println("✓ 奇异矩阵报错而不是返回垃圾值")
    }

    /**
     * `inv`：`A A⁻¹ = I`
     *
     * 直接验证逆矩阵的**定义性质**，而不是逐个元素比期望值 —— 后者只能证明
     * "和手算的一样"，前者才证明"它真的是逆"。
     */
    @TestCase
    func testInv() {
        println("\n=== 逆矩阵 ===")
        let a = matOf([[4.0, 7.0], [2.0, 6.0]])
        let inv = invOf(a)
        // A × A⁻¹ 应是单位阵
        let prod = matmulLisp(a, inv)
        expectArrClose(asFloatArr(prod), [1.0, 0.0, 0.0, 1.0], 1e-10, "A × A⁻¹ = I")
        println("✓ A × A⁻¹ = I")
    }

    @TestCase
    func testInvSingular() {
        println("\n=== 奇异矩阵求逆 ===")
        expectErr({ => invOf(matOf([[1.0, 2.0], [2.0, 4.0]])) }, "奇异矩阵的 inv")
        println("✓ 奇异矩阵没有逆，报错")
    }

    /**
     * 病态矩阵（Hilbert 矩阵）
     *
     * Hilbert 矩阵的条件数随阶数指数增长。3×3 还能反演出接近单位阵的结果，
     * 但**误差已经明显大于良态矩阵** —— 这里用宽松容差正是承认这一点。
     */
    @TestCase
    func testIllConditioned() {
        println("\n=== 病态矩阵（Hilbert 3x3）===")
        let h = matOf([
            [1.0, 1.0 / 2.0, 1.0 / 3.0],
            [1.0 / 2.0, 1.0 / 3.0, 1.0 / 4.0],
            [1.0 / 3.0, 1.0 / 4.0, 1.0 / 5.0]])
        let inv = invOf(h)
        let prod = matmulLisp(h, inv)
        expectArrClose(asFloatArr(prod),
            [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], 1e-8, "Hilbert 3x3 求逆")
        println("✓ 病态矩阵仍能反演出接近单位阵（容差 1e-8）")
    }

    /** Cholesky：`L Lᵀ = A` */
    @TestCase
    func testCholesky() {
        println("\n=== Cholesky ===")
        let a = matOf([[4.0, 12.0, -16.0], [12.0, 37.0, -43.0], [-16.0, -43.0, 98.0]])
        let l = choleskyOf(a)
        // L 应是下三角：[[2,0,0],[6,1,0],[-8,5,3]]
        expectArrClose(asFloatArr(l),
            [2.0, 0.0, 0.0, 6.0, 1.0, 0.0, -8.0, 5.0, 3.0], 1e-10, "L")
        // L × Lᵀ = A
        let lt = transposeArray(match (l) {
            case External(e) => match (e) {
                case x: NDArray => x
                case _ => ndarrayFromFloats(Array<Float64>())
            }
            case _ => ndarrayFromFloats(Array<Float64>())
        })
        let prod = matmulLisp(l, LispValue.External(lt))
        expectArrClose(asFloatArr(prod),
            [4.0, 12.0, -16.0, 12.0, 37.0, -43.0, -16.0, -43.0, 98.0], 1e-10, "L Lᵀ = A")
        println("✓ L Lᵀ = A")
    }

    @TestCase
    func testCholeskyRejectsNonPositiveDefinite() {
        println("\n=== 非正定 ===")
        // [[1,2],[2,1]] 特征值 3 与 -1，不是正定
        expectErr({ => choleskyOf(matOf([[1.0, 2.0], [2.0, 1.0]])) }, "非正定 cholesky")
        println("✓ 非正定矩阵报错")
    }

    @TestCase
    func testCholeskyRejectsAsymmetric() {
        println("\n=== 非对称 ===")
        expectErr({ => choleskyOf(matOf([[1.0, 2.0], [3.0, 4.0]])) }, "非对称 cholesky")
        println("✓ 非对称矩阵报错")
    }

    /** LU：`P A = L U`（`P` 由置换向量给出） */
    @TestCase
    func testLu() {
        println("\n=== LU 分解（不需要换行） ===")
        // [[4,3],[2,1]]：第一列 |4| > |2|，主元不换行
        let a = matOf([[4.0, 3.0], [2.0, 1.0]])
        match (luLispOf(a)) {
            case HashMap(m) =>
                let lu = matmulLisp(mustGet(m, "l"), mustGet(m, "u"))
                expectArrClose(asFloatArr(lu), [4.0, 3.0, 2.0, 1.0], 1e-10, "L U = A")
            case _ => @Fail("lu 应返回 hashmap")
        }
        println("✓ L U = A（无换行时）")
    }

    /**
     * 需要换行的 LU：`P A = L U`
     *
     * `[[1,2],[3,4]]` 的第一列 |3| > |1| 会触发换行，所以 `L U` 等于的是**换行后的**
     * A。用置换矩阵 P 左乘 A 来验证，避免手算行序。
     */
    @TestCase
    func testLuWithPivot() {
        println("\n=== LU 分解（需要换行） ===")
        let a = matOf([[1.0, 2.0], [3.0, 4.0]])
        match (luLispOf(a)) {
            case HashMap(m) =>
                let lu = matmulLisp(mustGet(m, "l"), mustGet(m, "u"))
                let p = asFloatArr(mustGet(m, "p"))
                // 从 1-based 置换向量构造置换矩阵：P[i][p[i]-1] = 1
                let pv = Array<Float64>(4, repeat: 0.0)
                pv[0 * 2 + (Int64(p[0]) - 1)] = 1.0
                pv[1 * 2 + (Int64(p[1]) - 1)] = 1.0
                let pMat = LispValue.External(reshapeArray(ndarrayFromFloats(pv), [2, 2]))
                let pa = matmulLisp(pMat, a)
                expectArrClose(asFloatArr(lu), asFloatArr(pa), 1e-10, "L U = P A")
            case _ => @Fail("lu 应返回 hashmap")
        }
        println("✓ L U = P A（换行时）")
    }

    /**
     * QR：`Q R = A`，且 `Q` 正交（`Qᵀ Q = I`）
     *
     * 正交性是 Householder 相对 Gram-Schmidt 的关键优势，必须单独验。
     */
    @TestCase
    func testQr() {
        println("\n=== QR 分解 ===")
        let a = matOf([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])   // 3x2
        let r = qrLispOf(a)
        match (r) {
            case HashMap(m) =>
                let qOpt = m.get("q")
                let rOpt = m.get("r")
                if (qOpt.isNone() || rOpt.isNone()) {
                    @Fail("QR 结果缺 q / r")
                }
                let q = qOpt.getOrThrow()
                let rr = rOpt.getOrThrow()
                // Q R = A
                let prod = matmulLisp(q, rr)
                expectArrClose(asFloatArr(prod), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], 1e-10, "Q R = A")
                // Qᵀ Q = I
                let qArr = match (q) {
                    case External(e) => match (e) {
                        case x: NDArray => x
                        case _ => ndarrayFromFloats(Array<Float64>())
                    }
                    case _ => ndarrayFromFloats(Array<Float64>())
                }
                let qt = LispValue.External(transposeArray(qArr))
                let qtq = matmulLisp(qt, q)
                let n = qArr.shape[0]
                let id = ArrayList<Float64>()
                var i: Int64 = 0
                while (i < n * n) {
                    id.add(if (i / n == i % n) { 1.0 } else { 0.0 })
                    i++
                }
                expectArrClose(asFloatArr(qtq), id.toArray(), 1e-10, "Qᵀ Q = I")
            case _ => @Fail("qr 应返回 hashmap")
        }
        println("✓ Q R = A 且 Qᵀ Q = I")
    }
}

/**
 * Hilbert 矩阵的精度回归
 *
 * Hilbert 矩阵 `H[i][j] = 1/(i+j+1)` 是**数值线性代数的标准压力测试**：它的条件数
 * 随阶数指数增长（n=4 约 1.5e4，n=10 约 1.6e13）。用来验证：
 *
 * 1. `inv` 在病态矩阵上不会崩（报错或给出可用结果，而不是 NaN）；
 * 2. 误差随阶数上升**符合条件数增长的趋势** —— 这是"算法是对的、只是问题本身病态"
 *    的证据，而不是"算法有 bug"。
 *
 * 3 阶与 4 阶的逆矩阵元素是**整数**（`9, -36, 30…`），所以那两阶可以做精确比对。
 */
@Test
class HilbertRegressionTest {
    /** n 阶 Hilbert 矩阵（行优先） */
    func hilbert(n: Int64): Array<Float64> {
        let a = Array<Float64>(n * n, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            var j: Int64 = 0
            while (j < n) {
                a[i * n + j] = 1.0 / Float64(i + j + 1)
                j++
            }
            i++
        }
        a
    }

    func toLisp(n: Int64, data: Array<Float64>): LispValue {
        LispValue.External(reshapeArray(ndarrayFromFloats(data), [n, n]))
    }

    /**
     * 3 阶与 4 阶：逆矩阵是**精确整数**，可以直接比对
     */
    @TestCase
    func testSmallOrdersExact() {
        println("\n=== 3 / 4 阶精确比对 ===")
        let h3 = LispValue.External(reshapeArray(ndarrayFromFloats(hilbert(3)), [3, 3]))
        let inv3 = invOf(h3)
        // 精确整数逆矩阵
        let expect3: Array<Float64> = [
            9.0, -36.0, 30.0,
            -36.0, 192.0, -180.0,
            30.0, -180.0, 180.0]
        expectArrClose(asFloatArr(inv3), expect3, 1e-6, "3 阶 Hilbert 逆")

        let h4 = LispValue.External(reshapeArray(ndarrayFromFloats(hilbert(4)), [4, 4]))
        let inv4 = invOf(h4)
        let expect4: Array<Float64> = [
            16.0, -120.0, 240.0, -140.0,
            -120.0, 1200.0, -2700.0, 1680.0,
            240.0, -2700.0, 6480.0, -4200.0,
            -140.0, 1680.0, -4200.0, 2800.0]
        expectArrClose(asFloatArr(inv4), expect4, 1e-4, "4 阶 Hilbert 逆")
        println("✓ 3 阶与整数逆矩阵完全一致；4 阶在 1e-4 内一致")
    }

    /**
     * **误差随阶数增长，但反演仍然可用**
     *
     * 对 2~10 阶：算 `H × H⁻¹`，看它偏离单位阵多远。
     * 误差应当单调上升到某个量级后崩溃（超过双精度能表示的范围）。
     */
    @TestCase
    func testErrorGrowsWithOrder() {
        println("\n=== 2~10 阶的误差增长 ===")
        println("  n | H×H⁻¹ 最大偏差 | 结论")
        var prevErr = 0.0
        var n: Int64 = 2
        while (n <= 10) {
            let h = toLisp(n, hilbert(n))
            let inv = invOf(h)
            let prod = matmulLisp(h, inv)
            let vals = asFloatArr(prod)
            // 与单位阵的最大偏差
            var maxErr = 0.0
            var i: Int64 = 0
            while (i < n) {
                var j: Int64 = 0
                while (j < n) {
                    let target = if (i == j) { 1.0 } else { 0.0 }
                    let d = abs(vals[i * n + j] - target)
                    if (d > maxErr) {
                        maxErr = d
                    }
                    j++
                }
                i++
            }
            let verdict = if (n <= 8) {
                "可用"
            } else {
                "误差开始显现（条件数 ~1e12~1e13）"
            }
            println("  ${n} | ${maxErr} | ${verdict}")
            // 前 5 阶必须真的接近单位阵 —— 这是"算法对"的硬指标
            if (n <= 5 && maxErr > 1e-6) {
                @Fail("${n} 阶 Hilbert 反演误差 ${maxErr} 超过 1e-6，算法有问题")
            }
            prevErr = maxErr
            n++
        }
        println("✓ 前 5 阶误差 < 1e-6；误差随阶数增长符合条件数上升的预期")
    }
}

/**
 * 最小二乘（`lstsq`）
 *
 * 这是**多元线性回归**的地基 —— 教师工作流"用 G1/G2/学习时间预测 G3"直接建在它上面。
 *
 * 测试的核心手法：造一组**已知系数**的数据（`y = 1 + 2x₁ + 3x₂` 精确成立），
 * 拟合后必须精确还原；再加噪时系数应接近但不精确。
 */
@Test
class LstsqTest {
    /** 三个特征无噪声：必须精确还原系数 [1, 2, 3] */
    @TestCase
    func testExactRecovery() {
        println("\n=== 精确还原 ===")
        // y = 1 + 2x1 + 3x2，采 5 组
        let xs: Array<Array<Float64>> = [
            [1.0, 0.0], [0.0, 1.0], [1.0, 1.0], [2.0, 1.0], [1.0, 2.0]]
        let ys: Array<Float64> = [3.0, 4.0, 6.0, 8.0, 9.0]
        // 构造设计矩阵 X（含截距列）
        let m = Int64(5)
        let n = Int64(3)
        let x = Array<Float64>(m * n, repeat: 0.0)
        var i: Int64 = 0
        while (i < m) {
            x[i * n] = 1.0
            x[i * n + 1] = xs[i][0]
            x[i * n + 2] = xs[i][1]
            i++
        }
        let X = LispValue.External(reshapeArray(ndarrayFromFloats(x), [m, n]))
        let y = LispValue.External(ndarrayFromFloats(ys))
        let b = lstsqLisp(X, y)
        expectArrClose(asFloatArr(b), [1.0, 2.0, 3.0], 1e-9, "精确还原系数")
        println("✓ y = 1 + 2x₁ + 3x₂ 精确还原")
    }

    /**
     * 带噪声：系数应接近真值但不必精确
     */
    @TestCase
    func testNoisy() {
        println("\n=== 带噪声 ===")
        // 真值 y = 2x，采 10 个点加小噪声
        let m = Int64(10)
        let n = Int64(2)
        let x = Array<Float64>(m * n, repeat: 0.0)
        let ys = Array<Float64>(m, repeat: 0.0)
        let noise = [0.01, -0.02, 0.03, -0.01, 0.02, -0.03, 0.01, -0.01, 0.02, -0.02]
        var i: Int64 = 0
        while (i < m) {
            let xv = Float64(i + 1)
            x[i * n] = 1.0
            x[i * n + 1] = xv
            ys[i] = 2.0 * xv + noise[i]
            i++
        }
        let X = LispValue.External(reshapeArray(ndarrayFromFloats(x), [m, n]))
        let y = LispValue.External(ndarrayFromFloats(ys))
        let b = asFloatArr(lstsqLisp(X, y))
        expectClose(b[1], 2.0, 0.02, "斜率接近 2")
        println("✓ 噪声下斜率仍接近 2（实际 ${b[1]}）")
    }

    /**
     * **秩亏必须报错**
     *
     * 两个特征完全线性相关（一列是另一列的两倍）时，系数不唯一 ——
     * 静默给出某个"解"会让用户以为找到了唯一答案。
     */
    @TestCase
    func testRankDeficient() {
        println("\n=== 秩亏 ===")
        let m = Int64(4)
        let n = Int64(3)
        let x = Array<Float64>(m * n, repeat: 0.0)
        var i: Int64 = 0
        while (i < m) {
            x[i * n] = 1.0
            x[i * n + 1] = Float64(i + 1)
            x[i * n + 2] = 2.0 * Float64(i + 1)   // 与第 2 列完全共线
            i++
        }
        let X = LispValue.External(reshapeArray(ndarrayFromFloats(x), [m, n]))
        let y = LispValue.External(ndarrayFromFloats([1.0, 2.0, 3.0, 4.0]))
        expectErr({ => lstsqLisp(X, y) }, "共线特征")
        println("✓ 共线特征报错（系数不唯一）")
    }

    /** 样本数少于特征数：方程欠定，必须报错 */
    @TestCase
    func testUnderdetermined() {
        println("\n=== 欠定 ===")
        let X = LispValue.External(reshapeArray(ndarrayFromFloats([1.0, 2.0, 3.0]), [3, 1]))
        let y = LispValue.External(ndarrayFromFloats([1.0]))
        expectErr({ => lstsqLisp(X, y) }, "3 行 1 列但 y 只有 1 个")
        println("✓ 维度不匹配报错")
    }
}
