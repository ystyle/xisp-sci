package ystyle::xisp_linalg

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用线性代数能力（追加到默认装配之上）
 *
 * ```cangjie
 * let interp = LispInterpreter([withArray(), withLinalg()])
 * interp.eval("(cangjie::det (cangjie::array [[1 2] [3 4]]))")
 * ```
 *
 * 纯仓颉实现，`hostPolicy = false` / `escapable = false`，可进 `PRESET_PURE`。
 */
public func withLinalg(): InterpreterOption {
    withDomains([linalgDomain()])
}
