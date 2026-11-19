# 信号处理 signal

`withSignal()` 装配。6 个符号。

## FFT

| 符号 | 说明 |
|---|---|
| `cangjie::fft` | 正变换 → `{re, im}` |
| `cangjie::ifft` | 逆变换 → `{re, im}` |
| `cangjie::fft-magnitude` | 幅度谱 `|X|` → ndarray |

输入接受 ndarray（实数序列）或 `{re, im}`（完整复数）。

长度是 2 的幂走 radix-2，任意长度走 Bluestein（chirp-z）。

## 卷积

| 符号 | 说明 |
|---|---|
| `cangjie::conv` | `(conv x y)` 一维 full 卷积，长度 `n+m-1` |

小数组直接法，大数组走 FFT（阈值是内部细节）。

## 滤波

| 符号 | 说明 |
|---|---|
| `cangjie::filter` | `(filter b a x)` IIR 滤波 |

`y[n] = (Σ b[i]·x[n−i] − Σ a[i]·y[n−i]) / a[0]`

`a[0]` 不能为 0。越界 `x` 当 0，输出长度与输入相同。

## 窗函数

| 符号 | 说明 |
|---|---|
| `cangjie::window` | `(window kind n)`，kind ∈ `rect` / `hann` / `hamming` / `blackman` |

## 复数的表示

Lisp 层没有复数类型，一律用 `{"re": ndarray, "im": ndarray}`。

这个接口是稳定的：内部换算法、或将来 ndarray 支持复数 dtype，调用方写法都不变。
