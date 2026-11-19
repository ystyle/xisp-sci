package ystyle::bench

import std.collection.ArrayList
import std.fs.*
import std.convert.*

/**
 * Matrix Market 读取
 *
 * 支持 `coordinate` 格式的四种字段组合：
 *
 * - `pattern` / `real` / `integer`（值的类型）
 * - `general` / `symmetric`（结构）
 *
 * 索引是 **1-based**，且 `symmetric` 只存下三角 —— 读取时要把 (j,i) 补上，
 * 否则矩阵少一半元素而形状不变，是那种"看着有数、其实错"的陷阱。
 */
class MtxMatrix {
    let rows: Int64
    let cols: Int64
    let nnz: Int64
    let symmetric: Bool
    let pattern: Bool
    /** 稠密表示（行优先）；`symmetric` 已展开 */
    let dense: Array<Float64>

    init(rows: Int64, cols: Int64, nnz: Int64, symmetric: Bool, pattern: Bool,
         dense: Array<Float64>) {
        this.rows = rows
        this.cols = cols
        this.nnz = nnz
        this.symmetric = symmetric
        this.pattern = pattern
        this.dense = dense
    }

    func density(): Float64 {
        Float64(this.nnz) / Float64(this.rows * this.cols)
    }
}

func parseMtx(path: String): MtxMatrix {
    let text = String.fromUtf8(File.readFrom(path))
    let lines = text.split("\n")
    if (lines.size < 2) {
        throw IllegalArgumentException("mtx：文件太短")
    }
    // 第一行：%%MatrixMarket matrix coordinate <field> <symmetry>
    let header = lines[0].trimAscii().split(" ")
    var pattern = false
    var symmetric = false
    for (part in header) {
        if (part == "pattern") {
            pattern = true
        }
        if (part == "symmetric") {
            symmetric = true
        }
    }
    // 第二行：rows cols nnz
    var dimsLine = ""
    var i: Int64 = 1
    while (i < lines.size) {
        let t = lines[i].trimAscii()
        if (t.size > 0 && !t.startsWith("%")) {
            dimsLine = t
            i++
            break
        }
        i++
    }
    let dims = dimsLine.split(" ")
    let rows = Int64.parse(dims[0])
    let cols = Int64.parse(dims[1])
    let nnz = Int64.parse(dims[2])
    let dense = Array<Float64>(rows * cols, repeat: 0.0)
    var count: Int64 = 0
    while (i < lines.size && count < nnz) {
        let t = lines[i].trimAscii()
        i++
        if (t.size == 0 || t.startsWith("%")) {
            continue
        }
        let parts = t.split(" ")
        if (parts.size < 2) {
            continue
        }
        let r = Int64.parse(parts[0]) - 1
        let c = Int64.parse(parts[1]) - 1
        let v = if (pattern) {
            1.0
        } else if (parts.size >= 3) {
            Float64.parse(parts[2])
        } else {
            1.0
        }
        if (r >= 0 && r < rows && c >= 0 && c < cols) {
            dense[r * cols + c] = v
            // 对称矩阵只存了一半，补出转置位置
            // 对称矩阵必然是方阵，转置位置用 cols 作为行宽
            if (symmetric && r != c) {
                dense[c * cols + r] = v
            }
        }
        count++
    }
    MtxMatrix(rows, cols, nnz, symmetric, pattern, dense)
}
