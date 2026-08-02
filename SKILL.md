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

1. **环境搭建** — conda 小环境 + dnbc4tools + 参考基因组下载
2. **环境验证** — 验证 conda/dnbc4tools/参考基因组索引
3. **脚本部署** — 批量分析脚本部署和配置
4. **脚本测试** — dry-run、参数校验
5. **批量启动** — nohup 后台运行
6. **故障排查** — 常见问题和解决方案

---

## 环境搭建（从零开始）— 实战验证版

> 以下步骤已在 Ubuntu 服务器上实战验证通过（conda 24.x + Python 3.9.25 + dnbc4tools v2.1.2）。
> 核心原则：**始终使用隔离的 conda 小环境，不影响服务器的其他环境。**

### 1. 安装 Miniconda（如服务器上已有 conda 则跳过）

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
source ~/.bashrc
```

### 2. 创建 dnbc4tools 专用 conda 环境

> **推荐做法**：一次性安装 Python + R + MACS2 + STAR 等所有依赖，避免后续 `pip install` 时缺少底层依赖而报错。

```bash
# 创建隔离环境，同时安装 Python 3.9、R、MACS2、STAR、以及常用科学计算包
conda create -n dnbc4tools \
    python=3.9 \
    r-base=4.4.1 \
    macs2 \
    star \
    numpy \
    scipy \
    pandas \
    matplotlib \
    -y

# 激活环境
conda activate dnbc4tools
```

> **为什么需要 MACS2 和 STAR？** dnbc4tools 的上游分析流程内部调用这两个工具——STAR 做序列比对，MACS2 做峰值 calling。必须预先安装。

### 3. pip 安装 dnbc4tools

> **国内服务器务必使用清华镜像**，直连 pypi.org 可能只有十几 KB/s。

```bash
# 使用清华镜像安装（实测速度可达 50-100 MB/s）
pip install dnbc4tools -i https://pypi.tuna.tsinghua.edu.cn/simple

# 验证安装
dnbc4tools --version
# 输出示例: dnbc4tools 2.1.2
```

### 4. 验证 conda 小环境功能完整性

```bash
conda activate dnbc4tools

# 验证 dnbc4tools CLI（所有子命令）
dnbc4tools --help
dnbc4tools rna --help
dnbc4tools rna mkref --help
dnbc4tools rna run --help

# 验证 MACS2
macs2 --version

# 验证 STAR
STAR --version

# 验证 Python 核心包
python -c "import pandas; import numpy; import scipy; import pysam; import matplotlib; print('All OK')"

