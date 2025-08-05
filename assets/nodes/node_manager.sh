#!/bin/bash
# 用法：
# 环境启动自动同步：bash /workspace/assets/nodes/node_manager.sh setup
# 手动提交更新：bash /workspace/assets/nodes/node_manager.sh push

# 目录配置
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
LOG_DIR="/workspace/assets/logs"
WORKSPACE_DIR="/workspace"

# 创建日志目录
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/system.log"

# 关键：首次运行时清空日志文件（仅在setup模式下执行，避免push时重复清空）
if [ "$1" = "setup" ] && [ -f "$LOG_FILE" ]; then
  > "$LOG_FILE"  # 清空日志
fi

# 日志函数
log_terminal() {
  echo "$1"
}

log_detail() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [NODE_MANAGER] [$level] $msg" >> "$LOG_FILE"
}

# 节点同步逻辑（setup模式）
setup_nodes() {
  log_terminal "同步自定义节点..."
  log_detail "INFO" "开始节点同步流程"
  
  mkdir -p "$CUSTOM_NODES_DIR"

  # 检查清单文件
  if [ ! -f "$NODE_LIST_FILE" ]; then
    log_terminal "❌ 节点清单不存在"
    log_detail "ERROR" "未找到 $NODE_LIST_FILE"
    exit 1
  fi

  # 读取清单
  mapfile -t node_repos < <(grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$')
  expected_count=${#node_repos[@]}
  log_detail "INFO" "清单节点数: $expected_count"

  # 处理节点
  for repo in "${node_repos[@]}"; do
    node_name=$(basename "$repo" .git)
    node_dir="$CUSTOM_NODES_DIR/$node_name"
    
    if [ -d "$node_dir" ]; then
      cd "$node_dir" && git pull origin main >/dev/null 2>&1 || {
        log_terminal "⚠️ $node_name 更新失败"
        log_detail "WARN" "$node_name 更新失败"
      }
    else
      git clone "$repo" "$node_dir" >/dev/null 2>&1 || {
        log_terminal "⚠️ $node_name 安装失败"
        log_detail "ERROR" "$node_name 克隆失败"
      }
    fi
  done

  # 数量校验：只统计一级子目录（排除父目录、隐藏目录、符号链接）
  actual_count=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -xtype d ! -name ".*" | wc -l)
  log_detail "INFO" "实际目录节点数: $actual_count"

  if [ "$expected_count" -ne "$actual_count" ]; then
    log_terminal "⚠️ 节点数量不一致（清单:$expected_count 实际:$actual_count）"
  else
    log_terminal "✅ 节点同步完成"
  fi
}

# 提交推送逻辑（push模式）
push_changes() {
  log_terminal "提交更新..."
  log_detail "INFO" "开始提交流程"
  
  # 清理嵌套仓库
  find "$CUSTOM_NODES_DIR" -mindepth 2 -type d -name ".git" -exec rm -rf {} + >/dev/null 2>&1

  # 提交操作
  cd "$WORKSPACE_DIR" && {
    git add . >/dev/null 2>&1
    git commit -m "同步节点（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    if git push >/dev/null 2>&1; then
      log_terminal "✅ 推送完成"
    else
      log_terminal "❌ 推送失败"
      log_detail "ERROR" "git push执行失败"
    fi
  } || {
    log_terminal "❌ 工作目录错误"
    log_detail "ERROR" "无法进入 $WORKSPACE_DIR"
  }
}

# 按参数执行
case "$1" in
  setup) setup_nodes ;;
  push) push_changes ;;
  *) echo "用法：$0 {setup|push}"; exit 1 ;;
esac
