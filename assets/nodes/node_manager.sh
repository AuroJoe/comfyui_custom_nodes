#!/bin/bash
# 功能：同步nodes_list清单到custom_nodes子模块，自动更新.gitmodules
# 用法：bash node_manager.sh sync

# 目录配置
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
GITMODULES_FILE="/workspace/.gitmodules"  # .gitmodules位置（仓库根目录）
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

# 读取nodes_list中的仓库列表（过滤注释和空行）
read_nodes_list() {
  grep -v '^\s*#' "$NODE_LIST_FILE" | grep -v '^\s*$' | sort
}

# 读取.gitmodules中已配置的子模块（仅custom_nodes下的）
read_existing_submodules() {
  if [ -f "$GITMODULES_FILE" ]; then
    # 提取[submodule "custom_nodes/xxx"]中的URL
    git config --file "$GITMODULES_FILE" --get-regexp 'submodule\."custom_nodes/.*"\.url' | \
    awk -F'url = ' '{print $2}' | sort
  else
    return 0
  fi
}

# 同步子模块：根据nodes_list新增/删除子模块
sync_submodules() {
  log_terminal "开始同步nodes_list到子模块..."
  log_detail "INFO" "同步子模块流程启动"

  # 获取清单和现有子模块的仓库列表
  local nodes_list=$(read_nodes_list)
  local existing_submodules=$(read_existing_submodules)

  # 临时文件存储列表（用于对比）
  echo "$nodes_list" > /tmp/nodes_list.txt
  echo "$existing_submodules" > /tmp/existing_submodules.txt

  # 1. 处理新增节点（清单有，现有子模块无）
  log_terminal "检查新增节点..."
  comm -23 /tmp/nodes_list.txt /tmp/existing_submodules.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)  # 从URL提取节点名（如"repo.git"→"repo"）
      submodule_path="${CUSTOM_NODES_DIR}/${node_name}"

      # 添加子模块到.gitmodules和custom_nodes
      if git submodule add --force "$repo_url" "$submodule_path" >/dev/null 2>&1; then
        log_terminal "✅ 新增子模块: $node_name"
        log_detail "INFO" "添加子模块成功: $repo_url → $submodule_path"
      else
        log_terminal "⚠️ 新增子模块失败: $node_name"
        log_detail "ERROR" "添加子模块失败: $repo_url"
      fi
    fi
  done

  # 2. 处理删除节点（现有子模块有，清单无）
  log_terminal "检查需删除的节点..."
  comm -13 /tmp/nodes_list.txt /tmp/existing_submodules.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      submodule_path="${CUSTOM_NODES_DIR}/${node_name}"

      # 从Git中移除子模块（保留配置，便于后续恢复）
      if git submodule deinit -f "$submodule_path" >/dev/null 2>&1 && \
         git rm -f "$submodule_path" >/dev/null 2>&1; then
        # 彻底删除工作区文件（可选，根据需求保留）
        rm -rf "$submodule_path"
        log_terminal "✅ 移除子模块: $node_name"
        log_detail "INFO" "移除子模块成功: $repo_url"
      else
        log_terminal "⚠️ 移除子模块失败: $node_name"
        log_detail "ERROR" "移除子模块失败: $repo_url"
      fi
    fi
  done

  # 3. 更新.gitmodules（清理无效配置）
  git config --file "$GITMODULES_FILE" --remove-section "submodule.${CUSTOM_NODES_DIR}/" 2>/dev/null
  log_detail "INFO" ".gitmodules已同步"

  # 4. 提交变更到主仓库
  cd "$WORKSPACE_DIR" && {
    git add "$GITMODULES_FILE" "$CUSTOM_NODES_DIR"
    git commit -m "同步nodes_list子模块（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1 && log_terminal "✅ 子模块变更已推送到远程"
  }

  # 验证数量
  local expected_count=$(wc -l < /tmp/nodes_list.txt)
  local actual_count=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -xtype d ! -name ".*" | wc -l)
  if [ "$expected_count" -eq "$actual_count" ]; then
    log_terminal "✅ 子模块同步完成（总数: $expected_count）"
  else
    log_terminal "⚠️ 子模块数量不一致（清单:$expected_count 实际:$actual_count）"
  fi
}

# 按参数执行
case "$1" in
  sync) sync_submodules ;;
  *) echo "用法：$0 sync（同步nodes_list到子模块）"; exit 1 ;;
esac