# 验证 R
R --version
```

> **重要发现：dnbc4tools 不需要 Seurat。** dnbc4tools 是纯 Python 工具，聚类/降维/注释使用 Scanpy（Python 版单细胞分析库），R 仅作为 conda 环境的附带组件存在。不需要在环境中安装 R 包。

> **已知无害警告**：`compiletime version 3.8 of module 'dnbc4tools.tools.text' does not match runtime version 3.9` — 不影响功能，dnbc4tools 官方以 Python 3.8 编译，但 3.9 下兼容运行。

---

## 准备参考基因组 — 完整指南

### 核心概念（给零基础同学）

单细胞上游分析需要两类文件：
- **FASTA（.fa.gz）** = 「DNA 密码本」，记录该物种每条染色体的完整 DNA 碱基序列（A/T/C/G）
- **GTF（.gtf.gz）** = 「基因坐标地图」，记录每条染色体上所有基因的精确起止坐标和外显子边界

两者合起来喂给 STAR 比对软件构建索引，之后华大测序的短 DNA 片段才能「对号入座」找到自己的基因组位置。

### 格式要求（关键！决定成败）

**dnbc4tools 使用 Ensembl 命名法（无 `chr` 前缀），而非 10x/UCSC 命名法。**

| 对比项 | Ensembl（华大/BGI）✅ | UCSC（10x Genomics）❌ |
|--------|----------------------|------------------------|
| 第1号染色体 | `>1 dna:primary_assembly` | `>chr1` |
| 第X号染色体 | `>X` | `>chrX` |
| 线粒体 | `>MT` | `>chrM` |
| 来源 | Ensembl FTP | 10x Cell Ranger 官方包 |

> **如果混用 10x 格式（chr1 命名）的参考基因组，STAR 比对会失败**——华大 DNBElab C4 平台输出的 FASTQ 使用的是 Ensembl 命名法，两者染色体名称不匹配会导致所有 reads 被当成「未比对」而丢弃。

> **实战教训**：本人在服务器上最初使用了 Cell Ranger 2024-A 的 Human/Mouse/Rat 参考基因组（10x 格式，`chr1` 命名），经检查后发现不兼容，全部删除并重新从 Ensembl 下载。

### 完整下载 URL 清单（4 物种，实战验证通过）

#### Ensembl 版本选择策略

| 文件类型 | 推荐 Release | 原因 |
|----------|-------------|------|
| **FASTA** | **release-113**（稳定版） | release-113 和 release-116 的 DNA 序列完全相同（同一本字典），选哪个都一样 |
| **GTF** | **release-116**（最新版，如可用） | GTF 注释每年更新 4 次，越新越完整，能识别更多基因；部分物种仅到 r113 |

#### 组装类型选择策略

| 组装类型 | 含义 | 适用物种 |
|----------|------|----------|
| **primary_assembly** | 核心染色体（干净版，无补丁、无未定位片段） | 人、小鼠（研究成熟，组装质量高） |
| **toplevel** | primary_assembly + 补丁区 + 单倍型区 + 未定位片段（完整版） | 大鼠、食蟹猴（组装较复杂） |

> ⚠️ **重要发现**：Ensembl 在 release-113 后对部分物种做了基因组分片——Macaque、Rat、Pig 的 primary_assembly 不再以单文件提供，而是拆成 `.dna.primary_assembly.1.fa.gz`、`.2.fa.gz`……最多 20+ 个分片文件。**推荐使用 toplevel 单一文件替代**，无需手动合并分片。

#### 完整下载 URL 清单

| 序号 | 物种 | 文件类型 | Release | 组装类型 | 下载 URL | 压缩大小 |
|------|------|----------|---------|----------|----------|----------|
| 1 | **人** Homo sapiens | FASTA | r113 | primary_assembly | `http://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz` | ~802 MB |
| 2 | **人** Homo sapiens | GTF | r116 | — | `http://ftp.ensembl.org/pub/release-116/gtf/homo_sapiens/Homo_sapiens.GRCh38.116.gtf.gz` | ~135 MB |
| 3 | **小鼠** Mus musculus | FASTA | r113 | primary_assembly | `http://ftp.ensembl.org/pub/release-113/fasta/mus_musculus/dna/Mus_musculus.GRCm39.dna.primary_assembly.fa.gz` | ~769 MB |
| 4 | **小鼠** Mus musculus | GTF | r116 | — | `http://ftp.ensembl.org/pub/release-116/gtf/mus_musculus/Mus_musculus.GRCm39.116.gtf.gz` | ~103 MB |
| 5 | **大鼠** Rattus norvegicus | FASTA | r113 | toplevel | `http://ftp.ensembl.org/pub/release-113/fasta/rattus_norvegicus/dna/Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz` | ~760 MB |
| 6 | **大鼠** Rattus norvegicus | GTF | r113 | — | `http://ftp.ensembl.org/pub/release-113/gtf/rattus_norvegicus/Rattus_norvegicus.mRatBN7.2.113.gtf.gz` | ~17 MB |
| 7 | **食蟹猴** Macaca fascicularis | FASTA | r113 | toplevel | `http://ftp.ensembl.org/pub/release-113/fasta/macaca_fascicularis/dna/Macaca_fascicularis.Macaca_fascicularis_6.0.dna.toplevel.fa.gz` | ~827 MB |
| 8 | **食蟹猴** Macaca fascicularis | GTF | r116 | — | `http://ftp.ensembl.org/pub/release-116/gtf/macaca_fascicularis/Macaca_fascicularis.Macaca_fascicularis_6.0.116.gtf.gz` | ~19 MB |
| 9 | **斑马鱼** Danio rerio | FASTA | r113 | primary_assembly | `http://ftp.ensembl.org/pub/release-113/fasta/danio_rerio/dna/Danio_rerio.GRCz11.dna.primary_assembly.fa.gz` | ~503 MB |
| 10 | **斑马鱼** Danio rerio | GTF | r116 | — | `http://ftp.ensembl.org/pub/release-116/gtf/danio_rerio/Danio_rerio.GRCz11.116.gtf.gz` | ~18 MB |
| 11 | **猪** Sus scrofa | FASTA | r113 | toplevel | `http://ftp.ensembl.org/pub/release-113/fasta/sus_scrofa/dna/Sus_scrofa.Sscrofa11.1.dna.toplevel.fa.gz` | ~718 MB |
| 12 | **猪** Sus scrofa | GTF | r116 | — | `http://ftp.ensembl.org/pub/release-116/gtf/sus_scrofa/Sus_scrofa.Sscrofa11.1.116.gtf.gz` | ~18 MB |

