# MeterBalance

MeterBalance 读取按统一时间窗导出的总表、配电箱和分支表记录，检查每个窗口内能否同时满足计量误差和未计量负载约束。报告保留各张表的源行号，适用于园区、学校和楼宇能源运维的离线对账。

[比赛申报书](docs/proposal.md) · [UCI 数据出处和复核](examples/uci/SOURCES.md)

## 运行演示

需要 MoonBit 0.10.15 系列和 Node.js 22+。独立验证还需要 Python 3.10+（仅用标准库）。

```sh
moon run cmd/main --target js -- audit examples/nested/config.json examples/nested/readings.csv
python scripts/verify.py
```

| 窗口（秒） | 总表直接对账 | 总表子树结论 | 如何在报告里定位 |
| --- | --- | --- | --- |
| 0–60 | `feasible` | `feasible` | 下级约束收窄配电箱到 6 Wh，总表名义差额 3 Wh |
| 60–120 | `feasible` | `inconsistent` | 配电箱受末端照明表约束至少 6 Wh，总表至多 5 Wh |
| 120–180 | `feasible` | `incomplete` | `blockers` 指向配电箱，配电箱的 `missing` 指向照明表 |
| 180–240 | `feasible` | `blocked` | 配电箱本身有证据证明不相容，查看配电箱的 `tree_witness` |
| 240–300 | `inconsistent` | `inconsistent` | 总表最低读数仍大于分表和允许残差的上界 |

```sh
python scripts/uci_examples.py _build/uci
moon run cmd/main --target js -- audit _build/uci/missing-minutes/config.json _build/uci/missing-minutes/readings.csv
```

真实样本复核覆盖 1,440 个完整日窗口，以及包含 21 个完整窗口和 15 个缺测窗口的第二段数据。独立验证以 [UCI 的 Wh 公式](https://archive.ics.uci.edu/dataset/235/individual+household+electric+power+consumption) 和 Python `Fraction` 核对 1,461 个差额与所有可见读数的原文行号。独立穷举复核另外生成 128 个三层树窗口，对照 640 个子树状态和可行端点。

## 接入自己的数据

`CONFIG.json` 声明单根有向树和窗口网格。节点可以按任意顺序给出。每个内部节点可用 `residual_min_uws` 和 `residual_max_uws` 指定未计量用电边界，分别默认零和无额外上限。字段值为十进制字符串，单位是微瓦秒（µW·s，`1 Wh = 3600000000 µW·s`）。

```json
{
  "schema": "meterbalance/v1",
  "window": {"start": "0", "step": 60, "count": 2},
  "meters": [
    {"id": "main", "parent": null, "residual_max_uws": "3600000000"},
    {"id": "panel", "parent": "main"}
  ]
}
```

`READINGS.csv` 每行写一个表计在一个窗口内的读数。输入为 UTF-8，接受 LF 或 CRLF、固定表头和不加引号的字段。ID 可含 ASCII 字母、数字、下划线、短横线和点，最长 64 个字符。允许 `Wh`、`kWh` 和 `mean_kW`，区间功率乘窗长得到电量。值和绝对容差用同一单位，接受非负十进制且最多六位小数。明确读到零则填零，某表某窗缺测则省略该行。

```csv
meter,start,end,value,unit,tolerance
main,0,60,0.006,kWh,0.001
panel,0,60,5,Wh,0
main,60,120,0.31,mean_kW,0.01
```

以同一时间基准预对齐半开窗 `[start,end)`。输入上限为 256 个表计、4,096 个窗口和 200,000 个表计窗单元。时间起点在零至 `10^12` 秒，窗长在 1 至 86,400 秒。在精确转换后，每项读数、容差和显式残差上界最多为 `10^16 µW·s`。CLI 每份输入文件上限为 16 MB。非法拓扑、重复读数、越界值和不对齐窗口退出码为 1，并将 JSON 错误写入标准错误流。有效输入会产生可机读报告，其中包含对账冲突和缺测状态。

## 读报告

- `local_state` 依据本表和直接分表的原始读数判断。每个完整内部节点都给出 `nominal_residual` 和原始测量所容许的 `residual_band`。
- `tree_state` 纳入后代约束。`feasible_band` 是子树守恒时本表能取到的电量区间。完整的叶节点为 `leaf`，完整可行的内部节点为 `feasible`。
- `inconsistent` 包含本表 `measured` 与所需 `required` 两个不相交区间。可查看 `local_witness` 或 `tree_witness`，以及分表收窄后的 `feasible_band`。
- `incomplete` 表示当前证据不足。直接缺测见 `missing`，下级缺测沿 `blockers` 追查。`blocked` 表示下级已有确定矛盾，同样沿 `blockers` 追查。发现直接冲突时，节点优先报告自己的矛盾证据。
- `own` 和 `children` 携带表计 ID、读数、容差和输入 CSV 物理行号（包含表头和空行）。UCI 转换另生成 `source-map.csv` 以连接原始记录。报告中的电量和时间均为十进制字符串，便于 JS 精确读取。

## 判定依据与适用范围

设某节点的测量区间为 `M = [max(0, 读数 − 容差), 读数 + 容差]`。设子树投影区间为 `F_i`、配置残差区间为 `R`，则内部节点的可行带是 `M ∩ (Σ F_i + R)`。区间加法分别加各下界和上界。树中各分支只通过父点约束相连，完整子树的可行值因此能用闭区间精确表示。零个有效交点即产生矛盾证据。省略残差上限时，计算使用所有本表读数都覆盖的通用上界 `2 × 10^16 µW·s`。给定窗口数 `W`、表计数 `N` 和输入行数 `R_count`，审计与报告生成的时间和空间为 `O(W × N + R_count)`。

模型适用于单向有功电量、同一时基、固定窗长、已知单根层级。表计误差是用户给定的独立闭区间，结果是模型可行性，可用于缩小现场排查范围。分布式电源回送、多根路由、相关误差、累计表归零及跨窗差分应在接入环节单独处理。多个窗口逐窗判定，子树可行带只纳入本子树的约束。UCI 样本使用零容差复核公开算式，多层约束、故障方向和不确定性场景由合成样本验证。

[Emoncms](https://docs.openenergymonitor.org/emoncms/inputs.html) 支持接入、累加、功率换算和曲线补齐，[MoonFrame](https://mooncakes.io/assets/ihb2032/MoonFrame%400.5.2/io/csv.mbt.html) 支持表格数据读写。MeterBalance 聚焦在固定采样窗里联合验证表计树的各级约束，并随结论交付逐条来源证据。

## 在 MoonBit 项目中使用

模块名是 `123123213weqw/moon_meterbalance`。核心库从 `topology` 构建表计树，或从 `configuration` 一次读取 JSON 中的树和网格。`readings_from_csv` 解析读数，`audit` 返回结构化报告，`report_json` 可将报告交给下游程序。

```moonbit
test "exact minute energy conversion" {
  assert_eq(
    @meter.energy_microwatt_seconds("4.216", @meter.MeanKw, 60L),
    252_960_000_000L,
  )
}
```

在消费者的 `moon.pkg` 中以 `@meter` 导入模块。运行 `moon test --target js --deny-warn` 或 `moon test --target wasm-gc --deny-warn` 可单独检查核心。

程序代码使用 Apache-2.0。UCI 节选采用 CC BY 4.0，见[数据归属](examples/uci/SOURCES.md)。
