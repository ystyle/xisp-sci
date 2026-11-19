# 数值方法 num

`withNum()` 装配。7 个符号。

> 本模块是 `escapable = true`：`fmin` / `rk4` 要回调 Lisp 函数，
> 那是「执行宿主代码」而非纯数据运算。

## 插值

| 符号 | 说明 |
|---|---|
| `cangjie::interp1` | `(interp1 x y xi)` 线性插值 |

`x` 必须严格升序（自动检查）。区间外**钳到端点**，不硬外推。

## 多项式

| 符号 | 说明 |
|---|---|
| `cangjie::polyfit` | `(polyfit x y degree)` → 降幂系数 |
| `cangjie::polyval` | `(polyval coef x)`，`x` 可以是标量或数组 |

## 积分

| 符号 | 说明 |
|---|---|
| `cangjie::trapz` | `(trapz y)` / `(trapz y dx)` / `(trapz x y)` |
| `cangjie::simpson` | `(simpson y dx)`，要求**奇数个点** |

Simpson 点数不合要求时**报错**，不静默降级成梯形。

## 优化

| 符号 | 说明 |
|---|---|
| `cangjie::fmin` | `(fmin f a b)` / `(fmin f a b tol)` 黄金分割 |

只在 `[a,b]` 上找**单峰**极值。多峰函数会落到其中一个峰，这是算法前提。

## ODE

| 符号 | 说明 |
|---|---|
| `cangjie::rk4` | `(rk4 f y0 t0 t1 h)` → `{t, y}` 四阶 Runge-Kutta |

`f(t, y)` 返回 `dy/dt`。固定步长。
