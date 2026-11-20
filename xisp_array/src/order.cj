package ystyle::xisp_array

import ystyle::xisp.*
import ystyle::xisp.types.*
import std.collection.ArrayList
import std.math.*

/**
 * 排序、排序索引与累积归约
 *
 * ## 为什么这几个现在才补
 *
 * 它们是「拿着一列数据做探索」时几乎必然用到的第一步 —— 看分布要排序，
 * 算秩要排序，画累积曲线要 `cumsum`。之前没有，用户只能自己写循环。
 *
 * ## NaN 排在最后
 *
 * 这是 R 的默认约定（`sort(x, na.last = TRUE)`），也是最安全的：把 NaN 当成
 * 「最小的数」会让缺失值悄悄污染 `head`，当成「最大的」会污染 `tail`。
 * 单独堆到末尾至少不会伪装成有效数据。
 *
 * 更关键的是：**NaN 在浮点比较里既不小于也不大于任何数**，直接用默认比较器
 * 排序会得到依赖实现的不确定顺序 —— 同一份数据两次跑出不同结果，是最难查的 bug。
 * 所以这里先把 NaN 挑出去，排完再拼回末尾。
 *
 * ## 为什么自己写归并排序
 *
 * 需要**稳定**（相等元素保持原顺序，`order` 的语义全靠它），并且要能自定义
 * NaN 的位置。归并排序两样都天然满足，代码也短。
 */

/** 把 NDArray 摊成一维 Float64 序列（非连续视图走 `at`，不去动底层缓冲） */
func floatsOf(a: NDArray): Array<Float64> {
    let n = a.length()
    let out = Array<Float64>(n, repeat: 0.0)
    var i: Int64 = 0
    while (i < n) {
        out[i] = match (a.at(i)) {
            case Float(x) => x
            case Int(x) => Float64(x)
            case _ => Float64.getNaN()
        }
        i++
    }
    out
}

/** 稳定归并：把 `a[lo..hi)` 排好序 */
func mergeSortRange(a: Array<Float64>, lo: Int64, hi: Int64, desc: Bool): Unit {
    if (hi - lo <= 1) {
        return
    }
    let mid = lo + (hi - lo) / 2
    mergeSortRange(a, lo, mid, desc)
    mergeSortRange(a, mid, hi, desc)
    let tmp = Array<Float64>(hi - lo, repeat: 0.0)
    var i = lo
    var j = mid
    var k: Int64 = 0
    while (i < mid && j < hi) {
        // 相等时取左边 —— 这就是「稳定」的定义
        let takeLeft = if (desc) { a[i] >= a[j] } else { a[i] <= a[j] }
        if (takeLeft) {
            tmp[k] = a[i]
            i++
        } else {
            tmp[k] = a[j]
            j++
        }
        k++
    }
    while (i < mid) {
        tmp[k] = a[i]
        i++
        k++
    }
    while (j < hi) {
        tmp[k] = a[j]
        j++
        k++
    }
    k = 0
    while (k < tmp.size) {
        a[lo + k] = tmp[k]
        k++
    }
}

/** 排序（NaN 一律排到末尾，不参与比较） */
func sortRaw(values: Array<Float64>, desc: Bool): Array<Float64> {
    let finite = ArrayList<Float64>()
    var nanCount: Int64 = 0
    for (x in values) {
        if (x != x) {
            nanCount++
        } else {
            finite.add(x)
        }
    }
    let arr = finite.toArray()
    mergeSortRange(arr, 0, arr.size, desc)
    if (nanCount == 0) {
        return arr
    }
    let out = Array<Float64>(arr.size + nanCount, repeat: 0.0)
    var i: Int64 = 0
    while (i < arr.size) {
        out[i] = arr[i]
        i++
    }
    while (i < out.size) {
        out[i] = Float64.getNaN()
        i++
    }
    out
}

/** 稳定归并（按 `vals` 的比较结果排 `idx`） */
func mergeSortIdx(idx: Array<Int64>, vals: Array<Float64>, lo: Int64, hi: Int64, desc: Bool): Unit {
    if (hi - lo <= 1) {
        return
    }
    let mid = lo + (hi - lo) / 2
    mergeSortIdx(idx, vals, lo, mid, desc)
    mergeSortIdx(idx, vals, mid, hi, desc)
    let tmp = Array<Int64>(hi - lo, repeat: 0)
    var i = lo
    var j = mid
    var k: Int64 = 0
    while (i < mid && j < hi) {
        let vi = vals[idx[i]]
        let vj = vals[idx[j]]
        let takeLeft = if (desc) { vi >= vj } else { vi <= vj }
        if (takeLeft) {
            tmp[k] = idx[i]
            i++
        } else {
            tmp[k] = idx[j]
            j++
        }
        k++
    }
    while (i < mid) {
        tmp[k] = idx[i]
        i++
        k++
    }
    while (j < hi) {
        tmp[k] = idx[j]
        j++
        k++
    }
    k = 0
    while (k < tmp.size) {
        idx[lo + k] = tmp[k]
        k++
    }
}

/**
 * 排序索引：`order(x)[i]` 是「排序后第 i 个元素在原数组里的下标」
 *
 * 用途是**同时重排多列**：`(cangjie::order col)` 拿到索引后，其它列按同一份
 * 索引重排，行与行的对应关系才不会错。直接排序每一列会打乱这个对应关系。
 *
 * 含 NaN 的元素在返回的索引里排最后。
 */
