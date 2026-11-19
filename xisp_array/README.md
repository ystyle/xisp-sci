# xisp_array

星枢（[xisp](https://gitcode.com/ystyle/xisp)）科学计算族的**唯一地基**：NDArray 的
dtype / shape / strides / 广播 / 视图 / 基础归约。

同族其它模块（`io` / `linalg` / `stats` / `signal` / `sci`）都建立在它之上，
所以它的 API 一旦发布就要保持兼容。

## 当前状态

**阶段 1（地基）已完成**：数组能创建、观察、切片，切片是零拷贝视图。

| 类别 | 符号 |
|---|---|
| 构造 | `cangjie::array` / `cangjie::zeros` / `cangjie::ones` / `cangjie::arange` |
| 形状 | `cangjie::shape` / `cangjie::reshape`（含 `-1` 推断）/ `cangjie::transpose` |
| 视图 | `cangjie::slice`（沿第 0 维，共享缓冲） |
| 谓词 | `cangjie::ndarray?` |

`length` / `nth` / `type-of` 由 core 的通用内建通过 `LispExternalIndexable` 分派，
本域**不重复注册**（重复注册会顶掉 core 的实现）。

```lisp
(cangjie::array [[1 2] [3 4]])        ; #<ndarray int64 [[1 2] [3 4]]>
(cangjie::shape (cangjie::zeros 2 3)) ; (2 3)
(length (cangjie::arange 0 10))       ; 10
(nth (cangjie::arange 0 10) 3)        ; 3
(cangjie::slice (cangjie::arange 0 10) 2 5)  ; #<ndarray int64 [2 3 4]>
(type-of (cangjie::array [1]))        ; "ndarray"
```

**还没有算术与广播** —— `(+ arr arr)` 要等阶段 2，它阻塞在 core 侧的算术能力接口上。

## 布局与视图

默认**行优先（C 序）**：`shape = [3, 4]` 的 strides 是 `[4, 1]`，元素下标换算为
`offset + i0*strides[0] + i1*strides[1] + …`。

`reshape` / `transpose` / `slice` 返回**共享 buffer 的视图**（零拷贝）；`reshape`
在非连续数组上会先连续化。要独立副本用 `copy()`。

## 设计定位

数组**不**做成 core 的一等变体也能获得近乎一等的观感——`length` / `nth` / `print` / `=` /
`type-of` 会探测能力接口（`LispExternalIndexable` / `Equatable` / …），走 `External` 接入即可。
专用变体唯一不可替代的收益是**编译器特化**。

完整论证见 xisp 仓
[`docs/plans/2026-10-11-sci-family-design.md` §7](https://gitcode.com/ystyle/xisp/blob/master/docs/plans/2026-10-11-sci-family-design.md)。

## 许可

MIT
