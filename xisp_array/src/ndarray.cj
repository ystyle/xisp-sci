package ystyle::xisp_array

import ystyle::xisp.types.*
import std.collection.ArrayList

/**
 * 元素类型
 *
 * 第一版只做三种。复数不在内：它需要 core 的 `LispValue` 先有复数标量变体，
 * 而那是 ~24 处 match 的破坏面 —— 见 docs/plans/2026-11-19-scope-and-roadmap.md §4.3。
 */
public enum DType <: Equatable<DType> {
    | Ints
    | Floats
    | Bools

    public func name(): String {
        match (this) {
            case Ints => "int64"
            case Floats => "float64"
            case Bools => "bool"
        }
    }

    public operator func ==(other: DType): Bool {
        match ((this, other)) {
            case (Ints, Ints) => true
            case (Floats, Floats) => true
            case (Bools, Bools) => true
            case _ => false
        }
    }

    public operator func !=(other: DType): Bool {
        !(this == other)
    }
}

/**
 * 底层连续缓冲
 *
 * 视图（切片 / reshape / transpose）共享同一个 Buffer 对象，靠 `NDArray` 的
 * offset + strides 表达不同的"看法"。仓颉有 GC，共享缓冲不需要手工引用计数。
 *
 * Buffer 的长度可能**大于**某个视图实际覆盖的范围（视图只覆盖其中一段）。
 */
enum Buffer {
    | Ints(Array<Int64>)
    | Floats(Array<Float64>)
    | Bools(Array<Bool>)

    func length(): Int64 {
        match (this) {
            case Ints(a) => a.size
            case Floats(a) => a.size
            case Bools(a) => a.size
        }
    }
}

/**
 * N 维数组（外部值）
 *
 * ## 表示
 *
 * 值 = `(buffer, offset, shape, strides)` 四元组：
 *
 * - `buffer`：连续存储（dtype 决定元素类型），**多个 NDArray 可共享**；
 * - `offset`：本视图的起始位置在 buffer 中的**元素下标**（不是字节）；
 * - `shape`：各维长度；
 * - `strides`：各维前进一格在 buffer 中跨过的**元素个数**。
 *
 * 逻辑下标 `(i0, i1, …, in-1)` 对应的 buffer 位置：
 *
 * ```
 * offset + i0*strides[0] + i1*strides[1] + … + i(n-1)*strides[n-1]
 * ```
 *
 * **默认布局是行优先（C 序）**：`shape = [3, 4]` 的 strides 是 `[4, 1]`。
 * 选行优先而非列优先，是因为 `[[1 2] [3 4]]` 的字面量直觉就是行优先，
 * 用户心智更接近 NumPy；与 BLAS 对接时在 linalg 层转置即可 ——
 * strides 通用化之后这只是**默认值**的选择，不是能力限制。
 *
 * ## 视图 vs 拷贝
 *
 * `reshape` / `transpose` / `slice` 默认返回**共享 buffer 的视图**（零拷贝）。
 * 要独立副本用 `copy()`。
 */
public class NDArray <: LispExternalIndexable {
    internal let buf: Buffer
    internal let off: Int64
    internal let dims: Array<Int64>
    internal let steps: Array<Int64>

    internal init(buf: Buffer, off: Int64, dims: Array<Int64>, steps: Array<Int64>) {
        this.buf = buf
        this.off = off
        this.dims = dims
        this.steps = steps
    }

    // ===== LispExternal =====

    public prop typeName: String {
        get() { "ndarray" }
    }

    public func display(): String {
        let sb = StringBuilder()
        sb.append("#<ndarray ")
        sb.append(this.dtypeName())
        sb.append(" ")
        if (this.dims.size == 0) {
            // 0 维：单个标量
            sb.append(this.scalarText(this.off))
        } else {
            sb.append(this.renderDim(0, this.off))
        }
        sb.append(">")
        sb.toString()
    }

    // ===== 基本属性 =====

    public prop dtype: DType {
        get() {
            match (this.buf) {
                case Ints(_) => DType.Ints
                case Floats(_) => DType.Floats
                case Bools(_) => DType.Bools
            }
        }
    }

    /** 各维长度（副本，外部改不动内部状态） */
    public prop shape: Array<Int64> {
        get() { this.dims.clone() }
    }

    /** 各维步长（元素个数） */
    public prop strideList: Array<Int64> {
        get() { this.steps.clone() }
    }

    public prop offset: Int64 {
        get() { this.off }
    }

    public func rank(): Int64 {
        this.dims.size
    }

