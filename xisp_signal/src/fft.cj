package ystyle::xisp_signal

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 快速傅里叶变换
 *
 * ## 接口稳定性优先
 *
 * Lisp 层只有实数，没有复数类型，所以复数一律用 **`{"re": ndarray, "im": ndarray}`**
 * 表示。这个接口是稳定的：将来内部从 Bluestein 换成混合基、或者给 ndarray 加复数
 * dtype，Lisp 层的写法都不用改。
 *
 * ## 算法
 *
 * - 长度是 2 的幂 → **迭代 radix-2 Cooley-Tukey**（位反转 + 蝶形）
 * - 任意长度 → **Bluestein**（chirp-z）：把 DFT 转成卷积，用 radix-2 算卷积，
 *   空间 O(M)、时间 O(M log M)，M 是 ≥ 2n-1 的最小 2 的幂
 *
 * 选 Bluestein 而不是混合基，是因为它**只在一个地方处理任意长度**：混合基要为
 * 3、5、7 等因子分别写蝶形，实现复杂度和出错面都大得多。真需要更快的特定长度时
 * 再换，接口不变。
 */

let TWO_PI: Float64 = 2.0 * Float64.getPI()

/** 复数数组：实部与虚部分开存，与 Lisp 层 `{"re": …, "im": …}` 一一对应 */
class ComplexSeq {
    var re: Array<Float64>
    var im: Array<Float64>

    init(re: Array<Float64>, im: Array<Float64>) {
        this.re = re
        this.im = im
    }

    func size(): Int64 {
        this.re.size
    }
}

/**
 * 迭代 radix-2 FFT（就地）
 *
 * 要求长度是 2 的幂。`inverse = true` 时做逆变换并除以 n。
 */
func fftRadix2InPlace(c: ComplexSeq, inverse: Bool): Unit {
    let n = c.size()
    if (n <= 1) {
        return
    }
    // 位反转置换
    var i: Int64 = 1
    var j: Int64 = 0
    while (i < n) {
        var bit = n >> 1
        while ((j & bit) != 0) {
            j = j ^ bit
            bit = bit >> 1
        }
        j = j | bit
        if (i < j) {
            let tr = c.re[i]
            c.re[i] = c.re[j]
            c.re[j] = tr
            let ti = c.im[i]
            c.im[i] = c.im[j]
            c.im[j] = ti
        }
        i++
    }
    // 蝶形
    var len: Int64 = 2
    while (len <= n) {
        let ang = TWO_PI / Float64(len) * (if (inverse) { 1.0 } else { -1.0 })
        let wRe = cos(ang)
        let wIm = sin(ang)
        let half = len >> 1
        var start: Int64 = 0
        while (start < n) {
            var wR = 1.0
            var wI = 0.0
            var k: Int64 = 0
            while (k < half) {
                let i0 = start + k
                let i1 = i0 + half
                let vR = c.re[i1] * wR - c.im[i1] * wI
                let vI = c.re[i1] * wI + c.im[i1] * wR
                let uR = c.re[i0]
                let uI = c.im[i0]
                c.re[i0] = uR + vR
                c.im[i0] = uI + vI
                c.re[i1] = uR - vR
                c.im[i1] = uI - vI
                let nwR = wR * wRe - wI * wIm
                let nwI = wR * wIm + wI * wRe
                wR = nwR
                wI = nwI
                k++
            }
            start = start + len
        }
        len = len << 1
    }
    if (inverse) {
        let inv = 1.0 / Float64(n)
        var t: Int64 = 0
        while (t < n) {
            c.re[t] = c.re[t] * inv
            c.im[t] = c.im[t] * inv
            t++
        }
    }
}

func isPowerOfTwo(n: Int64): Bool {
    n > 0 && (n & (n - 1)) == 0
}

/** 下一个不小于 n 的 2 的幂 */
func nextPow2(n: Int64): Int64 {
    var m: Int64 = 1
    while (m < n) {
        m = m << 1
    }
    m
}

/**
 * Bluestein（chirp-z）：任意长度的 DFT
 *
 * 把 `X[k] = Σ x[n] e^{-2πi nk/N}` 改写成卷积：
 *
 * ```
 * nk = (n² + k² - (k-n)²) / 2
 * X[k] = e^{-iπk²/N} · Σ_n [x[n] e^{-iπn²/N}] · e^{iπ(k-n)²/N}
 * ```
 *
 * 右边那个和就是 `a` 与 `b` 的线性卷积，`a[n] = x[n]e^{-iπn²/N}`、
 * `b[m] = e^{iπm²/N}`，用 radix-2 FFT 在长度 `M ≥ 2N-1` 上算。
 */
