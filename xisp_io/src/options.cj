package ystyle::xisp_io

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用 CSV 能力（追加到默认装配之上）
 *
 * ```cangjie
 * let interp = LispInterpreter([withArray(), withCsv()])
 * interp.eval(#"(cangjie::csv-read "sales.csv")"#)
 * ```
 *
 * 注意 `csv` 域的 `hostPolicy = true`（读写宿主文件），所以它**不会**进入
 * `PRESET_PURE` —— 纯环境里根本读不到文件，声明成纯只是自欺欺人。
 */
public func withCsv(): InterpreterOption {
    withDomains([csvDomain()])
}