    /** 元素总数（各维长度之积；0 维为 1） */
    public func size(): Int64 {
        var n: Int64 = 1
        for (d in this.dims) {
            n = n * d
        }
        n
    }

    /** 底层缓冲的容量（判断视图是否覆盖了整个缓冲） */
    public func bufferLength(): Int64 {
        this.buf.length()
    }

    // ===== LispExternalIndexable =====

    /**
     * 元素总数 —— 与 `at` 配对
     *
     * 用总元素数而不是首维长度，是因为 `length` / `nth` 在 core 里是一对
     * （`(length x)` 个元素、`(nth x i)` 取第 i 个）。取"第 i 行"用 `slice`。
     */
    public func length(): Int64 {
        this.size()
    }

    /**
     * 按**扁平下标**取值（行优先展开）
     *
     * 对 `shape = [3, 4]`，`(nth a 5)` 是第 1 行第 1 列的元素。
     * 注意与 NumPy 不同（NumPy `a[5]` 对 2D 会报错），这里选择扁平语义是为了
     * 让 `length` / `nth` 这一对在任何维数下都自洽。
     */
    public func at(index: Int64): LispValue {
        if (index < 0 || index >= this.size()) {
            return LispValue.Error(XispError(
                ErrorType.RuntimeError,
                "ndarray 下标越界：${index}（元素总数 ${this.size()}）"
            ))
        }
        this.scalarAt(this.flatOfLinear(index))
    }

    // ===== 内部：下标换算 =====

    /** 逻辑下标 → buffer 下标 */
    internal func flatIndex(indices: Array<Int64>): Int64 {
        var f = this.off
        var i = 0
        while (i < this.dims.size) {
            f = f + indices[i] * this.steps[i]
            i++
        }
        f
    }

    /** 扁平下标（行优先）→ buffer 下标 */
    internal func flatOfLinear(linear: Int64): Int64 {
        if (this.dims.size == 0) {
            return this.off
        }
        let idx = Array<Int64>(this.dims.size, repeat: 0)
        var rem = linear
        var i = this.dims.size - 1
        while (i >= 0) {
            let d = this.dims[i]
            if (d == 0) {
                return this.off
            }
            idx[i] = rem % d
            rem = rem / d
            i--
        }
        this.flatIndex(idx)
    }

    // ===== 内部：取值与渲染 =====

    internal func scalarAt(flat: Int64): LispValue {
        match (this.buf) {
            case Ints(a) => LispValue.Int(a[flat])
            case Floats(a) => LispValue.Float(a[flat])
            case Bools(a) => LispValue.Boolean(a[flat])
        }
    }

    internal func scalarText(flat: Int64): String {
        match (this.buf) {
            case Ints(a) => a[flat].toString()
            case Floats(a) => formatFloatValue(a[flat])
            case Bools(a) => if (a[flat]) { "true" } else { "false" }
        }
    }

    internal func dtypeName(): String {
        this.dtype.name()
    }

    /** 每维最多显示这么多个元素，超了折中显示头尾 */
    static let DISPLAY_LIMIT: Int64 = 1000
    static let DISPLAY_HEAD: Int64 = 3
    static let DISPLAY_TAIL: Int64 = 3

    internal func renderDim(d: Int64, base: Int64): String {
        let sb = StringBuilder()
        let n = this.dims[d]
        let last = d == this.dims.size - 1
        sb.append("[")
        var i: Int64 = 0
        while (i < n) {
            // 截断续接：头部之后直接跳到尾部
            if (n > NDArray.DISPLAY_LIMIT && i == NDArray.DISPLAY_HEAD) {
                sb.append("... ")
                i = n - NDArray.DISPLAY_TAIL
            }
            if (i > 0 && !(n > NDArray.DISPLAY_LIMIT && i == n - NDArray.DISPLAY_TAIL)) {
                sb.append(" ")
            }
            let flat = base + i * this.steps[d]
            if (last) {
                sb.append(this.scalarText(flat))
            } else {
                sb.append(this.renderDim(d + 1, flat))
            }
            i++
        }
        sb.append("]")
        sb.toString()
    }

    // ===== 拷贝与连续性 =====

    /**
     * 是否按行优先连续排列
     *
     * `reshape` 只有在连续视图上才能零拷贝地改形状 —— 否则元素在 buffer 里的
     * 实际顺序与新形状不匹配，必须先 `copy()` 连续化。
     */
    public func isContiguous(): Bool {
        if (this.dims.size == 0) {
            return true
        }
        var expected: Int64 = 1
        var i = this.dims.size - 1
        while (i >= 0) {
            if (this.steps[i] != expected) {
                return false
            }
            expected = expected * this.dims[i]
            i--
        }
        true
    }

