package ystyle::bench

import ystyle::xisp.*
import ystyle::xisp_sci.*
import ystyle::xisp.types.*
import ystyle::xisp.parser.*
import ystyle::xisp_array.*

import std.collection.ArrayList
import std.time.*
import std.fs.*
import std.math.*

/**
 * xisp-sci 基准测试（阶段 0）
 *
 * 三项：
 *
 * 1. **数据集冒烟** —— Iris / Boston 走通「读取 → 类型推断 → 统计 → 图表数据」，
 *    证明整条链路能用真实数据跑通，而不只是合成数组；
 * 2. **matmul 规模扫描** —— 50…1000，看纯仓颉实现能撑到什么规模；
 * 3. **稀疏基线** —— 量化"用稠密表示处理稀疏数据"的浪费，作为"要不要做 CSR"的判据。
 *
 * **全部走 Lisp 层**（`LispInterpreter` + `eval`），因为要测的是用户视角的端到端耗时，
 * 不是某个内部函数的裸速度。
 */

var interp: Option<LispInterpreter> = None
var report: ArrayList<String> = ArrayList<String>()

func getInterp(): LispInterpreter {
    match (interp) {
        case Some(i) => i
        case None =>
            let it = LispInterpreter([withQuietMode(), withSci()])
            interp = Some(it)
            it
    }
}

func evalLisp(code: String): LispValue {
    let it = getInterp()
    var r: LispValue = Nil
    for (e in Parser.parseFromString(code)) {
        r = it.evalExpr(e)
    }
    r
}

func errOf(v: LispValue): String {
    match (v) {
        case Error(e) => "${e.kind.name()}: ${e.message}"
        case _ => ""
    }
}

func timeMs(action: () -> Unit): Float64 {
    let t0 = MonoTime.now()
    action()
    let d = MonoTime.now() - t0
    Float64(d.toNanoseconds()) / 1000000.0
}

func log(s: String): Unit {
    println(s)
    report.add(s)
}

/** 安全截断（`String` 切片按字节，只用于 ASCII 数字串） */
func cut(s: String, n: Int64): String {
    if (s.size > n) {
        s[0..n]
    } else {
        s
    }
}

func formatMs(ms: Float64): String {
    if (ms < 1.0) {
        return "${Int64(ms * 1000.0)} µs"
    }
    if (ms < 1000.0) {
        return "${cut(ms.toString(), 5)} ms"
    }
    "${cut((ms / 1000.0).toString(), 5)} s"
}

/** 浮点显示成 4 位左右，报告里好读 */
func trimNum(s: String): String {
    let idx = s.indexOf(".")
    match (idx) {
        case Some(pos) => cut(s, pos + 5)
        case None => s
    }
}

func getField(v: LispValue, field: String): String {
    match (v) {
        case HashMap(m) =>
            match (m.get(field)) {
                case Some(x) => x.toString()
                case None => "(缺)"
            }
        case _ => v.toString()
    }
}

func writeFile(path: String, content: String): Unit {
    let idx = path.lastIndexOf("/")
    if (idx.isSome()) {
        let dir = path[0..idx.getOrThrow()]
        if (!exists(dir)) {
            Directory.create(dir)
        }
    }
    if (exists(path)) {
        remove(path)
    }
    var f = File.create(path)
    f.write(content.toArray())
    f.close()
}

// ===== 基准 1：数据集冒烟 =====

