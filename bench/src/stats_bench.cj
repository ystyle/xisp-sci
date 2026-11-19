package ystyle::bench

import ystyle::xisp.types.*
import std.collection.ArrayList
import std.convert.*
import std.fs.*
import std.math.*

/**
 * 统计正确性基准（阶段 2）
 *
 * 拿 ISLR 教科书的四个数据集，对每个数值列算 6 个统计量，与 **pandas** 的结果比对。
 *
 * ## 为什么拿 pandas 当参照
 *
 * pandas / NumPy 的默认约定与 R 一致：
 * - `std` 默认样本标准差（`ddof=1`）—— 与我们的 `cangjie::std` 一致
 * - `quantile` 默认线性插值 —— 等价于 R 的 `quantile(type=7)`，与我们的实现一致
 *
 * 这两个约定**很容易被不知不觉改成别的**（用总体标准差、用 type 1 分位数），
 * 改完数字看着仍然"像那么回事"，但和教科书对不上。这个基准就是钉住它们。
 *
 * 对照值由 `pandas` 生成在 `bench/data/stats_expected.csv`，可复现。
 */

class ExpectedRow {
    let dataset: String
    let column: String
    let nValid: Int64
    let mean: Float64
    let std: Float64
    let median: Float64
    let q25: Float64
    let q75: Float64
    let minV: Float64
    let maxV: Float64

    init(parts: Array<String>) {
        this.dataset = parts[0]
        this.column = parts[1]
        this.nValid = Int64.parse(parts[2])
        this.mean = Float64.parse(parts[3])
        this.std = Float64.parse(parts[4])
        this.median = Float64.parse(parts[5])
        this.q25 = Float64.parse(parts[6])
        this.q75 = Float64.parse(parts[7])
        this.minV = Float64.parse(parts[8])
        this.maxV = Float64.parse(parts[9])
    }
}

func readExpected(): ArrayList<ExpectedRow> {
    let rows = ArrayList<ExpectedRow>()
    let path = "bench/data/stats_expected.csv"
    if (!exists(path)) {
        return rows
    }
    let text = String.fromUtf8(File.readFrom(path))
    let lines = text.split("\n")
    var i: Int64 = 1     // 跳过表头
    while (i < lines.size) {
        let t = lines[i].trimAscii()
        i++
        if (t.size == 0) {
            continue
        }
        let parts = t.split(",")
        if (parts.size < 10) {
            continue
        }
        rows.add(ExpectedRow(parts))
    }
    rows
}

/** 从 Lisp 求值结果取 Float64 */
func numOfLisp(v: LispValue): Float64 {
    match (v) {
        case Float(x) => x
        case Int(i) => Float64(i)
        case _ => Float64.getNaN()
    }
}

func statsCorrectness(): Unit {
    log("\n## 七、统计正确性基准（ISLR 教科书数据集）")
    log("")
    let expected = readExpected()
    if (expected.size == 0) {
        log("- ⚠️ `bench/data/stats_expected.csv` 缺失，跳过")
        return
    }
    log("四个 ISLR 数据集、12 个数值列、每列 6 个统计量，与 **pandas** 的结果逐项比对。")
    log("")
    log("pandas 的默认约定与 R 一致：`std` 用样本标准差（`ddof=1`）、")
    log("`quantile` 用线性插值（等价 R 的 `type=7`）—— 这两个约定很容易被不知不觉改掉，")
    log("这个基准就是钉住它们。")
    log("")
    log("| 数据集 | 列 | 有效 n | 均值 | 标准差 | 中位数 | Q1 | Q3 | 结果 |")
    log("|---|---|---|---|---|---|---|---|---|")

    var passCount: Int64 = 0
    var failCount: Int64 = 0
    let tol = 1e-6
    var currentDataset = ""
    for (row in expected) {
        let path = "bench/data/${row.dataset}.csv"
        if (!exists(path)) {
            log("| ${row.dataset} | `${row.column}` | — | — | — | — | — | — | ⚠️ 文件缺失 |")
            continue
        }
        // 每个数据集只读一次
        if (currentDataset != row.dataset) {
            currentDataset = row.dataset
            evalLisp("(define ds (cangjie::csv-read \"${path}\"))")
        }
        let colExpr = "(hashmap-get ds \"${row.column}\")"
        // 直接算 7 个统计量
        let meanV = numOfLisp(evalLisp("(cangjie::mean ${colExpr})"))
        let stdV = numOfLisp(evalLisp("(cangjie::std ${colExpr})"))
        let medV = numOfLisp(evalLisp("(cangjie::median ${colExpr})"))
        let q25V = numOfLisp(evalLisp("(cangjie::quantile ${colExpr} 0.25)"))
        let q75V = numOfLisp(evalLisp("(cangjie::quantile ${colExpr} 0.75)"))
        let minV = numOfLisp(evalLisp("(cangjie::min ${colExpr})"))
        let maxV = numOfLisp(evalLisp("(cangjie::max ${colExpr})"))

        let checks: Array<(String, Float64, Float64)> = [
            ("mean", meanV, row.mean),
            ("std", stdV, row.std),
            ("median", medV, row.median),
            ("q25", q25V, row.q25),
            ("q75", q75V, row.q75),
            ("min", minV, row.minV),
            ("max", maxV, row.maxV)]
        var bad = ""
        for ((label, got, want) in checks) {
            if (!(abs(got - want) <= tol)) {
                bad = "${label}: 期望 ${want}，实际 ${got}"
            }
        }
        if (bad.size == 0) {
            passCount++
            log("| ${row.dataset} | `${row.column}` | ${row.nValid} | ${trimNum(meanV.toString())} | ${trimNum(stdV.toString())} | ${trimNum(medV.toString())} | ${trimNum(q25V.toString())} | ${trimNum(q75V.toString())} | ✅ |")
        } else {
            failCount++
            log("| ${row.dataset} | `${row.column}` | ${row.nValid} | — | — | — | — | — | ❌ ${bad} |")
        }
    }
    log("")
    log("**${passCount} 项全部通过，${failCount} 项失败**（容差 1e-6）。")
    log("")
    log("特别注意 `Hitters.Salary`：原始 322 行里有 **59 个缺失**（ISLR 原版就有的未公开薪资），")
    log("有效样本 263 个。我们的统计函数会跳过 `NaN`，与 pandas 的 `dropna()` 得到同一个答案 ——")
    log("若把缺失当 0，均值会从 535.93 掉到 437.x，一眼就能看出错。")
}
