# 数据来源与许可

Georges Hebrail 和 Alice Berard，*Individual Household Electric Power Consumption*（2006），UCI Machine Learning Repository，DOI `10.24432/C58K54`。源数据按 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布，本目录下两份数据节选沿用该许可。[数据说明与下载](https://archive.ics.uci.edu/dataset/235/individual+household+electric+power+consumption)

| 节选 | 原文物理行号（标题为第 1 行） | 原始记录 | SHA-256（LF 换行） |
| --- | --- | --- | --- |
| `clean-day.txt` | 398–1837 | 2006-12-17 00:00–23:59，共 1440 分钟 | `3acb8a52dcb66244ff6171c95e5eb61cb612ba47f83b32a10b83500241f37257` |
| `missing-minutes.txt` | 190478–190513 | 2007-04-28 00:00–00:35，共 36 分钟，其中 15 分钟缺数 | `442eb85ff1b837e83e4803f0c79bcfb5db7455d003cb4be69b69ff07818815db` |

两份节选保留原始表头和原始记录字段，统一为 LF 换行。`scripts/uci_examples.py` 选取总表平均有功功率与三个分表电量，以节选首条时间作为相对秒数零点，保留原始日期和时间到 `source-map.csv`。生成的输入对 `?` 和空值保留缺测，由窗口网格表示这些时段。适配器可使用 `--archive /path/to/uci235.zip` 对照官网提供的完整原始 ZIP。

