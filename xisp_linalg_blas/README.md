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

## 换成 OpenBLAS：只改一行

**CBLAS 是标准接口** —— `cblas_dgemm` 的签名、枚举值在所有实现里都一样。所以换
BLAS 实现**不需要改任何仓颉代码**，只改 `cjpm.toml` 里的链接参数：

```toml
# 默认（系统自带的一般是这个）
link-option = "-lcblas -lblas"

# 换成 OpenBLAS
link-option = "-lopenblas"
```

装 OpenBLAS：

```shell
# Debian / Ubuntu
sudo apt install libopenblas-dev

# Fedora / RHEL
sudo dnf install openblas-devel

# macOS（不用装 —— 系统自带 Accelerate）
# 改 link-option = "-framework Accelerate" 即可
```

### 为什么 `-lcblas` 和 `-lblas` 都要写

`cblas_dgemm` 在 `libcblas` 里（C 接口），`libblas` 里只有 `dgemm_`（Fortran 接口）——
发行版把两者分成不同的库。只写 `-lblas` 会报：

```
undefined reference to `cblas_dgemm'
```

这个坑很阴险：**库成员自己编译时不会暴露**（静态库只编译不链接），直到最终可执行
程序链接时才炸。

`-lopenblas` 一个就够（OpenBLAS 把 CBLAS 打包在同一个库里）。

## 各实现的性能

单核 `dgemm`，800×800 实测/典型值：

| 实现 | GFLOPS | 相对纯仓颉 | 备注 |
|---|---|---|---|
| 纯仓颉（不装本模块） | 3.3 | 1× | 零依赖 |
| netlib Reference BLAS | **7（实测）** | **2.2×** | 系统默认，教学级实现 |
| Eigen | 15~25 | — | **见下，不适合本场景** |
| **OpenBLAS** | 30~50 | **10~15×** | 推荐 |
| Intel MKL | 40~60 | 12~18× | Intel CPU 上最快 |
| Apple Accelerate | 30~50 | 10~15× | macOS 自带 |

有意思的是 netlib Reference 的源码就是**朴素三重循环**，比纯仓颉快一倍多完全来自
**gfortran -O2 的自动向量化**。差距不在算法，在编译器的向量化能力。

## 为什么不推荐 Eigen

Eigen 是 **header-only 的 C++ 模板库**，没有 `.so`、没有 `extern "C"` 函数 ——
模板在编译期实例化，符号名取决于编译器和版本，**ABI 不稳定，`foreign` 调不到**。

要用 Eigen 必须自己写 C++ 包装层：

```cpp
// wrapper.cpp
#include <Eigen/Dense>
extern "C" void my_dgemm(int m, int n, int k,
                         const double* a, const double* b, double* c) {
    Eigen::Map<const Eigen::MatrixXd> A(a, m, k);
    Eigen::Map<const Eigen::MatrixXd> B(b, k, n);
    Eigen::Map<Eigen::MatrixXd>(c, m, n).noalias() = A * B;
}
```

再 `g++ -O3 -shared -fPIC` 编成 .so —— **这就回到了「写 C++ 代码 + 维护 C++ 工具链」**，
正是这个模块想避免的事。

而且性能上 Eigen 也不占优：它有 SIMD 和表达式模板，但没有 BLAS 那种汇编级的
micro-kernel（寄存器分块 + 手工调度），大矩阵 `dgemm` 打不过 OpenBLAS。

**Eigen 的价值在别处**：功能全（LU / QR / SVD / 特征值 / 稀疏 / 几何）。如果将来要做
一整套分解，它值得考虑；但只要 `matmul` 快，OpenBLAS 是更好的选择。

## 跨平台

**BLAS 不属于 libc**，它是独立的数学库。符号名（CBLAS 接口）跨平台一致，
差别只在链接参数：

| 平台 | `link-option` | 库从哪来 |
|---|---|---|
| Linux | `-lcblas -lblas` 或 `-lopenblas` | 发行版包（`libblas3` / `libopenblas0`） |
| macOS | `-framework Accelerate` | **系统自带**，Apple 优化过 |
| Windows | OpenBLAS 的库路径 | 需要自己装 |

Linux 上「看起来像自带」通常是因为装了 numpy / scipy 顺带装上，fresh 系统其实没有。

## 为什么做成独立成员

`xisp_linalg` 保持**零依赖**，这样不装 BLAS 的机器照样能构建。加速器是这个前提
之外的**可选叠加**：

- 有 BLAS → 装上，2~15 倍
- 没有 → 不装，功能一样

不把 C 依赖塞进主模块，是因为 `cjpm` 没有可选依赖机制 —— 一旦写进
`xisp_linalg`，所有用户都被迫装 BLAS。

## 许可

MIT
