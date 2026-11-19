package ystyle::xisp_array

import ystyle::xisp.types.*
import std.collection.ArrayList

/**
 * Lisp 值 ↔ NDArray 转换
 *
 * 数组字面量从**嵌套列表**构造：`[1 2 3]` 是 1D，`[[1 2] [3 4]]` 是 2D。
 * `[...]` 在 xisp 里的语义是 `(cangjie::vector ...)` → 列表，本模块**不改**这个语义
 * —— 装一个域就改变语言字面量的含义，违反最小惊讶，且会让所有既有 `[...]` 代码变行为。
 * 要数组就显式写 `(cangjie::array [...])`。
 *
 * 规整性（ragged）检查是必须的：`[[1 2] [3]]` 在 NumPy 里会退化成 object 数组，
 * 这里直接报错 —— 静默降级比报错更难查。
 */

/** 只支持这三个标量类型；`nil` 按空列表处理，因此 `[1 nil]` 是非法嵌套 */
class DTypeScan {
    var hasInt: Bool = false
    var hasFloat: Bool = false
    var hasBool: Bool = false
    var badTypeName: String = ""
}

/** 填充游标 —— 仓颉不支持引用传参，用可变对象在递归中传递位置 */
class Cursor {
    var pos: Int64 = 0
}

func isListValue(v: LispValue): Bool {
    match (v) {
        case Cons(_) => true
        case Nil => true
        case _ => false
    }
}

func listElements(v: LispValue): ArrayList<LispValue> {
    let out = ArrayList<LispValue>()
    var cur = v
    var go = true
    while (go) {
        match (cur) {
            case Cons(cell) =>
                out.add(cell.car)
                cur = cell.cdr
            case _ => go = false
        }
    }
    out
}

func listFrom(items: ArrayList<LispValue>): LispValue {
    var result: LispValue = Nil
    var i = items.size - 1
    while (i >= 0) {
        result = consValue(items[i], result)
        i--
    }
    result
}

func sameShape(a: Array<Int64>, b: Array<Int64>): Bool {
    if (a.size != b.size) {
        return false
    }
    var i: Int64 = 0
    while (i < a.size) {
        if (a[i] != b[i]) {
            return false
        }
        i++
    }
    true
}

/**
 * 求嵌套列表的形状
 *
 * 标量返回 0 维（空数组）；`[]` 返回 `[0]`；`[[], []]` 返回 `[2, 0]`。
 * 同一层的各元素形状必须一致，否则报错。
 */
func deepShape(v: LispValue): Array<Int64> {
    if (!isListValue(v)) {
        return Array<Int64>()
    }
    let elems = listElements(v)
    let out = ArrayList<Int64>()
    out.add(elems.size)
    if (elems.size == 0) {
        return out.toArray()
    }
    let first = deepShape(elems[0])
    var i: Int64 = 1
    while (i < elems.size) {
        let s = deepShape(elems[i])
        if (!sameShape(s, first)) {
            throw IllegalArgumentException(
                "数组字面量不是规整嵌套：第 0 个元素形状 ${first}，第 ${i} 个是 ${s}")
        }
        i++
    }
    for (d in first) {
        out.add(d)
    }
    out.toArray()
}

func scalarTypeName(v: LispValue): String {
    match (v) {
        case Int(_) => "int64"
        case Float(_) => "float64"
        case Boolean(_) => "bool"
        case Str(_) => "string"
        case Symbol(_) => "symbol"
        case HashMap(_) => "hashmap"
        case External(_) => "external"
        case Error(_) => "error"
        case Cons(_) => "list"
        case _ => "procedure"
    }
}

func scanDType(v: LispValue, s: DTypeScan): Unit {
    if (isListValue(v)) {
        for (e in listElements(v)) {
            scanDType(e, s)
        }
        return
    }
    match (v) {
        case Int(_) => s.hasInt = true
        case Float(_) => s.hasFloat = true
        case Boolean(_) => s.hasBool = true
        case _ =>
            if (s.badTypeName.size == 0) {
                s.badTypeName = scalarTypeName(v)
            }
    }
}

