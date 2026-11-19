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
