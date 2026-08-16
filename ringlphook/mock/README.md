# RingLPHook EMA 双引擎模拟器

## 快速开始

### 1. 安装依赖

```bash
cd ringlphook/mock
pip install -r requirements.txt
```

### 2. 运行模拟

```bash
python run.py
```

### 3. 查看结果

```bash
# 命令行方式
open output/report.html    # macOS
xdg-open output/report.html # Linux

# 或直接用浏览器打开 output/report.html
```

## 输出说明

运行后会生成 `output/` 目录，包含：

| 文件 | 说明 |
|---|---|
| `report.html` | **主报告**，用浏览器打开，包含所有图表和文字分析 |
| `00_汇总对比.png` | 所有场景的平均 fee 和总 LP 收入对比 |
| `01_正常波动.png` | 正常市场下的 EMA 表现 |
| `02_慢跌2%_核心场景.png` | **核心场景**：慢跌 2%，展示双 EMA 优势 |
| `03_慢涨2%.png` | 慢涨场景 |
| `04_闪跌10%.png` | 闪电贷砸盘，展示 surge 保护 |
| `05_慢跌+闪跌组合.png` | 复杂场景 |
| `06_震荡市.png` | 震荡市场 |
| `07_V型反转.png` | V 型反转 |

## 每张图的含义

每张图有 3 个子图：

1. **价格与 EMA 走势**：黑线是实际价格，蓝线是短周期 EMA，绿线是长周期 EMA，红线是单 EMA
2. **偏离度对比**：展示双 EMA（紫）vs 单 EMA（红）的偏离度差异
3. **动态 Fee 费率**：**最关键**——展示双 EMA（紫）vs 单 EMA（红）收取的 fee 差异

## 核心结论（预期）

在 **02_慢跌2%_核心场景** 中：
- 单 EMA fee：~0.37%
- 双 EMA fee：~1.80%
- **双 EMA 提升约 5 倍 LP 收入**

## 调整参数

编辑 `run.py` 中的参数：

```python
alpha_short = 0.1      # 短周期 EMA 灵敏度（越大越灵敏）
alpha_long = 0.01      # 长周期 EMA 灵敏度（越小越滞后）
base_fee = 0.0005      # 基础费率 0.05%
```

或编辑 `scenarios.py` 创建新场景。
