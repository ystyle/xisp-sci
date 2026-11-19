package ystyle::bench

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp_array.*
import std.collection.ArrayList
import std.fs.*
import std.math.*

/**
 * 图表数据的基准（本仓只出结构，不渲染）
 *
 * 演示两种真需要计算的图表数据：**箱线图**（五数概括 + 离群点）与**相关矩阵**。
 * 散点图、折线图不用专门函数 —— 要的就是数据本身。
 */
func chartData(): Unit {
    log("\n## 八、图表数据（可渲染的结构）")
    log("")
    log("本仓**不渲染**图表，只产出绘图层需要的数据结构。散点图/折线图不需要专门函数，")
    log("箱线图与相关矩阵则需要真实计算。")
    log("")

    // 1) 箱线图：Iris 各物种的花瓣长度
    let iris = "bench/data/iris.csv"
    if (exists(iris)) {
        evalLisp("(define ir (cangjie::csv-read \"${iris}\"))")
        let g = evalLisp(
            "(cangjie::group-by (hashmap-get ir \"species\") (hashmap-get ir \"petal_length\"))")
        log("### 箱线图：Iris 各物种的 `petal_length`")
        log("")
        log("| 物种 | Q1 | 中位数 | Q3 | IQR | 下须 | 上须 | 离群点 |")
        log("|---|---|---|---|---|---|---|---|")
        let keys = groupKeys(g)
        var i: Int64 = 0
        while (i < keys.size) {
            let arr = groupArr(g, i)
            getInterp().getEnvironment().define(
                "BX", LispValue.External(ndarrayFromFloats(arr)))
            let fn = evalLisp("(cangjie::five-num BX)")
            let q1 = trimNum(getField(fn, "q1"))
            let med = trimNum(getField(fn, "median"))
            let q3 = trimNum(getField(fn, "q3"))
            let iqr = trimNum(getField(fn, "iqr"))
            let lw = trimNum(getField(fn, "low_whisker"))
            let hw = trimNum(getField(fn, "high_whisker"))
            let oc = countOf(fn, "outliers")
            log("| ${keys[i]} | ${q1} | ${med} | ${q3} | ${iqr} | ${lw} | ${hw} | ${oc} |")
            i++
        }
        log("")
        log("注意 **须不是 min/max**：Tukey 的 1.5·IQR 规则下，须止于围栏内最远的实际数据点，")
        log("围栏外的点单列为离群点。若用极值当须，一个离群点会把箱体压扁到看不出来。")
    }

    // 2) 相关矩阵：Boston 的四个变量
    let boston = "bench/data/boston.csv"
    if (exists(boston)) {
        evalLisp("(define bo (cangjie::csv-read \"${boston}\"))")
        let cols = ["crim", "rm", "lstat", "medv"]
        let n = columnOf("(hashmap-get bo \"medv\")").size
        let data = Array<Float64>(n * cols.size, repeat: 0.0)
        var c: Int64 = 0
        while (c < cols.size) {
            let col = columnOf("(hashmap-get bo \"${cols[c]}\")")
            var i: Int64 = 0
            while (i < n) {
                data[i * cols.size + c] = col[i]
                i++
            }
            c++
        }
        let mat = reshapeArray(ndarrayFromFloats(data), [n, cols.size])
        getInterp().getEnvironment().define("CM", LispValue.External(mat))
        let cm = evalLisp("(cangjie::corr-matrix CM)")
        log("")
        log("### 相关矩阵：Boston 的 4 个变量（热力图数据）")
        log("")
        let vals = matrixValues(cm, cols.size)
        // 表头
        var hdr = "| |"
        for (c2 in cols) {
            hdr = hdr + " ${c2} |"
        }
        log(hdr)
        var sep = "|---|"
        var k: Int64 = 0
        while (k < cols.size) {
            sep = sep + "---|"
            k++
        }
        log(sep)
        var r: Int64 = 0
        while (r < cols.size) {
            var line = "| **${cols[r]}** |"
            var j: Int64 = 0
            while (j < cols.size) {
                line = line + " ${trimNum(vals[r * cols.size + j].toString())} |"
                j++
            }
            log(line)
            r++
        }
        log("")
        log("`medv` 与 `lstat` 强负相关（-0.74）、与 `rm` 强正相关（0.70）—— 与 ISLR")
        log("对这个数据集的结论一致。对角线恒为 1，矩阵对称。")
    }
}

func countOf(v: LispValue, field: String): Int64 {
    match (v) {
        case HashMap(m) =>
            match (m.get(field)) {
                case Some(External(e)) =>
                    match (e) {
                        case a: NDArray => a.length()
                        case _ => -1
                    }
                case _ => -1
            }
        case _ => -1
    }
}

func matrixValues(v: LispValue, p: Int64): Array<Float64> {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray =>
                    let out = ArrayList<Float64>()
                    var i: Int64 = 0
                    while (i < p * p) {
                        out.add(match (a.at(i)) {
                            case Float(x) => x
                            case Int(n) => Float64(n)
                            case _ => Float64.getNaN()
                        })
                        i++
                    }
                    out.toArray()
                case _ => Array<Float64>()
            }
        case _ => Array<Float64>()
    }
}