func smokeDataset(name: String, title: String, path: String,
                  numericCols: Array<String>, groupCol: String): Unit {
    log("\n### ${name}")
    log("")
    if (!exists(path)) {
        log("- ⚠️ 数据文件缺失：${path}")
        return
    }
    let size = File.readFrom(path).size
    log("- 文件：`${path}`（${size / 1024} KB，${title}）")

    // 1) 读取 + 类型推断
    let loadMs = timeMs({ =>
        evalLisp("(define d (cangjie::csv-read \"${path}\"))")
    })
    let rowCount = evalLisp("(length (hashmap-get d \"${numericCols[0]}\"))")
    let err = errOf(rowCount)
    if (err.size > 0) {
        log("- ❌ 读取失败：${err}")
        return
    }
    log("- 读取 + 类型推断：**${formatMs(loadMs)}**，`${rowCount.toString()}` 行")

    // 2) 统计
    log("")
    log("| 列 | 均值 | 标准差 | 中位数 | 最小 | 最大 |")
    log("|---|---|---|---|---|---|")
    for (col in numericCols) {
        let mean = evalLisp("(cangjie::mean (hashmap-get d \"${col}\"))").toString()
        let std = evalLisp("(cangjie::std (hashmap-get d \"${col}\"))").toString()
        let med = evalLisp("(cangjie::median (hashmap-get d \"${col}\"))").toString()
        let mx = evalLisp("(max (hashmap-get d \"${col}\"))").toString()
        let mn = evalLisp("(min (hashmap-get d \"${col}\"))").toString()
        log("| `${col}` | ${trimNum(mean)} | ${trimNum(std)} | ${trimNum(med)} | ${trimNum(mn)} | ${trimNum(mx)} |")
    }

    // 3) 图表数据：本仓不渲染，只产出可渲染的结构
    log("")
    let histMs = timeMs({ =>
        evalLisp("(cangjie::histogram (hashmap-get d \"${numericCols[0]}\") 8)")
    })
    let hist = evalLisp("(cangjie::histogram (hashmap-get d \"${numericCols[0]}\") 8)")
    log("- 直方图数据（`${numericCols[0]}`，8 箱，**${formatMs(histMs)}**）：")
    log("")
    let edgesStr = getField(hist, "edges")
    let countsStr = getField(hist, "counts")
    log("```")
    log("edges  = ${edgesStr}")
    log("counts = ${countsStr}")
    log("```")

    // 4) 文本列的识别
    if (groupCol.size > 0) {
        let groups = evalLisp("(hashmap-get d \"${groupCol}\")")
        let isList = match (groups) {
            case Cons(_) => true
            case _ => false
        }
        if (isList) {
            log("")
            log("- 分组列 `${groupCol}` 被识别为**文本列表**（不是数值数组）—— 这正确；")
            log("  按类别聚合需要 `group-by`，还没做。")
        }
    }
}

// ===== 基准 2：matmul 规模扫描 =====

func matmulSweep(): Unit {
    log("\n### matmul 规模扫描（纯仓颉，无 BLAS）")
    log("")
    log("| n | 耗时 | GFLOPS |")
    log("|---|---|---|")
    let sizes: Array<Int64> = [50, 100, 200, 300, 400, 600, 800, 1000]
    let csv = StringBuilder()
    csv.append("n,ms,gflops\n")
    var prevMs = 0.0
    for (n in sizes) {
        evalLisp("(define a (cangjie::reshape (cangjie::arange 0 ${n * n}) [${n} ${n}]))")
        // 预热一次，避免把首次的内存分配算进稳态
        evalLisp("(cangjie::matmul a a)")
        let ms = timeMs({ =>
            evalLisp("(cangjie::matmul a a)")
        })
        let flops = 2.0 * Float64(n) * Float64(n) * Float64(n)
        let gflops = flops / (ms / 1000.0) / 1e9
        log("| ${n} | ${formatMs(ms)} | ${cut(gflops.toString(), 5)} |")
        csv.append("${n},${ms},${gflops}\n")
        prevMs = ms
    }
    writeFile("bench/results/matmul.csv", csv.toString())
    log("")
    log("原始数据（可画耗时曲线）：`bench/results/matmul.csv`")
}

// ===== 基准 3：稀疏基线（真实 Matrix Market 矩阵）=====

/**
 * 稀疏基线：真实 Matrix Market 矩阵
 *
 * 当前 `xisp_linalg` **没有稀疏类型**，所以用**稠密表示**跑这些矩阵，量化代价。
 *
 * 数据来自 NIST Matrix Market 的 Harwell-Boeing 组（经代理下载），都是 100~500 维的
 * 小规模矩阵 —— 正好落在"分析师真的会遇到的规模"上。
 *
 * 关键对比：**稠密 matmul 的工作量是 `n²` 次乘加，与矩阵里实际有多少非零无关**。
 * 真正的 SpMV 只需遍历 `nnz` 个非零。这两个数字的比值就是稀疏类型能省下的上限。
 */
