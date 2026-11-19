# xisp_linalg_blas

`xisp_linalg` 的**可选** BLAS 加速后端。零 C 代码 —— 只有 `foreign` 声明。

```cangjie
import ystyle::xisp_linalg_blas.*

enableBlas()                                  // 之后所有 matmul 走 cblas_dgemm
let interp = LispInterpreter([withSci()])
```

不加这一行就是纯仓颉实现，功能完全一样，只是慢一些。

## 性能

800×800 的 `matmul`：

| 实现 | 耗时 | GFLOPS | 相对 |
|---|---|---|---|
| 纯仓颉 | 313 ms | 3.3 | 1× |
| netlib Reference BLAS（本机实测） | 139 ms | 7.3 | **2.2×** |
| OpenBLAS（单核） | ~25 ms | 30~50 | 10~15× |
| MKL（单核） | ~20 ms | 40~60 | 12~18× |

有意思的是 netlib Reference 的源码就是朴素三重循环 —— 比我们快一倍多完全来自
**gfortran -O2 的自动向量化**。差距不在算法，在编译器的向量化能力。

## 跨平台

**BLAS 不属于 libc**，它是独立的数学库。符号名（CBLAS 接口）跨平台一致，
差别只在链接参数：

| 平台 | `link-option` | 库从哪来 |
|---|---|---|
| Linux | `-lblas` | 发行版包（Debian: `libblas3`；要快就装 `libopenblas0`） |
| macOS | `-framework Accelerate` | **系统自带**，Apple 优化过 |
| Windows | OpenBLAS 的库路径 | 需要自己装 |

Linux 上「看起来像自带」通常是因为装了 numpy / scipy 顺带装上，fresh 系统其实没有。

改 `cjpm.toml` 的 `link-option` 即可切换。

## 为什么做成独立成员

`xisp_linalg` 保持**零依赖**，这样不装 BLAS 的机器照样能构建。加速器是这个前提
之外的**可选叠加**：

- 有 BLAS → 装上，2~15 倍
- 没有 → 不装，功能一样

不把 C 依赖塞进主模块，是因为 `cjpm` 没有可选依赖机制 —— 一旦写进
`xisp_linalg`，所有用户都被迫装 BLAS。

## 许可

MIT
