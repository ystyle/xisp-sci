package ystyle::xisp_array

import ystyle::xisp.types.*

/**
 * 归约：实现 `LispExternalReducible`
 *
 * `sum` / `product` / `max` / `min` 遇到数组时走这里，而不是 core 逐元素装箱。
 *
 * ## 空数组
 *
 * 一律返回 `None`（→ core 报 `TypeError`）。`sum` 空数组是 0 还是"无意义"？
 * 数学上单位元是 0，但把它当成功会让"读文件读空了"这类 bug 伪装成一个正常的 0。
 * `max` 更是没有单位元。统一拒绝，让调用方显式判断长度。
 *
 * ## Bool 数组
 *
 * `max` / `min` 可用（`false < true`），`sum` / `product` 不支持 —— 布尔求和
 * 是"数 true 的个数"，那是 `count` 不是 `sum`，不该混在一个符号里。
 */
func reduceArray(a: NDArray, op: String): Option<LispValue> {
    let n = a.size()
    if (n == 0) {
        return None
    }
    // 用逻辑下标读，视图可能非连续
    let isSum = op == "sum"
    let isProduct = op == "product"
    let isMax = op == "max"
    let isMin = op == "min"
    if (!isSum && !isProduct && !isMax && !isMin) {
        return None
    }
    match (a.dtype) {
        case Ints =>
            var acc = readAsInt(a, a.flatOfLinear(0))
            if (isSum || isProduct) {
                // 从第 2 个元素开始累加（第 1 个已作为初值）
                var i: Int64 = 1
                while (i < n) {
                    let v = readAsInt(a, a.flatOfLinear(i))
                    if (isSum) {
                        acc = acc + v
                    } else {
                        acc = acc * v
                    }
                    i++
                }
                return Some(LispValue.Int(acc))
            }
            var i: Int64 = 1
            while (i < n) {
                let v = readAsInt(a, a.flatOfLinear(i))
                if (isMax && v > acc) {
                    acc = v
                }
                if (isMin && v < acc) {
                    acc = v
                }
                i++
            }
            Some(LispValue.Int(acc))
        case Floats =>
            // **快路径**：连续 float64 直接迭代底层数组，省掉每元素一次
            // `flatOfLinear` + `at` 的逻辑下标计算（10 万元素上差 40 倍）。
            match (a.floatView()) {
                case Some(data) =>
                    var acc = data[0]
                    if (isSum || isProduct) {
                        var i: Int64 = 1
                        while (i < n) {
                            if (isSum) {
                                acc = acc + data[i]
                            } else {
                                acc = acc * data[i]
                            }
                            i++
                        }
                        return Some(LispValue.Float(acc))
                    }
                    var i: Int64 = 1
                    while (i < n) {
                        if (isMax && data[i] > acc) {
                            acc = data[i]
                        }
                        if (isMin && data[i] < acc) {
                            acc = data[i]
                        }
                        i++
                    }
                    return Some(LispValue.Float(acc))
                case None => ()
            }
            var acc = readAsFloat(a, a.flatOfLinear(0))
            if (isSum || isProduct) {
                var i: Int64 = 1
                while (i < n) {
                    let v = readAsFloat(a, a.flatOfLinear(i))
                    if (isSum) {
                        acc = acc + v
                    } else {
                        acc = acc * v
                    }
                    i++
                }
                return Some(LispValue.Float(acc))
            }
            var i: Int64 = 1
            while (i < n) {
                let v = readAsFloat(a, a.flatOfLinear(i))
                if (isMax && v > acc) {
                    acc = v
                }
                if (isMin && v < acc) {
                    acc = v
                }
                i++
            }
            Some(LispValue.Float(acc))
        case Bools =>
            if (isSum || isProduct) {
                return None
            }
            var acc = readAsBool(a, a.flatOfLinear(0))
            var i: Int64 = 1
            while (i < n) {
                let v = readAsBool(a, a.flatOfLinear(i))
                if (isMax && v && !acc) {
                    acc = v
                }
                if (isMin && !v && acc) {
                    acc = v
                }
                i++
            }
            Some(LispValue.Boolean(acc))
    }
}

extend NDArray <: LispExternalReducible {
    public func reduceAll(op: String): Option<LispValue> {
        reduceArray(this, op)
    }
}