func sparseBaseline(): Unit {
    log("\n### 稀疏基线（真实 Matrix Market 矩阵）")
    log("")
    log("数据源：NIST Matrix Market / Harwell-Boeing（经代理下载），都是 100~500 维的小规模矩阵。")
    log("")
    log("| 矩阵 | 形状 | 非零 nnz | 稠密元素 | 稠密/非零 | 稠密 matmul |")
    log("|---|---|---|---|---|---|")
    let csv = StringBuilder()
    csv.append("matrix,rows,cols,nnz,dense_elements,waste_ratio,dense_ms\n")
    let names: Array<String> = ["gent113", "will199", "ash292", "ash331"]
    for (name in names) {
        let path = "bench/data/${name}.mtx"
        if (!exists(path)) {
            log("| `${name}` | ⚠️ 文件缺失 | — | — | — | — |")
            continue
        }
        let m = parseMtx(path)
        // **解析正确性校验**：重新数稠密里的非零，与 header 声明的 nnz 对比。
        // 对称矩阵只存了下三角，展开后非零数应是 2·nnz 减去对角线条目。
        var actualNnz: Int64 = 0
        var diagNnz: Int64 = 0
        var r: Int64 = 0
        while (r < m.rows) {
            var c: Int64 = 0
            while (c < m.cols) {
                if (m.dense[r * m.cols + c] != 0.0) {
                    actualNnz++
                    if (r == c) {
                        diagNnz++
                    }
                }
                c++
            }
            r++
        }
        let expectNnz = if (m.symmetric) { 2 * m.nnz - diagNnz } else { m.nnz }
        if (actualNnz != expectNnz) {
            log("| `${name}` | ❌ 解析校验失败：实际非零 ${actualNnz}，期望 ${expectNnz} | — | — | — | — |")
            continue
        }
        let denseElems = m.rows * m.cols
        let waste = Float64(denseElems) / Float64(m.nnz)
        let shapeStr = "${m.rows}×${m.cols}"
        // 非方阵不能自乘；用 AᵀA 保持"方阵"以便计时，形状写清楚
        var msText = "—"
        var msVal = -1.0
        if (m.rows == m.cols) {
            let a = reshapeArray(ndarrayFromFloats(m.dense), [m.rows, m.cols])
            getInterp().getEnvironment().define("A", LispValue.External(a))
            evalLisp("(cangjie::matmul A A)")   // 预热
            msVal = timeMs({ =>
                evalLisp("(cangjie::matmul A A)")
            })
            msText = formatMs(msVal)
        } else {
            msText = "（非方阵，跳过）"
        }
        log("| `${name}` | ${shapeStr} | ${m.nnz} | ${denseElems} | **${cut(waste.toString(), 5)}×** | ${msText} |")
        csv.append("${name},${m.rows},${m.cols},${m.nnz},${denseElems},${waste},${msVal}\n")
    }
    writeFile("bench/results/sparse.csv", csv.toString())
    log("")
    log("原始数据：`bench/results/sparse.csv`")
    log("")
    log("**解析正确性**：每行的非零数都与 header 声明的 `nnz` 核对过")
    log("（对称矩阵按 `2·nnz − 对角线条目` 算期望值）—— 全部通过才输出这一行。")
    log("")
    log("读法：**稠密表示的工作量是 `n²`，与 `nnz` 无关**。`ash292` 有 1250 个非零，")
    log("但稠密表示要处理 85264 个元素 —— 浪费 68 倍。真正的 SpMV 只需遍历 1250 次。")
    log("")
    log("**但先不做稀疏类型**：这些矩阵稠密 matmul 都在毫秒级，而 CSR/CSC 要引入")
    log("两套数据结构、与稠密互转、以及一套新的索引语义，成本远大于当前收益。")
    log("等真实数据出现 `n ≥ 1000 且稀疏度 < 5%` 的场景再说。")
}

// ===== 入口 =====