    /**
     * **零拷贝**取出连续的 Float64 数据
     *
     * 返回底层 `Array<Float64>` 的引用（仓颉的 `Array` 是引用类型，不复制）。
     *
     * ## 为什么要有这个方法
     *
     * 统计函数原本逐个 `a.at(i)` 取 `LispValue` 再 match 成 `Float64`，装进
     * `ArrayList` 再拷一遍 —— 10 万元素上这一步要 6~7 毫秒，而真正的计算只要
     * 0.06 毫秒。**跨层转换比计算本身慢 100 倍**。
     *
     * 直接从底层数组读就没有这个开销。
     *
     * ## 什么时候返回 None
     *
     * 只有「dtype 是 float64 + 连续 + 从缓冲区起点开始 + 没有多余尾部」四个条件
     * 全满足时才是零拷贝的。其余情况（int64 / bool / 非连续视图 / 带偏移）返回
     * `None`，调用方回退到逐个转换 —— 快路径不改变语义，只是快。
     */
    public func floatView(): Option<Array<Float64>> {
        if (!this.isContiguous()) {
            return None
        }
        match (this.buf) {
            case Floats(data) =>
                // 偏移与尾部都必须干脆，否则拿到的不是"这一整个数组"
                if (this.off != 0 || data.size != this.length()) {
                    return None
                }
                Some(data)
            case _ => None
        }
    }

    /** 深拷贝成一段新的连续缓冲 */
    public func copy(): NDArray {
        let n = this.size()
        let newSteps = contiguousStrides(this.dims)
        match (this.buf) {
            case Ints(_) =>
                let out = Array<Int64>(n, repeat: 0)
                var i: Int64 = 0
                while (i < n) {
                    out[i] = match (this.scalarAt(this.flatOfLinear(i))) {
                        case LispValue.Int(v) => v
                        case _ => 0
                    }
                    i++
                }
                NDArray(Ints(out), 0, this.dims.clone(), newSteps)
            case Floats(_) =>
                let out = Array<Float64>(n, repeat: 0.0)
                var i: Int64 = 0
                while (i < n) {
                    out[i] = match (this.scalarAt(this.flatOfLinear(i))) {
                        case LispValue.Float(v) => v
                        case _ => 0.0
                    }
                    i++
                }
                NDArray(Floats(out), 0, this.dims.clone(), newSteps)
            case Bools(_) =>
                let out = Array<Bool>(n, repeat: false)
                var i: Int64 = 0
                while (i < n) {
                    out[i] = match (this.scalarAt(this.flatOfLinear(i))) {
                        case LispValue.Boolean(v) => v
                        case _ => false
                    }
                    i++
                }
                NDArray(Bools(out), 0, this.dims.clone(), newSteps)
        }
    }
}

/** 行优先连续布局下，给定 shape 的 strides */
func contiguousStrides(dims: Array<Int64>): Array<Int64> {
    let out = Array<Int64>(dims.size, repeat: 1)
    var acc: Int64 = 1
    var i = dims.size - 1
    while (i >= 0) {
        out[i] = acc
        acc = acc * dims[i]
        i--
    }
    out
}

/** shape 的元素总数；负数维视为非法，返回 -1 */
func shapeSize(dims: Array<Int64>): Int64 {
    var n: Int64 = 1
    for (d in dims) {
        if (d < 0) {
            return -1
        }
        n = n * d
    }
    n
}

/**
 * 浮点数的显示文本
 *
 * `Float64.toString()` 固定给 6 位小数（`2.5` → `"2.500000"`），直接打印会让数组
 * 很难看。这里对整值补 `.0`、对小数去掉尾部多余的 0，与 `json-dump` 的
 * `.17g` 保真策略**故意不同** —— 那个是为了数据往返不失真，这个是给人看的。
 */
func formatFloatValue(f: Float64): String {
    // 先挡掉 nan / inf：`Int64(inf)` 会抛 OverflowException
    // （"Casting Infinite or NaN value to integer"），而数值计算里 inf / nan
    // 是正常结果（`(log 0)` 就是 -inf），显示层不能崩。
    if (f.isNaN()) {
        return "nan"
    }
    if (f.isInf()) {
        return if (f > 0.0) { "inf" } else { "-inf" }
    }
    if (f < 1e15 && f > -1e15 && f == Float64(Int64(f))) {
        return "${Int64(f)}.0"
    }
    var s = f.toString()
    while (s.size > 2 && s.endsWith("0") && !s.endsWith(".0")) {
        s = s[0..s.size - 1]
    }
    s
}
