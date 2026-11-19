# 信号处理

## FFT

```lisp
(cangjie::fft x)              ; → {"re": ndarray, "im": ndarray}
(cangjie::ifft s)             ; 逆变换，同样返回 {re, im}
(cangjie::fft-magnitude x)    ; 幅度谱 |X|
```

Lisp 层没有复数类型，所以复数用**两个数组**表示。这个接口是稳定的：内部从 Bluestein
换成混合基、或者将来 ndarray 支持复数 dtype，调用方写法都不用改。

### 任意长度

- 长度是 2 的幂 → 迭代 radix-2
- 任意长度 → **Bluestein**（chirp-z）：把 DFT 转成卷积，用 radix-2 算卷积，
  空间 O(M)、时间 O(M log M)

选 Bluestein 而不是混合基，是因为它**只在一个地方处理任意长度**：混合基要为 3、5、7
等因子分别写蝶形，复杂度和出错面都大得多。真需要更快的特定长度时再换，接口不变。

### 验证方式

**用朴素 DFT 作为独立参照**。用另一个 FFT 实现验证一个 FFT 实现是没意义的，
共模故障（比如 chirp 的符号写反）会一起错。

朴素 DFT 按定义直接算，O(n²)，但它对「FFT 该等于什么」是独立判据。测试覆盖
1/2/3/4/5/7/8/16/17/32/100 共 11 种长度，含非 2 的幂。

## 卷积

```lisp
(cangjie::conv x y)      ; full 卷积，长度 n+m-1
```

小数组直接法（`n·m ≤ 4096`），大数组走 FFT。阈值是内部细节，接口不变。

## IIR 滤波

```lisp
(cangjie::filter b a x)
```

`y[n] = (Σ b[i]·x[n−i] − Σ a[i]·y[n−i]) / a[0]`

`a[0]` 不能为 0（那是退化到无穷大的递推）。越界的 `x` 当 0 处理，输出长度与输入相同。

两抽头移动平均：

```lisp
(cangjie::filter (cangjie::array [0.5 0.5]) (cangjie::array [1.0])
                 (cangjie::array [1.0 2.0 3.0 4.0]))
;; → [0.5 1.5 2.5 3.5]
```

## 窗函数

```lisp
(cangjie::window "hann" 64)
(cangjie::window "hamming" 64)
(cangjie::window "blackman" 64)
(cangjie::window "rect" 64)
```

做频谱分析前先加窗：直接对截断的信号做 FFT 会引入频谱泄漏，因为截断相当于乘了一个
矩形窗，它的旁瓣会让强信号的频率成分「渗」到邻近频段去。
