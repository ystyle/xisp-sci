package ystyle::xisp_num

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 数值方法：插值、多项式拟合、数值积分、一维优化、ODE
 *
 * ## 接口稳定性
 *
 * 每个符号的**调用形式**是契约，内部算法可换：
 *
 * - `fmin` 现在是黄金分割，将来换 Brent 不影响调用方
 * - `rk4` 是固定步长，将来加自适应版本时另开符号（`ode45` 之类），不改 `rk4`
 * - `polyfit` 现在用正规方程，将来换 QR 也对调用方透明
 *
 * 这与用户对 FFT 的要求一致：**Lisp 层写法不随内部算法变**。
 */

let NUM_SYMBOLS: Array<String> = [
    "cangjie::interp1", "cangjie::polyfit", "cangjie::polyval",
    "cangjie::trapz", "cangjie::simpson", "cangjie::fmin", "cangjie::rk4"]

public func numDomain(): LispCapability {
    SimpleCapability(
        "num",
        NUM_SYMBOLS,
        { ctx => registerNum(ctx) },
        // `fmin` / `rk4` 要回调 Lisp 函数 —— 那是"执行宿主代码"，不是纯数据运算，
        // 所以声明为 escapable。这与 array / linalg 的纯计算域不同。
        escapable: true,
        hostPolicy: false)
}

