# bench

xisp-sci 的基准测试（可执行程序，**不发布**）。

```shell
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
cjpm build && ./target/release/bin/ystyle::bench
```

报告写到 [`report.md`](report.md)，原始数据在 `results/`。

## 七项基准

| # | 内容 | 数据 |
|---|---|---|
| 一 | 数据集冒烟（读取 → 推断 → 统计 → 图表数据 → 分组） | Iris / Boston |
| 二 | `matmul` 规模扫描 50…1000 | 合成矩阵 |
| 三 | 稀疏基线（稠密表示的代价） | Matrix Market `gent113` / `will199` / `ash292` / `ash331` |
| 四 | 回归工作流（教师预测 / 汽车 MPG） | UCI Student / ISLR Auto |
| 五 | 正确性对照（公开统计量） | Iris / Boston |
| 六 | `-O2` 开关的影响 | A/B 实测 |
| 七 | 统计正确性（12 列 × 7 指标） | Wage / Smarket / Hitters / Carseats |

## 全部走 Lisp 层

基准通过 `LispInterpreter` + `eval` 跑，测的是**用户视角的端到端耗时**，
不是某个内部函数的裸速度。

## 数据

`data/` 下 12 个文件，全部进仓（约 700KB），基准随时可复现：

- `iris.csv` / `boston.csv` —— 经典分类 / 回归
- `student-mat.csv` —— UCI Student Performance（原格式是分号分隔，已转逗号）
- `auto.csv` / `auto_clean.csv` —— ISLR Auto（原始 397 行，清洗后 392 行）
- `Wage.csv` / `Smarket.csv` / `Hitters.csv` / `Carseats.csv` —— ISLR 教科书数据集
- `*.mtx` —— Matrix Market Harwell-Boeing 稀疏矩阵（经代理从 NIST 下载）
- `stats_expected.csv` —— pandas 生成的统计对照值

## 为什么必须有这些基准

「跑通了」和「算对了」是两件事。这里的每一项都在回答后者：

- 统计量与 **pandas** 逐位比对（pandas 的默认约定与 R 一致）
- 回归系数与 **Python 正规方程**对照（与 `lstsq` 的 QR 是不同算法 ——
  算法不同却给出同一个答案，才是证据）
- Iris 的分组均值在 **pandas 的 `groupby`** 与教科书三行数字之间都能对上

这些基准抓到过四个真 bug：CSV 写出的多余引号、`ctx.invoke` 在字节码后端下不可用、
`?` 让整列退化成文本、core 的 `max` 遇 NaN 返回 NaN。

## 许可

MIT
