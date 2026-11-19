package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.collection.HashMap
import std.math.*

/**
 * 图表数据（本仓只出**可渲染的结构**，不渲染）
 *
 * 图表分两类：
 *
 * - **散点图、折线图**：要的就是数据本身，调用方拿两个数组就能画，不需要专门函数；
 * - **箱线图、相关矩阵**：需要真实计算才能得到绘图坐标，所以放在这里。
 *
 * 输出一律是**结构化数据**（`HashMap` 或 ndarray）。渲染归前端 —— 本仓不引入
 * 图形依赖，也不生成 SVG/PNG，那样会让「一个数据分析库」变成「半个绘图库」。
 */

/**
 * 箱线图的五数概括 + 离群点
 *
 * ## Tukey 的 1.5·IQR 规则
 *
 * 箱线图的「须」**不是**最小/最大值，而是**围栏内最远的实际数据点**：
 *
 * ```
 * IQR   = Q3 − Q1
 * 下围栏 = Q1 − 1.5·IQR
 * 上围栏 = Q3 + 1.5·IQR
 * ```
 *
 * 落在围栏外的点单独列为离群点，画成散点。这个约定很重要 —— 如果直接用
 * min/max 当须，一个极端值会把整张图压扁到看不出中位数在哪。
 *
 * 返回：
 * ```
 * {min, q1, median, q3, max,
 *  iqr, lower_fence, upper_fence,
 *  low_whisker, high_whisker,   ← 须的实际端点（围栏内最远的数据点）
 *  outliers}                    ← ndarray，可能为空
 * ```
 */
func fiveNumSummary(values: Array<Float64>): LispValue {
    let f = finiteOf(values)
    if (f.size < 4) {
        throw IllegalArgumentException(
            "five-num：至少需要 4 个有效样本，当前 ${f.size} 个")
    }
    let s = sortedCopy(f)
    let n = s.size
    let q1 = quantileOf(s, 0.25)
    let med = quantileOf(s, 0.50)
    let q3 = quantileOf(s, 0.75)
    let iqr = q3 - q1
    let lower = q1 - 1.5 * iqr
    let upper = q3 + 1.5 * iqr
    // 须 = 围栏内最远的实际数据点
    let outliers = ArrayList<Float64>()
    var lowWhisker = s[0]
    var highWhisker = s[n - 1]
    var seenLow = false
    var seenHigh = false
    var i: Int64 = 0
    while (i < n) {
        let v = s[i]
        if (v < lower || v > upper) {
            outliers.add(v)
        } else {
            if (!seenLow) {
                lowWhisker = v
                seenLow = true
            }
            highWhisker = v
            seenHigh = true
        }
        i++
    }
    let out = HashMap<String, LispValue>()
    out.add("min", LispValue.Float(s[0]))
    out.add("q1", LispValue.Float(q1))
    out.add("median", LispValue.Float(med))
    out.add("q3", LispValue.Float(q3))
    out.add("max", LispValue.Float(s[n - 1]))
    out.add("iqr", LispValue.Float(iqr))
    out.add("lower_fence", LispValue.Float(lower))
    out.add("upper_fence", LispValue.Float(upper))
    out.add("low_whisker", LispValue.Float(lowWhisker))
    out.add("high_whisker", LispValue.Float(highWhisker))
    out.add("outliers", LispValue.External(ndarrayFromFloats(outliers.toArray())))
    out.add("n", LispValue.Int(n))
    LispValue.HashMap(out)
}

/**
 * 相关矩阵（热力图数据）
 *
 * 输入 `n×p` 矩阵，输出 `p×p` 的皮尔逊相关系数矩阵。对角线是 1。
 *
 * **成对删除缺失值**：某一行在变量 i 上有缺失、在变量 j 上没有时，这一行对
 * `(i,j)` 不可用，但对其它变量对仍然可用。所以每个格子用各自的有效样本对算 ——
 * 这与 `corr` 的成对过滤语义一致。若改成"整行删除"，样本量会凭空少掉一大截。
 *
 * 某对变量少于 3 个有效样本（或有一侧方差为 0）时该格记 `NaN`。
 */
func correlationMatrix(rows: Array<Array<Float64>>, p: Int64): LispValue {
    let out = Array<Float64>(p * p, repeat: 0.0)
    var i: Int64 = 0
    while (i < p) {
        var j: Int64 = 0
        while (j < p) {
            if (i == j) {
                out[i * p + j] = 1.0
            } else {
                // 成对收集有效样本
                let xs = ArrayList<Float64>()
                let ys = ArrayList<Float64>()
                for (r in rows) {
                    let a = r[i]
                    let b = r[j]
                    if (!a.isNaN() && !b.isNaN()) {
                        xs.add(a)
                        ys.add(b)
                    }
                }
                if (xs.size < 3) {
                    out[i * p + j] = Float64.getNaN()
                } else {
                    let r2 = correlationOf(xs.toArray(), ys.toArray())
                    out[i * p + j] = r2
                }
            }
            j++
        }
        i++
    }
    LispValue.External(reshapeArray(ndarrayFromFloats(out), [p, p]))
}
