package ystyle::xisp_num

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用数值方法能力（追加到默认装配之上）
 *
 * 纯计算，可进 `PRESET_PURE`。
 */
public func withNum(): InterpreterOption {
    withDomains([numDomain()])
}
