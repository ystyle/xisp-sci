package ystyle::xisp_array

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import std.collection.ArrayList

/**
 * 数组能力域
 *
 * 符号统一用 `cangjie::` 命名空间 —— 与 `cangjie::json-get` / `cangjie::http-get` /
 * `cangjie::httpd-listen` 保持一致，也避免与 core 内建（`length` / `nth` / `shape`
 * 这类通用名）抢名字。
 *
 * `length` / `nth` / `type-of` 不在清单里 —— 它们由 core 的通用内建通过
 * `LispExternalIndexable` 分派，本域不需要也不应该重复注册（重复注册会顶掉 core 的实现）。
 */
public func arrayDomain(): LispCapability {
    SimpleCapability(
        "array",
        ["cangjie::array", "cangjie::zeros", "cangjie::ones", "cangjie::arange",
         "cangjie::shape", "cangjie::reshape", "cangjie::transpose", "cangjie::slice",
         "cangjie::ndarray?",
         // 排序与累积归约（order.cj）
         "cangjie::sort", "cangjie::sort-desc", "cangjie::order",
         "cangjie::cumsum", "cangjie::cumprod", "cangjie::ranks"],
        { ctx => registerArray(ctx.env) },
        // 数组运算不执行宿主传入的代码：不逃逸，可以进 PRESET_PURE。
        // 将来若加入"对每个元素调用 Lisp 函数"这类高阶操作（如 array-map），
        // 必须重新评估为 true —— 那时数值计算就不再是纯数据操作了。
        escapable: false,
        hostPolicy: false)
}

/** 把内部异常转成 Lisp 错误值；内部函数用抛异常表达失败，避免每步 match */
func guarded(action: () -> LispValue): LispValue {
    try {
        action()
    } catch (e: IllegalArgumentException) {
        LispValue.Error(XispError(ErrorType.TypeError, e.message))
    } catch (e: Exception) {
        LispValue.Error(XispError(ErrorType.RuntimeError, e.message))
    }
}

func arity(args: ArrayList<LispValue>, want: Int64, who: String): Unit {
    if (args.size != want) {
        throw IllegalArgumentException("${who} 需要 ${want} 个参数，得到 ${args.size} 个")
    }
}

func asNDArray(v: LispValue, who: String): NDArray {
    match (v) {
        case External(e) =>
            match (e) {
                case nd: NDArray => nd
                case _ => throw IllegalArgumentException(
                    "${who} 需要 ndarray，得到外部值 ${e.typeName}")
            }
        case _ => throw IllegalArgumentException(
            "${who} 需要 ndarray，得到 ${scalarTypeName(v)}")
    }
}

func intOf(v: LispValue, who: String): Int64 {
    match (v) {
        case Int(x) => x
        case Float(x) =>
            if (x != Float64(Int64(x))) {
                throw IllegalArgumentException("${who} 需要整数，得到 ${x}")
            }
            Int64(x)
        case _ => throw IllegalArgumentException(
            "${who} 需要整数，得到 ${scalarTypeName(v)}")
    }
}

/**
 * 解析维度参数
 *
 * 两种写法都通：`(zeros 3 4)` 与 `(zeros [3 4])`。
 */
func dimsOf(args: ArrayList<LispValue>, who: String): Array<Int64> {
    let out = ArrayList<Int64>()
    if (args.size == 1 && isListValue(args[0])) {
        for (e in listElements(args[0])) {
            out.add(intOf(e, who))
        }
    } else {
        for (e in args) {
            out.add(intOf(e, who))
        }
    }
    out.toArray()
}

func intsToLisp(values: Array<Int64>): LispValue {
    var result: LispValue = Nil
    var i = values.size - 1
    while (i >= 0) {
        result = consValue(LispValue.Int(values[i]), result)
        i--
    }
    result
}

