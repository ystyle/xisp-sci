package ystyle::xisp_signal

import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import std.math.*

/**
 * FFT / 卷积 / 滤波 / 窗函数的白盒测试
 *
 * **核心手法：用朴素 DFT 作为独立参照**。
 *
 * 用另一个 FFT 实现验证一个 FFT 实现是没意义的 —— 共模故障（比如 chirp 的符号写反）
 * 会一起错。朴素 DFT 直接按定义算，虽然 O(n²)，但它对"FFT 该等于什么"是独立的判据。
 */

func randSeq(n: Int64, seed: Int64): ComplexSeq {
    let re = Array<Float64>(n, repeat: 0.0)
    let im = Array<Float64>(n, repeat: 0.0)
    var s = seed
    var i: Int64 = 0
    while (i < n) {
        // 线性同余伪随机，够用且可复现
        s = (s * 1103515245 + 12345) % 2147483648
        re[i] = Float64(s % 2000) / 1000.0 - 1.0
        s = (s * 1103515245 + 12345) % 2147483648
        im[i] = Float64(s % 2000) / 1000.0 - 1.0
        i++
    }
    ComplexSeq(re, im)
}

func maxDiff(a: ComplexSeq, b: ComplexSeq): Float64 {
    if (a.size() != b.size()) {
        return 999.0
    }
    var m = 0.0
    var i: Int64 = 0
    while (i < a.size()) {
        let dr = abs(a.re[i] - b.re[i])
        let di = abs(a.im[i] - b.im[i])
        if (dr > m) {
            m = dr
        }
        if (di > m) {
            m = di
        }
        i++
    }
    m
}

