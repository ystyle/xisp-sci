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
    "cangjie::lstsq",
    // 分解与派生量（svd.cj / derived.cj）
    "cangjie::svd", "cangjie::eigen", "cangjie::rank", "cangjie::cond",
    "cangjie::ginv", "cangjie::pca"]

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

    // ───────── 奇异值分解与对称特征分解（svd.cj）─────────

    // (cangjie::svd A) —— A = U·diag(S)·Vᵀ，返回 {u, s, vt}
    env.define("cangjie::svd", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::svd")
            svdLispOf(args[0])
        })
    }))

    // (cangjie::eigen A) —— 只接受对称矩阵，返回 {values, vectors}
    env.define("cangjie::eigen", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::eigen")
            eigenLispOf(args[0])
        })
    }))

    // ───────── 派生量（derived.cj）─────────

    env.define("cangjie::rank", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::rank")
            rankLispOf(args[0])
        })
    }))

    env.define("cangjie::cond", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::cond")
            condLispOf(args[0])
        })
    }))

    env.define("cangjie::ginv", NativeFunc({ args =>
        guardedLinalg({ =>
            arity(args, 1, "cangjie::ginv")
            pinvLispOf(args[0])
        })
    }))

    // (cangjie::pca X) / (cangjie::pca X k)
    env.define("cangjie::pca", NativeFunc({ args =>
        guardedLinalg({ =>
            pcaLispOf(args)
        })
    }))
}
