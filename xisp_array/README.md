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

## 算术、归约与数学（阶段 2）

**不注册新符号** —— 复用 core 的同名内建，靠能力接口分派：

| 用法 | 分派接口 |
|---|---|
| `(+ arr arr)` / `(* arr 2)` / `(- 10 arr)` | `LispExternalArithmetic` |
| `(sum arr)` / `(max arr)` / `(product arr)` / `(min arr)` | `LispExternalReducible` |
| `(sin arr)` / `(sqrt arr)` / `(abs arr)` / `(floor arr)` | `LispExternalElementwise` |

```lisp
(+ (cangjie::array [1 2 3]) 10)                          ; #<ndarray int64 [11 12 13]>
(+ (cangjie::array [[1] [2]]) (cangjie::array [[3 4]]))  ; #<ndarray int64 [[4 5] [5 6]]>
(sum (cangjie::array [1 2 3 4]))                         ; 10
(sin (cangjie::array [0.0]))                             ; #<ndarray float64 [0.0]>
(floor (cangjie::array [3.7 -3.2]))                      ; #<ndarray int64 [3 -4]>
```

### 广播

NumPy 规则，**从尾部维度对齐**：

| a | b | 结果 |
|---|---|---|
| `[2,3]` | `[3]` | `[2,3]` |
| `[3,1]` | `[1,4]` | `[3,4]` |
| `[2,3]` | `[2]` | **不兼容** → `TypeError` |

零拷贝：被广播的维度把 **stride 置 0**，同一份数据在逻辑上重复，不复制。

### 类型规则

- 任一方 `float64` → 结果 `float64`；都是 `int64` → `int64`
- **除法恒 `float64`**（与 core 的 `(/ 1 2)` => `0.5` 一致）
- **`bool` 不参与算术** → `TypeError`（`#t + 1` 没有公认答案，隐式转 1 会把写错伪装成算出来）
- `floor` / `ceil` 结果转 `int64`；`abs` / `sign` 保留入参 dtype
- 定义域外返回 `nan` / `-inf` 而不是报错（与 core 的标量版本一致）
- **空数组归约一律拒绝** —— `sum` 空数组给 0 会让「文件读空了」伪装成正常结果

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
