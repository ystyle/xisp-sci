package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.types.*
import ystyle::xisp.core.eval.*
import std.collection.ArrayList

/**
 * 线性代数能力域
 *
 * 纯仓颉实现，**不依赖 BLAS / LAPACK** —— cjpm 没有可选依赖，接 C 库意味着每个
 * 用本模块的宿主都得装 C 工具链，与 `xisp_array` 的零依赖前提冲突。
 * 详见路线图 §6 S4。
 */

let LINALG_SYMBOLS: Array<String> = [
    "cangjie::matmul", "cangjie::trace", "cangjie::det", "cangjie::solve",
    "cangjie::inv", "cangjie::cholesky", "cangjie::lu", "cangjie::qr",
    "cangjie::lstsq"]

public func linalgDomain(): LispCapability {
    SimpleCapability(
        "linalg",
        LINALG_SYMBOLS,
        { ctx => registerLinalg(ctx.env) },
        // 纯计算，不触及宿主资源
        escapable: false,
        hostPolicy: false)
}

func guardedLinalg(action: () -> LispValue): LispValue {
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

func registerLinalg(env: Environment): Unit {
    env.define("cangjie::matmul", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 2, "cangjie::matmul")
            matmulLisp(args[0], args[1])
        })
    }))

    env.define("cangjie::trace", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::trace")
            LispValue.Float(traceOf(args[0]))
        })
    }))

    env.define("cangjie::det", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::det")
            LispValue.Float(detOf(args[0]))
        })
    }))

    env.define("cangjie::solve", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 2, "cangjie::solve")
            solveLisp(args[0], args[1])
        })
    }))

    env.define("cangjie::inv", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::inv")
            invOf(args[0])
        })
    }))

    env.define("cangjie::cholesky", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::cholesky")
            choleskyOf(args[0])
        })
    }))

    env.define("cangjie::lu", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::lu")
            luLispOf(args[0])
        })
    }))

    env.define("cangjie::qr", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::qr")
            qrLispOf(args[0])
        })
    }))

    // (cangjie::lstsq X y) —— 最小二乘（多元线性回归的地基）
    env.define("cangjie::lstsq", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 2, "cangjie::lstsq")
            lstsqLisp(args[0], args[1])
        })
    }))
}
