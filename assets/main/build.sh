docker#!/usr/bin/env bash
# build.sh - 构建并推送 ComfyUI 镜像（支持日志输出，版本号含当天日期）

set -euo pipefail

# ========== 激活 Conda 环境 ==========
if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
  source /opt/conda/etc/profile.d/conda.sh
  conda activate py312 || { echo "❌ 激活 py312 环境失败"; exit 1; }
else
  echo "❌ 未找到 Conda 配置文件，跳过环境激活"
fi

# ========== 基本参数配置（含日期版本号） ==========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "$LOG_DIR"
BUILD_LOG="${LOG_DIR}/build.log"
SYSTEM_LOG="${LOG_DIR}/system.log"

# 动态生成版本号：当天日期（格式：YYYYMMDD，如 20250805）
DATE_VERSION=$(date +'%Y%m%d')
# 镜像名称（版本号使用当天日期）
IMAGE_NAME="docker.cnb.cool/luojunhao/comfyui_alpha"
TAG="${DATE_VERSION}"  # 版本号为当天日期，如 20250805

# Dockerfile 路径与构建上下文
DOCKERFILE_PATH="DOCKERFILE_PATH="/workspace/assets/dockerfile"
CONTEXT_DIR="${SCRIPT_DIR}/../../"

# ========== 日志重定向 ==========
: > "$BUILD_LOG"
exec > >(tee -a "$BUILD_LOG") 2>&1

# ========== 初始化 Git 子模块 ==========
echo "🔄 初始化 Git 子模块..."
cd "$CONTEXT_DIR" || { echo "❌ 进入上下文目录失败: $CONTEXT_DIR"; exit 1; }
git submodule sync --recursive
git submodule update --init --recursive
echo "✅ 子模块初始化完成"

# ========== 执行节点管理脚本 ==========
MANAGE_NODES="/workspace/assets/nodes/node_manager.sh"
if [ ! -f "$MANAGE_NODES" ]; then
  echo "❌ 未找到节点管理脚本: $MANAGE_NODES"
  exit 1
fi

echo "📦 执行节点同步脚本（使用 setup 参数）..."
bash "$MANAGE_NODES" setup || { echo "❌ 节点同步脚本执行失败"; exit 1; }
echo "✅ 节点同步完成"

# ========== 输出构建信息（含版本号） ==========
echo -e "\n📦 开始构建 Docker 镜像..."
echo "🕒 开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
echo "📌 本次构建版本号: ${DATE_VERSION}"  # 显示版本号
echo "📂 Dockerfile 路径: $DOCKERFILE_PATH"
echo "📁 构建上下文目录: $CONTEXT_DIR"
echo "🐳 镜像名称: $IMAGE_NAME:$TAG"
echo "🔍 构建日志路径: $BUILD_LOG"

if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ Dockerfile 不存在: $DOCKERFILE_PATH"
  exit 1
fi

# ========== 构建并推送镜像 ==========
echo -e "\n🔨 开始构建镜像（版本: ${DATE_VERSION}）..."
docker buildx build \
  --progress=plain \
  --platform=linux/amd64 \
  --tag "$IMAGE_NAME:$TAG" \
  --tag "$IMAGE_NAME:latest" \
  -f "$DOCKERFILE_PATH" \
  "$CONTEXT_DIR" \
  --push

# ========== 清理缓存 ==========
echo -e "\n🧹 清理 Docker 缓存..."
docker builder prune -f
docker image prune -f
docker container prune -f
docker volume prune -f
echo "✅ 缓存清理完成"

# ========== 合并日志到 system.log ==========
echo -e "\n📝 合并构建日志到 system.log..."
echo -e "\n===== [$(date +'%Y-%m-%d %H:%M:%S')] 构建日志（版本: ${DATE_VERSION}）开始 =====" >> "$SYSTEM_LOG"
cat "$BUILD_LOG" >> "$SYSTEM_LOG"
echo -e "===== [$(date +'%Y-%m-%d %H:%M:%S')] 构建日志（版本: ${DATE_VERSION}）结束 =====\n" >> "$SYSTEM_LOG"

# ========== 构建完成提示（含版本号） ==========
echo -e "\n✅ 镜像构建成功！"
echo "📌 构建版本号: ${DATE_VERSION}"
echo "📥 拉取命令: docker pull $IMAGE_NAME:$TAG"
echo "📥 拉取最新版: docker pull $IMAGE_NAME:latest"  # 若添加了 latest 标签
echo "🌐 镜像地址: https://docker.cnb.cool/luojunhao/comfyui_alpha:$TAG"
echo "🕒 结束时间: $(date +'%Y-%m-%d %H:%M:%S')"
echo "📄 构建日志已保存至: $BUILD_LOG"
echo "📄 构建日志已合并至: $SYSTEM_LOG"