package ystyle::xisp_signal

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 启用信号处理能力（追加到默认装配之上）
 *
 * ```cangjie
 * let interp = LispInterpreter([withArray(), withSignal()])
 * interp.eval("(cangjie::fft-magnitude (cangjie::array [1.0 0.0 -1.0 0.0]))")
 * ```
 *
 * 纯计算，可进 `PRESET_PURE`。
 */
public func withSignal(): InterpreterOption {
    withDomains([signalDomain()])
}
