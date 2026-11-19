package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 描述统计
 *
 * ## 缺失值
 *
 * 所有函数**跳过 `NaN`**（`xisp_io` 读 CSV 时把空单元格填成 `NaN`）。
 * 这是唯一不会把"缺失"和"真的是 0"混为一谈的做法：`[1, NaN, 3]` 的均值是 2
 * 而不是 1.333。
 *
 * ## 空输入
 *
 * 一律返回 `NaN` —— "没有数据的均值"是未定义的，返回 0 会让调用方算出一个
 * 看起来正常的结果。
 *
 * ## 标准差用哪个自由度
 *
 * `cangjie::std` 用**样本**标准差（除以 `n-1`），`cangjie::std-pop` 用总体
 *（除以 `n`）。默认选样本，是因为数据分析里手上的数据几乎总是样本；
 * **注意这与 NumPy 相反**（`np.std` 默认 `ddof=0` 即总体）。
 */

let STATS_SYMBOLS: Array<String> = [
    "cangjie::mean", "cangjie::median", "cangjie::std", "cangjie::std-pop",
    "cangjie::var", "cangjie::quantile", "cangjie::corr", "cangjie::cov",
    "cangjie::histogram", "cangjie::min", "cangjie::max",
    "cangjie::group-by", "cangjie::group-agg",
    "cangjie::t-test1", "cangjie::t-test2", "cangjie::ci",
    "cangjie::five-num", "cangjie::corr-matrix",
    // 分布函数族（18 个）由 dist_ops.cj 注册，声明并在这里保持「清单 = 实现」
    "cangjie::norm-pdf", "cangjie::norm-cdf", "cangjie::norm-quantile",
    "cangjie::t-pdf", "cangjie::t-cdf", "cangjie::t-quantile",
    "cangjie::chisq-pdf", "cangjie::chisq-cdf", "cangjie::chisq-quantile",
    "cangjie::f-pdf", "cangjie::f-cdf", "cangjie::f-quantile",
    "cangjie::pois-pmf", "cangjie::pois-cdf", "cangjie::pois-quantile",
    "cangjie::binom-pmf", "cangjie::binom-cdf", "cangjie::binom-quantile"]

public func statsDomain(): LispCapability {
    SimpleCapability(
        "stats",
        STATS_SYMBOLS,
        { ctx => registerStats(ctx) },
        // 纯计算，不触及宿主资源
        // `group-agg` 要回调 Lisp 函数 —— 那是"执行宿主代码"而不是纯数据运算，
        // 所以标 escapable。与 num 域（fmin / rk4）同理。
        escapable: true,
        hostPolicy: false)
}

func guardedStats(action: () -> LispValue): LispValue {
    try {
        action()
    } catch (e: IllegalArgumentException) {
        LispValue.Error(XispError(ErrorType.TypeError, e.message))
    } catch (e: Exception) {
        LispValue.Error(XispError(ErrorType.RuntimeError, e.message))
    }
}

/** 一个数值转 `Float64`；非数值报错 */
func numOf(v: LispValue, who: String): Float64 {
    match (v) {
        case Int(i) => Float64(i)
        case Float(i2) => i2
        case _ => throw IllegalArgumentException(
            "${who} 需要数值，得到 ${v.toString()}")
    }
}

/**
 * 把参数转成 `Float64` 数组
 *
 * 同时接受 ndarray 与普通列表 —— `(cangjie::mean arr)` 与 `(cangjie::mean [1 2 3])`
 * 都该能用，不该因为数据装在不同容器里就分成两套函数。
 */
func asFloatValues(v: LispValue, who: String): Array<Float64> {
    let out = ArrayList<Float64>()
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    // **快路径**：连续 float64 直接拿底层数组的引用，零拷贝。
                    // 慢路径（int64 / bool / 非连续视图）才逐个转换 —— 后者在
                    // 10 万元素上要 6~7 ms，而计算本身只要 0.06 ms。
                    match (a.floatView()) {
                        case Some(data) => return data
                        case None => ()
                    }
                    var i: Int64 = 0
                    let n = a.length()
                    while (i < n) {
                        out.add(numOf(a.at(i), who))
                        i++
                    }
                case _ => throw IllegalArgumentException(
                    "${who} 需要 ndarray 或数值列表，得到外部值 ${e.typeName}")
            }
        case Cons(_) =>
            var cur = v
            var go = true
            while (go) {
                match (cur) {
                    case Cons(cell) =>
                        out.add(numOf(cell.car, who))
                        cur = cell.cdr
                    case _ => go = false
                }
            }
        case Nil => ()
        case _ => throw IllegalArgumentException(
            "${who} 需要 ndarray 或数值列表，得到 ${v.toString()}")
    }
    out.toArray()
}

