package ystyle::xisp_array

/**
 * NumPy 风格的广播
 *
 * 规则（**从尾部维度对齐**，前面的维度补 1）：
 *
 * | a 的形状 | b 的形状 | 结果 |
 * |---|---|---|
 * | `[3]` | `[3]` | `[3]` |
 * | `[2,3]` | `[3]` | `[2,3]` |
 * | `[3,1]` | `[1,4]` | `[3,4]` |
 * | `[1]` | `[4]` | `[4]` |
 * | `[2,3]` | `[2]` | **不兼容**（3 与 2 无法对齐） |
 *
 * 从尾部对齐而不是从头，是因为数学上"长度"是内层维度，`[2,3]` 与 `[3]`
 * 天然应当对齐到列。
 */

/**
 * 计算两个形状广播后的形状
 *
 * 不兼容返回 `None` —— 由调用方转成 `TypeError`，不要静默截断或补零。
 */
func broadcastShape(a: Array<Int64>, b: Array<Int64>): Option<Array<Int64>> {
    let n = if (a.size > b.size) { a.size } else { b.size }
    let out = Array<Int64>(n, repeat: 1)
    var i = 0
    while (i < n) {
        // 从尾部取：a 的第 ia 维对应结果的第 i 维
        let ia = a.size - (n - i)
        let ib = b.size - (n - i)
        let da = if (ia >= 0) { a[ia] } else { 1 }
        let db = if (ib >= 0) { b[ib] } else { 1 }
        if (da == db) {
            out[i] = da
        } else if (da == 1) {
            out[i] = db
        } else if (db == 1) {
            out[i] = da
        } else {
            return None
        }
        i++
    }
    Some(out)
}

/**
 * 把数组广播到目标形状，返回**共享 buffer 的视图**
 *
 * 关键技巧：**把被广播的维度的 stride 置 0**。stride 为 0 意味着"沿这一维移动
 * 不改变数据位置"，于是同一份数据被逻辑上重复 —— 零拷贝。
 *
 * 例：`[3,1]` 的 strides 是 `[1,1]`，广播到 `[3,4]` 后 strides 变 `[1,0]`。
 *
 * 补出来的前导维度同样 stride = 0。
 */
func broadcastTo(a: NDArray, target: Array<Int64>): NDArray {
    let n = target.size
    let pad = n - a.dims.size
    let steps = Array<Int64>(n, repeat: 0)
    var i = 0
    while (i < n) {
        if (i < pad) {
            // 比原数组多出来的前导维度
            steps[i] = 0
        } else {
            let src = i - pad
            if (a.dims[src] == 1 && target[i] != 1) {
                steps[i] = 0
            } else {
                steps[i] = a.steps[src]
            }
        }
        i++
    }
    NDArray(a.buf, a.off, target.clone(), steps)
}

/**
 * 读数组的某个 buffer 位置为 `Float64`
 *
 * 算术运算在结果 dtype 上统一算，读取时按需转换 —— 这样 `int 数组 + float 标量`
 * 不需要先把整个 int 数组转成 float 再算（那是一次 O(n) 的额外拷贝）。
 *
 * Bool 在算术里**不允许**（见 `arithResultType`），所以这里不会遇到。
 */
func readAsFloat(a: NDArray, flat: Int64): Float64 {
    match (a.buf) {
        case Ints(arr) => Float64(arr[flat])
        case Floats(arr) => arr[flat]
        case Bools(arr) => if (arr[flat]) { 1.0 } else { 0.0 }
    }
}

func readAsInt(a: NDArray, flat: Int64): Int64 {
    match (a.buf) {
        case Ints(arr) => arr[flat]
        case Floats(arr) => Int64(arr[flat])
        case Bools(arr) => if (arr[flat]) { 1 } else { 0 }
    }
}

func readAsBool(a: NDArray, flat: Int64): Bool {
    match (a.buf) {
        case Ints(arr) => arr[flat] != 0
        case Floats(arr) => arr[flat] != 0.0
        case Bools(arr) => arr[flat]
    }
}