func fftBluestein(c: ComplexSeq, inverse: Bool): ComplexSeq {
    let n = c.size()
    let m = nextPow2(2 * n - 1)
    let sign = if (inverse) { 1.0 } else { -1.0 }
    // chirp 因子 w[k] = e^{-iπk²/N}（逆变换取共轭）
    // k² 可能溢出，用 k² mod 2N 化简：e^{-iπk²/N} 的周期是 k→k+2N
    let chirpRe = Array<Float64>(n, repeat: 0.0)
    let chirpIm = Array<Float64>(n, repeat: 0.0)
    var k: Int64 = 0
    while (k < n) {
        let k2 = (k * k) % (2 * n)
        let ang = sign * Float64.getPI() * Float64(k2) / Float64(n)
        chirpRe[k] = cos(ang)
        chirpIm[k] = sin(ang)
        k++
    }
    // a[n] = x[n] * w[n]
    let aRe = Array<Float64>(m, repeat: 0.0)
    let aIm = Array<Float64>(m, repeat: 0.0)
    k = 0
    while (k < n) {
        let xr = c.re[k]
        let xi = c.im[k]
        // 乘 chirp（sign 已在 chirp 里体现：正向 -1、逆变换 +1），不再二次取反
        let cr = chirpRe[k]
        let ci = chirpIm[k]
        aRe[k] = xr * cr - xi * ci
        aIm[k] = xr * ci + xi * cr
        k++
    }
    // b[m] = e^{+iπm²/N}，布置成循环卷积的对称形式
    let bRe = Array<Float64>(m, repeat: 0.0)
    let bIm = Array<Float64>(m, repeat: 0.0)
    bRe[0] = 1.0
    k = 1
    while (k < n) {
        let k2 = (k * k) % (2 * n)
        let ang = -sign * Float64.getPI() * Float64(k2) / Float64(n)
        let vr = cos(ang)
        let vi = sin(ang)
        bRe[k] = vr
        bIm[k] = vi
        // 负频率部分（循环卷积需要对称）
        bRe[m - k] = vr
        bIm[m - k] = vi
        k++
    }
    // 卷积：FFT(a) * FFT(b) 再逆变换
    let aSeq = ComplexSeq(aRe, aIm)
    let bSeq = ComplexSeq(bRe, bIm)
    fftRadix2InPlace(aSeq, false)
    fftRadix2InPlace(bSeq, false)
    k = 0
    while (k < m) {
        let ar = aSeq.re[k]
        let ai = aSeq.im[k]
        let br = bSeq.re[k]
        let bi = bSeq.im[k]
        aSeq.re[k] = ar * br - ai * bi
        aSeq.im[k] = ar * bi + ai * br
        k++
    }
    fftRadix2InPlace(aSeq, true)
    // X[k] = w[k] * conv[k]
    let outRe = Array<Float64>(n, repeat: 0.0)
    let outIm = Array<Float64>(n, repeat: 0.0)
    k = 0
    while (k < n) {
        let cr = chirpRe[k]
        let ci = chirpIm[k]
        let vr = aSeq.re[k]
        let vi = aSeq.im[k]
        outRe[k] = vr * cr - vi * ci
        outIm[k] = vr * ci + vi * cr
        k++
    }
    // 逆变换要除以 n（radix-2 路径在 `fftRadix2InPlace` 里做了，Bluestein 要自己补）
    if (inverse) {
        let inv = 1.0 / Float64(n)
        k = 0
        while (k < n) {
            outRe[k] = outRe[k] * inv
            outIm[k] = outIm[k] * inv
            k++
        }
    }
    ComplexSeq(outRe, outIm)
}

/** 任意长度的 FFT / IFFT 入口 */
func fftAny(c: ComplexSeq, inverse: Bool): ComplexSeq {
    let n = c.size()
    if (n == 0) {
        return ComplexSeq(Array<Float64>(), Array<Float64>())
    }
    if (isPowerOfTwo(n)) {
        let copy = ComplexSeq(c.re.clone(), c.im.clone())
        fftRadix2InPlace(copy, inverse)
        return copy
    }
    fftBluestein(c, inverse)
}

/**
 * 朴素 DFT（只用于测试对照）
 *
 * 直接按定义算 O(n²)，作为 FFT 正确性的独立参照 —— 用另一个 FFT 实现验证
 * 一个 FFT 实现，共模故障会一起错。
 */
func naiveDft(c: ComplexSeq, inverse: Bool): ComplexSeq {
    let n = c.size()
    let outRe = Array<Float64>(n, repeat: 0.0)
    let outIm = Array<Float64>(n, repeat: 0.0)
    let sign = if (inverse) { 1.0 } else { -1.0 }
    var k: Int64 = 0
    while (k < n) {
        var sr = 0.0
        var si = 0.0
        var t: Int64 = 0
        while (t < n) {
            let ang = sign * TWO_PI * Float64(t) * Float64(k) / Float64(n)
            let cr = cos(ang)
            let ci = sin(ang)
            sr = sr + c.re[t] * cr - c.im[t] * ci
            si = si + c.re[t] * ci + c.im[t] * cr
            t++
        }
        outRe[k] = sr
        outIm[k] = si
        k++
    }
    if (inverse) {
        let inv = 1.0 / Float64(n)
        var i: Int64 = 0
        while (i < n) {
            outRe[i] = outRe[i] * inv
            outIm[i] = outIm[i] * inv
            i++
        }
    }
    ComplexSeq(outRe, outIm)
}
