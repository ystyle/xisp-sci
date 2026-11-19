package ystyle::xisp_signal

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 信号处理能力域：FFT、卷积、IIR 滤波、窗函数
 *
 * ## 复数怎么表示
 *
 * Lisp 层没有复数类型，一律用 **`{"re": ndarray, "im": ndarray}`**。
 * 这个接口是稳定的 —— 内部从 Bluestein 换成别的算法、或者将来 ndarray 支持复数
 * dtype，Lisp 层的写法都不用改。
 *
 * ## 卷积的算法切换
 *
 * 小数组用直接法（O(n·m)，无 FFT 开销），大数组用 FFT（O(N log N)）。
 * 阈值是内部细节，接口不变。
 */

let SIGNAL_SYMBOLS: Array<String> = [
    "cangjie::fft", "cangjie::ifft", "cangjie::fft-magnitude",
    "cangjie::conv", "cangjie::filter", "cangjie::window"]

public func signalDomain(): LispCapability {
    SimpleCapability(
        "signal",
        SIGNAL_SYMBOLS,
        { ctx => registerSignal(ctx.env) },
        escapable: false,
        hostPolicy: false)
}

func guardedSignal(action: () -> LispValue): LispValue {
    try {
        action()
    } catch (e: IllegalArgumentException) {
        LispValue.Error(XispError(ErrorType.TypeError, e.message))
    } catch (e: Exception) {
        LispValue.Error(XispError(ErrorType.RuntimeError, e.message))
    }
}

func arity(args: ArrayList<LispValue>, want: Int64, who: String): Unit {
    if (args.size != want) {
        throw IllegalArgumentException("${who} 需要 ${want} 个参数，得到 ${args.size} 个")
    }
}

func asNDArray(v: LispValue, who: String): NDArray {
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

func floatsOf(a: NDArray, who: String): Array<Float64> {
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
 * 解析复数序列
 *
 * 接受两种输入：
 * - ndarray（实数序列，虚部为 0）
 * - `{"re": ndarray, "im": ndarray}`（完整复数）
 */
func asComplexSeq(v: LispValue, who: String): ComplexSeq {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    let re = floatsOf(a, who)
                    ComplexSeq(re, Array<Float64>(re.size, repeat: 0.0))
                case _ => throw IllegalArgumentException(
                    "${who} 需要 ndarray 或 {re, im}，得到外部值 ${e.typeName}")
            }
        case HashMap(m) =>
            let reV = match (m.get("re")) {
                case Some(x) => x
                case None => throw IllegalArgumentException("${who} 的 {re, im} 缺少 re")
            }
            let imV = match (m.get("im")) {
                case Some(x) => x
                case None => throw IllegalArgumentException("${who} 的 {re, im} 缺少 im")
            }
            let re = floatsOf(asNDArray(reV, who), who)
            let im = floatsOf(asNDArray(imV, who), who)
            if (re.size != im.size) {
                throw IllegalArgumentException(
                    "${who} 的 re / im 长度不一致：${re.size} 与 ${im.size}")
            }
            ComplexSeq(re, im)
        case _ => throw IllegalArgumentException(
            "${who} 需要 ndarray 或 {re, im}，得到 ${v.toString()}")
    }
}

func complexToLisp(c: ComplexSeq): LispValue {
    let out = HashMap<String, LispValue>()
    out.add("re", LispValue.External(ndarrayFromFloats(c.re)))
    out.add("im", LispValue.External(ndarrayFromFloats(c.im)))
    LispValue.HashMap(out)
}

/**
 * 卷积
 *
 * 小数组直接法，大数组走 FFT —— 阈值是内部细节，接口不变。
 * 输出长度 `n + m - 1`（"full" 卷积）。
 */
func convRaw(x: Array<Float64>, y: Array<Float64>): Array<Float64> {
    let n = x.size
    let m = y.size
    if (n == 0 || m == 0) {
        return Array<Float64>()
    }
    let outLen = n + m - 1
    // 小数组直接算，避免 FFT 的固定开销
    if (n * m <= 4096) {
        let out = Array<Float64>(outLen, repeat: 0.0)
        var i: Int64 = 0
        while (i < n) {
            let xi = x[i]
            var j: Int64 = 0
            while (j < m) {
                out[i + j] = out[i + j] + xi * y[j]
                j++
            }
            i++
        }
        return out
    }
    // FFT 卷积：补零到 ≥ n+m-1 的 2 的幂
    let size = nextPow2(outLen)
    let aRe = Array<Float64>(size, repeat: 0.0)
    let bRe = Array<Float64>(size, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        aRe[i] = x[i]
        i++
    }
    i = 0
    while (i < m) {
        bRe[i] = y[i]
        i++
    }
    let aSeq = ComplexSeq(aRe, Array<Float64>(size, repeat: 0.0))
    let bSeq = ComplexSeq(bRe, Array<Float64>(size, repeat: 0.0))
    fftRadix2InPlace(aSeq, false)
    fftRadix2InPlace(bSeq, false)
    i = 0
    while (i < size) {
        let ar = aSeq.re[i]
        let ai = aSeq.im[i]
        let br = bSeq.re[i]
        let bi = bSeq.im[i]
        aSeq.re[i] = ar * br - ai * bi
        aSeq.im[i] = ar * bi + ai * br
        i++
    }
    fftRadix2InPlace(aSeq, true)
    let out = Array<Float64>(outLen, repeat: 0.0)
    i = 0
    while (i < outLen) {
        out[i] = aSeq.re[i]
        i++
    }
    out
}