/**
 * 去掉 NaN —— 缺失值不参与统计
 *
 * **没有 NaN 时直接返回原数组**（不复制）。绝大多数数据没有缺失值，
 * 为它们付一次全量拷贝没有道理。
 */
func finiteOf(values: Array<Float64>): Array<Float64> {
    var hasNaN = false
    for (v in values) {
        if (v.isNaN()) {
            hasNaN = true
            break
        }
    }
    if (!hasNaN) {
        return values
    }
    let out = ArrayList<Float64>()
    for (v in values) {
        if (!v.isNaN()) {
            out.add(v)
        }
    }
    out.toArray()
}

func meanOf(values: Array<Float64>): Float64 {
    if (values.size == 0) {
        return Float64.getNaN()
    }
    var s = 0.0
    for (v in values) {
        s = s + v
    }
    s / Float64(values.size)
}

/**
 * 方差
 *
 * `ddof = 0` 是总体方差（除以 n），`ddof = 1` 是样本方差（除以 n-1）。
 * `n - ddof <= 0` 时返回 `NaN` —— 一个样本算不出样本方差，报 `NaN` 比报错
 * 更适合批量计算（一行数据一个样本时不该整批中断）。
 */
func varianceOf(values: Array<Float64>, ddof: Int64): Float64 {
    let n = Float64(values.size)
    if (Float64(values.size - ddof) <= 0.0) {
        return Float64.getNaN()
    }
    let m = meanOf(values)
    var s = 0.0
    for (v in values) {
        let d = v - m
        s = s + d * d
    }
    s / (n - Float64(ddof))
}

/** 升序排序（插入序由调用方保证稳定；这里用简单归并避免原地修改入参） */
func sortedCopy(values: Array<Float64>): Array<Float64> {
    let arr = values.clone()
    // 归并排序：稳定的 O(n log n)，避免快速排序在近似有序数据上的最坏情况
    var width: Int64 = 1
    let n = arr.size
    let tmp = Array<Float64>(n, repeat: 0.0)
    while (width < n) {
        var i: Int64 = 0
        while (i < n) {
            let mid = if (i + width < n) { i + width } else { n }
            let end = if (i + 2 * width < n) { i + 2 * width } else { n }
            var p = i
            var q = mid
            var k = i
            while (p < mid && q < end) {
                if (arr[p] <= arr[q]) {
                    tmp[k] = arr[p]
                    p++
                } else {
                    tmp[k] = arr[q]
                    q++
                }
                k++
            }
            while (p < mid) {
                tmp[k] = arr[p]
                p++
                k++
            }
            while (q < end) {
                tmp[k] = arr[q]
                q++
                k++
            }
            i = i + 2 * width
        }
        var j: Int64 = 0
        while (j < n) {
            arr[j] = tmp[j]
            j++
        }
        width = width * 2
    }
    arr
}

/**
 * 分位数（线性插值，与 NumPy 的默认 `method="linear"` 一致）
 *
 * 位置 `pos = q * (n-1)`，取相邻两点按小数部分插值。
 */
func quantileOf(sorted: Array<Float64>, q: Float64): Float64 {
    let n = sorted.size
    if (n == 0) {
        return Float64.getNaN()
    }
    if (n == 1) {
        return sorted[0]
    }
    let pos = q * Float64(n - 1)
    if (pos <= 0.0) {
        return sorted[0]
    }
    if (pos >= Float64(n - 1)) {
        return sorted[n - 1]
    }
    let lo = Int64(floor(pos))
    let hi = lo + 1
    let frac = pos - Float64(lo)
    sorted[lo] * (1.0 - frac) + sorted[hi] * frac
}

/** 协方差（样本，除以 n-1）；两个数组必须等长 */
func covarianceOf(x: Array<Float64>, y: Array<Float64>): Float64 {
    let n = x.size
    if (n != y.size || n < 2) {
        return Float64.getNaN()
    }
    let mx = meanOf(x)
    let my = meanOf(y)
    var s = 0.0
    var i: Int64 = 0
    while (i < n) {
        s = s + (x[i] - mx) * (y[i] - my)
        i++
    }
    s / Float64(n - 1)
}

