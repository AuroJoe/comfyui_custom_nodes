#!/bin/bash
# 子模块更新脚本（日志整合版）

# 目录配置
WORKSPACE_DIR="/workspace"
COMFYUI_DIR="${WORKSPACE_DIR}/ComfyUI"
LOG_DIR="/workspace/assets/logs"  # 统一日志文件夹

# 创建统一日志目录（确保存在）
mkdir -p "$LOG_DIR"

# 输出控制：终端显示关键信息，详细日志写入统一目录
log_terminal() {
  echo "$1"
}

log_detail() {
  local level=$1
  local msg=$2
  # 所有日志整合到一个文件，添加模块标识便于区分
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUBMODULE] [$level] $msg" >> "${LOG_DIR}/system.log"
}

# 检查目录是否存在
check_directory() {
  if [ ! -d "$1" ]; then
    log_terminal "❌ 目录不存在: $1"
    log_detail "ERROR" "目录验证失败: $1"
    exit 1
  fi
}

# 主逻辑
log_terminal "更新ComfyUI子模块..."
log_detail "INFO" "开始子模块更新流程"

# 检查工作目录
check_directory "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}" || exit

# 拉取外层仓库更新（静默执行，仅提示结果）
if git checkout main >/dev/null 2>&1 && git pull origin main --rebase >/dev/null 2>&1; then
  log_detail "INFO" "外层仓库更新成功"
else
  log_terminal "⚠️ 外层仓库更新失败"
  log_detail "WARN" "外层仓库拉取失败"
fi

# 初始化并更新子模块（静默执行）
if git submodule init >/dev/null 2>&1 && git submodule update --recursive >/dev/null 2>&1; then
  log_detail "INFO" "子模块初始化完成"
else
  log_terminal "⚠️ 子模块初始化失败"
  log_detail "WARN" "子模块初始化过程出错"
fi

# 更新ComfyUI本身（静默执行）
check_directory "${COMFYUI_DIR}"
cd "${COMFYUI_DIR}" || exit

if git checkout master >/dev/null 2>&1 && git pull origin master >/dev/null 2>&1; then
  log_terminal "✅ ComfyUI更新完成"
  log_detail "INFO" "ComfyUI主仓库更新成功"
else
  log_terminal "⚠️ ComfyUI更新失败"
  log_detail "WARN" "ComfyUI主仓库拉取失败"
fi