func orderRaw(values: Array<Float64>, desc: Bool): Array<Int64> {
    let finiteIdx = ArrayList<Int64>()
    let finiteVal = ArrayList<Float64>()
    let nanIdx = ArrayList<Int64>()
    var i: Int64 = 0
    while (i < values.size) {
        if (values[i] != values[i]) {
            nanIdx.add(i)
        } else {
            finiteIdx.add(i)
            finiteVal.add(values[i])
        }
        i++
    }
    let vals = finiteVal.toArray()
    let n = vals.size
    // 排序的是**压缩后**的位置 0..n-1；原始下标最后再映射回去。
    // 直接拿原始下标当 `vals` 的索引会越界 —— 遇到 NaN 时压缩后的数组比原数组短，
    // 而原始下标是按完整长度编的。
    let pos = Array<Int64>(n, repeat: 0)
    i = 0
    while (i < n) {
        pos[i] = i
        i++
    }
    mergeSortIdx(pos, vals, 0, n, desc)
    let idx = Array<Int64>(n, repeat: 0)
    i = 0
    while (i < n) {
        idx[i] = finiteIdx[pos[i]]
        i++
    }
    if (nanIdx.size == 0) {
        return idx
    }
    let out = Array<Int64>(idx.size + nanIdx.size, repeat: 0)
    i = 0
    while (i < idx.size) {
        out[i] = idx[i]
        i++
    }
    var k: Int64 = 0
    while (k < nanIdx.size) {
        out[i] = nanIdx[k]
        i++
        k++
    }
    out
}

/** 累积和 */
func cumsumRaw(values: Array<Float64>): Array<Float64> {
    let out = Array<Float64>(values.size, repeat: 0.0)
    var acc = 0.0
    var i: Int64 = 0
    while (i < values.size) {
        acc = acc + values[i]
        out[i] = acc
        i++
    }
    out
}

/** 累积积 */
func cumprodRaw(values: Array<Float64>): Array<Float64> {
    let out = Array<Float64>(values.size, repeat: 0.0)
    var acc = 1.0
    var i: Int64 = 0
    while (i < values.size) {
        acc = acc * values[i]
        out[i] = acc
        i++
    }
    out
}

/** 一维数组校验：这几个函数对矩阵没有明确定义，报错比默默 flatten 好 */
func requireOneDim(a: NDArray, who: String): Unit {
    if (a.rank() != 1) {
        throw IllegalArgumentException(
            "${who} 只接受一维数组，得到 ${a.rank()} 维（形状 ${a.display()}）")
    }
}

/**
 * 秩（并列取**平均秩**）
 *
 * R 的 `rank()` 默认 `ties.method = "average"`，这里跟它一致：三个并列的观测
 * 应当占据第 3、4、5 名，每个拿 4 分 —— 而不是「谁先出现谁拿 3」。
 * 并列处理选错，非参数检验（Wilcoxon / 秩相关）的结果就会系统性偏。
 *
 * `NaN` 位置的秩是 `NaN`（R 的 `na.last` 行为），不参与排序也不占用名次。
 */
public func ranksRaw(values: Array<Float64>): Array<Float64> {
    let idx = orderRaw(values, false)
    let out = Array<Float64>(values.size, repeat: 0.0)
    var i: Int64 = 0
    while (i < idx.size) {
        // 排序后的序列里，相邻且值相等的归为同一组
        var j = i
        while (j + 1 < idx.size && values[idx[j + 1]] == values[idx[j]]) {
            j++
        }
        let avg = (Float64(i + 1) + Float64(j + 1)) / 2.0
        var k = i
        while (k <= j) {
            out[idx[k]] = avg
            k++
        }
        i = j + 1
    }
    // NaN 位置单独覆盖回去
    i = 0
    while (i < values.size) {
        if (values[i] != values[i]) {
            out[i] = Float64.getNaN()
        }
        i++
    }
    out
}

// ───────────────────────── Lisp 接口 ─────────────────────────

func registerOrder(env: Environment): Unit {
    // (cangjie::sort x) —— 升序
    env.define("cangjie::sort", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::sort")
            let a = asNDArray(args[0], "cangjie::sort")
            requireOneDim(a, "cangjie::sort")
            LispValue.External(ndarrayFromFloats(sortRaw(floatsOf(a), false)))
        })
    }))

    // (cangjie::sort-desc x) —— 降序
    env.define("cangjie::sort-desc", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::sort-desc")
            let a = asNDArray(args[0], "cangjie::sort-desc")
            requireOneDim(a, "cangjie::sort-desc")
            LispValue.External(ndarrayFromFloats(sortRaw(floatsOf(a), true)))
        })
    }))

    // (cangjie::order x) —— 排序索引
    env.define("cangjie::order", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::order")
            let a = asNDArray(args[0], "cangjie::order")
            requireOneDim(a, "cangjie::order")
            LispValue.External(ndarrayFromInts(orderRaw(floatsOf(a), false)))
        })
    }))

    // (cangjie::cumsum x) —— 累积和
    env.define("cangjie::cumsum", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::cumsum")
            let a = asNDArray(args[0], "cangjie::cumsum")
            requireOneDim(a, "cangjie::cumsum")
            LispValue.External(ndarrayFromFloats(cumsumRaw(floatsOf(a))))
        })
    }))

    // (cangjie::ranks x) —— 秩（并列取平均秩）
    env.define("cangjie::ranks", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::ranks")
            let a = asNDArray(args[0], "cangjie::ranks")
            requireOneDim(a, "cangjie::ranks")
            LispValue.External(ndarrayFromFloats(ranksRaw(floatsOf(a))))
        })
    }))

    // (cangjie::cumprod x) —— 累积积
    env.define("cangjie::cumprod", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::cumprod")
            let a = asNDArray(args[0], "cangjie::cumprod")
            requireOneDim(a, "cangjie::cumprod")
            LispValue.External(ndarrayFromFloats(cumprodRaw(floatsOf(a))))
        })
    }))
}