/** 皮尔逊相关系数 */
func correlationOf(x: Array<Float64>, y: Array<Float64>): Float64 {
    let cov = covarianceOf(x, y)
    let sx = varianceOf(x, 1)
    let sy = varianceOf(y, 1)
    if (sx.isNaN() || sy.isNaN() || sx <= 0.0 || sy <= 0.0) {
        return Float64.getNaN()
    }
    cov / (sqrt(sx) * sqrt(sy))
}

/**
 * 成对过滤：`corr` / `cov` 必须同时丢弃任一侧缺失的样本
 *
 * 若各自独立跳 `NaN`，两个数组的长度会错位，算出来的是"1 号的价格对 5 号的销量"
 * —— 数字看着正常，结论完全错。
 */
func pairedFinite(x: Array<Float64>, y: Array<Float64>): (Array<Float64>, Array<Float64>) {
    if (x.size != y.size) {
        throw IllegalArgumentException(
            "两个数组长度必须一致：${x.size} 与 ${y.size}")
    }
    let xs = ArrayList<Float64>()
    let ys = ArrayList<Float64>()
    var i: Int64 = 0
    while (i < x.size) {
        if (!x[i].isNaN() && !y[i].isNaN()) {
            xs.add(x[i])
            ys.add(y[i])
        }
        i++
    }
    (xs.toArray(), ys.toArray())
}

