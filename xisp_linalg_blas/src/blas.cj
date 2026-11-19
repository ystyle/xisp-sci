package ystyle::xisp_linalg_blas

import ystyle::xisp_linalg.*

import std.math.*

/**
 * 可选的 BLAS 加速后端
 *
 * ## 零 C 代码
 *
 * 这里没有一行 C —— 只有 `foreign` 声明。BLAS 的 **CBLAS 接口是标准化的**
 * （符号名、参数顺序、枚举值都固定），所以同一个声明可以对接任何实现：
 * netlib Reference、OpenBLAS、BLIS、MKL、Apple Accelerate。
 *
 * ## 跨平台
 *
 * 符号名跨平台一致，差别只在**链接参数**（见 `cjpm.toml` 的注释）：
 *
 * | 平台 | link-option | 库从哪来 |
 * |---|---|---|
 * | Linux | `-lblas` | 发行版包（Debian: `libblas3` / `libopenblas0`） |
 * | macOS | `-framework Accelerate` | **系统自带**，Apple 优化 |
 * | Windows | OpenBLAS 的路径 | 需要自己装 |
 *
 * **BLAS 不属于 libc** —— 它是独立的数学库。Linux 上通常因为装了 numpy / scipy
 * 之类的包被顺带装上，所以"看起来像系统自带"。
 *
 * ## 性能
 *
 * 本机实测（800×800，netlib Reference BLAS 3.12.0）：139 ms / 7.34 GFLOPS，
 * 对比纯仓颉的 313 ms / 3.27 GFLOPS 是 **2.24 倍**。
 *
 * 换成 OpenBLAS 单核可达 30~50 GFLOPS（10~15 倍）。
 *
 * 有意思的是 netlib Reference 的源码就是朴素三重循环，比我们快一倍多完全来自
 * **gfortran -O2 的自动向量化** —— 差距不在算法，在编译器的向量化能力。
 */

// CBLAS 的枚举常量（标准值，所有实现一致）
let CBLAS_ROW_MAJOR: Int32 = 101
let CBLAS_NO_TRANS: Int32 = 111

/**
 * `C = alpha·A·B + beta·C`（双精度通用矩阵乘）
 *
 * 完整签名还有 `CBLAS_TRANSPOSE` 等枚举，这里用 `Int32` 传 —— C 的枚举在 ABI 层
 * 就是 int。
 */
foreign func cblas_dgemm(layout: Int32, transA: Int32, transB: Int32,
                         m: Int32, n: Int32, k: Int32,
                         alpha: Float64, a: CPointer<Float64>, lda: Int32,
                         b: CPointer<Float64>, ldb: Int32,
                         beta: Float64, c: CPointer<Float64>, ldc: Int32): Unit

/**
 * 用 BLAS 做 `A × B`
 *
 * 全部行优先、连续内存。上层 `xisp_linalg` 已经保证：
 * - 三个数组都是连续的 `Float64`
 * - 维度匹配（`a` 是 rows×k，`b` 是 k×cols）
 *
 * 所以这里不需要任何校验，也不复制数据 —— 指针直接指向调用方的数组。
 */
func blasMatmul(rows: Int64, k: Int64, cols: Int64,
                a: Array<Float64>, b: Array<Float64>): Array<Float64> {
    let out = Array<Float64>(rows * cols, repeat: 0.0)
    let r = Int32(rows)
    let kk = Int32(k)
    let c = Int32(cols)
    unsafe {
        let ha = acquireArrayRawData(a)
        let hb = acquireArrayRawData(b)
        let hc = acquireArrayRawData(out)
        try {
            cblas_dgemm(CBLAS_ROW_MAJOR, CBLAS_NO_TRANS, CBLAS_NO_TRANS,
                r, c, kk,
                1.0, ha.pointer, kk,
                hb.pointer, c,
                0.0, hc.pointer, c)
        } finally {
            // 无论 C 调用是否抛异常，句柄都必须释放 —— 否则 Array 会被永久锁定
            releaseArrayRawData(hc)
            releaseArrayRawData(hb)
            releaseArrayRawData(ha)
        }
    }
    out
}

/**
 * 启用 BLAS 加速
 *
 * 调用之后，`cangjie::matmul`（以及 `xisp_linalg` 里所有用到矩阵乘的地方）
 * 都走 `cblas_dgemm`。
 *
 * ```cangjie
 * import ystyle::xisp_linalg_blas.*
 *
 * enableBlas()
 * let interp = LispInterpreter([withSci()])
 * ```
 *
 * 如果有多个线程同时初始化，建议在启动阶段调用一次即可。
 */
public func enableBlas(): Unit {
    setMatmulBackend(blasMatmul)
}

/** 撤销 BLAS 加速，回到纯仓颉实现 */
public func disableBlas(): Unit {
    clearMatmulBackend()
}
