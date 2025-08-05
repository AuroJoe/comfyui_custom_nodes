#!/usr/bin/env bash
# build.sh - 构建并推送 ComfyUI 镜像（支持日志输出）

set -euo pipefail  # 严格模式：遇到错误、未定义变量、管道失败时退出

# ========== 激活 Conda 环境（确保节点脚本依赖的环境正确） ==========
if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
  source /opt/conda/etc/profile.d/conda.sh
  conda activate py312 || { echo "❌ 激活 py312 环境失败"; exit 1; }
else
  echo "❌ 未找到 Conda 配置文件，跳过环境激活"
fi

# ========== 基本参数配置（适配你的目录结构） ==========
# 脚本所在目录（/workspace/assets/main/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 日志目录（统一到 assets/logs/，与 system.log 同目录）
LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "$LOG_DIR"
BUILD_LOG="${LOG_DIR}/build.log"  # 构建日志路径

# Dockerfile 路径（位于 workspace 根目录）
DOCKERFILE_PATH="${SCRIPT_DIR}/../../Dockerfile"
# 构建上下文目录（workspace 根目录）
CONTEXT_DIR="${SCRIPT_DIR}/../../"
# 镜像名称与标签（替换为你的仓库地址）
IMAGE_NAME="docker.cnb.cool/luojunhao/comfyui_alpha"  # 保持与参考一致
TAG="latest"  # 可根据需要改为版本号（如 v1.0）

# ========== 日志重定向（所有输出写入 build.log 并打印到终端） ==========
: > "$BUILD_LOG"  # 每次构建前清空日志
exec > >(tee -a "$BUILD_LOG") 2>&1  # 标准输出和错误均写入日志

# ========== 初始化 Git 子模块（同步 ComfyUI 及嵌套子模块） ==========
echo "🔄 初始化 Git 子模块..."
cd "$CONTEXT_DIR" || { echo "❌ 进入上下文目录失败: $CONTEXT_DIR"; exit 1; }
git submodule sync --recursive  # 同步子模块远程地址
git submodule update --init --recursive  # 拉取子模块代码
echo "✅ 子模块初始化完成"

# ========== 执行节点管理脚本（同步 custom_nodes） ==========
MANAGE_NODES="${SCRIPT_DIR}/../nodes/manage_nodes.sh"  # 节点脚本路径
if [ ! -f "$MANAGE_NODES" ]; then
  echo "❌ 未找到节点管理脚本: $MANAGE_NODES"
  exit 1
fi

echo "📦 执行节点同步脚本..."
bash "$MANAGE_NODES" || { echo "❌ 节点同步脚本执行失败"; exit 1; }
echo "✅ 节点同步完成"

# ========== 输出构建信息（便于调试） ==========
echo -e "\n📦 开始构建 Docker 镜像..."
echo "🕒 开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
echo "📂 Dockerfile 路径: $DOCKERFILE_PATH"
echo "📁 构建上下文目录: $CONTEXT_DIR"
echo "🐳 镜像名称: $IMAGE_NAME:$TAG"
echo "🔍 构建日志路径: $BUILD_LOG"

# 检查 Dockerfile 是否存在
if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ Dockerfile 不存在: $DOCKERFILE_PATH"
  exit 1
fi

# ========== 构建并推送镜像（使用 buildx 支持多平台） ==========
echo -e "\n🔨 开始构建镜像..."
docker buildx build \
  --progress=plain \  # 显示详细构建过程
  --platform=linux/amd64 \  # 目标平台（根据你的需求调整）
  --tag "$IMAGE_NAME:$TAG" \
  -f "$DOCKERFILE_PATH" \
  "$CONTEXT_DIR" \
  --push  # 如需仅构建不推送，移除 --push

# ========== 清理构建缓存（释放空间） ==========
echo -e "\n🧹 清理 Docker 缓存..."
docker builder prune -f  # 清理构建器缓存
docker image prune -f    # 清理无用镜像
docker container prune -f  # 清理停止的容器
docker volume prune -f    # 清理无用卷
echo "✅ 缓存清理完成"

# ========== 构建完成提示 ==========
echo -e "\n✅ 镜像构建成功！"
echo "📥 拉取命令: docker pull $IMAGE_NAME:$TAG"
echo "🌐 镜像地址: https://docker.cnb.cool/luojunhao/comfyui_alpha:$TAG"
echo "🕒 结束时间: $(date +'%Y-%m-%d %H:%M:%S')"
echo "📄 构建日志已保存至: $BUILD_LOG"