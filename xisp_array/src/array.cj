package ystyle::xisp_array

import ystyle::xisp.*
import ystyle::xisp.core.eval.*

/**
 * 数组能力域（科学计算族的地基）
 *
 * 本阶段只落**结构**：独立 workspace、对 `ystyle::xisp` 的依赖接缝、发布配置与闸门。
 * 符号清单为空，API 面等 `docs/plans/` 下的数组设计定稿后填入。
 *
 * `symbols` 必须与 `install` 里实际注册的符号保持一致 —— 它是沙箱审计、文档生成与
 * 跨域重名检出的唯一来源（能力域设计 §5.1 "把符号清单作为域声明的一部分"）。
 * 数组族会引入大量顶层符号（`shape` / `mean` / `fft`），与 core 内建重名风险高，
 * 所以这个清单不是装饰。
 */
public func arrayDomain(): LispCapability {
    SimpleCapability(
        "array",
        Array<String>(),
        { _ => () },
        // 数组运算不执行宿主传入的代码：不逃逸，可以让它进入 PRESET_PURE。
        // 将来若加入"对每个元素调用 Lisp 函数"这类高阶操作（如 `array-map`），
        // 必须重新评估为 true。
        escapable: false,
        hostPolicy: false)
}
