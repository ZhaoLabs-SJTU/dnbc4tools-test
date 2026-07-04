# dnbc4tools Docker 使用指南

## 📦 镜像包含内容

| 组件 | 版本 |
|------|------|
| Miniconda3 | 24.1.2 |
| Python | 3.9 |
| dnbc4tools | 2.1.3 |
| 批量分析脚本 | v3.1 |
| 说明文档 | README / SKILL / 新手完全指南 |

---

## 🚀 快速开始

### 方式一: 安装 Docker 后从 Docker Hub 拉取 (推荐)

```bash
# 拉取镜像
docker pull zhaolabs/dnbc4tools:v3.1

# 测试
docker run --rm zhaolabs/dnbc4tools:v3.1 -h
```

### 方式二: 从 tar.gz 文件导入

```bash
# 导入镜像
docker load < dnbc4tools-v3.1-docker.tar.gz

# 验证
docker images | grep dnbc4tools
```

### 方式三: 本地构建

```bash
cd dnbc4tools-test/
bash docker-build.sh
```

---

## 📋 三步骤运行

### 第 1 步: 准备目录结构

```bash
your_project/
├── fastq/          # FASTQ 文件 (只读挂载)
├── ref/            # 参考基因组 (只读挂载)
└── output/         # 输出目录
```

### 第 2 步: Dry-run 测试

```bash
docker run --rm \
  -v /your/project/fastq:/data/fastq:ro \
  -v /your/project/ref:/data/ref:ro \
  -v /your/project/output:/data/output \
  dnbc4tools:v3.1 \
  bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh \
    -f /data/fastq \
    -o /data/output \
    -r /data/ref \
    -n
```

成功后你会看到所有样本被正确识别。

### 第 3 步: 正式运行

```bash
# 后台运行
docker run -d --name dnbc4tools-batch \
  -v /your/project/fastq:/data/fastq:ro \
  -v /your/project/ref:/data/ref:ro \
  -v /your/project/output:/data/output \
  dnbc4tools:v3.1 \
  bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh \
    -f /data/fastq \
    -o /data/output \
    -r /data/ref

# 查看日志
docker logs -f dnbc4tools-batch

# 查看状态
docker ps -a | grep dnbc4tools
```

---

## 🐳 常用命令

```bash
# 查看帮助
docker run --rm dnbc4tools:v3.1

# Dry-run
docker run --rm -v /data:/data dnbc4tools:v3.1 bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh -f /data/fastq -o /data/output -r /data/ref -n

# 4 样本并行
docker run -d --name batch -v /data:/data dnbc4tools:v3.1 bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh -f /data/fastq -o /data/output -r /data/ref -j 4

# 进入容器调试
docker exec -it dnbc4tools-batch /bin/bash
conda activate dnbc4tools
dnbc4tools --version

# 停止并删除
docker stop dnbc4tools-batch && docker rm dnbc4tools-batch
```

---

## 🐳 Docker Compose 方式

```bash
# 修改 docker-compose.yml 中的路径
vim docker-compose.yml

# 启动
docker compose up -d

# 查看日志
docker compose logs -f

# 停止
docker compose down
```

---

## ⚙️ 硬件要求

| 物种 | 基因组大小 | 推荐内存 | 推荐 CPU |
|------|-----------|---------|---------|
| 人类 | 3.2 Gb | 128 GB | 16 核 |
| 小鼠 | 2.7 Gb | 96 GB | 16 核 |
| 食蟹猴 | 2.9 Gb | 128 GB | 16 核 |
| 大鼠 | 2.6 Gb | 96 GB | 16 核 |
| 斑马鱼 | 1.4 Gb | 64 GB | 12 核 |

> Docker 默认使用宿主机全部资源，可通过 `--memory="120g" --cpus="16"` 限制。

---

## ❓ 常见问题

### Q: Docker 报 "no space left on device"

清理 Docker 缓存:
```bash
docker system prune -a
```

### Q: 如何查看容器内的文件

```bash
docker exec dnbc4tools-batch ls /opt/dnbc4tools-skill/
```

### Q: 如何更新镜像

```bash
docker pull zhaolabs/dnbc4tools:v3.1
# 或重新构建
bash docker-build.sh
```

### Q: 能在没有 GPU 的服务器上运行吗

可以。dnbc4tools (STAR) 纯 CPU 运行，不需要 GPU。
