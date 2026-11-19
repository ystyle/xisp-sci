package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.math.*

/**
 * 线性代数：矩阵提取与乘法
 *
 * ## 为什么先做纯仓颉
 *
 * `cjpm` 没有可选依赖，「接 BLAS / LAPACK」意味着**每个**想用本模块的宿主都得
 * 装 C 工具链 —— 这与 `xisp_array` 一直守着的"纯仓颉、零外部依赖"前提直接冲突。
 * 所以第一版全部自己写：矩阵乘法用转置技巧保证缓存友好，分解用带部分主元的标准算法。
 *
 * 真需要性能时再按路线图 S4 的讨论加 `xisp_linalg_native` 之类的加速模块，
 * **不把 C 依赖塞进本模块**。
 *
 * ## 数值约定
 *
 * - 输入一律按 **Float64** 计算（Int 数组自动提升）
 * - 奇异 / 非正定等情形**报错**，不返回垃圾值 —— 一个悄悄算错的逆矩阵比一次报错危险得多
 * - 奇异判定用相对容差（见 `linalgEps`），不写死绝对阈值
 */

/** 相对容差的基准；实际阈值还要乘上矩阵元素的最大绝对值 */
const LINALG_REL_EPS: Float64 = 1e-12

/** 矩阵元素的最大绝对值，用于把绝对阈值换成相对阈值 */
func maxAbsOf(values: Array<Float64>): Float64 {
    var m = 0.0
    for (v in values) {
        let a = abs(v)
        if (a > m) {
            m = a
        }
    }
    m
}

func linalgEps(values: Array<Float64>): Float64 {
    let m = maxAbsOf(values)
    if (m == 0.0) {
        return LINALG_REL_EPS
    }
    LINALG_REL_EPS * m
}

/**
 * 把参数转成行优先的 `Float64` 矩阵
 *
 * 返回 `(行数, 列数, 数据)`。一维数组按**列向量**处理（`n × 1`）—— 这是线性代数
 * 里的默认语义：`y = A x` 中的 `x` 是列向量。
 */
func toMatrix(v: LispValue, who: String): (Int64, Int64, Array<Float64>) {
    let arr = match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray => a.copy()      // 取连续副本，避免非连续视图的 strides 干扰
                case _ => throw IllegalArgumentException(
                    "${who} 需要 ndarray，得到外部值 ${e.typeName}")
            }
        case _ => throw IllegalArgumentException(
            "${who} 需要 ndarray，得到 ${v.toString()}")
    }
    let dims = arr.shape
    if (dims.size > 2) {
        throw IllegalArgumentException("${who} 只支持 1D / 2D 数组，得到 ${dims.size} 维")
    }
    var rows: Int64 = 1
    var cols: Int64 = 1
    if (dims.size == 1) {
        rows = dims[0]
        cols = 1
    } else if (dims.size == 2) {
        rows = dims[0]
        cols = dims[1]
    }
    let out = Array<Float64>(rows * cols, repeat: 0.0)
    var i: Int64 = 0
    let total = rows * cols
    while (i < total) {
        out[i] = match (arr.at(i)) {
            case Float(x) => x
            case Int(x) => Float64(x)
            case _ => throw IllegalArgumentException("${who} 的元素必须是数值")
        }
        i++
    }
    (rows, cols, out)
}

/** 把行优先矩阵包回 ndarray */
func matrixToArray(rows: Int64, cols: Int64, data: Array<Float64>): NDArray {
    if (rows == 1 || cols == 1) {
        // 单行或单列还原成 1D，与"一维数组按向量处理"的入口约定对称
        ndarrayFromFloats(data)
    } else {
        let a = ndarrayFromFloats(data)
        reshapeArray(a, [rows, cols])
    }
}

/**
 * 矩阵乘法（转置 B 保证内层循环连续访问）
 *
 * `C[i][j] = Σ_k A[i][k] * B[k][j]` —— 直接写会让 B 的访问跨行跳跃；
 * 先把 B 转置成 `BT[j][k]`，两个操作数在内层循环里都是连续的。
 */
/**
 * matmul 的可替换后端
 *
 * 默认是纯仓颉实现。外部可以注册一个更快的实现（比如 CBLAS 的 `cblas_dgemm`）——
 * 这样 `xisp_linalg` **保持零依赖**，加速器作为独立的可选成员存在。
 *
 * 签名与 `matmulRaw` 一致：`(rows, k, cols, a, b) → 结果`，全部行优先、连续
 * `Float64`。注册方必须保证语义相同（包括维度校验已在上层做过）。
 *
 * 返回 `Some` 表示已注册后端；`None` 时走纯仓颉实现。
 */
var matmulBackend: Option<(Int64, Int64, Int64, Array<Float64>, Array<Float64>) -> Array<Float64>> =
    None

/** 注册加速后端（由可选成员在装配时调用） */
public func setMatmulBackend(
    f: (Int64, Int64, Int64, Array<Float64>, Array<Float64>) -> Array<Float64>): Unit {
    matmulBackend = Some(f)
}

/** 撤销加速后端，回到纯仓颉实现 */
public func clearMatmulBackend(): Unit {
    matmulBackend = None
}

/** 是否已注册加速后端 */
public func hasMatmulBackend(): Bool {
    match (matmulBackend) {
        case Some(_) => true
        case None => false
    }
}

