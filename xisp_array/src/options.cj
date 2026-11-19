package ystyle::xisp_array

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用数组能力（追加到默认装配之上，不清空已有内建）
 *
 * 用法：
 *
 * ```cangjie
 * let interp = LispInterpreter([withArray()])
 * ```
 *
 * 只要数组一档时用 `withDomains([arrayDomain()], replace: true)` —— 但那样连
 * `println` 都没有，需要自己补域。
 */
public func withArray(): InterpreterOption {
    withDomains([arrayDomain()])
}
