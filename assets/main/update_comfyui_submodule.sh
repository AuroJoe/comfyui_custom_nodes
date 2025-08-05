#!/bin/bash
# /workspace/assets/main/update_comfyui_submodule.sh

# 定义工作目录（确保与你的实际目录一致）
WORKSPACE_DIR="/workspace"
COMFYUI_DIR="${WORKSPACE_DIR}/ComfyUI"

# 函数：检查目录是否存在
check_directory() {
  if [ ! -d "$1" ]; then
    echo "错误：目录 $1 不存在，请检查路径是否正确"
    exit 1
  fi
}

# 1. 检查外层仓库目录
check_directory "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}" || exit

# 2. 确保外层仓库处于main分支并拉取最新配置
echo "拉取外层仓库最新代码..."
git checkout main || git checkout -b main  # 若main分支不存在则创建
git pull origin main --rebase  # 拉取最新代码并变基，避免冲突

# 3. 初始化并更新子模块
echo "初始化子模块..."
git submodule init || echo "子模块已初始化，跳过初始化步骤"

echo "更新子模块内容..."
git submodule update --recursive  # --recursive确保子模块的子依赖也更新

# 4. 拉取ComfyUI官方最新代码（子模块自身更新）
check_directory "${COMFYUI_DIR}"
cd "${COMFYUI_DIR}" || exit
echo "拉取ComfyUI官方最新代码..."
git checkout master  # 切换到ComfyUI的默认分支（官方默认是master）
git pull origin master

# 5. 完成提示
echo "子模块更新完成！ComfyUI目录已同步至最新版本"