func expectClose(actual: Float64, want: Float64, tol: Float64, what: String): Unit {
    if (abs(actual - want) > tol) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

func expectInt(actual: Int64, want: Int64, what: String): Unit {
    if (actual != want) {
        @Fail("${what}：期望 ${want}，实际 ${actual}")
    }
}

@Test
class FftTest {
    /**
     * **FFT 必须等于朴素 DFT**
     *
     * 覆盖 2 的幂（走 radix-2）与非 2 的幂（走 Bluestein）各若干长度。
     * Bluestein 的 chirp 符号、索引对称性任何一处写错，这条都会红。
     */
    @TestCase
    func testMatchesNaiveDft() {
        println("\n=== FFT vs 朴素 DFT ===")
        let lengths: Array<Int64> = [1, 2, 3, 4, 5, 7, 8, 16, 17, 32, 100]
        for (n in lengths) {
            let x = randSeq(n, n * 7 + 3)
            let got = fftAny(x, false)
            let want = naiveDft(x, false)
            let d = maxDiff(got, want)
            if (d > 1e-9) {
                @Fail("长度 ${n}：与朴素 DFT 最大偏差 ${d}")
            }
        }
        println("✓ 11 种长度（含非 2 的幂）都与朴素 DFT 一致")
    }

    @TestCase
    func testMatchesNaiveInverse() {
        println("\n=== 逆变换 vs 朴素 IDFT ===")
        let lengths: Array<Int64> = [1, 2, 3, 5, 8, 13, 16]
        for (n in lengths) {
            let x = randSeq(n, n * 11 + 5)
            let got = fftAny(x, true)
            let want = naiveDft(x, true)
            let d = maxDiff(got, want)
            if (d > 1e-9) {
                @Fail("长度 ${n}：逆变换最大偏差 ${d}")
            }
        }
        println("✓ 逆变换与朴素 IDFT 一致")
    }

    /**
     * `IFFT(FFT(x)) = x` —— 往返恒等
     */
    @TestCase
    func testRoundTrip() {
        println("\n=== 往返恒等 ===")
        let lengths: Array<Int64> = [2, 4, 6, 8, 15, 16, 64, 100]
        for (n in lengths) {
            let x = randSeq(n, n * 13 + 7)
            let back = fftAny(fftAny(x, false), true)
            let d = maxDiff(back, x)
            if (d > 1e-9) {
                @Fail("长度 ${n}：IFFT(FFT(x)) 最大偏差 ${d}")
            }
        }
        println("✓ IFFT(FFT(x)) = x（含非 2 的幂）")
    }

    /**
     * 已知信号
     *
     * 常数信号的频谱集中在直流分量；冲激的频谱是全 1。这两条是 FFT 定义最直接的体现。
     */
    @TestCase
    func testKnownSignals() {
        println("\n=== 已知信号 ===")
        // 常数 1 的 DFT：X[0] = n，其余为 0
        let n: Int64 = 8
        let ones = ComplexSeq(Array<Float64>(n, repeat: 1.0), Array<Float64>(n, repeat: 0.0))
        let f = fftAny(ones, false)
        expectClose(f.re[0], 8.0, 1e-9, "常数信号的直流分量")
        var i: Int64 = 1
        while (i < n) {
            if (abs(f.re[i]) > 1e-9 || abs(f.im[i]) > 1e-9) {
                @Fail("常数信号在 k=${i} 处应为 0，实际 ${f.re[i]}+${f.im[i]}i")
            }
            i++
        }
        // 冲激信号的频谱全 1
        let imp = Array<Float64>(4, repeat: 0.0)
        imp[0] = 1.0
        let fi = fftAny(ComplexSeq(imp, Array<Float64>(4, repeat: 0.0)), false)
        i = 0
        while (i < 4) {
            expectClose(fi.re[i], 1.0, 1e-9, "冲激的 k=${i} 实部")
            expectClose(fi.im[i], 0.0, 1e-9, "冲激的 k=${i} 虚部")
            i++
        }
        println("✓ 常数 → 只有直流；冲激 → 全 1")
    }

    /**
     * 正弦信号的峰值位置
     *
     * 周期为 N 的正弦应在 k=1（和 k=N-1）处出峰 —— 这条同时验证了频率轴的正确性。
     */
    @TestCase
    func testSinePeak() {
        println("\n=== 正弦峰值 ===")
        let n: Int64 = 16
        let re = Array<Float64>(n, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            re[i] = sin(2.0 * Float64.getPI() * Float64(i) / Float64(n))
            i++
        }
        let f = fftAny(ComplexSeq(re, Array<Float64>(n, repeat: 0.0)), false)
        let mag = Array<Float64>(n, repeat: 0.0)
        i = 0
        while (i < n) {
            mag[i] = sqrt(f.re[i] * f.re[i] + f.im[i] * f.im[i])
            i++
        }
        // k=1 与 k=15 应各约为 n/2 = 8，其余接近 0
        expectClose(mag[1], 8.0, 1e-6, "k=1 幅度")
        expectClose(mag[15], 8.0, 1e-6, "k=15 幅度")
        expectClose(mag[0], 0.0, 1e-6, "k=0 幅度")
        println("✓ 周期 N 的正弦在 k=1 / k=N-1 处出峰")
    }

    @TestCase
    func testEmptyAndSingle() {
        println("\n=== 空与单点 ===")
        let e = fftAny(ComplexSeq(Array<Float64>(), Array<Float64>()), false)
        expectInt(e.size(), 0, "空序列")
        let one = fftAny(ComplexSeq([3.0], [0.0]), false)
        expectInt(one.size(), 1, "单点长度")
        expectClose(one.re[0], 3.0, 1e-12, "单点 DFT 是自身")
        println("✓ 空序列与单点")
    }
}

@Test
class ConvolutionTest {
    /**
     * 直接法与 FFT 法必须给同一个答案
     *
     * 用足够大的数组逼出 FFT 路径（阈值是 n*m > 4096）。
     */
    @TestCase
    func testDirectAndFastAgree() {
        println("\n=== 直接法与 FFT 法一致 ===")
        // 小数组走直接法
        let small = convRaw([1.0, 2.0, 3.0], [0.0, 1.0, 0.5])
        expectInt(small.size, 5, "小数组输出长度")
        expectClose(small[0], 0.0, 1e-12, "[0]")
        expectClose(small[1], 1.0, 1e-12, "[1]")
        expectClose(small[2], 2.5, 1e-12, "[2]")
        expectClose(small[3], 4.0, 1e-12, "[3]")
        expectClose(small[4], 1.5, 1e-12, "[4]")
        // 大数组走 FFT 法：结果必须与直接卷积一致
        let n: Int64 = 200
        let a = Array<Float64>(n, repeat: 0.0)
        let b = Array<Float64>(n, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            a[i] = Float64(i % 7) / 7.0
            b[i] = Float64((i * 3) % 5) / 5.0
            i++
        }
        let fast = convRaw(a, b)
        // 直接算一遍对照
        let direct = Array<Float64>(2 * n - 1, repeat: 0.0)
        i = 0
        while (i < n) {
            var j: Int64 = 0
            while (j < n) {
                direct[i + j] = direct[i + j] + a[i] * b[j]
                j++
            }
            i++
        }
        let d = maxAbsDiff(fast, direct)
        if (d > 1e-8) {
            @Fail("FFT 卷积与直接卷积最大偏差 ${d}")
        }
        println("✓ 200×200 的 FFT 卷积与直接法一致")
    }

    @TestCase
    func testConvWithDelta() {
        println("\n=== 与冲激卷积 ===")
        // 冲激 [1,0,0] 卷积任何序列 = 原序列
        let x = [2.0, -1.0, 0.5]
        let r = convRaw([1.0, 0.0, 0.0], x)
        expectInt(r.size, 5, "输出长度")
        expectClose(r[0], 2.0, 1e-12, "[0]")
        expectClose(r[1], -1.0, 1e-12, "[1]")
        expectClose(r[2], 0.5, 1e-12, "[2]")
        println("✓ 冲激卷积是恒等")
    }

    @TestCase
    func testConvEmpty() {
        println("\n=== 空输入 ===")
        expectInt(convRaw(Array<Float64>(), [1.0]).size, 0, "空 x")
        expectInt(convRaw([1.0], Array<Float64>()).size, 0, "空 y")
        println("✓ 任一为空则结果为空")
    }
}

func maxAbsDiff(a: Array<Float64>, b: Array<Float64>): Float64 {
    if (a.size != b.size) {
        return 999.0
    }
    var m = 0.0
    var i: Int64 = 0
    while (i < a.size) {
        let d = abs(a[i] - b[i])
        if (d > m) {
            m = d
        }
        i++
    }
    m
}

@Test
class FilterTest {
    /**
     * 移动平均：`y[n] = (x[n] + x[n-1]) / 2`
     *
     * 系数 `b = [0.5, 0.5]`、`a = [1]`。
     */
    @TestCase
    func testMovingAverage() {
        println("\n=== 移动平均 ===")
        let y = filterRaw([0.5, 0.5], [1.0], [1.0, 2.0, 3.0, 4.0])
        expectInt(y.size, 4, "输出长度")
        expectClose(y[0], 0.5, 1e-12, "y[0]")
        expectClose(y[1], 1.5, 1e-12, "y[1]")
        expectClose(y[2], 2.5, 1e-12, "y[2]")
        expectClose(y[3], 3.5, 1e-12, "y[3]")
        println("✓ 两抽头移动平均")
    }

    /**
     * 一阶 IIR：`y[n] = x[n] + 0.5 y[n-1]`
     *
     * 阶跃输入的响应应单调上升并收敛到 `1/(1-0.5) = 2`。
     */
    @TestCase
    func testFirstOrderIir() {
        println("\n=== 一阶 IIR ===")
        let x = Array<Float64>(20, repeat: 1.0)
        let y = filterRaw([1.0], [1.0, -0.5], x)
        expectClose(y[0], 1.0, 1e-12, "y[0]")
        expectClose(y[1], 1.5, 1e-12, "y[1]")
        expectClose(y[2], 1.75, 1e-12, "y[2]")
        // 收敛到 2
        if (abs(y[19] - 2.0) > 1e-3) {
            @Fail("阶跃响应应收敛到 2，实际 ${y[19]}")
        }
        println("✓ 阶跃响应收敛到 2")
    }

    @TestCase
    func testFilterErrors() {
        println("\n=== 滤波参数错误 ===")
        var caught = false
        try {
            filterRaw([1.0], [0.0], [1.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("a[0] = 0 应当报错")
        }
        caught = false
        try {
            filterRaw([1.0], Array<Float64>(), [1.0])
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("空分母应当报错")
        }
        println("✓ a[0]=0 与空分母都报错")
    }
}

@Test
class WindowTest {
    @TestCase
    func testHann() {
        println("\n=== Hann 窗 ===")
        let w = windowRaw("hann", 5)
        expectInt(w.size, 5, "长度")
        // Hann：两端为 0，中间为 1
        expectClose(w[0], 0.0, 1e-12, "w[0]")
        expectClose(w[2], 1.0, 1e-12, "w[2]")
        expectClose(w[4], 0.0, 1e-12, "w[4]")
        // 对称
        expectClose(w[1], w[3], 1e-12, "对称性")
        println("✓ 两端 0、中间 1、左右对称")
    }

    @TestCase
    func testHamming() {
        println("\n=== Hamming 窗 ===")
        let w = windowRaw("hamming", 5)
        // Hamming 端点不是 0 而是 0.08
        expectClose(w[0], 0.08, 1e-12, "w[0]")
        expectClose(w[2], 1.0, 1e-12, "w[2]")
        expectClose(w[4], 0.08, 1e-12, "w[4]")
        println("✓ 端点 0.08、中间 1")
    }

    @TestCase
    func testBlackmanAndRect() {
        println("\n=== Blackman / 矩形窗 ===")
        let b = windowRaw("blackman", 5)
        expectClose(b[0], 0.0, 1e-12, "blackman 端点")
        expectClose(b[2], 1.0, 1e-12, "blackman 中点")
        let r = windowRaw("rect", 4)
        var i: Int64 = 0
        while (i < 4) {
            expectClose(r[i], 1.0, 1e-12, "矩形窗")
            i++
        }
        println("✓ Blackman 与矩形窗")
    }

    @TestCase
    func testUnknownWindow() {
        println("\n=== 未知窗名 ===")
        var caught = false
        try {
            windowRaw("nosuch", 4)
        } catch (e: IllegalArgumentException) {
            caught = true
        }
        if (!caught) {
            @Fail("未知窗名应当报错")
        }
        println("✓ 未知窗名报错")
    }
}
