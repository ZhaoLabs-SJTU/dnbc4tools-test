# =============================================================================
# dnbc4tools 华大单细胞上游批量分析 Docker 镜像
# 
# 使用方法:
#   构建: docker build -t dnbc4tools:latest .
#   运行: docker run -v /your/data:/data -v /your/ref:/ref -v /your/output:/output dnbc4tools:latest ...
# =============================================================================

FROM continuumio/miniconda3:24.1.2-0

LABEL maintainer="ZhaoLabs-SJTU"
LABEL description="华大单细胞转录组上游批量分析环境 (dnbc4tools)"
LABEL version="3.1"

# ---- 安装系统依赖 ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    procps \
    vim \
    less \
    && rm -rf /var/lib/apt/lists/*

# ---- 创建 dnbc4tools conda 环境 ----
RUN conda create -n dnbc4tools python=3.9 -y && \
    conda clean -afy

# ---- 安装 dnbc4tools ----
# 注意: 如果 pip 安装失败, 请替换为实际安装方式
RUN /bin/bash -c "source /opt/conda/etc/profile.d/conda.sh && \
    conda activate dnbc4tools && \
    pip install dnbc4tools==2.1.3"

# ---- 设置 conda 默认环境 ----
RUN echo "source /opt/conda/etc/profile.d/conda.sh && conda activate dnbc4tools" >> /root/.bashrc

# ---- 复制脚本和文档 ----
RUN mkdir -p /opt/dnbc4tools-skill
COPY scripts/华大批量上游分析dnbc4tools.sh /opt/dnbc4tools-skill/
COPY README.md /opt/dnbc4tools-skill/
COPY SKILL.md /opt/dnbc4tools-skill/
COPY 新手完全指南.md /opt/dnbc4tools-skill/

# ---- 设置执行权限 ----
RUN chmod +x /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh

# ---- 设置工作目录 ----
WORKDIR /workspace

# ---- 默认入口 ----
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["source /opt/conda/etc/profile.d/conda.sh && conda activate dnbc4tools && bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh -h"]
