# 🧬 dnbc4tools-test — 华大批量上游分析技能包

> **一句话说明**：帮你在 Linux 服务器上从零搭建华大单细胞转录组上游分析环境，并批量跑完所有样本。

[![version](https://img.shields.io/badge/version-v3.1-blue)]()

---

## 📖 文档导航

| 文档 | 适用人群 | 预计时间 |
|------|---------|:--:|
| **[🌟 新手完全指南](新手完全指南.md)** | 零基础组学分析小白（从安装 conda 到验收结果） | 30 分钟阅读 + 1 天执行 |
| **[SKILL.md](SKILL.md)** | WispTerm AI 助手调用 | — |
| **[scripts/华大批量上游分析dnbc4tools.sh](scripts/华大批量上游分析dnbc4tools.sh)** | 批量分析脚本 | — |

> ⚠️ **如果你不确定该看哪个** → 直接打开 **[新手完全指南](新手完全指南.md)**，从第一章开始！

---

## ⚡ 30 秒快速上手（有经验的分析人员）

```bash
git clone https://github.com/ZhaoLabs-SJTU/dnbc4tools-test.git
cp dnbc4tools-test/scripts/华大批量上游分析dnbc4tools.sh /your/project/
conda activate dnbc4tools
bash 华大批量上游分析dnbc4tools.sh -n
nohup bash 华大批量上游分析dnbc4tools.sh -j 4 > batch_analysis.log 2>&1 & echo $! > batch.pid
tail -f batch_analysis.log
```

---

## 🔧 环境要求

| 要求 | 说明 |
|------|------|
| **操作系统** | Linux (CentOS 7 / Ubuntu 18.04+) |
| **conda** | Miniconda3 或 Anaconda3 |
| **内存** | 64-128 GB（取决于基因组大小） |
| **磁盘** | 样本数 × 60 GB |
| **dnbc4tools** | >= 2.1.3 (`pip install dnbc4tools`) |

---

## 📂 仓库内容

```
dnbc4tools-test/
├── README.md                                    ← 本文件
├── 新手完全指南.md                                ← 🌟 从这里开始！
├── SKILL.md                                     ← WispTerm 技能文件
└── scripts/
    └── 华大批量上游分析dnbc4tools.sh               ← 批量分析脚本 (747 行, v3.1)
```

---

## 🚀 支持物种

| 物种 | 基因组大小 | 参考下载 |
|------|:--:|------|
| 人 (Homo sapiens) GRCh38 | 3.2 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/) |
| 小鼠 (Mus musculus) GRCm39 | 2.7 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/mus_musculus/dna/) |
| 大鼠 (Rattus norvegicus) mRatBN7.2 | 2.6 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/rattus_norvegicus/dna/) |
| 食蟹猴 (Macaca fascicularis) | 2.9 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/macaca_fascicularis/dna/) |
| 斑马鱼 (Danio rerio) GRCz11 | 1.4 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/danio_rerio/dna/) |
| 猪 (Sus scrofa) Sscrofa11.1 | 2.5 Gb | [Ensembl](https://ftp.ensembl.org/pub/release-113/fasta/sus_scrofa/dna/) |

---

## ❓ 常见问题速查

| 问题 | 解决 |
|------|------|
| conda 未安装 | 看[新手完全指南第二章](新手完全指南.md#第二章环境搭建从零开始) |
| FASTQ 命名不匹配 | 看[新手完全指南 Q3](新手完全指南.md#q3-dry-run-显示-cdnar-) |
| 内存不足 | 减少并行 `-j 1` 和线程 `-t 10` |
| 步骤失败重跑 | `rm .step*_*.done` 后重跑 |
| 切换到其他项目 | 看[新手完全指南第十章](新手完全指南.md#第十章切换到其他项目) |

---

## 📋 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v3.1 | 2026-07-04 | 《新手完全指南》、conda 从零安装、6 物种基因组下载、硬件参考、检查清单 |
| v3.0 | 2026-07-02 | 输入校验、断点续跑、并行支持 (-j)、15 项优化 |
| v2.0 | 2026-06-30 | CLI 参数化、dry-run、双命名适配 |
| v1.0 | 2026-06-28 | 初始版本 |