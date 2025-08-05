#!/bin/bash
# 功能：在ComfyUI子模块内同步nodes_list清单，支持日志覆盖
# 用法：bash node_manager.sh sync

# 目录配置
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
COMFYUI_SUBMODULE_DIR="/workspace/ComfyUI"
WORKSPACE_DIR="/workspace"
LOG_DIR="/workspace/assets/logs"
LOG_FILE="${LOG_DIR}/system.log"

# 初始化目录
mkdir -p "$CUSTOM_NODES_DIR" "$LOG_DIR"

# 日志函数：输出到终端
log_terminal() {
  echo "$1"
}

# 日志函数：输出到文件（追加模式）
log_detail() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [NODE_MANAGER] [$level] $msg" >> "$LOG_FILE"
}

# 读取nodes_list中的仓库列表（过滤注释和空行）
read_nodes_list() {
  grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$' | sort
}

# 读取当前已存在的节点（从URL提取名称）
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

# 自动检测仓库的默认分支
get_default_branch() {
  local repo_url=$1
  # 尝试获取远程默认分支（支持HTTPS和SSH格式）
  local branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2}')
  # 若获取失败，默认使用main
  echo "${branch:-main}"
}

# 同步节点（核心逻辑）
sync_nodes() {
  # 每次sync时清空日志文件（关键修复）
  if [ -f "$LOG_FILE" ]; then
    > "$LOG_FILE"
    log_detail "INFO" "日志已清空，开始新的同步会话"
  fi

  log_terminal "开始同步nodes_list到custom_nodes..."
  log_detail "INFO" "同步节点流程启动（子模块内模式）"

  # 获取清单和现有节点的仓库列表
  local nodes_list=$(read_nodes_list)
  local existing_nodes=$(read_existing_nodes)

  # 临时文件存储列表（用于对比）
  echo "$nodes_list" > /tmp/nodes_list.txt
  echo "$existing_nodes" > /tmp/existing_nodes.txt

  # 1. 处理新增节点
  log_terminal "检查新增节点..."
  comm -23 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      # 克隆仓库
      if git clone "$repo_url" "$node_dir" >/dev/null 2>&1; then
        log_terminal "✅ 新增节点: $node_name"
        log_detail "INFO" "克隆节点成功: $repo_url → $node_dir"
      else
        log_terminal "⚠️ 新增节点失败: $node_name"
        log_detail "ERROR" "克隆节点失败: $repo_url"
      fi
    fi
  done

  # 2. 处理节点更新（自动适配分支）
  log_terminal "检查节点更新..."
  comm -12 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      if [ -d "${node_dir}/.git" ]; then
        # 检测节点仓库的默认分支
        branch=$(get_default_branch "$repo_url")
        cd "$node_dir" && {
          if git pull origin "$branch" >/dev/null 2>&1; then
            log_terminal "🔄 更新节点成功: $node_name（分支: $branch）"
            log_detail "INFO" "更新节点成功: $node_name（分支: $branch）"
          else
            log_terminal "⚠️ 节点更新失败: $node_name（分支: $branch）"
            log_detail "WARN" "拉取节点更新失败: $repo_url（分支: $branch）"
          fi
        }
      else
        log_detail "INFO" "节点无.git目录，跳过更新: $node_name"
      fi
    fi
  done

  # 3. 处理删除节点
  log_terminal "检查需删除的节点..."
  find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name ".*" | while read -r node_dir; do
    node_name=$(basename "$node_dir")
    # 检查节点是否在清单中
    if ! grep -q "/${node_name}\.git" "$NODE_LIST_FILE" && \
       ! grep -q "/${node_name}$" "$NODE_LIST_FILE"; then
      rm -rf "$node_dir"
      log_terminal "❌ 移除节点: $node_name"
      log_detail "INFO" "删除节点目录: $node_dir"
    fi
  done

  # 4. 提交变更到主仓库（通过ComfyUI子模块）
  cd "$WORKSPACE_DIR" && {
    # 提交ComfyUI子模块（包含custom_nodes的变化）
    git add "$COMFYUI_SUBMODULE_DIR"
    git commit -m "同步custom_nodes节点（$(date +'%Y-%m-%d %H:%M')）" >/dev/null 2>&1
    if git push origin main >/dev/null 2>&1; then
      log_terminal "✅ 节点变更已通过ComfyUI子模块推送到远程"
      log_detail "INFO" "节点变更已推送到远程仓库"
    else
      log_terminal "⚠️ 推送失败，请手动提交ComfyUI子模块"
      log_detail "ERROR" "推送远程仓库失败"
    fi
  }

  # 验证节点数量
  local expected_count=$(wc -l < /tmp/nodes_list.txt)
  local actual_count=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -xtype d ! -name ".*" | wc -l)
  if [ "$expected_count" -eq "$actual_count" ]; then
    log_terminal "✅ 节点同步完成（总数: $expected_count）"
    log_detail "INFO" "节点同步完成，数量匹配（预期: $expected_count, 实际: $actual_count）"
  else
    log_terminal "⚠️ 节点数量不一致（清单:$expected_count 实际:$actual_count）"
    log_detail "WARN" "节点数量不匹配（预期: $expected_count, 实际: $actual_count）"
  fi
}

# 按参数执行
case "$1" in
  sync) sync_nodes ;;
  *) echo "用法：$0 sync（同步nodes_list到custom_nodes）"; exit 1 ;;
esac