func resolveDType(s: DTypeScan): DType {
    if (s.badTypeName.size > 0) {
        throw IllegalArgumentException(
            "数组元素类型不支持：${s.badTypeName}（只支持 int64 / float64 / bool）")
    }
    // float 优先：int 与 float 混排时整体提升为 float64（与 C / NumPy 一致）
    if (s.hasFloat) {
        return DType.Floats
    }
    if (s.hasBool) {
        if (s.hasInt) {
            throw IllegalArgumentException(
                "数组不能混合 bool 与 int —— 隐式提升会把 true 变成 1，掩盖语义错误")
        }
        return DType.Bools
    }
    if (s.hasInt) {
        return DType.Ints
    }
    // 空数组没有元素可推断，默认 float64
    DType.Floats
}

func fillInts(v: LispValue, buf: Array<Int64>, c: Cursor): Unit {
    if (isListValue(v)) {
        for (e in listElements(v)) {
            fillInts(e, buf, c)
        }
        return
    }
    match (v) {
        case Int(x) => buf[c.pos] = x
        case Float(x) => buf[c.pos] = Int64(x)
        case Boolean(b) => buf[c.pos] = if (b) { 1 } else { 0 }
        case _ => ()
    }
    c.pos++
}

func fillFloats(v: LispValue, buf: Array<Float64>, c: Cursor): Unit {
    if (isListValue(v)) {
        for (e in listElements(v)) {
            fillFloats(e, buf, c)
        }
        return
    }
    match (v) {
        case Int(x) => buf[c.pos] = Float64(x)
        case Float(x) => buf[c.pos] = x
        case Boolean(b) => buf[c.pos] = if (b) { 1.0 } else { 0.0 }
        case _ => ()
    }
    c.pos++
}

func fillBools(v: LispValue, buf: Array<Bool>, c: Cursor): Unit {
    if (isListValue(v)) {
        for (e in listElements(v)) {
            fillBools(e, buf, c)
        }
        return
    }
    match (v) {
        case Boolean(b) => buf[c.pos] = b
        case _ => ()
    }
    c.pos++
}

/**
 * 从嵌套列表构造数组
 *
 * dtype 推断规则：含 float → float64；全 int → int64；全 bool → bool。
 * `bool` 与 `int` 混排**报错**（不隐式转换），空数组默认 float64。
 */
public func arrayFromLisp(value: LispValue): NDArray {
    let dims = deepShape(value)
    let scan = DTypeScan()
    scanDType(value, scan)
    let dt = resolveDType(scan)
    let n = shapeSize(dims)
    let steps = contiguousStrides(dims)
    match (dt) {
        case Ints =>
            let buf = Array<Int64>(n, repeat: 0)
            fillInts(value, buf, Cursor())
            NDArray(Ints(buf), 0, dims, steps)
        case Floats =>
            let buf = Array<Float64>(n, repeat: 0.0)
            fillFloats(value, buf, Cursor())
            NDArray(Floats(buf), 0, dims, steps)
        case Bools =>
            let buf = Array<Bool>(n, repeat: false)
            fillBools(value, buf, Cursor())
            NDArray(Bools(buf), 0, dims, steps)
    }
}

/**
 * 从 `cangjie::array` 的实参构造
 *
 * 两种写法都要通：
 *
 * ```lisp
 * (cangjie::array [1 2 3])      ; 单参数：整个嵌套列表照原样解释
 * (cangjie::array 1 2 3)        ; 变参：实参本身就是顶层列表
 * ```
 */
public func arrayFromArgs(args: ArrayList<LispValue>): NDArray {
    if (args.size == 1) {
        return arrayFromLisp(args[0])
    }
    arrayFromLisp(listFrom(args))
}