func registerArray(env: Environment): Unit {
    // (cangjie::array [1 2 3]) / (cangjie::array 1 2 3) / (cangjie::array [[1 2] [3 4]])
    env.define("cangjie::array", NativeFunc({ args =>
        guarded({ =>
            LispValue.External(arrayFromArgs(args))
        })
    }))

    env.define("cangjie::zeros", NativeFunc({ args =>
        guarded({ =>
            if (args.size == 0) {
                throw IllegalArgumentException("cangjie::zeros 至少需要一个维度")
            }
            LispValue.External(zerosArray(dimsOf(args, "cangjie::zeros")))
        })
    }))

    env.define("cangjie::ones", NativeFunc({ args =>
        guarded({ =>
            if (args.size == 0) {
                throw IllegalArgumentException("cangjie::ones 至少需要一个维度")
            }
            LispValue.External(onesArray(dimsOf(args, "cangjie::ones")))
        })
    }))

    // (cangjie::arange 0 10) / (cangjie::arange 0 10 2) / (cangjie::arange 0 1 0.1)
    env.define("cangjie::arange", NativeFunc({ args =>
        guarded({ =>
            if (args.size != 2 && args.size != 3) {
                throw IllegalArgumentException(
                    "cangjie::arange 需要 2 或 3 个参数（start end [step]），得到 ${args.size} 个")
            }
            let allInts = allIntArgs(args)
            if (allInts) {
                let start = intOf(args[0], "cangjie::arange")
                let end = intOf(args[1], "cangjie::arange")
                let step = if (args.size == 3) { intOf(args[2], "cangjie::arange") } else { 1 }
                LispValue.External(arangeInts(start, end, step))
            } else {
                let start = floatOf(args[0], "cangjie::arange")
                let end = floatOf(args[1], "cangjie::arange")
                let step = if (args.size == 3) { floatOf(args[2], "cangjie::arange") } else { 1.0 }
                LispValue.External(arangeFloats(start, end, step))
            }
        })
    }))

    // (cangjie::shape a) → (3 4)
    env.define("cangjie::shape", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::shape")
            intsToLisp(asNDArray(args[0], "cangjie::shape").shape)
        })
    }))

    // (cangjie::reshape a [4]) / (cangjie::reshape a 4) / (cangjie::reshape a [-1])
    env.define("cangjie::reshape", NativeFunc({ args =>
        guarded({ =>
            if (args.size < 2) {
                throw IllegalArgumentException("cangjie::reshape 需要数组和至少一个维度")
            }
            let a = asNDArray(args[0], "cangjie::reshape")
            let rest = ArrayList<LispValue>()
            var i: Int64 = 1
            while (i < args.size) {
                rest.add(args[i])
                i++
            }
            LispValue.External(reshapeArray(a, dimsOf(rest, "cangjie::reshape")))
        })
    }))

    // (cangjie::transpose a)
    env.define("cangjie::transpose", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::transpose")
            LispValue.External(transposeArray(asNDArray(args[0], "cangjie::transpose")))
        })
    }))

    // (cangjie::slice a 1 3) —— 沿第 0 维 [start, end)
    env.define("cangjie::slice", NativeFunc({ args =>
        guarded({ =>
            arity(args, 3, "cangjie::slice")
            let a = asNDArray(args[0], "cangjie::slice")
            let start = intOf(args[1], "cangjie::slice")
            let end = intOf(args[2], "cangjie::slice")
            LispValue.External(sliceArray(a, start, end))
        })
    }))

    // (cangjie::ndarray? x)
    env.define("cangjie::ndarray?", NativeFunc({ args =>
        guarded({ =>
            arity(args, 1, "cangjie::ndarray?")
            let hit = match (args[0]) {
                case External(e) => match (e) {
                    case _: NDArray => true
                    case _ => false
                }
                case _ => false
            }
            LispValue.Boolean(hit)
        })
    }))

    // 排序与累积归约（order.cj）：纯数组操作，不碰宿主资源
    registerOrder(env)
}

func allIntArgs(args: ArrayList<LispValue>): Bool {
    for (a in args) {
        match (a) {
            case Int(_) => ()
            case _ => return false
        }
    }
    true
}

func floatOf(v: LispValue, who: String): Float64 {
    match (v) {
        case Float(x) => x
        case Int(x) => Float64(x)
        case _ => throw IllegalArgumentException(
            "${who} 需要数值，得到 ${scalarTypeName(v)}")
    }
}
