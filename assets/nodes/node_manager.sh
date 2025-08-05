#!/bin/bash
# 功能：节点管理脚本（支持setup初始化和sync同步）
# 用法：
#   bash node_manager.sh setup  # 初始化环境
#   bash node_manager.sh sync   # 同步节点

# 目录配置
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
COMFYUI_SUBMODULE_DIR="/workspace/ComfyUI"
WORKSPACE_DIR="/workspace"
LOG_DIR="/workspace/assets/logs"
LOG_FILE="${LOG_DIR}/system.log"

# 初始化目录
mkdir -p "$CUSTOM_NODES_DIR" "$LOG_DIR"

# 日志函数
log_terminal() {
  echo "$1"
}

log_detail() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [NODE_MANAGER] [$level] $msg" >> "$LOG_FILE"
}

# 读取nodes_list
read_nodes_list() {
  grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$' | sort
}

# 读取现有节点
read_existing_nodes() {
  while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      if [ -d "${CUSTOM_NODES_DIR}/${node_name}" ]; then
        echo "$repo_url"
      fi
    fi
  done < <(read_nodes_list) | sort
}

# 检测默认分支
get_default_branch() {
  local repo_url=$1
  local branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2}')
  echo "${branch:-main}"
}

# setup模式：初始化环境（首次运行）
setup_env() {
  log_terminal "开始初始化环境..."
  > "$LOG_FILE"  # 清空日志
  log_detail "INFO" "setup模式：环境初始化开始"

  # 1. 确保ComfyUI子模块已初始化
  if [ ! -d "${COMFYUI_SUBMODULE_DIR}/.git" ]; then
    log_terminal "初始化ComfyUI子模块..."
    git submodule init "$COMFYUI_SUBMODULE_DIR" >/dev/null 2>&1
    git submodule update "$COMFYUI_SUBMODULE_DIR" >/dev/null 2>&1 || {
      log_terminal "⚠️ ComfyUI子模块初始化失败"
      log_detail "ERROR" "ComfyUI子模块初始化失败"
      exit 1
    }
  fi

  # 2. 创建custom_nodes目录（如果不存在）
  if [ ! -d "$CUSTOM_NODES_DIR" ]; then
    mkdir -p "$CUSTOM_NODES_DIR"
    log_detail "INFO" "创建custom_nodes目录: $CUSTOM_NODES_DIR"
  fi

  # 3. 确保nodes_list文件存在
  if [ ! -f "$NODE_LIST_FILE" ]; then
    log_terminal "创建默认nodes_list文件..."
    touch "$NODE_LIST_FILE"
    echo "# 节点仓库URL列表（每行一个）" >> "$NODE_LIST_FILE"
    log_detail "INFO" "创建默认nodes_list: $NODE_LIST_FILE"
  fi

  log_terminal "✅ 环境初始化完成"
  log_detail "INFO" "setup模式：环境初始化完成"
}

# sync模式：同步节点
sync_nodes() {
  log_terminal "开始同步nodes_list到custom_nodes..."
  > "$LOG_FILE"  # 清空日志
  log_detail "INFO" "sync模式：节点同步开始"

  local nodes_list=$(read_nodes_list)
  local existing_nodes=$(read_existing_nodes)

  echo "$nodes_list" > /tmp/nodes_list.txt
  echo "$existing_nodes" > /tmp/existing_nodes.txt

  # 1. 新增节点
  log_terminal "检查新增节点..."
  comm -23 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      if git clone "$repo_url" "$node_dir" >/dev/null 2>&1; then
        log_terminal "✅ 新增节点: $node_name"
        log_detail "INFO" "克隆节点成功: $repo_url"
      else
        log_terminal "⚠️ 新增节点失败: $node_name"
        log_detail "ERROR" "克隆节点失败: $repo_url"
      fi
    fi
  done

  # 2. 更新节点
  log_terminal "检查节点更新..."
  comm -12 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      if [ -d "${node_dir}/.git" ]; then
        branch=$(get_default_branch "$repo_url")
        cd "$node_dir" && {
          if git pull origin "$branch" >/dev/null 2>&1; then
            log_terminal "🔄 更新节点成功: $node_name（分支: $branch）"
            log_detail "INFO" "更新节点成功: $node_name"
          else
            log_terminal "⚠️ 节点更新失败: $node_name（分支: $branch）"
            log_detail "WARN" "拉取失败: $repo_url"
          fi
        }
      fi
    fi
  done

  # 3. 删除节点
  log_terminal "检查需删除的节点..."
  find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name ".*" | while read -r node_dir; do
    node_name=$(basename "$node_dir")
    if ! grep -q "/${node_name}\.git" "$NODE_LIST_FILE" && ! grep -q "/${node_name}$" "$NODE_LIST_FILE"; then
      rm -rf "$node_dir"
      log_terminal "❌ 移除节点: $node_name"
      log_detail "INFO" "删除节点: $node_dir"
    fi
  done

  # 4. 提交变更
  cd "$WORKSPACE_DIR" && {
    git add "$COMFYUI_SUBMODULE_DIR"
    git commit -m "同步节点（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    if git push origin main >/dev/null 2>&1; then
      log_terminal "✅ 变更已推送到远程"
    else
      log_terminal "⚠️ 推送失败，请手动提交"
    fi
  }

  # 验证数量
  local expected_count=$(wc -l < /tmp/nodes_list.txt)
  local actual_count=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -xtype d ! -name ".*" | wc -l)
  if [ "$expected_count" -eq "$actual_count" ]; then
    log_terminal "✅ 同步完成（总数: $expected_count）"
  else
    log_terminal "⚠️ 数量不一致（清单:$expected_count 实际:$actual_count）"
  fi
}

# 按参数执行
case "$1" in
  setup) setup_env ;;
  sync) sync_nodes ;;
  *) echo "用法：$0 {setup|sync}"; exit 1 ;;
esac