> **注**：大鼠 GTF 在 release-113 后未更新，斑马鱼 r116 GTF 需确认存在。所有 URL 使用 `http://` 而非 `https://`（见下文网络优化章节）。

### 下载策略与网络优化

> **本章节源自实战经验：在服务器国际带宽仅 ~15 KB/s 单线程的条件下，经过多轮优化最终将 3.4 GB 下载时间从 ~76 小时缩短到 ~12 小时。**

#### 优化策略总览

| 优化手段 | 效果 | 实战结论 |
|----------|------|----------|
| **HTTPS → HTTP** | 单线程从 ~13 KB/s → ~20 KB/s | ✅ 推荐。Ensembl FTP 对 HTTP 限流更宽松 |
| **wget 串行 → 并行** | 聚合从 ~15 KB/s → ~80-100 KB/s | ✅ 推荐。8 个 wget 同时下载不会互相抢带宽 |
| **aria2c 多连接** | 尝试 16 连接后遭 `Connection Refused` | ❌ 不推荐。Ensembl 有限流机制，过多连接会被封 IP |
| **国内镜像** | 清华/北大镜像不托管 Ensembl 基因组数据 | ❌ 不可行。Ensembl 基因组文件仅英国主站和少数欧洲镜像 |
| **FTP 协议** | `ftp://ftp.ensembl.org` 被防火墙拦截 | ❌ 不可行 |
| **rsync** | 同样受限于国际带宽 | ❌ 无提升 |

#### 推荐下载脚本（8 进程并行，实战验证通过）

```bash
#!/bin/bash
# 4 物种参考基因组并行下载脚本
# 路径: /data_disk/Soft/dnbc4tools/ref/
# 用法: bash download_all.sh

LOG="download.log"
echo "[$(date "+%m-%d %H:%M:%S")] ██ START: 4-species parallel wget" >> $LOG

for species in human mouse rat macaque; do
  case $species in
    human)
      FA="http://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz"
      GTF="http://ftp.ensembl.org/pub/release-116/gtf/homo_sapiens/Homo_sapiens.GRCh38.116.gtf.gz"
      ;;
    mouse)
      FA="http://ftp.ensembl.org/pub/release-113/fasta/mus_musculus/dna/Mus_musculus.GRCm39.dna.primary_assembly.fa.gz"
      GTF="http://ftp.ensembl.org/pub/release-116/gtf/mus_musculus/Mus_musculus.GRCm39.116.gtf.gz"
      ;;
    rat)
      FA="http://ftp.ensembl.org/pub/release-113/fasta/rattus_norvegicus/dna/Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz"
      GTF="http://ftp.ensembl.org/pub/release-113/gtf/rattus_norvegicus/Rattus_norvegicus.mRatBN7.2.113.gtf.gz"
      ;;
    macaque)
      FA="http://ftp.ensembl.org/pub/release-113/fasta/macaca_fascicularis/dna/Macaca_fascicularis.Macaca_fascicularis_6.0.dna.toplevel.fa.gz"
      GTF="http://ftp.ensembl.org/pub/release-116/gtf/macaca_fascicularis/Macaca_fascicularis.Macaca_fascicularis_6.0.116.gtf.gz"
      ;;
  esac

  mkdir -p "$species"

  # FASTA 和 GTF 同时并行下载（每个物种 2 个 wget）
  fname=$(basename "$FA")
  (wget -c -q "$FA" -O "$species/$fname" && echo "[$(date "+%m-%d %H:%M:%S")] ✅ $species FASTA done" >> $LOG) &

  gname=$(basename "$GTF")
  (wget -c -q "$GTF" -O "$species/$gname" && echo "[$(date "+%m-%d %H:%M:%S")] ✅ $species GTF done" >> $LOG) &
done

wait
echo "[$(date "+%m-%d %H:%M:%S")] 🏁 ALL 8 files downloaded!" >> $LOG
```

