#!/bin/bash
# 功能：在ComfyUI子模块内同步nodes_list（修复提交和更新失败）
# 用法：bash node_manager.sh sync

# 保持目录在ComfyUI子模块内
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
COMFYUI_SUBMODULE_DIR="/workspace/ComfyUI"  # ComfyUI子模块路径
WORKSPACE_DIR="/workspace"
LOG_DIR="/workspace/assets/logs"

# 初始化目录和日志
mkdir -p "$CUSTOM_NODES_DIR" "$LOG_DIR"
LOG_FILE="${LOG_DIR}/system.log"

# 日志函数
log_terminal() {
  echo "$1"
}

log_detail() {
  local level=$1
  local msg=$2
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [NODE_MANAGER] [$level] $msg" >> "$LOG_FILE"
}

# 读取nodes_list中的仓库列表
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

# 自动检测仓库的默认分支（解决更新失败）
get_default_branch() {
  local repo_url=$1
  # 尝试获取远程默认分支（支持HTTPS和SSH格式）
  local branch=$(git ls-remote --symref "$repo_url" HEAD | awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2}')
  # 若获取失败，默认使用main或master
  echo "${branch:-main}"
}

# 同步节点
sync_nodes() {
  log_terminal "开始同步nodes_list到custom_nodes..."
  log_detail "INFO" "同步节点流程启动（子模块内模式）"

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
        rm -rf "${node_dir}/.git"  # 移除嵌套Git仓库
        log_terminal "✅ 新增节点: $node_name"
        log_detail "INFO" "克隆节点成功: $repo_url"
      else
        log_terminal "⚠️ 新增节点失败: $node_name（网络或URL错误）"
        log_detail "ERROR" "克隆失败: $repo_url"
      fi
    fi
  done

  # 2. 更新节点（自动适配分支）
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
            log_detail "INFO" "更新节点成功: $node_name（分支: $branch）"
          else
            log_terminal "⚠️ 节点更新失败: $node_name（分支: $branch）"
            log_detail "WARN" "拉取失败: $repo_url（分支: $branch）"
          fi
        }
      else
        log_detail "INFO" "节点无.git目录，跳过更新: $node_name"
      fi
    fi
  done

  # 3. 删除节点
  log_terminal "检查需删除的节点..."
  find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name ".*" | while read -r node_dir; do
    node_name=$(basename "$node_dir")
    # 检查节点是否在清单中
    if ! grep -q "/${node_name}\.git" "$NODE_LIST_FILE" && \
       ! grep -q "/${node_name}$" "$NODE_LIST_FILE"; then
      rm -rf "$node_dir"
      log_terminal "✅ 移除节点: $node_name"
      log_detail "INFO" "删除节点: $node_dir"
    fi
  done

  # 4. 提交变更（关键修复：提交ComfyUI子模块的整体变化）
  # 因为custom_nodes在ComfyUI子模块内，需通过提交子模块引用实现同步
  cd "$WORKSPACE_DIR" && {
    # 提交ComfyUI子模块（包含其内部custom_nodes的变化）
    git add "$COMFYUI_SUBMODULE_DIR"
    git commit -m "同步custom_nodes节点（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    if git push origin main >/dev/null 2>&1; then
      log_terminal "✅ 节点变更已通过ComfyUI子模块推送到远程"
    else
      log_terminal "⚠️ 推送失败，请手动提交ComfyUI子模块"
    fi
  }

  # 验证数量
  local expected_count=$(wc -l < /tmp/nodes_list.txt)
  local actual_count=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -xtype d ! -name ".*" | wc -l)
  if [ "$expected_count" -eq "$actual_count" ]; then
    log_terminal "✅ 节点同步完成（总数: $expected_count）"
  else
    log_terminal "⚠️ 节点数量不一致（清单:$expected_count 实际:$actual_count）"
  fi
}

# 按参数执行
case "$1" in
  sync) sync_nodes ;;
  *) echo "用法：$0 sync（同步nodes_list到custom_nodes）"; exit 1 ;;
esac
