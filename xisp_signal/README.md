# xisp_signal

星枢科学计算信号处理：FFT、卷积、IIR 滤波、窗函数。

```lisp
(cangjie::fft-magnitude (cangjie::array [1.0 0.0 -1.0 0.0]))   ; 幅度谱
(cangjie::conv x y)                                            ; 一维卷积（full）
(cangjie::filter b a x)                                        ; IIR 滤波
(cangjie::window "hann" 64)                                    ; 窗函数
```

## 复数怎么表示

Lisp 层没有复数类型，一律用 **`{"re": ndarray, "im": ndarray}`**：

```lisp
(define spectrum (cangjie::fft x))
(hashmap-get spectrum "re")   ; 实部
(hashmap-get spectrum "im")   ; 虚部
(cangjie::ifft spectrum)      ; 逆变换，同样返回 {re, im}
```

这个接口是**稳定的** —— 内部从 Bluestein 换成混合基、或者将来 ndarray 支持复数 dtype，
Lisp 层的写法都不用改。

## 符号

| 符号 | 说明 |
|---|---|
| `cangjie::fft` | 正变换，`输出 {re, im}` |
| `cangjie::ifft` | 逆变换 |
| `cangjie::fft-magnitude` | 幅度谱 `|X|` |
| `cangjie::conv` | 一维卷积（full 长度 `n+m-1`） |
| `cangjie::filter` | IIR 滤波 `y[n] = (Σ b[i]x[n-i] − Σ a[i]y[n-i]) / a[0]` |
| `cangjie::window` | `rect` / `hann` / `hamming` / `blackman` |

## 算法

**FFT**：长度是 2 的幂走迭代 radix-2；任意长度走 **Bluestein**（chirp-z）——
把 DFT 转成卷积用 radix-2 算，O(M log M)。选 Bluestein 而不是混合基，是因为它
**只在一个地方处理任意长度**：混合基要为 3、5、7 等因子分别写蝶形，复杂度和出错面
都大得多。真需要更快的特定长度时再换，**Lisp 接口不变**。

**卷积**：小数组直接法（`n·m ≤ 4096`），大数组走 FFT。阈值是内部细节。

**QR 用 Householder**（在 `xisp_linalg`），不是 Gram-Schmidt —— 后者在近线性相关的
列上会严重丢正交性。

## 测试

**核心手法是用朴素 DFT 作为独立参照**。用另一个 FFT 实现验证一个 FFT 实现是没意义的
——共模故障（比如 chirp 的符号写反）会一起错。朴素 DFT 按定义直接算，虽然 O(n²)，
但它对"FFT 该等于什么"是独立判据。

覆盖 11 种长度（1/2/3/4/5/7/8/16/17/32/100），含非 2 的幂。

## 许可

MIT