> **`wget -c`（断点续传）**：如果下载中断，重新运行脚本会自动从断点继续，不会丢失已下载数据。

### 存储空间预估

| 物种 | FASTA 压缩 | FASTA 解压 | GTF 压缩 | GTF 解压 | STAR 索引 | 小计（含索引） |
|------|-----------|-----------|---------|---------|----------|--------------|
| 人 | 802 MB | ~3.0 GB | 135 MB | ~1.6 GB | ~12 GB | **~17 GB** |
| 小鼠 | 769 MB | ~2.8 GB | 103 MB | ~1.2 GB | ~10 GB | **~15 GB** |
| 大鼠 | 760 MB | ~2.7 GB | 17 MB | ~0.5 GB | ~10 GB | **~14 GB** |
| 食蟹猴 | 827 MB | ~3.0 GB | 19 MB | ~0.5 GB | ~11 GB | **~15 GB** |
| 斑马鱼 | 503 MB | ~1.5 GB | 18 MB | ~0.5 GB | ~5 GB | **~7 GB** |
| 猪 | 718 MB | ~2.5 GB | 18 MB | ~0.5 GB | ~9 GB | **~12 GB** |
| **合计（6 物种）** | **~4.4 GB** | **~15.5 GB** | **~310 MB** | **~4.8 GB** | **~57 GB** | **~80 GB** |
| **合计（4 物种）** | **~3.1 GB** | **~11.5 GB** | **~274 MB** | **~3.8 GB** | **~43 GB** | **~61 GB** |

> ⚠️ 建议数据盘预留至少 **70-80 GB**（6 物种）或 **50-55 GB**（4 物种），为解压+索引构建留足空间。

### 推荐目录组织（每个物种独立文件夹）

```
/data_disk/Soft/dnbc4tools/ref/
├── human/
│   ├── Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz   ← 下载的原文件
│   ├── Homo_sapiens.GRCh38.116.gtf.gz                   ← 下载的原文件
│   ├── genome.fa                                        ← 解压后重命名（mkref 需要）
│   ├── genes.gtf                                        ← 解压后重命名（mkref 需要）
│   └── STAR/                                            ← mkref 生成的索引
├── mouse/
│   ├── Mus_musculus.GRCm39.dna.primary_assembly.fa.gz
│   ├── Mus_musculus.GRCm39.116.gtf.gz
│   ├── genome.fa
│   ├── genes.gtf
│   └── STAR/
├── rat/
│   ├── Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz
│   ├── Rattus_norvegicus.mRatBN7.2.113.gtf.gz
│   ├── genome.fa
│   ├── genes.gtf
│   └── STAR/
├── macaque/
│   ├── Macaca_fascicularis.Macaca_fascicularis_6.0.dna.toplevel.fa.gz
│   ├── Macaca_fascicularis.Macaca_fascicularis_6.0.116.gtf.gz
│   ├── genome.fa
│   ├── genes.gtf
│   └── STAR/
├── zebrafish/     ← 可选
│   └── ...
└── pig/           ← 可选
    └── ...
```

### 下载完整性验证

> **必须做！** 网速慢的服务器容易出现文件截断或损坏。

#### 方法一：gzip 完整性测试（快速）

```bash
# 测试每个 .gz 文件是否可以正常解压
for f in */*.fa.gz */*.gtf.gz; do
    gzip -t "$f" && echo "✅ $f OK" || echo "❌ $f CORRUPT"
done
```