func guardedNum(action: () -> LispValue): LispValue {
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

func numOf(v: LispValue, who: String): Float64 {
    match (v) {
        case Float(x) => x
        case Int(i) => Float64(i)
        case _ => throw IllegalArgumentException("${who} 需要数值，得到 ${v.toString()}")
    }
}

/**
 * 一维线性插值
 *
 * `x` 必须**严格升序**（自动检查）：插值要求能唯一确定区间，乱序的 x 会让
 * 二分查找给出错误的邻居。
 */
func interp1Raw(x: Array<Float64>, y: Array<Float64>, xi: Array<Float64>): Array<Float64> {
    let n = x.size
    if (n != y.size) {
        throw IllegalArgumentException("interp1：x 与 y 长度不一致（${n} 与 ${y.size}）")
    }
    if (n < 2) {
        throw IllegalArgumentException("interp1：至少需要 2 个数据点")
    }
    var i: Int64 = 1
    while (i < n) {
        if (x[i] <= x[i - 1]) {
            throw IllegalArgumentException(
                "interp1：x 必须严格升序，但 x[${i - 1}]=${x[i - 1]} >= x[${i}]=${x[i]}")
        }
        i++
    }
    let out = Array<Float64>(xi.size, repeat: 0.0)
    var k: Int64 = 0
    while (k < xi.size) {
        let t = xi[k]
        if (t <= x[0]) {
            out[k] = y[0]
        } else if (t >= x[n - 1]) {
            out[k] = y[n - 1]
        } else {
            // 二分找区间
            var lo: Int64 = 0
            var hi: Int64 = n - 1
            while (hi - lo > 1) {
                let mid = (lo + hi) / 2
                if (x[mid] <= t) {
                    lo = mid
                } else {
                    hi = mid
                }
            }
            let dx = x[hi] - x[lo]
            let w = (t - x[lo]) / dx
            out[k] = y[lo] * (1.0 - w) + y[hi] * w
        }
        k++
    }
    out
}

/**
 * 多项式拟合（最小二乘）
 *
 * 返回**从高次到低次**的系数（与 `polyval` 及常见习惯一致）：`c[0]·x^d + … + c[d]`。
 *
 * 用正规方程 `VᵀV c = Vᵀy` 直接解。对低阶（≤ 6）没问题；高阶时 Vandermonde 矩阵
 * 条件数会爆炸，那时应该换正交多项式基 —— 接口不变，内部换即可。
 */
func polyfitRaw(x: Array<Float64>, y: Array<Float64>, degree: Int64): Array<Float64> {
    let n = x.size
    if (n != y.size) {
        throw IllegalArgumentException("polyfit：x 与 y 长度不一致")
    }
    if (degree < 0) {
        throw IllegalArgumentException("polyfit：阶数不能为负")
    }
    if (n < degree + 1) {
        throw IllegalArgumentException(
            "polyfit：${n} 个点不足以拟合 ${degree} 阶多项式（至少需要 ${degree + 1} 个）")
    }
    let m = degree + 1
    // 构造 VᵀV 与 Vᵀy
    let ata = Array<Float64>(m * m, repeat: 0.0)
    let aty = Array<Float64>(m, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        // 行 V[i] = [x^0, x^1, …, x^d]，但最终系数要倒序输出
        let powers = Array<Float64>(m, repeat: 1.0)
        var p: Int64 = 1
        while (p < m) {
            powers[p] = powers[p - 1] * x[i]
            p++
        }
        var r: Int64 = 0
        while (r < m) {
            aty[r] = aty[r] + powers[r] * y[i]
            var c: Int64 = 0
            while (c < m) {
                ata[r * m + c] = ata[r * m + c] + powers[r] * powers[c]
                c++
            }
            r++
        }
        i++
    }
    // 高斯消元（部分主元）解 ata · coef = aty
    let coef = gaussSolve(m, ata, aty)
    // 升幂 → 降幂
    let out = Array<Float64>(m, repeat: 0.0)
    i = 0
    while (i < m) {
        out[i] = coef[m - 1 - i]
        i++
    }
    out
}

/** 高斯消元（部分主元），`a` 与 `b` 会被当作工作区 */
func gaussSolve(n: Int64, a: Array<Float64>, b: Array<Float64>): Array<Float64> {
    let x = b.clone()
    var k: Int64 = 0
    while (k < n) {
        // 选主元
        var p = k
        var maxV = abs(a[k * n + k])
        var i = k + 1
        while (i < n) {
            let v = abs(a[i * n + k])
            if (v > maxV) {
                maxV = v
                p = i
            }
            i++
        }
        if (maxV == 0.0) {
            throw IllegalArgumentException("polyfit：正规方程奇异（数据点共线或阶数过高）")
        }
        if (p != k) {
            var j: Int64 = 0
            while (j < n) {
                let t = a[k * n + j]
                a[k * n + j] = a[p * n + j]
                a[p * n + j] = t
                j++
            }
            let tb = x[k]
            x[k] = x[p]
            x[p] = tb
        }
        let pivot = a[k * n + k]
        i = k + 1
        while (i < n) {
            let f = a[i * n + k] / pivot
            a[i * n + k] = 0.0
            var j = k + 1
            while (j < n) {
                a[i * n + j] = a[i * n + j] - f * a[k * n + j]
                j++
            }
            x[i] = x[i] - f * x[k]
            i++
        }
        k++
    }
    // 回代
    var kk = n - 1
    while (kk >= 0) {
        var s = x[kk]
        var j = kk + 1
        while (j < n) {
            s = s - a[kk * n + j] * x[j]
            j++
        }
        x[kk] = s / a[kk * n + kk]
        kk--
    }
    x
}

/** 多项式求值（Horner），系数从高次到低次 */
func polyvalRaw(coef: Array<Float64>, t: Float64): Float64 {
    if (coef.size == 0) {
        return 0.0
    }
    var r = coef[0]
    var i: Int64 = 1
    while (i < coef.size) {
        r = r * t + coef[i]
        i++
    }
    r
}

/** 梯形积分；`dx` 是等间距步长 */
func trapzUniform(y: Array<Float64>, dx: Float64): Float64 {
    let n = y.size
    if (n < 2) {
        return 0.0
    }
    var s = 0.0
    var i: Int64 = 0
    while (i < n - 1) {
        s = s + (y[i] + y[i + 1]) * 0.5 * dx
        i++
    }
    s
}

/** 梯形积分（给定 x）；x 不要求等距 */
func trapzVar(x: Array<Float64>, y: Array<Float64>): Float64 {
    let n = x.size
    if (n != y.size) {
        throw IllegalArgumentException("trapz：x 与 y 长度不一致")
    }
    if (n < 2) {
        return 0.0
    }
    var s = 0.0
    var i: Int64 = 0
    while (i < n - 1) {
        s = s + (y[i] + y[i + 1]) * 0.5 * (x[i + 1] - x[i])
        i++
    }
    s
}

/**
 * Simpson 法则
 *
 * 要求**等距且点数为奇数**（偶数个区间）。不满足时报错而不是退回梯形 ——
 * 静默降级会让调用方以为拿到了 Simpson 的精度。
 */
func simpsonRaw(y: Array<Float64>, dx: Float64): Float64 {
    let n = y.size
    if (n < 3) {
        throw IllegalArgumentException("simpson：至少需要 3 个点")
    }
    if (n % 2 == 0) {
        throw IllegalArgumentException(
            "simpson：点数必须为奇数（偶数个区间），当前 ${n} 个点。请用 trapz 或调整采样")
    }
    var s = y[0] + y[n - 1]
    var i: Int64 = 1
    while (i < n - 1) {
        if (i % 2 == 1) {
            s = s + 4.0 * y[i]
        } else {
            s = s + 2.0 * y[i]
        }
        i++
    }
    s * dx / 3.0
}

/**
 * 黄金分割法求一维极小值
 *
 * 只在 `[a, b]` 上找**单峰**极值。多峰函数会落到其中一个峰，这是算法的前提
 * 而不是 bug —— 文档里说清楚比假装全能好。
 */
func goldenSectionMin(f: (Float64) -> Float64, a0: Float64, b0: Float64,
                      tol: Float64, maxIter: Int64): Float64 {
    let gr = (sqrt(5.0) - 1.0) / 2.0
    var a = a0
    var b = b0
    if (a > b) {
        let t = a
        a = b
        b = t
    }
    var c = b - gr * (b - a)
    var d = a + gr * (b - a)
    var fc = f(c)
    var fd = f(d)
    var iter: Int64 = 0
    while (abs(b - a) > tol && iter < maxIter) {
        if (fc < fd) {
            b = d
            d = c
            fd = fc
            c = b - gr * (b - a)
            fc = f(c)
        } else {
            a = c
            c = d
            fc = fd
            d = a + gr * (b - a)
            fd = f(d)
        }
        iter++
    }
    (a + b) / 2.0
}

/**
 * 四阶 Runge-Kutta 单步
 *
 * `f(t, y)` 返回 `dy/dt`。固定步长 —— 刚性方程或需要误差控制时应该用自适应版本
 *（另开符号），不改 `rk4`。
 */
func rk4Raw(f: (Float64, Float64) -> Float64, y0: Float64,
            t0: Float64, t1: Float64, h: Float64): (Array<Float64>, Array<Float64>) {
    if (h <= 0.0) {
        throw IllegalArgumentException("rk4：步长必须为正")
    }
    if (t1 <= t0) {
        throw IllegalArgumentException("rk4：终止时间必须大于起始时间")
    }
    let steps = Int64(ceil((t1 - t0) / h))
    let ts = Array<Float64>(steps + 1, repeat: 0.0)
    let ys = Array<Float64>(steps + 1, repeat: 0.0)
    var t = t0
    var y = y0
    ts[0] = t
    ys[0] = y
    var i: Int64 = 1
    while (i <= steps) {
        // 最后一步不要越过 t1
        let step = if (i == steps && t + h > t1) { t1 - t } else { h }
        let k1 = f(t, y)
        let k2 = f(t + step / 2.0, y + step / 2.0 * k1)
        let k3 = f(t + step / 2.0, y + step / 2.0 * k2)
        let k4 = f(t + step, y + step * k3)
        y = y + step / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
        t = if (i == steps && t + h > t1) { t1 } else { t + h }
        ts[i] = t
        ys[i] = y
        i++
    }
    (ts, ys)
}

func registerNum(ctx: CapabilityContext): Unit {
    let env = ctx.env

    // (cangjie::interp1 x y xi) —— 线性插值
    env.define("cangjie::interp1", NativeFunc({ args =>
        guardedNum({ =>
            if (args.size != 3) {
                throw IllegalArgumentException("cangjie::interp1 需要 (x y xi) 三个参数")
            }
            let x = floatsOf(asNDArray(args[0], "cangjie::interp1"), "cangjie::interp1")
            let y = floatsOf(asNDArray(args[1], "cangjie::interp1"), "cangjie::interp1")
            let xi = floatsOf(asNDArray(args[2], "cangjie::interp1"), "cangjie::interp1")
            LispValue.External(ndarrayFromFloats(interp1Raw(x, y, xi)))
        })
    }))

    // (cangjie::polyfit x y degree) → 系数（降幂）
    env.define("cangjie::polyfit", NativeFunc({ args =>
        guardedNum({ =>
            arity(args, 3, "cangjie::polyfit")
            let x = floatsOf(asNDArray(args[0], "cangjie::polyfit"), "cangjie::polyfit")
            let y = floatsOf(asNDArray(args[1], "cangjie::polyfit"), "cangjie::polyfit")
            let d = match (args[2]) {
                case Int(k) => k
                case _ => throw IllegalArgumentException("polyfit 的阶数必须是整数")
            }
            LispValue.External(ndarrayFromFloats(polyfitRaw(x, y, d)))
        })
    }))

    // (cangjie::polyval coef x) —— 多项式求值（x 可以是标量或数组）
    env.define("cangjie::polyval", NativeFunc({ args =>
        guardedNum({ =>
            arity(args, 2, "cangjie::polyval")
            let coef = floatsOf(asNDArray(args[0], "cangjie::polyval"), "cangjie::polyval")
            match (args[1]) {
                case External(e) =>
                    match (e) {
                        case a: NDArray =>
                            let xs = floatsOf(a.copy(), "cangjie::polyval")
                            let out = Array<Float64>(xs.size, repeat: 0.0)
                            var i: Int64 = 0
                            while (i < xs.size) {
                                out[i] = polyvalRaw(coef, xs[i])
                                i++
                            }
                            LispValue.External(ndarrayFromFloats(out))
                        case _ => throw IllegalArgumentException("cangjie::polyval 的 x 需要 ndarray 或数值")
                    }
                case _ => LispValue.Float(polyvalRaw(coef, numOf(args[1], "cangjie::polyval")))
            }
        })
    }))

    // (cangjie::trapz y [dx]) 或 (cangjie::trapz x y)
    env.define("cangjie::trapz", NativeFunc({ args =>
        guardedNum({ =>
            if (args.size == 1 || args.size == 2) {
                let y = floatsOf(asNDArray(args[0], "cangjie::trapz"), "cangjie::trapz")
                if (args.size == 1) {
                    return LispValue.Float(trapzUniform(y, 1.0))
                }
                // 第二个参数是数值 → dx；是数组 → 变距积分
                match (args[1]) {
                    case External(_) =>
                        let x = floatsOf(asNDArray(args[1], "cangjie::trapz"), "cangjie::trapz")
                        LispValue.Float(trapzVar(x, y))
                    case _ => LispValue.Float(trapzUniform(y, numOf(args[1], "cangjie::trapz")))
                }
            } else {
                throw IllegalArgumentException("cangjie::trapz 需要 (y) / (y dx) / (x y)")
            }
        })
    }))

    // (cangjie::simpson y dx)
    env.define("cangjie::simpson", NativeFunc({ args =>
        guardedNum({ =>
            arity(args, 2, "cangjie::simpson")
            let y = floatsOf(asNDArray(args[0], "cangjie::simpson"), "cangjie::simpson")
            LispValue.Float(simpsonRaw(y, numOf(args[1], "cangjie::simpson")))
        })
    }))

    // (cangjie::fmin f a b [tol]) —— 找 [a,b] 上单峰极小
    env.define("cangjie::fmin", NativeFunc({ args =>
        guardedNum({ =>
            if (args.size < 3 || args.size > 4) {
                throw IllegalArgumentException("cangjie::fmin 需要 (f a b [tol])")
            }
            let fn = args[0]
            let a = numOf(args[1], "cangjie::fmin")
            let b = numOf(args[2], "cangjie::fmin")
            let tol = if (args.size == 4) { numOf(args[3], "cangjie::fmin") } else { 1e-8 }
            let evalFn: (Float64) -> Float64 = { t =>
                let callArgs = ArrayList<LispValue>()
                callArgs.add(LispValue.Float(t))
                match (ctx.invoke(fn, callArgs)) {
                    case Float(v) => v
                    case Int(v) => Float64(v)
                    case other => throw IllegalArgumentException(
                        "fmin 的目标函数必须返回数值，得到 ${other.toString()}")
                }
            }
            LispValue.Float(goldenSectionMin(evalFn, a, b, tol, 200))
        })
    }))

    // (cangjie::rk4 f y0 t0 t1 h) → {"t": …, "y": …}
    env.define("cangjie::rk4", NativeFunc({ args =>
        guardedNum({ =>
            arity(args, 5, "cangjie::rk4")
            let fn = args[0]
            let y0 = numOf(args[1], "cangjie::rk4")
            let t0 = numOf(args[2], "cangjie::rk4")
            let t1 = numOf(args[3], "cangjie::rk4")
            let h = numOf(args[4], "cangjie::rk4")
            let evalFn: (Float64, Float64) -> Float64 = { t, y =>
                let callArgs = ArrayList<LispValue>()
                callArgs.add(LispValue.Float(t))
                callArgs.add(LispValue.Float(y))
                match (ctx.invoke(fn, callArgs)) {
                    case Float(v) => v
                    case Int(v) => Float64(v)
                    case other => throw IllegalArgumentException(
                        "rk4 的右端函数必须返回数值，得到 ${other.toString()}")
                }
            }
            let r = rk4Raw(evalFn, y0, t0, t1, h)
            let out = HashMap<String, LispValue>()
            out.add("t", LispValue.External(ndarrayFromFloats(r[0])))
            out.add("y", LispValue.External(ndarrayFromFloats(r[1])))
            LispValue.HashMap(out)
        })
    }))
}
