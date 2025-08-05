#!/bin/bash
# 用法：
# 环境启动自动同步节点：bash /workspace/assets/nodes/node_manager.sh setup
# 手动提交更新：bash /workspace/assets/nodes/node_manager.sh push

# 适配你的目录结构（关键调整）
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"  # 清单路径
LOG_FILE="/workspace/assets/nodes/node_manager.log"  # 日志路径
WORKSPACE_DIR="/workspace"

# 日志函数
log() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$LOG_FILE"
  echo "[$level] $msg"
}

# 节点同步逻辑（setup模式）
setup_nodes() {
  log "INFO" "开始同步自定义节点（适配assets/nodes目录）..."
  mkdir -p "$CUSTOM_NODES_DIR"
  touch "$LOG_FILE"

  # 检查清单文件是否存在（路径适配）
  if [ ! -f "$NODE_LIST_FILE" ]; then
    log "ERROR" "节点清单 $NODE_LIST_FILE 不存在，请确认路径"
    exit 1
  fi

  # 读取清单（过滤注释和空行）
  mapfile -t node_repos < <(grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$')
  expected_count=${#node_repos[@]}
  log "INFO" "清单定义节点数：$expected_count"

  # 克隆/更新节点
  for repo in "${node_repos[@]}"; do
    node_name=$(basename "$repo" .git)
    node_dir="$CUSTOM_NODES_DIR/$node_name"
    
    if [ -d "$node_dir" ]; then
      log "INFO" "更新节点：$node_name"
      cd "$node_dir" && git pull origin main || log "WARN" "节点 $node_name 更新失败"
    else
      log "INFO" "安装节点：$node_name"
      git clone "$repo" "$node_dir" || log "ERROR" "节点 $node_name 克隆失败"
    fi
  done

  # 数量校验
  actual_count=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
  log "INFO" "实际存在节点数：$actual_count"
  
  if [ "$expected_count" -ne "$actual_count" ]; then
    log "WARN" "节点数量不一致（清单：$expected_count，实际：$actual_count）"
  else
    log "INFO" "节点同步完成"
  fi
}

# 提交推送逻辑（push模式）
push_changes() {
  log "INFO" "开始提交更新..."
  
  # 清理嵌套Git仓库
  log "INFO" "清理custom_nodes中的嵌套.git目录..."
  find "$CUSTOM_NODES_DIR" -mindepth 2 -type d -name ".git" -exec rm -rf {} +

  # 提交到外层仓库
  cd "$WORKSPACE_DIR" || {
    log "ERROR" "无法进入工作目录 $WORKSPACE_DIR"
    exit 1
  }
  
  git add .
  git commit -m "同步节点更新（$(date +'%Y-%m-%d')）"
  git push || log "ERROR" "推送失败，请检查网络或权限"
  
  log "INFO" "提交完成"
}

# 按参数执行对应功能
case "$1" in
  setup) setup_nodes ;;
  push) push_changes ;;
  *) echo "用法：$0 {setup|push}"; exit 1 ;;
esac