#### 方法二：对比文件大小与 Ensembl 官方 CHECKSUMS

```bash
# Ensembl 每个目录下都有 CHECKSUMS 文件
# 例如：http://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/CHECKSUMS

# 下载 CHECKSUMS 并对比
SPECIES="homo_sapiens"
wget -q "http://ftp.ensembl.org/pub/release-113/fasta/${SPECIES}/dna/CHECKSUMS" -O /tmp/checksums.txt
grep "primary_assembly.fa.gz" /tmp/checksums.txt
# 输出格式: 42845  867002  Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz
#           ^CRC   ^bytes  ^filename

# 本地用 sum 命令计算 BSD CRC 对比
sum human/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz
# 输出格式: 42845 867002
#           ^CRC  ^blocks
```

> ⚠️ **注意**：`sum` 命令输出的是 **blocks 数**（每块 1024 字节），不是字节数。例如 802 MB 文件 = 802×1024×1024÷1024 ≈ 820,000 blocks。只有 CRC 值和 blocks 数都与 CHECKSUMS 一致，文件才算完整。

#### 方法三：解压后检查 FASTA 文件头

```bash
# 解压并查看 FASTA 文件的第一行（染色体命名）
gunzip -c human/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz | head -1
# 期望输出: >1 dna:primary_assembly chromosome:GRCh38:1:1:248956422:1
# 如果出现 >chr1 则说明下错了（10x 格式），必须重下！
```

### 构建 STAR 索引（mkref）

下载并验证完成后，为每个物种构建 STAR 比对索引：

```bash
conda activate dnbc4tools

# === 方法一：逐个物种构建 ===

# 人
cd /data_disk/Soft/dnbc4tools/ref/human
gunzip -k Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz
mv Homo_sapiens.GRCh38.dna.primary_assembly.fa genome.fa
gunzip -k Homo_sapiens.GRCh38.116.gtf.gz
mv Homo_sapiens.GRCh38.116.gtf genes.gtf
dnbc4tools rna mkref --fasta genome.fa --gtf genes.gtf --out STAR

# 小鼠
cd /data_disk/Soft/dnbc4tools/ref/mouse
# ...类似操作...

# === 方法二：批量构建 ===

for sp in human mouse rat macaque; do
  echo "=== Building STAR index for $sp ==="
  cd /data_disk/Soft/dnbc4tools/ref/$sp
  gunzip -k *.fa.gz && mv *.fa genome.fa
  gunzip -k *.gtf.gz && mv *.gtf genes.gtf
  dnbc4tools rna mkref --fasta genome.fa --gtf genes.gtf --out STAR
  echo "=== $sp done! ==="
done
```

> **mkref 是 CPU 密集型操作**，不依赖网络。每个物种约 30-60 分钟，建议用 `nohup` 后台运行。

---

## 网络优化经验总结

> 本章是实战经验精华：在服务器国际出口带宽硬限制（~15 KB/s 单线程）下的所有尝试和结论。

### 尝试过的方案及结果

| 方案 | 详情 | 结果 |
|------|------|------|
| HTTPS 直连 Ensembl | `https://ftp.ensembl.org/` | 单线程 ~13 KB/s（最慢） |
| HTTP 直连 Ensembl | `http://ftp.ensembl.org/` | 单线程 ~20 KB/s（比 HTTPS 快 ~50%） |
| FTP 直连 | `ftp://ftp.ensembl.org/` | ❌ 被防火墙拦截 |
| aria2c 16 连接 | `aria2c -x 16` | ❌ 被 Ensembl 限流，`Connection Refused` |
| 8 进程 wget 并行 | 8 个 wget 同时下载不同文件 | ✅ 聚合 ~80-100 KB/s（最优方案） |
| 清华 pip 镜像 | `pypi.tuna.tsinghua.edu.cn` | ✅ 50-100 MB/s（pip 包下载极快） |
| 清华 conda 镜像 | conda 已配置清华源 | ✅ 基础包下载快 |
| 国内 Ensembl 镜像 | 清华/北大/阿里云 | ❌ 均不托管基因组 FASTA/GTF 大文件 |
| 欧洲 Ensembl 镜像 | 德国/瑞典节点 | ❌ 同样受限于国际出口带宽 |

