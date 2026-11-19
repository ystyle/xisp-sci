# xisp_sci

星枢科学计算**门面**：一次装齐全族能力。

```cangjie
let interp = LispInterpreter([withSci()])
interp.eval(#"(cangjie::mean (cangjie::array [1 2 3]))"#)
```

```lisp
;; 或从 Lisp 侧一次装齐
(cangjie::csv-read "sales.csv")     ; IO
(cangjie::std amount)               ; 统计
(cangjie::matmul A B)               ; 线代
(cangjie::fft-magnitude x)          ; 信号
(cangjie::polyfit x y 2)            ; 数值方法
(cangjie::array [[1 2] [3 4]])      ; 数组地基
```

## 为什么门面单独成一个成员

族内模块是**严格单向依赖**：`io` / `stats` / `linalg` / `signal` / `num` 互不依赖，
谁都不知道其它族存在。门面是唯一允许「知道所有族」的地方。

这样「只想用统计」的宿主可以只装 `xisp_stats`，不必把 FFT 和线代一起拖进来。

## 门面只做聚合

不含任何重实现。每个域只注册自己的符号（全部 `cangjie::` 前缀），装载顺序由
`LispCapability.after` 与域排序决定，不存在谁顶掉谁。跨域重名检测以
`LispCapability.symbols` 清单为唯一来源。

## 许可

MIT
