package ystyle::xisp_stats

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用统计能力（追加到默认装配之上）
 *
 * ```cangjie
 * let interp = LispInterpreter([withArray(), withStats()])
 * interp.eval("(cangjie::mean (cangjie::array [1 2 3]))")
 * ```
 *
 * `stats` 是纯计算域（`hostPolicy = false` / `escapable = false`），可以进 `PRESET_PURE`。
 */
public func withStats(): InterpreterOption {
    withDomains([statsDomain()])
}