### 关键结论

1. **pip 包安装 → 清华镜像**，速度快（50-100 MB/s），无脑使用
2. **Ensembl 基因组文件 → 仅英国主站有**，国内无镜像，国际出口带宽是唯一瓶颈
3. **最优下载方式 = HTTP 协议 + wget 多进程并行**（不要用 aria2c，会被封）
4. **预期速度**：单线程 15-20 KB/s，8 进程聚合 80-100 KB/s
5. **4 物种（8 文件，~3.4 GB）预计耗时 ~12 小时**
6. **6 物种（12 文件，~4.7 GB）预计耗时 ~16 小时**

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

### Q8: pip 安装失败（国内服务器）
```bash
# 优先使用清华镜像
pip install dnbc4tools -i https://pypi.tuna.tsinghua.edu.cn/simple

# 如果清华镜像也失败，升级 pip 后重试
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

### Q11: 参考基因组下载速度太慢
这是服务器国际出口带宽瓶颈，无法从软件层面根本解决。优化手段见本文「下载策略与网络优化」章节：
1. 使用 HTTP 而非 HTTPS（实测快 50%）
2. 使用 8 进程 wget 并行下载（聚合 80-100 KB/s）
3. 不要用 aria2c 多连接（会被 Ensembl 封 IP）
4. 国内没有 Ensembl 基因组镜像，不用找了

### Q12: 10x 参考基因组能用在 dnbc4tools 上吗？
**不能。** 10x Cell Ranger 使用 UCSC 命名法（`chr1`、`chr2`），华大 DNBElab C4 使用 Ensembl 命名法（`1`、`2`），染色体名称不匹配会导致比对全军覆没。必须从 Ensembl 重新下载。

### Q13: 需要安装 R 包（如 Seurat）吗？
**不需要。** dnbc4tools 是纯 Python 工具，使用 Scanpy 做聚类/降维/注释。R 在 conda 环境中存在但不被调用。不需要安装任何 R 包。

### Q14: 下载的 .gz 文件如何验证是否完整？
三重验证：
1. `gzip -t 文件名.gz` — 快速检测文件是否可正常解压
2. 对比文件大小与 Ensembl 官方 CHECKSUMS — 精确验证字节级完整性
3. `gunzip -c 文件名.gz | head -1` — 检查 FASTA 染色体命名是否为 Ensembl 格式（`>1` 而非 `>chr1`）

### Q15: Ensembl primary_assembly 文件不存在（404）？
部分物种（Macaque、Rat、Pig）在 release-113 中将 primary_assembly 拆成了多个分片文件（`.1.fa.gz`、`.2.fa.gz`...）。解决方案：使用 `toplevel.fa.gz` 替代，它包含了 primary_assembly 的全部内容，且为单一文件，无需手动合并分片。

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
| v3.2 | 2026-08-02 | **参考基因组章节全面重写**：新增格式要求（10x vs Ensembl）、完整下载URL清单（6物种12文件）、组装类型选择策略（primary vs toplevel）、下载策略与网络优化（HTTP>HTTPS、8进程并行最优、aria2c避坑）、存储空间预估（含STAR索引）、目录组织规范（每物种独立文件夹）、下载完整性验证（gzip -t + CHECKSUMS + FASTA文件头检查）、mkref批量构建脚本。**环境搭建章节实战化**：conda一次性安装所有依赖（MACS2+STAR+R）、清华镜像加速、功能验证步骤。**FAQ 扩充**：新增 Q11-Q15（网速优化、10x不兼容、不需要Seurat、完整性验证、primary分片问题）。 |
| v3.1 | 2026-07-04 | 新手完全指南、conda 安装、物种基因组下载、硬件参考、10 FAQ |
| v3.0 | 2026-07-02 | 输入校验、断点续跑、并行、15 项优化 |
| v2.0 | 2026-06-30 | CLI 参数化、dry-run |
| v1.0 | 2026-06-28 | 初始版本 |
