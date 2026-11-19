# 数组 array

`withArray()` 装配。9 个符号。

## 构造

| 符号 | 说明 |
|---|---|
| `cangjie::array` | 从字面量构造（嵌套 = 多维） |
| `cangjie::zeros` | `(zeros m n)` → m×n 全零 float64 |
| `cangjie::ones` | 全一 |
| `cangjie::arange` | `(arange start stop)` / `(arange start stop step)` |

## 变形与信息

| 符号 | 说明 |
|---|---|
| `cangjie::shape` | 返回形状列表，如 `[2 3]` |
| `cangjie::reshape` | `(reshape a [m n])`，`-1` 表示自动推断 |
| `cangjie::transpose` | 转置（不复制数据） |
| `cangjie::slice` | `(slice a i)` 沿第 0 维取第 i 行 |
| `cangjie::ndarray?` | 判断是否 ndarray |

## 核心内建（不属于本模块，但作用于数组）

这些由 `xisp` 核心提供，数组实现对应能力接口后自动获得：

### 索引与长度

```lisp
(length a)      ; **元素总数**
(nth a i)       ; 按行优先的**扁平**下标
```

### 算术

```lisp
(+ a b)  (- a b)  (* a b)  (/ a b)      ; 逐元素，支持广播
(- a)                                   ; 一元取负
(< a b)  (> a b)  (= a b)               ; 逐元素比较 → bool 数组
```

### 归约

```lisp
(sum a)  (product a)  (max a)  (min a)
```

`max` / `min` 是数学语义（NaN 传播）。数据分析场景用 `cangjie::max` / `cangjie::min`。

### 标量数学（逐元素）

```lisp
(sin a) (cos a) (tan a) (asin a) (acos a) (atan a)
(exp a) (log a) (log10 a) (sqrt a) (cbrt a)
(pow a b) (hypot a b)
(abs a) (floor a) (ceil a) (sign a) (round a)
```

## dtype

`int64` / `float64` / `bool`，从字面量自动推断。含小数 → `float64`。
`/` 的结果恒为 `float64`。

## 广播

NumPy 风格，从末维往前对齐，每维要么相等要么其中一个是 1。

实现上把被广播维的 stride 设为 0，**不复制数据**。

## 显示

```
#<ndarray float64 [1.5 2.5]>
#<ndarray int64 [[1 2] [3 4]]>
```

超过 20 个元素时截断显示。
