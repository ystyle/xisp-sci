package ystyle::xisp_array

import ystyle::xisp.types.*

/**
 * 四则运算：实现 `LispExternalArithmetic`
 *
 * `(+ arr arr)` / `(* arr 2)` / `(- 10 arr)` 都由这里接管，core 不认识数组，
 * 只按接口分派。广播规则见 `broadcast.cj`。
 *
 * ## 结果类型
 *
 * | 情况 | 结果 dtype |
 * |---|---|
 * | 任一方 `float64` | `float64` |
 * | 都是 `int64` | `int64` |
 * | 运算符是 `/` | **恒 `float64`**（与 core 的 `/` 一致） |
 * | 任一方 `bool` | **不支持**（返回 `None` → `TypeError`） |
 *
 * `bool` 不参与算术是有意的：`#t + 1` 该得什么没有公认答案，隐式转成 1 会
 * 把"写错了"伪装成"算出来了"。
 */

/** 把数值标量包成 0 维数组，好让它走同一条广播路径 */
func scalarToZeroDim(v: LispValue): Option<NDArray> {
    match (v) {
        case Int(i) => Some(NDArray(Ints([i]), 0, Array<Int64>(), Array<Int64>()))
        case Float(x) => Some(NDArray(Floats([x]), 0, Array<Int64>(), Array<Int64>()))
        case _ => None
    }
}

/** 任一操作数转成可参与运算的数组：外部值取自身，数值标量包 0 维 */
func operandAsArray(v: LispValue): Option<NDArray> {
    match (v) {
        case External(e) =>
            match (e) {
                case a: NDArray => Some(a)
                case _ => None
            }
        case _ => scalarToZeroDim(v)
    }
}

/**
 * 四则运算的结果 dtype
 *
 * 返回 `None` 表示"这个组合不支持"，由 core 报 `TypeError`。
 */
func arithResultType(op: String, a: NDArray, b: NDArray): Option<DType> {
    // 除法恒为浮点：`[1 2] / 2` 得 `[0.5 1.0]`，与 core 的 `(/ 1 2)` => 0.5 一致
    if (op == "/") {
        if (a.dtype == DType.Bools || b.dtype == DType.Bools) {
            return None
        }
        return Some(DType.Floats)
    }
    if (a.dtype == DType.Bools || b.dtype == DType.Bools) {
        return None
    }
    if (a.dtype == DType.Floats || b.dtype == DType.Floats) {
        return Some(DType.Floats)
    }
    Some(DType.Ints)
}

func intBinop(op: String, x: Int64, y: Int64): Int64 {
    if (op == "+") {
        return x + y
    }
    if (op == "-") {
        return x - y
    }
    if (op == "*") {
        return x * y
    }
    x / y
}

func floatBinop(op: String, x: Float64, y: Float64): Float64 {
    if (op == "+") {
        return x + y
    }
    if (op == "-") {
        return x - y
    }
    if (op == "*") {
        return x * y
    }
    x / y
}

/**
 * 逐元素二元运算（广播已处理）
 *
 * 除法按 IEEE 语义走：`1.0 / 0.0` 得 `inf` 而不是报错。逐个元素检查除零会让
 * 向量化运算退化成标量循环 + 分支，而且"一批数据里有零"不该让整批计算失败。
 */
func elementwiseBinop(op: String, a: NDArray, b: NDArray,
                       target: Array<Int64>, dt: DType): NDArray {
    let n = shapeSize(target)
    let steps = contiguousStrides(target)
    let ba = broadcastTo(a, target)
    let bb = broadcastTo(b, target)
    match (dt) {
        case Floats =>
            let out = Array<Float64>(n, repeat: 0.0)
            var i: Int64 = 0
            while (i < n) {
                out[i] = floatBinop(op,
                    readAsFloat(ba, ba.flatOfLinear(i)),
                    readAsFloat(bb, bb.flatOfLinear(i)))
                i++
            }
            NDArray(Floats(out), 0, target.clone(), steps)
        case Ints =>
            let out = Array<Int64>(n, repeat: 0)
            var i: Int64 = 0
            while (i < n) {
                out[i] = intBinop(op,
                    readAsInt(ba, ba.flatOfLinear(i)),
                    readAsInt(bb, bb.flatOfLinear(i)))
                i++
            }
            NDArray(Ints(out), 0, target.clone(), steps)
        case Bools =>
            // arithResultType 已挡掉 bool，这里只是让 match 穷尽
            NDArray(Ints(Array<Int64>(0, repeat: 0)), 0, [0], [1])
    }
}

/**
 * 二元运算的总入口
 *
 * `selfOnRight` 为真表示 `other op self` —— 减法与除法不满足交换律，
 * 方向必须由调用方指明而不能靠"交换两个参数"。
 */
func binopWith(op: String, self: NDArray, other: LispValue, selfOnRight: Bool): Option<LispValue> {
    let rhs = match (operandAsArray(other)) {
        case Some(x) => x
        case None => return None
    }
    let left = if (selfOnRight) { rhs } else { self }
    let right = if (selfOnRight) { self } else { rhs }
    let target = match (broadcastShape(left.dims, right.dims)) {
        case Some(s) => s
        case None => return None
    }
    let dt = match (arithResultType(op, left, right)) {
        case Some(t) => t
        case None => return None
    }
    Some(LispValue.External(elementwiseBinop(op, left, right, target, dt)))
}

extend NDArray <: LispExternalArithmetic {
    public func arithLeft(op: String, other: LispValue): Option<LispValue> {
        binopWith(op, this, other, false)
    }

    public func arithRight(op: String, other: LispValue): Option<LispValue> {
        binopWith(op, this, other, true)
    }
}
