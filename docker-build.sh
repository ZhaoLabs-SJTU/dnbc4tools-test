#!/bin/bash
# =============================================================================
# dnbc4tools Docker 镜像构建与导出脚本
# 
# 用法:
#   bash docker-build.sh              # 构建并导出为 tar.gz
#   bash docker-build.sh --push       # 构建并推送到 Docker Hub
#   bash docker-build.sh --save-only  # 仅导出已构建的镜像
#
# 导出文件:
#   dnbc4tools-v3.1-docker.tar.gz     (约 2-5 GB)
# =============================================================================

set -euo pipefail

IMAGE_NAME="dnbc4tools"
IMAGE_TAG="v3.1"
FULL_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
EXPORT_FILE="dnbc4tools-${IMAGE_TAG}-docker.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " dnbc4tools Docker 镜像构建工具"
echo " 镜像: ${FULL_NAME}"
echo "============================================"

# ---- 检查 Docker ----
if ! command -v docker &> /dev/null; then
    echo "❌ 未找到 Docker。请先安装 Docker。"
    echo "   Ubuntu: sudo apt install docker.io"
    echo "   CentOS: sudo yum install docker"
    echo "   Windows/Mac: https://www.docker.com/products/docker-desktop"
    exit 1
fi

# ---- 构建镜像 ----
if [[ "${1:-}" != "--save-only" ]]; then
    echo ""
    echo "[1/3] 构建 Docker 镜像..."
    cd "${SCRIPT_DIR}"
    docker build -t "${FULL_NAME}" -t "${IMAGE_NAME}:latest" .
    echo "✓ 镜像构建完成: ${FULL_NAME}"
else
    echo ""
    echo "[1/3] 跳过构建 (--save-only)"
fi

# ---- 导出镜像 ----
echo ""
echo "[2/3] 导出镜像为 tar.gz 文件..."
docker save "${FULL_NAME}" | gzip > "${EXPORT_FILE}"
echo "✓ 导出完成: ${EXPORT_FILE}"
ls -lh "${EXPORT_FILE}"

# ---- 推送到 Docker Hub (可选) ----
if [[ "${1:-}" == "--push" ]]; then
    echo ""
    echo "[3/3] 推送到 Docker Hub..."
    read -p "Docker Hub 用户名: " DOCKER_USER
    docker tag "${FULL_NAME}" "${DOCKER_USER}/${FULL_NAME}"
    docker push "${DOCKER_USER}/${FULL_NAME}"
    echo "✓ 推送完成: ${DOCKER_USER}/${FULL_NAME}"
else
    echo ""
    echo "[3/3] 跳过推送 (使用 --push 启用)"
fi

echo ""
echo "============================================"
echo " ✅ 全部完成！"
echo ""
echo "  📦 镜像文件: ${EXPORT_FILE}"
echo ""
echo "  🚀 使用方法:"
echo "     # 1. 导入镜像到目标服务器"
echo "     docker load < ${EXPORT_FILE}"
echo ""
echo "     # 2. 查看帮助"
echo "     docker run --rm ${FULL_NAME} -h"
echo ""
echo "     # 3. Dry-run 测试"
echo "     docker run --rm \\"
echo "       -v /your/data/fastq:/data/fastq \\"
echo "       -v /your/data/ref:/data/ref \\"
echo "       -v /your/data/output:/data/output \\"
echo "       ${FULL_NAME} bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh \\"
echo "         -f /data/fastq -o /data/output -r /data/ref -n"
echo ""
echo "     # 4. 正式运行 (后台)"
echo "     docker run -d --name dnbc4tools-run \\"
echo "       -v /your/data/fastq:/data/fastq \\"
echo "       -v /your/data/ref:/data/ref \\"
echo "       -v /your/data/output:/data/output \\"
echo "       ${FULL_NAME} bash /opt/dnbc4tools-skill/华大批量上游分析dnbc4tools.sh \\"
echo "         -f /data/fastq -o /data/output -r /data/ref"
echo "============================================"
