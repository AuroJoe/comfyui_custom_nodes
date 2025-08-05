#!/usr/bin/env bash
# build.sh - 精简版ComfyUI镜像构建脚本（无调试代码）

set -euo pipefail

# ========== 激活Conda环境 ==========
if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
  source /opt/conda/etc/profile.d/conda.sh
  conda activate py312 || { echo "❌ 激活py312环境失败"; exit 1; }
else
  echo "⚠️ 未找到Conda配置文件，跳过环境激活"
fi

# ========== 日志配置 ==========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "$LOG_DIR"
BUILD_LOG="${LOG_DIR}/build.log"
SYSTEM_LOG="${LOG_DIR}/system.log"
: > "$BUILD_LOG"
exec > >(tee -a "$BUILD_LOG") 2>&1

# ========== 版本与镜像配置 ==========
DATE_VERSION=$(date +'%Y%m%d')
IMAGE_NAME="docker.cnb.cool/luojunhao/comfyui_alpha"
TAG="${DATE_VERSION}"

# ========== 核心路径验证 ==========
if [ ! -f "/workspace/dockerfile" ] || [ ! -d "/workspace/" ]; then
  echo "❌ Dockerfile或构建上下文不存在"
  exit 1
fi

MANAGE_NODES="/workspace/assets/nodes/node_manager.sh"
if [ ! -f "$MANAGE_NODES" ]; then
  echo "❌ 节点管理脚本不存在: $MANAGE_NODES"
  exit 1
fi

# ========== 子模块与节点同步 ==========
echo "🔄 初始化Git子模块..."
cd /workspace/ || exit 1
git submodule sync --recursive
git submodule update --init --recursive
echo "✅ 子模块初始化完成"

echo "📦 执行节点同步..."
bash "$MANAGE_NODES" setup || { echo "❌ 节点同步失败"; exit 1; }
echo "✅ 节点同步完成"

# ========== 构建镜像 ==========
echo -e "\n🔨 开始构建镜像（版本: ${DATE_VERSION}）..."
docker buildx build \
  --no-cache \
  --platform=linux/amd64 \
  --tag "${IMAGE_NAME}:${TAG}" \
  --tag "${IMAGE_NAME}:latest" \
  -f /workspace/dockerfile \
  /workspace/ \
  --push || { echo "❌ 构建推送失败"; exit 1; }

# ========== 清理缓存 ==========
echo -e "\n🧹 清理Docker资源..."
docker builder prune -a -f
docker system prune -a -f
echo "✅ 缓存清理完成"

# ========== 合并日志 ==========
echo -e "\n📝 合并日志到system.log..."
echo -e "\n===== [$(date +'%Y-%m-%d %H:%M:%S')] 构建日志（版本: ${DATE_VERSION}）开始 =====" >> "$SYSTEM_LOG"
cat "$BUILD_LOG" >> "$SYSTEM_LOG"
echo -e "===== 构建日志结束 =====\n" >> "$SYSTEM_LOG"

# ========== 完成提示 ==========
echo -e "\n✅ 镜像构建推送成功！"
echo "📅 版本号: ${DATE_VERSION}"
echo "📥 拉取指定版本: docker pull ${IMAGE_NAME}:${TAG}"
echo "📥 拉取最新版本: docker pull ${IMAGE_NAME}:latest"
echo "📄 构建日志: ${BUILD_LOG}"
echo "🕒 完成时间: $(date +'%Y-%m-%d %H:%M:%S')"