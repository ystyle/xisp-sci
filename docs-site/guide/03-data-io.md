# 读数据：CSV 与缺失值

`xisp_io` 负责把磁盘上的表格变成 ndarray。

## 一次性读

```lisp
(define d (cangjie::csv-read "sales.csv"))

(hashmap-keys d)                       ; ("region" "amount" "qty")
(hashmap-get d "amount")               ; ndarray
(cangjie::csv-read "big.csv" 100)      ; 只读前 100 行
```

## 流式读

一次性 `csv-read` 会把整个文件读进内存。**2GB 的 CSV 会先占 2GB 字节，再放大成更多
字符串对象**。而且「只想看前 10 行」也要付全部代价。

流式接口的内存占用是 **64KB** —— 与文件大小无关：

```lisp
(define cur (cangjie::csv-open "big.csv"))
(cangjie::csv-next cur)                       ; 跳过表头
(define n (cangjie::csv-each cur (lambda (row)
            (println (nth row 0)))))
(cangjie::csv-close cur)                      ; 必须关，否则句柄等 GC
```

`csv-next` 在 EOF 返回 `nil`，其余情况永远返回行 —— 不会用 `nil` 表示"空行"，
那样就无法区分「空行」和「文件结束」。

### 为什么是字节级状态机

不是「按行读文件再 split」，而是按 64KB 块推进的状态机。原因有两个：

1. **引号内可以换行**（RFC 4180）。一个逻辑行可能跨多个物理行，所以不能按行读。
2. **按字节扫描而不是按字符**。UTF-8 的续字节落在 `0x80..0xBF`，而 CSV 的分隔符
   都是 ASCII —— 不可能出现在续字节位置。所以按字节扫描不会把汉字劈开，还省掉解码开销。

## 列类型推断

| 列内容 | 结果 |
|---|---|
| 全是整数、无缺失 | `int64` 数组 |
| 有小数或缺失 | `float64` 数组，缺失位是 `NaN` |
| 其它 | `Str` 列表 |

**含缺失的整数列会提升为 `float64`**，因为 `Int64` 装不下 `NaN`。这是必要的：
把缺失当 0 会让均值和求和全部静默算错，而那种错误没人会去查。

## 缺失标记认 10 种

空串、`?`、`NA`、`N/A`、`null`、`NULL`、`NaN`、`nan`、`#N/A`（前后空白忽略）。

**这不是过度设计**。真实数据里「没有值」远不止空字符串一种写法：R 导出 `NA`、
pandas 可能写 `NaN`、Excel 手工表常见 `?` 和 `N/A`。

只认空串的后果是**整列退化成文本**，而文本列无法参与统计 —— 一个 `?` 就毁掉一列。

真实案例：ISLR 的 `Hitters.Salary` 有 322 行、其中 59 个 `?`。这类数据在教科书里
是标准练习，直接用只认空串的解析器会得到一列"文本"，然后 `max` / `mean` 全部失败。

## 写出

```lisp
(cangjie::csv-write "out.csv" d)                     ; 按原列序
(cangjie::csv-write "out.csv" d (list "a" "b"))      ; 指定列序
(cangjie::csv-format d)                              ; 生成文本
```

写出后读回是**逐字节一致**的，含逗号、引号、换行的字段都正确转义。

## 从字符串解析

```lisp
(cangjie::csv-parse "a,b\n1,2\n")     ; 同 csv-read 的返回结构
```

## 下一步

- [描述统计](/guide/04-stats) —— 拿到 ndarray 之后干什么
