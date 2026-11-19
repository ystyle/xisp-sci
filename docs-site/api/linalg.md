# 线性代数 linalg

`withLinalg()` 装配。9 个符号。**纯仓颉，零外部依赖**。

## 乘法与迹

| 符号 | 说明 |
|---|---|
| `cangjie::matmul` | 矩阵乘法（含向量、点积） |
| `cangjie::trace` | 方阵对角线之和 |

`matmul` 的维度组合：2D×2D → 2D；1D×2D 与 2D×1D → 1D；1D×1D → 标量。
一维数组在 A 位置当行向量、B 位置当列向量。

## 解方程

| 符号 | 说明 |
|---|---|
| `cangjie::solve` | `(solve A b)` 解 `A x = b`；`b` 是 n×m 时一次解 m 个 |

用带**部分主元**的 LU 分解。不选主元时 `[[0,1],[1,0]]` 会直接除零。

## 分解

| 符号 | 说明 |
|---|---|
| `cangjie::lu` | → `{l, u, p}`，满足 `P A = L U` |
| `cangjie::qr` | → `{q, r}`，满足 `Q R = A`（Householder） |
| `cangjie::cholesky` | → `L`，满足 `A = L Lᵀ`（要求对称正定） |

`lu` 的 `p` 是**累积后的最终置换**（1-based），不是 LAPACK 那种「每步与谁交换」的中间量。

`cholesky` 要求对称正定，非正定 / 非对称都会报错。

## 其它

| 符号 | 说明 |
|---|---|
| `cangjie::det` | 行列式（用 LU，不是按定义展开） |
| `cangjie::inv` | 逆矩阵 |
| `cangjie::lstsq` | `(lstsq X y)` 最小二乘，返回系数 |

`lstsq` 走 QR 而不是正规方程 —— 后者把条件数平方。

## 错误

以下情形报 `TypeError`：

- 非方阵传给 `det` / `trace` / `inv` / `lu` / `cholesky`
- 矩阵奇异或接近奇异（`inv` / `solve` / `lu`）
- 非正定或非对称（`cholesky`）
- 维度不匹配（`matmul` / `solve`）
- 秩亏（`lstsq`）
- 样本数少于特征数（`lstsq`）

奇异判据用**相对容差**（乘以元素最大绝对值），不写死绝对阈值。
