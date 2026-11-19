# 数据 IO

`withCsv()` 装配。8 个符号。

> 本模块是 `hostPolicy = true`（读写宿主文件），所以整族不会进 `PRESET_PURE`。

## 读

| 符号 | 说明 |
|---|---|
| `cangjie::csv-read` | `(csv-read path)` / `(csv-read path limit)` → `HashMap<列名, 列值>` |
| `cangjie::csv-parse` | 从字符串解析，返回同样结构 |
| `cangjie::csv-open` | 打开流式游标 |
| `cangjie::csv-next` | 取下一行 → `Str` 列表；EOF 返回 `nil` |
| `cangjie::csv-each` | `(csv-each cur f)` 对剩余每行调用 `f`，返回行数 |
| `cangjie::csv-close` | 关闭游标（必须调用） |

## 写

| 符号 | 说明 |
|---|---|
| `cangjie::csv-write` | `(csv-write path table)` / `(csv-write path table cols)` |
| `cangjie::csv-format` | 生成 CSV 文本，不落盘 |

## 列类型推断

| 列内容 | 结果 |
|---|---|
| 全整数、无缺失 | `int64` ndarray |
| 有小数或缺失 | `float64` ndarray（缺失位是 `NaN`） |
| 其它 | `Str` 列表 |

## 缺失标记

识别这 10 种（前后空白忽略）：

```
空串  ?  NA  N/A  null  NULL  NaN  nan  #N/A
```

不把 `-` 当缺失（它是合法的负号前缀）。

## 流式读取的内存

`csv-open` 用 64KB 缓冲区推进状态机，内存占用**与文件大小无关**。

适合大文件或只需扫一遍的场景。一次性 `csv-read` 适合要按列反复计算的场景。

## 引号规则

RFC 4180。引号内允许**换行**，所以逻辑行可能跨多个物理行，这也是为什么流式读取
必须是状态机而不是「按行读再 split」。

写出时含逗号、引号、换行的字段会自动加引号并转义内部引号。
