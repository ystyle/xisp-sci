package ystyle::xisp_array

import ystyle::xisp.types.*
import std.math.*

/**
 * 逐元素数学：实现 `LispExternalElementwise`
 *
 * `(sin arr)` 与 `(sin 1.0)` 是**同一个符号** —— core 的标量数学函数遇到数组时
 * 调这里，不需要 `array-sin` 这类第二套名字。
 *
 * ## 结果类型分两组
 *
 * | 组 | 函数 | 结果 dtype |
 * |---|---|---|
 * | 恒浮点 | `sin cos tan asin acos atan exp log log10 sqrt cbrt` | 恒 `float64` |
 * | 保留量纲 | `abs` / `sign` | 同入参 |
 * | 取整转整数 | `floor` / `ceil` | `int64` |
 *
 * `floor` / `ceil` 转整数与 core 的标量行为一致 —— 它们的主要用途是取下标与计数，
 * 返回浮点会让 `(nth arr (floor 3.7))` 直接类型错。
 *
 * ## 定义域外
 *
 * 返回 `nan` / `-inf` 而不是报错，与 core 的标量版本保持一致：一批数据里有一个
 * 非法值不该让整批计算中断。
 */

/** 一元浮点函数查表；不认识的返回 None */
func floatFnOf(fn: String): Option<(Float64) -> Float64> {
    if (fn == "sin") {
        return Some({ x => sin(x) })
    }
    if (fn == "cos") {
        return Some({ x => cos(x) })
    }
    if (fn == "tan") {
        return Some({ x => tan(x) })
    }
    if (fn == "asin") {
        return Some({ x => asin(x) })
    }
    if (fn == "acos") {
        return Some({ x => acos(x) })
    }
    if (fn == "atan") {
        return Some({ x => atan(x) })
    }
    if (fn == "exp") {
        return Some({ x => exp(x) })
    }
    if (fn == "sqrt") {
        return Some({ x => sqrt(x) })
    }
    if (fn == "cbrt") {
        return Some({ x => cbrt(x) })
    }
    // 对数在 0 处是 -inf、负数是 nan，与 core 的标量版本一致
    if (fn == "log") {
        return Some({ x =>
            if (x == 0.0) { -Float64.getInf() } else if (x < 0.0) { Float64.getNaN() } else { log(x) }
        })
    }
    if (fn == "log10") {
        return Some({ x =>
            if (x == 0.0) { -Float64.getInf() } else if (x < 0.0) { Float64.getNaN() } else { log10(x) }
        })
    }
    None
}

/** 定义域外返回 nan —— 仓颉 std.math 的 sqrt / asin 对越界入参会抛异常 */
func safeApplyFloat(f: (Float64) -> Float64, x: Float64): Float64 {
    try {
        f(x)
    } catch (e: Exception) {
        Float64.getNaN()
    }
}

/** 逐元素应用一元浮点函数，结果恒为 float64 数组 */
func mapToFloatArray(a: NDArray, f: (Float64) -> Float64): NDArray {
    let n = a.size()
    let out = Array<Float64>(n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = safeApplyFloat(f, readAsFloat(a, a.flatOfLinear(i)))
        i++
    }
    NDArray(Floats(out), 0, a.dims.clone(), contiguousStrides(a.dims))
}

/** `abs` / `sign`：保留入参 dtype */
func mapPreservingDtype(a: NDArray, fn: String): NDArray {
    let n = a.size()
    match (a.dtype) {
        case Ints =>
            let out = Array<Int64>(n, repeat: 0)
            var i: Int64 = 0
            while (i < n) {
                let v = readAsInt(a, a.flatOfLinear(i))
                out[i] = if (fn == "abs") {
                    if (v < 0) { -v } else { v }
                } else {
                    if (v > 0) { 1 } else if (v < 0) { -1 } else { 0 }
                }
                i++
            }
            NDArray(Ints(out), 0, a.dims.clone(), contiguousStrides(a.dims))
        case Floats =>
            let out = Array<Float64>(n, repeat: 0.0)
            var i: Int64 = 0
            while (i < n) {
                let v = readAsFloat(a, a.flatOfLinear(i))
                out[i] = if (fn == "abs") {
                    abs(v)
                } else {
                    if (v > 0.0) { 1.0 } else if (v < 0.0) { -1.0 } else { 0.0 }
                }
                i++
            }
            NDArray(Floats(out), 0, a.dims.clone(), contiguousStrides(a.dims))
        case Bools =>
            // Bool 数组的 abs / sign 没有定义；调用方在 applyElementwiseArray 里已挡掉，
            // 这里给回一份原值只是让 match 穷尽
            a.copy()
    }
}

/** `floor` / `ceil`：结果转 int64 */
func mapRoundToInt(a: NDArray, fn: String): NDArray {
    let n = a.size()
    let out = Array<Int64>(n, repeat: 0)
    var i: Int64 = 0
    while (i < n) {
        let x = readAsFloat(a, a.flatOfLinear(i))
        out[i] = Int64(if (fn == "floor") { floor(x) } else { ceil(x) })
        i++
    }
    NDArray(Ints(out), 0, a.dims.clone(), contiguousStrides(a.dims))
}

func applyElementwiseArray(a: NDArray, fn: String): Option<LispValue> {
    // Bool 数组没有有意义的数学函数
    if (a.dtype == DType.Bools) {
        return None
    }
    match (floatFnOf(fn)) {
        case Some(f) => return Some(LispValue.External(mapToFloatArray(a, f)))
        case None => ()
    }
    if (fn == "abs" || fn == "sign") {
        return Some(LispValue.External(mapPreservingDtype(a, fn)))
    }
    if (fn == "floor" || fn == "ceil") {
        return Some(LispValue.External(mapRoundToInt(a, fn)))
    }
    None
}

extend NDArray <: LispExternalElementwise {
    public func applyElementwise(fn: String): Option<LispValue> {
        applyElementwiseArray(this, fn)
    }
}
