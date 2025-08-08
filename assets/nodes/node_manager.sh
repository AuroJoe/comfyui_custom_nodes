#!/bin/bash
# 用法：
# 环境启动自动同步子模块：bash /workspace/assets/nodes/node_manager.sh setup
# 手动提交子模块更新：bash /workspace/assets/nodes/node_manager.sh push

# 目录配置（与项目结构对齐）
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"  # 自定义节点目录
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"  # 节点仓库清单
LOG_DIR="/workspace/assets/logs"                     # 日志目录
WORKSPACE_DIR="/workspace"                           # 主仓库根目录（需是Git仓库）
GIT_MODULES_FILE="${WORKSPACE_DIR}/.gitmodules"      # Git子模块配置文件

# 创建日志目录和文件
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/node_manager.log"

# 日志函数：终端输出+文件记录
log() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] $msg" | tee -a "$LOG_FILE"
}

# 初始化子模块配置（首次运行时）
init_submodules() {
  if [ ! -f "$GIT_MODULES_FILE" ]; then
    log "INFO" "初始化Git子模块配置文件"
    cd "$WORKSPACE_DIR" && git init >/dev/null 2>&1  # 确保主目录是Git仓库
    touch "$GIT_MODULES_FILE"
    git add "$GIT_MODULES_FILE" >/dev/null 2>&1
  fi
}

# 同步子模块（setup模式核心逻辑）
setup_nodes() {
  log "INFO" "开始自定义节点子模块同步..."
  
  # 确保自定义节点目录存在
  mkdir -p "$CUSTOM_NODES_DIR"
  
  # 检查节点清单文件
  if [ ! -f "$NODE_LIST_FILE" ]; then
    log "ERROR" "节点清单文件不存在：$NODE_LIST_FILE"
    exit 1
  fi

  # 读取清单（过滤注释和空行）
  mapfile -t node_repos < <(grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$')
  local total=${#node_repos[@]}
  log "INFO" "清单中发现 $total 个节点仓库"

  # 初始化子模块配置
  init_submodules

  # 处理每个节点仓库（作为子模块）
  local success=0
  local failed=0

  for repo in "${node_repos[@]}"; do
    # 提取节点名称（从仓库URL解析）
    node_name=$(basename "$repo" .git)
    submodule_path="${CUSTOM_NODES_DIR}/${node_name}"  # 子模块路径（相对主仓库）
    relative_path=$(realpath --relative-to="$WORKSPACE_DIR" "$submodule_path")  # 主仓库相对路径

    log "INFO" "处理节点：$node_name（路径：$relative_path）"

    # 检查是否已作为子模块存在
    if git -C "$WORKSPACE_DIR" submodule status "$relative_path" >/dev/null 2>&1; then
      # 已存在：更新子模块到最新版本
      log "INFO" "更新子模块 $node_name..."
      if git -C "$WORKSPACE_DIR" submodule update --remote "$relative_path" >/dev/null 2>&1; then
        ((success++))
        log "INFO" "$node_name 更新成功"
      else
        ((failed++))
        log "ERROR" "$node_name 更新失败"
      fi
    else
      # 不存在：添加为新子模块
      log "INFO" "添加子模块 $node_name..."
      if git -C "$WORKSPACE_DIR" submodule add --force "$repo" "$relative_path" >/dev/null 2>&1; then
        # 初始化新添加的子模块
        git -C "$WORKSPACE_DIR" submodule update --init "$relative_path" >/dev/null 2>&1
        ((success++))
        log "INFO" "$node_name 添加成功"
      else
        ((failed++))
        log "ERROR" "$node_name 添加失败（可能已存在非子模块目录）"
      fi
    fi
  done

  # 同步结果统计
  log "INFO" "子模块同步完成：成功 $success 个，失败 $failed 个（总计 $total 个）"
  if [ $failed -gt 0 ]; then
    log "WARN" "部分节点同步失败，请查看日志：$LOG_FILE"
  fi
}

# 提交子模块更新（push模式核心逻辑）
push_changes() {
  log "INFO" "开始提交子模块及主仓库更新..."

  # 检查主仓库是否为Git仓库
  if [ ! -d "${WORKSPACE_DIR}/.git" ]; then
    log "ERROR" "主目录不是Git仓库：$WORKSPACE_DIR"
    exit 1
  fi

  # 1. 提交所有子模块的本地更改
  log "INFO" "提交子模块本地更改..."
  find "$CUSTOM_NODES_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r submodule; do
    node_name=$(basename "$submodule")
    if [ -d "${submodule}/.git" ]; then
      # 检查子模块是否有更改
      if ! git -C "$submodule" diff --quiet; then
        log "INFO" "提交子模块 $node_name 的更改..."
        git -C "$submodule" add . >/dev/null 2>&1
        git -C "$submodule" commit -m "更新节点 $node_name（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
        git -C "$submodule" push >/dev/null 2>&1 || log "WARN" "$node_name 推送失败（可能无权限）"
      else
        log "INFO" "子模块 $node_name 无更改，跳过提交"
      fi
    fi
  done

  # 2. 提交主仓库中子模块的版本引用更新
  log "INFO" "提交主仓库对子模块的版本引用..."
  cd "$WORKSPACE_DIR" || {
    log "ERROR" "无法进入主仓库目录：$WORKSPACE_DIR"
    exit 1
  }

  if ! git diff --quiet; then
    git add .gitmodules */*  # 添加子模块配置和版本引用
    git commit -m "同步子模块版本（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    if git push >/dev/null 2>&1; then
      log "INFO" "主仓库推送成功"
    else
      log "ERROR" "主仓库推送失败"
      exit 1
    fi
  else
    log "INFO" "主仓库无子模块版本更新，跳过提交"
  fi

  log "INFO" "所有更新提交完成"
}

# 按参数执行对应功能
case "$1" in
  setup) setup_nodes ;;
  push) push_changes ;;
  *) 
    log "ERROR" "用法：$0 {setup|push}"
    exit 1 
    ;;
esac