/** 实际入口：有后端走后端，没有走纯仓颉 */
func matmulDispatch(rows: Int64, k: Int64, cols: Int64,
                    a: Array<Float64>, b: Array<Float64>): Array<Float64> {
    match (matmulBackend) {
        case Some(f) => f(rows, k, cols, a, b)
        case None => matmulRaw(rows, k, cols, a, b)
    }
}

func matmulRaw(rows: Int64, k: Int64, cols: Int64,
               a: Array<Float64>, b: Array<Float64>): Array<Float64> {
    let bt = Array<Float64>(k * cols, repeat: 0.0)
    var i: Int64 = 0
    while (i < k) {
        var j: Int64 = 0
        while (j < cols) {
            bt[j * k + i] = b[i * cols + j]
            j++
        }
        i++
    }
    let out = Array<Float64>(rows * cols, repeat: 0.0)
    i = 0
    while (i < rows) {
        var j: Int64 = 0
        while (j < cols) {
            var s = 0.0
            var p: Int64 = 0
            while (p < k) {
                s = s + a[i * k + p] * bt[j * k + p]
                p++
            }
            out[i * cols + j] = s
            j++
        }
        i++
    }
    out
}

/**
 * `(cangjie::matmul A B)`
 *
 * 维度组合：
 *
 * | A | B | 结果 |
 * |---|---|---|
 * | `2D (m,k)` | `2D (k,n)` | `2D (m,n)` |
 * | `1D (k)` | `2D (k,n)` | `1D (n)`（行向量乘矩阵） |
 * | `2D (m,k)` | `1D (k)` | `1D (m)`（矩阵乘列向量） |
 * | `1D (k)` | `1D (k)` | **标量**（点积） |
 */
/** 取 ndarray 参数，并把元素按行优先拍平成 `Float64` */
func asNDArray2(v: LispValue, who: String): NDArray {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray => a.copy()
                case _ => throw IllegalArgumentException(
                    "${who} 需要 ndarray，得到外部值 ${e.typeName}")
            }
        case _ => throw IllegalArgumentException(
            "${who} 需要 ndarray，得到 ${v.toString()}")
    }
}

func flattenFloats(a: NDArray, who: String): Array<Float64> {
    let n = a.size()
    let out = Array<Float64>(n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = match (a.at(i)) {
            case Float(x) => x
            case Int(x) => Float64(x)
            case _ => throw IllegalArgumentException("${who} 的元素必须是数值")
        }
        i++
    }
    out
}

/**
 * `(cangjie::matmul A B)`
 *
 * 维度组合（**一维数组在 A 位置当行向量、在 B 位置当列向量**，与 `y = A x` 的
 * 书写顺序一致）：
 *
 * | A | B | 结果 |
 * |---|---|---|
 * | `2D (m,k)` | `2D (k,n)` | `2D (m,n)` |
 * | `1D (k)` | `2D (k,n)` | `1D (n)` |
 * | `2D (m,k)` | `1D (k)` | `1D (m)` |
 * | `1D (k)` | `1D (k)` | **标量**（点积） |
 */
func matmulLisp(av: LispValue, bv: LispValue): LispValue {
    let aArr = asNDArray2(av, "cangjie::matmul")
    let bArr = asNDArray2(bv, "cangjie::matmul")
    let ad = aArr.shape
    let bd = bArr.shape
    if (ad.size > 2 || bd.size > 2) {
        throw IllegalArgumentException("cangjie::matmul 只支持 1D / 2D 数组")
    }
    let aData = flattenFloats(aArr, "cangjie::matmul")
    let bData = flattenFloats(bArr, "cangjie::matmul")
    let aIsVec = ad.size == 1
    let bIsVec = bd.size == 1

    if (aIsVec && bIsVec) {
        let k = ad[0]
        if (bd[0] != k) {
            throw IllegalArgumentException(
                "matmul 点积维度不匹配：${k} 与 ${bd[0]}")
        }
        var s = 0.0
        var i: Int64 = 0
        while (i < k) {
            s = s + aData[i] * bData[i]
            i++
        }
        return LispValue.Float(s)
    }
    if (aIsVec) {
        let k = ad[0]
        let bk = bd[0]
        let n = bd[1]
        if (bk != k) {
            throw IllegalArgumentException(
                "matmul 维度不匹配：行向量长度 ${k}，矩阵行数 ${bk}")
        }
        return LispValue.External(ndarrayFromFloats(matmulDispatch(1, k, n, aData, bData)))
    }
    if (bIsVec) {
        let m = ad[0]
        let k = ad[1]
        if (bd[0] != k) {
            throw IllegalArgumentException(
                "matmul 维度不匹配：矩阵列数 ${k}，向量长度 ${bd[0]}")
        }
        return LispValue.External(ndarrayFromFloats(matmulDispatch(m, k, 1, aData, bData)))
    }
    let m = ad[0]
    let k = ad[1]
    let bk = bd[0]
    let n = bd[1]
    if (bk != k) {
        throw IllegalArgumentException(
            "matmul 维度不匹配：A 是 ${m}×${k}，B 是 ${bk}×${n}")
    }
    LispValue.External(matrixToArray(m, n, matmulDispatch(m, k, n, aData, bData)))
}

/** `(cangjie::trace A)` —— 方阵对角线之和 */
func traceOf(av: LispValue): Float64 {
    let (rows, cols, data) = toMatrix(av, "cangjie::trace")
    if (rows != cols) {
        throw IllegalArgumentException("trace 需要方阵，得到 ${rows}×${cols}")
    }
    var s = 0.0
    var i: Int64 = 0
    while (i < rows) {
        s = s + data[i * cols + i]
        i++
    }
    s
}
