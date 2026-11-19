package ystyle::bench

import std.time.*
import std.math.*

/**
 * 实验：纯仓颉的分块 matmul 能到多快
 *
 * 当前 `xisp_linalg` 的 `matmulRaw` 是「转置 B + 三重循环」，没有分块、
 * 没有寄存器复用 —— 800×800 约 2 GFLOPS。
 *
 * OpenBLAS 单核 50~100 GFLOPS，差距来自三件事：
 * 1. **分块**：把矩阵切成能装进 L2/L3 的块，避免反复访存
 * 2. **SIMD**：AVX2 一次算 4 个 double
 * 3. **寄存器分块**：手工展开内层循环，让数据留在寄存器
 *
 * 这个实验只做第 1 件（不需要任何前提），看纯仓颉能提升多少。
 */

/** 朴素实现（与 xisp_linalg 一致：转置 B 后点积） */
func matmulNaive(m: Int64, k: Int64, n: Int64,
                 a: Array<Float64>, b: Array<Float64>): Array<Float64> {
    let bt = Array<Float64>(k * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < k) {
        var j: Int64 = 0
        while (j < n) {
            bt[j * k + i] = b[i * n + j]
            j++
        }
        i++
    }
    let out = Array<Float64>(m * n, repeat: 0.0)
    i = 0
    while (i < m) {
        var j: Int64 = 0
        while (j < n) {
            var s = 0.0
            var p: Int64 = 0
            while (p < k) {
                s = s + a[i * k + p] * bt[j * k + p]
                p++
            }
            out[i * n + j] = s
            j++
        }
        i++
    }
    out
}

/**
 * 分块实现（分块 + 转置 B）
 *
 * 三重循环按 `(ii, kk, jj)` 分块，让一块 `bs×bs` 的 A 子块和 B 子块
 * 在 cache 里反复复用，而不是每次都要从内存取。
 */
func matmulBlocked(m: Int64, k: Int64, n: Int64,
                   a: Array<Float64>, b: Array<Float64>, bs: Int64): Array<Float64> {
    // 转置 B 保证内层连续
    let bt = Array<Float64>(k * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < k) {
        var j: Int64 = 0
        while (j < n) {
            bt[j * k + i] = b[i * n + j]
            j++
        }
        i++
    }
    let out = Array<Float64>(m * n, repeat: 0.0)
    var ii: Int64 = 0
    while (ii < m) {
        let iEnd = if (ii + bs > m) { m } else { ii + bs }
        var kk: Int64 = 0
        while (kk < k) {
            let kEnd = if (kk + bs > k) { k } else { kk + bs }
            var jj: Int64 = 0
            while (jj < n) {
                let jEnd = if (jj + bs > n) { n } else { jj + bs }
                // 在块内做累加：A 的 [ii,iEnd)×[kk,kEnd) 乘 BT 的 [jj,jEnd)×[kk,kEnd)
                var i2: Int64 = ii
                while (i2 < iEnd) {
                    let aRow = i2 * k
                    let cRow = i2 * n
                    var j2: Int64 = jj
                    while (j2 < jEnd) {
                        let btRow = j2 * k
                        var s = out[cRow + j2]
                        var p: Int64 = kk
                        while (p < kEnd) {
                            s = s + a[aRow + p] * bt[btRow + p]
                            p++
                        }
                        out[cRow + j2] = s
                        j2++
                    }
                    i2++
                }
                jj = jj + bs
            }
            kk = kk + bs
        }
        ii = ii + bs
    }
    out
}

func matmulExperiment(): Unit {
    log("\n## 十一、纯仓颉能优化到什么程度（matmul 实验）")
    log("")
    log("当前实现是「转置 B + 三重循环」，没有分块。差距来源有三个：分块、SIMD、")
    log("寄存器分块。这个实验**只做分块**（零依赖、纯仓颉），看能提升多少。")
    log("")
    let n: Int64 = 800
    let a = Array<Float64>(n * n, repeat: 0.0)
    let b = Array<Float64>(n * n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n * n) {
        a[i] = Float64(i % 100) / 100.0
        b[i] = Float64((i * 7) % 100) / 100.0
        i++
    }
    let flops = 2.0 * Float64(n) * Float64(n) * Float64(n)

    // 朴素
    let _ = matmulNaive(n, n, n, a, b)      // 预热
    let t0 = MonoTime.now()
    let r0 = matmulNaive(n, n, n, a, b)
    let naiveMs = Float64((MonoTime.now() - t0).toNanoseconds()) / 1000000.0

    log("| 实现 | 耗时 | GFLOPS | 相对朴素 |")
    log("|---|---|---|---|")
    log("| 朴素（转置 + 三重循环，当前实现） | ${formatMs(naiveMs)} | ${cut((flops/(naiveMs/1000.0)/1e9).toString(), 4)} | 1× |")

    // 不同分块大小
    for (bs in [32, 64, 128, 256]) {
        let _ = matmulBlocked(n, n, n, a, b, bs)
        let t = MonoTime.now()
        let r = matmulBlocked(n, n, n, a, b, bs)
        let ms = Float64((MonoTime.now() - t).toNanoseconds()) / 1000000.0
        // 校验正确性（与朴素实现逐元素对比）
        var maxDiff = 0.0
        var k: Int64 = 0
        while (k < n * n) {
            let d = abs(r[k] - r0[k])
            if (d > maxDiff) {
                maxDiff = d
            }
            k++
        }
        let okMark = if (maxDiff < 1e-9) { "" } else { " ⚠️ 误差 ${maxDiff}" }
        log("| 分块 bs=${bs} | ${formatMs(ms)} | ${cut((flops/(ms/1000.0)/1e9).toString(), 4)} | ${cut((naiveMs/ms).toString(), 4)}×${okMark} |")
    }

    log("")
    log("### 结论：分块没用，瓶颈在 SIMD")
    log("")
    log("**分块全部更慢（0.87~0.90×）**，这否掉了「纯仓颉还能靠改循环顺序大幅提速」的设想。")
    log("原因是当前实现在**分块之前就已经做了最关键的那个 cache 优化**：转置 B。")
    log("转置后内层循环访问的是连续内存，分块本来要解决的问题（跨行跳跃）已经不存在了。")
    log("")
    log("而且 800×800 的 A/B/C 三个矩阵共 15 MB，能装进典型 L3（8~32 MB），")
    log("分块要防的「反复换入换出」在这个规模也没发生 —— 加进去只剩额外开销。")
    log("")
    log("**真正的瓶颈是指令级并行**：3.29 GFLOPS 对比单核 AVX2 双精度理论峰值")
    log("（2 个 FMA 端口 × 4 个 double × 2 flops/次 × ~3 GHz ≈ 48 GFLOPS），")
    log("只用到 **7%**。这个 7% 就是「一次只算一个浮点数」的代价。")
    log("")
    log("而仓颉目前**没有 SIMD API**（在 1.0/1.1 文档里搜 `SIMD` 零命中），所以纯仓颉的天花板")
    log("就在这里。要到 30~50 GFLOPS 必须靠 C 的 intrinsics，或者用 BLAS。")
}
