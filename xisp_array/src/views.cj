package ystyle::xisp_array

/**
 * 形状操作与视图
 *
 * 这三个操作默认返回**共享 buffer 的视图**（零拷贝），只有 `reshape` 在
 * 非连续数组上会先 `copy()` 连续化。这是 SciPy/NumPy 的语义，也是"切片是视图"
 * 这条要求的落点：改视图会改原数组。
 *
 * 出错一律抛 `IllegalArgumentException`，由注册层转成 Lisp 错误值 ——
 * 内部函数返回 `LispValue` 会让每一步都多一层 match，得不偿失。
 */

/**
 * 改变形状
 *
 * 元素总数必须不变。`-1` 表示该维由总数自动推断（最多一个）。
 *
 * 连续数组零拷贝；非连续（例如转置过）先连续化 —— 否则元素在 buffer 里的
 * 实际顺序与新形状不匹配，读出来就是错的。
 */
public func reshapeArray(a: NDArray, newDims: Array<Int64>): NDArray {
    var inferIdx: Int64 = -1
    var known: Int64 = 1
    var i = 0
    while (i < newDims.size) {
        let d = newDims[i]
        if (d == -1) {
            if (inferIdx >= 0) {
                throw IllegalArgumentException("reshape 只能有一个 -1 维")
            }
            inferIdx = i
        } else if (d < 0) {
            throw IllegalArgumentException("reshape 的维度不能为负：${d}")
        } else {
            known = known * d
        }
        i++
    }
    let total = a.size()
    let resolved = newDims.clone()
    if (inferIdx >= 0) {
        if (known <= 0 || total % known != 0) {
            throw IllegalArgumentException(
                "reshape 无法推断 -1 维：总数 ${total} 不能被 ${known} 整除")
        }
        resolved[inferIdx] = total / known
    }
    let got = shapeSize(resolved)
    if (got != total) {
        throw IllegalArgumentException(
            "reshape 元素总数必须一致：新形状 ${resolved} 共 ${got} 个，原数组 ${total} 个")
    }
    let base = if (a.isContiguous()) { a } else { a.copy() }
    NDArray(base.buf, base.off, resolved, contiguousStrides(resolved))
}

/**
 * 反转所有维度（返回视图）
 *
 * 2D 即矩阵转置；N 维是轴的完全反转。矩阵乘法要的"转置"用这一个就够，
 * 轴置换（permute）等有真实需求再做。
 */
public func transposeArray(a: NDArray): NDArray {
    let n = a.dims.size
    let nd = Array<Int64>(n, repeat: 0)
    let ns = Array<Int64>(n, repeat: 0)
    var i = 0
    while (i < n) {
        nd[i] = a.dims[n - 1 - i]
        ns[i] = a.steps[n - 1 - i]
        i++
    }
    NDArray(a.buf, a.off, nd, ns)
}

/**
 * 沿**第 0 维**取 `[start, end)` 的视图
 *
 * 1D 就是取子序列；2D 是取若干行；N 维是取若干个 (N-1) 维切片。
 * 返回的视图与原数组共享缓冲。
 */
public func sliceArray(a: NDArray, start: Int64, end: Int64): NDArray {
    if (a.dims.size == 0) {
        throw IllegalArgumentException("0 维数组不能切片")
    }
    let n = a.dims[0]
    if (start < 0 || end > n || start > end) {
        throw IllegalArgumentException(
            "slice 范围非法：[${start}, ${end})，第 0 维长度 ${n}")
    }
    let nd = a.dims.clone()
    nd[0] = end - start
    NDArray(a.buf, a.off + start * a.steps[0], nd, a.steps.clone())
}

/** 全 0 数组（Float64 —— 数值计算场景的默认类型，与 NumPy 一致） */
public func zerosArray(dims: Array<Int64>): NDArray {
    let n = shapeSize(dims)
    if (n < 0) {
        throw IllegalArgumentException("zeros 的维度不能为负：${dims}")
    }
    NDArray(Floats(Array<Float64>(n, repeat: 0.0)), 0, dims.clone(), contiguousStrides(dims))
}

/** 全 1 数组（Float64） */
public func onesArray(dims: Array<Int64>): NDArray {
    let n = shapeSize(dims)
    if (n < 0) {
        throw IllegalArgumentException("ones 的维度不能为负：${dims}")
    }
    NDArray(Floats(Array<Float64>(n, repeat: 1.0)), 0, dims.clone(), contiguousStrides(dims))
}

/** `arange`：整数版（`[start, end)`，步长正负均可） */
public func arangeInts(start: Int64, end: Int64, step: Int64): NDArray {
    if (step == 0) {
        throw IllegalArgumentException("arange 的步长不能为 0")
    }
    let count = arangeCount(Float64(start), Float64(end), Float64(step))
    let out = Array<Int64>(count, repeat: 0)
    var i: Int64 = 0
    while (i < count) {
        out[i] = start + i * step
        i++
    }
    NDArray(Ints(out), 0, [count], [1])
}

/** `arange`：浮点版 */
public func arangeFloats(start: Float64, end: Float64, step: Float64): NDArray {
    if (step == 0.0) {
        throw IllegalArgumentException("arange 的步长不能为 0")
    }
    let count = arangeCount(start, end, step)
    let out = Array<Float64>(count, repeat: 0.0)
    var i: Int64 = 0
    while (i < count) {
        out[i] = start + Float64(i) * step
        i++
    }
    NDArray(Floats(out), 0, [count], [1])
}

/**
 * arange 的元素个数
 *
 * `ceil(span/step)` 的直觉是对的，但**不能直接对商取整**：`1.0/0.1` 在浮点下是
 * `10.000000000000002`，直接 `ceil` 会得到 11；而 `0.9999999999999999` 又会少一个。
 * 所以先判断商离整数有多近（容差 1e-9），近就算整数，否则才向上取整。
 *
 * 这条不是理论洁癖：`arange(0, 1, 0.1)` 少一个元素会让后续统计全部错位。
 */
func arangeCount(start: Float64, end: Float64, step: Float64): Int64 {
    let span = end - start
    if (span == 0.0) {
        return 0
    }
    if ((span > 0.0 && step < 0.0) || (span < 0.0 && step > 0.0)) {
        return 0
    }
    let q = span / step
    if (q <= 0.0) {
        return 0
    }
    let epsilon = 1e-9
    let trunc = Int64(q + epsilon)
    if (Float64(trunc) + epsilon >= q) {
        trunc
    } else {
        trunc + 1
    }
}