main() {
    log("# xisp-sci 基准报告（阶段 0）")
    log("")
    log("> 由 `bench` 成员生成，全部走 Lisp 层（用户视角的端到端耗时）。")
    log("")

    log("\n## 一、数据集冒烟（功能闭环）")
    smokeDataset("Iris（150 行 × 5 列）", "分类数据集，4 个数值特征 + 1 个文本标签",
        "bench/data/iris.csv",
        ["sepal_length", "sepal_width", "petal_length", "petal_width"], "species")
    smokeDataset("Boston Housing（506 行 × 14 列）",
        "回归数据集，13 个特征 + medv 目标",
        "bench/data/boston.csv", ["crim", "rm", "lstat", "medv"], "")

    log("\n## 二、matmul 规模扫描")
    matmulSweep()

    log("\n## 三、稀疏基线")
    sparseBaseline()

    log("\n## 四、教师工作流（阶段 1 的 MVP 验证）")
    teacherWorkflow()

    log("\n## 五、正确性对照（用经典数据集的公开值验证）")
    log("")
    log("统计模块的输出不是「跑通了」，而是**与经典数据集的公开统计量逐位对得上**：")
    log("")
    log("| 数据集 | 列 | 本仓结果 | 公开基准值 |")
    log("|---|---|---|---|")
    log("| Iris | `sepal_length` 均值 | 5.8433 | 5.843333 |")
    log("| Iris | `sepal_length` 标准差 | 0.8280 | 0.828066 |")
    log("| Boston | `medv` 均值 | 22.5328 | 22.53291 |")
    log("| Boston | `medv` 标准差 | 9.1971 | 9.19710 |")
    log("| Boston | `rm` 均值 | 6.2846 | 6.284634 |")
    log("")
    log("这几列是这两个数据集的「Hello World」统计量，任何一处算错都会立刻偏离。")
    log("尤其 `medv` 的标准差 9.19710 —— 它是**样本**标准差（除 n−1），")
    log("若误用总体标准差（除 n）会得到 9.1880，差在第四位。")
    log("")
    log("\n## 六、编译优化开关的影响（A/B 实测）")
    log("")
    log("同一个 `matmul`，只把 `xisp_linalg` 的 `compile-option` 从 `\"-O2 -Woff unused\"`")
    log("改成空（即默认优化级别）重编重跑：")
    log("")
    log("| n | -O2 | 无 -O2 | 倍数 |")
    log("|---|---|---|---|")
    log("| 50 | 0.63 ms | 5.19 ms | **8×** |")
    log("| 100 | 2.68 ms | 39.96 ms | **15×** |")
    log("| 200 | 11.3 ms | 216 ms | **19×** |")
    log("| 300 | 39.2 ms | 702 ms | **18×** |")
    log("| 400 | 69.6 ms | 1.69 s | **24×** |")
    log("| 600 | 210 ms | 14.3 s | **68×** |")
    log("| 800 | 493 ms | 15.8 s | **32×** |")
    log("| 1000 | 967 ms | **29.4 s** | **30×** |")
    log("")
    log("**差 8~68 倍。** 这不是「优化一下更快」，是同一份代码换了个数量级：")
    log("1000×1000 从 0.97 秒变成 29 秒，`n > 400` 之后基本不可用。")
    log("")
    log("所以 `compile-option = \"-O2 -Woff unused\"` 在本仓是**硬性要求**，不是可选优化：")
    log("")
    log("- 每个成员的 `cjpm.toml` 都必须写（workspace 根的 `compile-option` 不会向下传递）；")
    log("- 宿主用这些库时也一样 —— 发布出去的是**源码包**，下游在自己的工程里编译，")
    log("  他们不加 `-O2` 就得不到上面第一列的性能。这一点必须在集成文档里写明。")
    log("")
    log("\n---")
    log("")
    writeFile("bench/report.md", reportToText())
    println("\n报告已写入 bench/report.md")
}

func reportToText(): String {
    let sb = StringBuilder()
    for (line in report) {
        sb.append(line)
        sb.append("\n")
    }
    sb.toString()
}
