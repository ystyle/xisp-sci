package ystyle::xisp_sci

import ystyle::xisp.*
import ystyle::xisp.core.eval.*
import ystyle::xisp_array.*
import ystyle::xisp_io.*
import ystyle::xisp_stats.*
import ystyle::xisp_linalg.*
import ystyle::xisp_signal.*
import ystyle::xisp_num.*

/**
 * 科学计算门面
 *
 * 一次装齐全族能力，宿主不必逐个 `withArray()` / `withCsv()` / `withStats()`…
 *
 * ```cangjie
 * let interp = LispInterpreter([withSci()])
 * interp.eval(#"(cangjie::mean (cangjie::array [1 2 3]))"#)
 * ```
 *
 * ## 为什么门面要单独成一个成员
 *
 * 族内模块是**严格单向依赖**：`io` / `stats` / `linalg` / `signal` / `num` 互不依赖，
 * 谁也不知道其它族存在。门面是唯一允许"知道所有族"的地方 —— 它只做聚合，
 * 不含任何重实现。这样"只想用统计"的宿主可以只装 `xisp_stats`，
 * 不必把 FFT 和线代一起拖进来。
 *
 * ## 符号冲突
 *
 * 门面装的是**域**，每个域只注册自己的符号（全部 `cangjie::` 前缀）。装载顺序由
 * `LispCapability.after` 与域排序决定，不存在谁顶掉谁的问题 —— 如果要检测跨域重名，
 * `LispCapability.symbols` 清单是唯一来源（沙箱审计与文档生成也读它）。
 */

/** 全族的域清单（顺序由 `orderDomains` 按 `after` 约束重排） */
public func sciDomains(): Array<LispCapability> {
    [
        arrayDomain(),
        csvDomain(),
        statsDomain(),
        linalgDomain(),
        signalDomain(),
        numDomain()
    ]
}

/**
 * 一次装齐全族能力（追加到默认装配之上）
 *
 * 注意 `csv` 域是 `hostPolicy = true`（读写宿主文件），所以整族不会进
 * `PRESET_PURE` —— 要纯计算环境的话，用 `withDomains([arrayDomain(), statsDomain(), …])`
 * 自己挑。
 */
public func withSci(): InterpreterOption {
    withDomains(sciDomains())
}