func registerStats(ctx: CapabilityContext): Unit {
    let env = ctx.env
    // (cangjie::mean x)
    env.define("cangjie::mean", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::mean 需要 1 个参数")
            }
            LispValue.Float(meanOf(finiteOf(asFloatValues(args[0], "cangjie::mean"))))
        })
    }))

    // (cangjie::median x)
    env.define("cangjie::median", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::median 需要 1 个参数")
            }
            let v = finiteOf(asFloatValues(args[0], "cangjie::median"))
            LispValue.Float(quantileOf(sortedCopy(v), 0.5))
        })
    }))

    // (cangjie::std x) —— 样本标准差（n-1）
    env.define("cangjie::std", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::std 需要 1 个参数")
            }
            LispValue.Float(sqrt(varianceOf(finiteOf(asFloatValues(args[0], "cangjie::std")), 1)))
        })
    }))

    // (cangjie::std-pop x) —— 总体标准差（n）
    env.define("cangjie::std-pop", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::std-pop 需要 1 个参数")
            }
            LispValue.Float(sqrt(varianceOf(finiteOf(asFloatValues(args[0], "cangjie::std-pop")), 0)))
        })
    }))

    // (cangjie::var x) —— 样本方差
    env.define("cangjie::var", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::var 需要 1 个参数")
            }
            LispValue.Float(varianceOf(finiteOf(asFloatValues(args[0], "cangjie::var")), 1))
        })
    }))

    // (cangjie::quantile x q)
    env.define("cangjie::quantile", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::quantile 需要数组与分位值")
            }
            let q = numOf(args[1], "cangjie::quantile")
            if (q < 0.0 || q > 1.0) {
                throw IllegalArgumentException("分位值必须在 [0, 1]，得到 ${q}")
            }
            let v = finiteOf(asFloatValues(args[0], "cangjie::quantile"))
            LispValue.Float(quantileOf(sortedCopy(v), q))
        })
    }))

    // (cangjie::cov x y)
    env.define("cangjie::cov", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::cov 需要两个数组")
            }
            let x = asFloatValues(args[0], "cangjie::cov")
            let y = asFloatValues(args[1], "cangjie::cov")
            let pair = pairedFinite(x, y)
            LispValue.Float(covarianceOf(pair[0], pair[1]))
        })
    }))

    // (cangjie::corr x y)
    env.define("cangjie::corr", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::corr 需要两个数组")
            }
            let x = asFloatValues(args[0], "cangjie::corr")
            let y = asFloatValues(args[1], "cangjie::corr")
            let pair = pairedFinite(x, y)
            LispValue.Float(correlationOf(pair[0], pair[1]))
        })
    }))

    // (cangjie::min x) / (cangjie::max x) —— **跳过 NaN** 的版本
    //
    // core 的 `(min x)` / `(max x)` 保持数学语义：NaN 参与比较后整体变成 NaN。
    // 这对数值计算是对的（NaN 就该传播），但数据分析里 NaN 是"缺失"而不是"无穷小"，
    // 一批数据里有一个空值就让最大值变成 NaN 是不能接受的。
    //
    // 所以这里提供 nan-aware 的版本：**加了 `cangjie::` 前缀就是"数据分析语义"**。
    // 这不是重复实现，是两套语义各有正确用法。
    env.define("cangjie::min", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::min 需要 1 个参数")
            }
            let v = finiteOf(asFloatValues(args[0], "cangjie::min"))
            if (v.size == 0) {
                return LispValue.Float(Float64.getNaN())
            }
            var m = v[0]
            for (x in v) {
                if (x < m) {
                    m = x
                }
            }
            LispValue.Float(m)
        })
    }))

    env.define("cangjie::max", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::max 需要 1 个参数")
            }
            let v = finiteOf(asFloatValues(args[0], "cangjie::max"))
            if (v.size == 0) {
                return LispValue.Float(Float64.getNaN())
            }
            var m = v[0]
            for (x in v) {
                if (x > m) {
                    m = x
                }
            }
            LispValue.Float(m)
        })
    }))

    // (cangjie::group-by labels values) → [[key, ndarray] …]，按首次出现顺序
    env.define("cangjie::group-by", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::group-by 需要 (labels values) 两个参数")
            }
            let labels = labelsOf(args[0], "cangjie::group-by")
            let values = asFloatValues(args[1], "cangjie::group-by")
            if (values.size != labels.size) {
                throw IllegalArgumentException(
                    "cangjie::group-by：分组键 ${labels.size} 个，值 ${values.size} 个，长度不一致")
            }
            let vals = ArrayList<Float64>()
            var i: Int64 = 0
            while (i < values.size) {
                vals.add(values[i])
                i++
            }
            groupedToLisp(groupValues(labels, vals.toArray()))
        })
    }))

    // (cangjie::group-agg labels values f) → [[key, 聚合值] …]
    //
    // `f` 是任意 Lisp 函数（`cangjie::mean`、`(lambda (v) (cangjie::quantile v 0.9))` 都行）。
    // 这是"一行出结果"的形态，省掉调用方自己写 map 拼 alist。
    env.define("cangjie::group-agg", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 3) {
                throw IllegalArgumentException(
                    "cangjie::group-agg 需要 (labels values f) 三个参数")
            }
            let labels = labelsOf(args[0], "cangjie::group-agg")
            let values = asFloatValues(args[1], "cangjie::group-agg")
            if (values.size != labels.size) {
                throw IllegalArgumentException(
                    "cangjie::group-agg：分组键 ${labels.size} 个，值 ${values.size} 个，长度不一致")
            }
            let vals = ArrayList<Float64>()
            var i: Int64 = 0
            while (i < values.size) {
                vals.add(values[i])
                i++
            }
            let g = groupValues(labels, vals.toArray())
            let fn = args[2]
            let pairs = ArrayList<LispValue>()
            var k: Int64 = 0
            while (k < g.keys.size) {
                let callArgs = ArrayList<LispValue>()
                callArgs.add(LispValue.External(ndarrayFromFloats(g.groups[k])))
                let r = match (ctx.invoke(fn, callArgs)) {
                    case Error(e) => throw IllegalArgumentException(
                        "group-agg：对分组 `${g.keys[k]}` 应用函数时出错：${e.message}")
                    case other => other
                }
                pairs.add(listOf([LispValue.Str(g.keys[k]), r]))
                k++
            }
            listOf(pairs.toArray())
        })
    }))

    // (cangjie::t-test1 x mu0) —— 单样本 t 检验
    env.define("cangjie::t-test1", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::t-test1 需要 (x mu0) 两个参数")
            }
            let x = asFloatValues(args[0], "cangjie::t-test1")
            let mu0 = numOf(args[1], "cangjie::t-test1")
            tTestOne(x, mu0)
        })
    }))

    // (cangjie::t-test2 x y) —— 双样本 Welch t 检验
    env.define("cangjie::t-test2", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::t-test2 需要 (x y) 两个参数")
            }
            let x = asFloatValues(args[0], "cangjie::t-test2")
            let y = asFloatValues(args[1], "cangjie::t-test2")
            tTestTwo(x, y)
        })
    }))

    // (cangjie::ci x level) —— 均值置信区间
    env.define("cangjie::ci", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::ci 需要 (x level) 两个参数")
            }
            let x = asFloatValues(args[0], "cangjie::ci")
            let level = numOf(args[1], "cangjie::ci")
            confidenceInterval(x, level)
        })
    }))

    // (cangjie::five-num x) —— 箱线图数据（五数概括 + 离群点）
    env.define("cangjie::five-num", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::five-num 需要 1 个参数")
            }
            fiveNumSummary(asFloatValues(args[0], "cangjie::five-num"))
        })
    }))

    // (cangjie::corr-matrix X) —— 相关矩阵（热力图数据），X 是 n×p
    env.define("cangjie::corr-matrix", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 1) {
                throw IllegalArgumentException("cangjie::corr-matrix 需要 1 个参数")
            }
            let a = match (args[0]) {
                case External(e) => match (e) {
                    case x: NDArray => x.copy()
                    case _ => throw IllegalArgumentException(
                        "cangjie::corr-matrix 需要 ndarray")
                }
                case _ => throw IllegalArgumentException(
                    "cangjie::corr-matrix 需要 ndarray")
            }
            let dims = a.shape
            if (dims.size != 2) {
                throw IllegalArgumentException(
                    "cangjie::corr-matrix 需要 2D 矩阵（n×p），得到 ${dims.size} 维")
            }
            let n = dims[0]
            let p = dims[1]
            let rows = ArrayList<Array<Float64>>()
            var i: Int64 = 0
            while (i < n) {
                let row = Array<Float64>(p, repeat: 0.0)
                var j: Int64 = 0
                while (j < p) {
                    row[j] = match (a.at(i * p + j)) {
                        case Float(x) => x
                        case Int(x) => Float64(x)
                        case _ => Float64.getNaN()
                    }
                    j++
                }
                rows.add(row)
                i++
            }
            correlationMatrix(rows.toArray(), p)
        })
    }))

    // (cangjie::histogram x bins) → {"edges": ndarray, "counts": ndarray}
    env.define("cangjie::histogram", NativeFunc({ args =>
        guardedStats({ =>
            if (args.size != 2) {
                throw IllegalArgumentException("cangjie::histogram 需要数组与箱数")
            }
            let bins = match (args[1]) {
                case Int(n) => n
                case _ => throw IllegalArgumentException("箱数必须是整数")
            }
            if (bins < 1) {
                throw IllegalArgumentException("箱数必须 >= 1")
            }
            let v = finiteOf(asFloatValues(args[0], "cangjie::histogram"))
            let result = HashMap<String, LispValue>()
            if (v.size == 0) {
                result.add("edges", LispValue.External(ndarrayFromFloats(Array<Float64>())))
                result.add("counts", LispValue.External(ndarrayFromInts(Array<Int64>())))
                return LispValue.HashMap(result)
            }
            var lo = v[0]
            var hi = v[0]
            for (x in v) {
                if (x < lo) {
                    lo = x
                }
                if (x > hi) {
                    hi = x
                }
            }
            let edges = Array<Float64>(bins + 1, repeat: 0.0)
            let width = if (hi > lo) { (hi - lo) / Float64(bins) } else { 1.0 }
            var i: Int64 = 0
            while (i <= bins) {
                edges[i] = lo + Float64(i) * width
                i++
            }
            let counts = Array<Int64>(bins, repeat: 0)
            for (x in v) {
                var idx = if (width > 0.0) { Int64(floor((x - lo) / width)) } else { 0 }
                if (idx < 0) {
                    idx = 0
                }
                // 最大值归入最后一箱（左闭右开区间的右端点）
                if (idx >= bins) {
                    idx = bins - 1
                }
                counts[idx] = counts[idx] + 1
            }
            result.add("edges", LispValue.External(ndarrayFromFloats(edges)))
            result.add("counts", LispValue.External(ndarrayFromInts(counts)))
            LispValue.HashMap(result)
        })
    }))

    // 分布函数族（18 个）：数学在 distributions.cj，接口与参数校验在 dist_ops.cj。
    // 单开文件是因为它们吃标量、吐标量，与上面这些「吃数组算一个数」的不是同一类工作。
    registerDistributions(ctx)
}