func windowRaw(kind: String, n: Int64): Array<Float64> {
    if (n <= 0) {
        return Array<Float64>()
    }
    let out = Array<Float64>(n, repeat: 1.0)
    if (kind == "rect" || n == 1) {
        return out
    }
    var i: Int64 = 0
    while (i < n) {
        let t = TWO_PI * Float64(i) / Float64(n - 1)
        if (kind == "hann") {
            out[i] = 0.5 * (1.0 - cos(t))
        } else if (kind == "hamming") {
            out[i] = 0.54 - 0.46 * cos(t)
        } else if (kind == "blackman") {
            out[i] = 0.42 - 0.5 * cos(t) + 0.08 * cos(2.0 * t)
        } else {
            throw IllegalArgumentException(
                "未知窗函数 `${kind}`（支持 rect / hann / hamming / blackman）")
        }
        i++
    }
    out
}

/**
 * IIR 滤波（直接 I 型）
 *
 * `y[n] = (1/a[0]) · ( Σ_{i=0..p} b[i]·x[n-i] − Σ_{i=1..q} a[i]·y[n-i] )`
 *
 * `a[0]` 不能为 0（那是一条退化到无穷大的递推）。越界的 `x` 当 0 处理；
 * 输出长度与输入相同。
 */
func filterRaw(b: Array<Float64>, a: Array<Float64>, x: Array<Float64>): Array<Float64> {
    if (a.size == 0) {
        throw IllegalArgumentException("filter：分母系数 a 不能为空")
    }
    if (a[0] == 0.0) {
        throw IllegalArgumentException("filter：a[0] 不能为 0")
    }
    let n = x.size
    let out = Array<Float64>(n, repeat: 0.0)
    let a0 = a[0]
    var i: Int64 = 0
    while (i < n) {
        var s = 0.0
        var k: Int64 = 0
        while (k < b.size) {
            let idx = i - k
            if (idx >= 0) {
                s = s + b[k] * x[idx]
            }
            k++
        }
        k = 1
        while (k < a.size) {
            let idx = i - k
            if (idx >= 0) {
                s = s - a[k] * out[idx]
            }
            k++
        }
        out[i] = s / a0
        i++
    }
    out
}

func registerSignal(env: Environment): Unit {
    env.define("cangjie::fft", NativeFunc({ args =>
        guardedSignal({ =>
            arity(args, 1, "cangjie::fft")
            complexToLisp(fftAny(asComplexSeq(args[0], "cangjie::fft"), false))
        })
    }))

    env.define("cangjie::ifft", NativeFunc({ args =>
        guardedSignal({ =>
            arity(args, 1, "cangjie::ifft")
            complexToLisp(fftAny(asComplexSeq(args[0], "cangjie::ifft"), true))
        })
    }))

    // (cangjie::fft-magnitude x) —— 幅度谱 |X|
    env.define("cangjie::fft-magnitude", NativeFunc({ args =>
        guardedSignal({ =>
            arity(args, 1, "cangjie::fft-magnitude")
            let c = fftAny(asComplexSeq(args[0], "cangjie::fft-magnitude"), false)
            let mag = Array<Float64>(c.size(), repeat: 0.0)
            var i: Int64 = 0
            while (i < c.size()) {
                mag[i] = sqrt(c.re[i] * c.re[i] + c.im[i] * c.im[i])
                i++
            }
            LispValue.External(ndarrayFromFloats(mag))
        })
    }))

    // (cangjie::conv x y) —— 一维卷积（full）
    env.define("cangjie::conv", NativeFunc({ args =>
        guardedSignal({ =>
            arity(args, 2, "cangjie::conv")
            let x = floatsOf(asNDArray(args[0], "cangjie::conv"), "cangjie::conv")
            let y = floatsOf(asNDArray(args[1], "cangjie::conv"), "cangjie::conv")
            LispValue.External(ndarrayFromFloats(convRaw(x, y)))
        })
    }))

    // (cangjie::filter b a x) —— IIR 滤波
    env.define("cangjie::filter", NativeFunc({ args =>
        guardedSignal({ =>
            if (args.size != 3) {
                throw IllegalArgumentException("cangjie::filter 需要 (b a x) 三个参数")
            }
            let b = floatsOf(asNDArray(args[0], "cangjie::filter"), "cangjie::filter")
            let a = floatsOf(asNDArray(args[1], "cangjie::filter"), "cangjie::filter")
            let x = floatsOf(asNDArray(args[2], "cangjie::filter"), "cangjie::filter")
            LispValue.External(ndarrayFromFloats(filterRaw(b, a, x)))
        })
    }))

    // (cangjie::window kind n) —— 窗函数
    env.define("cangjie::window", NativeFunc({ args =>
        guardedSignal({ =>
            arity(args, 2, "cangjie::window")
            let kind = match (args[0]) {
                case Str(s) => s
                case _ => throw IllegalArgumentException("cangjie::window 的第一个参数是窗名")
            }
            let n = match (args[1]) {
                case Int(k) => k
                case _ => throw IllegalArgumentException("cangjie::window 的长度必须是整数")
            }
            LispValue.External(ndarrayFromFloats(windowRaw(kind, n)))
        })
    }))
}
