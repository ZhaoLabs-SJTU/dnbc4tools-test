---
name: dnbc4tools-test
description: 华大单细胞上游批量分析环境检测与脚本部署。用于验证 conda/dnbc4tools/参考基因组索引环境、部署批量分析脚本、dry-run 测试、nohup 启动、以及排查常见问题。

---

# dnbc4tools 华大单细胞上游批量分析 测试与环境搭建

## 文档导航

> 本技能随 GitHub 仓库 [dnbc4tools-test](https://github.com/ZhaoLabs-SJTU/dnbc4tools-test) 分发。

| 文件 | 用途 |
|------|------|
| **[新手完全指南.md](新手完全指南.md)** | 面向零基础小白，从 conda 安装到验收结果（11 章，900+ 行） |
| [README.md](README.md) | 快速参考卡片，有经验人员 30 秒上手 |
| [scripts/华大批量上游分析dnbc4tools.sh](scripts/华大批量上游分析dnbc4tools.sh) | 批量分析脚本 (747 行, v3.1) |

---

## 概述

本技能帮助组学分析人员完成华大单细胞转录组上游批量分析的完整流程：

1. **环境验证**
2. **脚本部署**
3. **脚本测试**
4. **批量启动**
5. **故障排查**

---

## 环境搭建（从零开始）

### 1. 安装 Miniconda

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
source ~/.bashrc
```

### 2. 创建 dnbc4tools 专用环境

```bash
conda create -n dnbc4tools python=3.9 -y
conda activate dnbc4tools
```

### 3. 安装 dnbc4tools

```bash
pip install dnbc4tools -i https://pypi.org/simple/
dnbc4tools --version
```

---

## 准备参考基因组

| 物种 | Ensembl FTP |
|------|-------------|
| 人 (GRCh38) | https://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/ |
| 小鼠 (GRCm39) | https://ftp.ensembl.org/pub/release-113/fasta/mus_musculus/dna/ |
| 大鼠 (mRatBN7.2) | https://ftp.ensembl.org/pub/release-113/fasta/rattus_norvegicus/dna/ |
| 食蟹猴 | https://ftp.ensembl.org/pub/release-113/fasta/macaca_fascicularis/dna/ |
| 斑马鱼 (GRCz11) | https://ftp.ensembl.org/pub/release-113/fasta/danio_rerio/dna/ |
| 猪 (Sscrofa11.1) | https://ftp.ensembl.org/pub/release-113/fasta/sus_scrofa/dna/ |

```bash
mkdir -p Ref && cd Ref
wget [FASTA_URL]
wget [GTF_URL]
gunzip *.gz
mv *.fa genome.fa
mv *.gtf genes.gtf
cd ..
```

### 构建 STAR 索引

```bash
dnbc4tools rna mkref --fasta Ref/genome.fa --gtf Ref/genes.gtf --out Ref/dnbc4tools_ref
```

### 线粒体基因列表

人类: MT-ND1, MT-ND2, MT-COX1, MT-COX2, MT-ATP8, MT-ATP6, MT-COX3, MT-ND3, MT-ND4L, MT-ND4, MT-ND5, MT-ND6, MT-CYTB
小鼠: mt-Nd1, mt-Nd2, mt-Co1, mt-Co2, mt-Atp8, mt-Atp6, mt-Co3, mt-Nd3, mt-Nd4l, mt-Nd4, mt-Nd5, mt-Nd6, mt-Cytb

---

## 环境验证

```bash
conda activate dnbc4tools
dnbc4tools --version
ls -lh Ref/dnbc4tools_ref/
ls -lh 上游/fastq/*.fastq.gz | head -30
df -h 下游/0.RAW/
```

---

## 脚本参数速查

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-f` | `./上游/fastq` | FASTQ 目录 |
| `-o` | `./下游/0.RAW` | 输出目录 |
| `-r` | `./Ref` | 参考基因组目录 |
| `-p` | `26SC-KY` | 样本名前缀 |
| `-t` | `30` | 线程数 |
| `-e` | `3000` | 期望细胞数 |
| `-m` | `emptydrops` | 细胞鉴定方法 |
| `-j` | `1` | 并行样本数 |
| `-n` | — | Dry-run |
| `--force` | — | 强制重跑 |
| `--resume-from` | — | 从指定样本开始 |
| `--debug` | — | 调试模式 |
| `-h` | — | 帮助 |

---

## 测试流程

```bash
bash -n 华大批量上游分析dnbc4tools.sh
bash 华大批量上游分析dnbc4tools.sh -h
bash 华大批量上游分析dnbc4tools.sh -n
```

---

## nohup 批量启动

```bash
cd /path/to/your/project
conda activate dnbc4tools
bash 华大批量上游分析dnbc4tools.sh -n
nohup bash 华大批量上游分析dnbc4tools.sh > batch_analysis.log 2>&1 &
echo $! > batch.pid
ps -p $(cat batch.pid)
tail -f batch_analysis.log
```

### 常用变体

```bash
nohup bash 华大批量上游分析dnbc4tools.sh -j 4 > batch_analysis.log 2>&1 &
nohup bash 华大批量上游分析dnbc4tools.sh -f /data/fastq -o /data/output -r /data/ref -p "Sample-" > batch.log 2>&1 &
nohup bash 华大批量上游分析dnbc4tools.sh --resume-from Sample05 > batch_analysis.log 2>&1 &
nohup bash 华大批量上游分析dnbc4tools.sh --force > batch_analysis.log 2>&1 &
```

### 监控

```bash
tail -f batch_analysis.log
tail -f batch_logs/样本名_*.log
grep -E "✓|✗" batch_analysis.log | tail -20
ps -p $(cat batch.pid) -o pid,etime,%cpu,%mem,rss
```

### 终止

```bash
kill $(cat batch.pid)
kill -9 $(cat batch.pid)
pkill -f dnbc4tools
```

---

## 常见问题排查

### Q1: conda activate 失败
修改脚本 CONDA_BASE 为实际路径。

### Q2: dnbc4tools: command not found
```bash
conda activate dnbc4tools
which dnbc4tools
```

### Q3: FASTQ 命名不匹配 (cDNA: ✗)
脚本 v3.1 支持三种模式：标准型、wk型、通配符回退。

### Q4: 基因组索引不完整
```bash
dnbc4tools rna mkref --fasta Ref/genome.fa --gtf Ref/genes.gtf --out Ref/dnbc4tools_ref
```

### Q5: 内存不足
降低并行数 `-j 1` 和线程数 `-t 10`。

### Q6: 磁盘写满
清理 BAM 文件: `rm 下游/0.RAW/*/01.data/final_sorted.bam`

### Q7: 只重跑某个步骤
```bash
rm 下游/0.RAW/样本名/.step*_02.count.done
```
步骤标记: .step_1_01.data.done, .step_2_02.count.done, .step_3_03.analysis.done, .step_4_04.report.done

### Q8: pip 安装失败
```bash
pip install --upgrade pip setuptools wheel
pip install dnbc4tools -i https://pypi.tuna.tsinghua.edu.cn/simple
```

### Q9: conda 环境冲突
```bash
conda deactivate
conda activate dnbc4tools
```

### Q10: FASTQ 命名不规范
手动重命名为标准格式。

---

## 硬件参考

| 物种 | 基因组 | 内存 | 索引耗时 | 单样本耗时 |
|------|:--:|:--:|:--:|:--:|
| 斑马鱼 | 1.4 Gb | 32 GB | ~30 min | ~1.5 h |
| 猪 | 2.5 Gb | 64 GB | ~1 h | ~2.5 h |
| 大鼠 | 2.6 Gb | 64 GB | ~1 h | ~2.5 h |
| 小鼠 | 2.7 Gb | 64 GB | ~1 h | ~2.5 h |
| 食蟹猴 | 2.9 Gb | 80 GB | ~1.5 h | ~3 h |
| 人 | 3.2 Gb | 80 GB | ~2 h | ~3.5 h |

---

## 输出目录结构

```
下游/0.RAW/{样本名}/
├── .step_1_01.data.done
├── .step_2_02.count.done
├── .step_3_03.analysis.done
├── .step_4_04.report.done
├── 01.data/ (BAM + 报告)
├── 02.count/ (矩阵)
├── 03.analysis/ (h5ad + 聚类)
├── 04.report/ (HTML)
└── output/ (最终汇总: filter_feature.h5ad)
```

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v3.1 | 2026-07-04 | 新手完全指南、conda 安装、物种基因组下载、硬件参考、10 FAQ |
| v3.0 | 2026-07-02 | 输入校验、断点续跑、并行、15 项优化 |
| v2.0 | 2026-06-30 | CLI 参数化、dry-run |
| v1.0 | 2026-06-28 | 初始版本 |
