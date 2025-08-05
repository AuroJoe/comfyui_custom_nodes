#!/bin/bash
# 功能：同步nodes_list清单到custom_nodes（不使用子模块，避免嵌套问题）
# 用法：bash node_manager.sh sync

# 保持原有目录结构（在ComfyUI子模块内部）
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
NODE_LIST_FILE="/workspace/assets/nodes/nodes_list"
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

# 读取当前custom_nodes中已存在的节点目录（从URL提取的名称）
read_existing_nodes() {
  # 遍历nodes_list中的URL，检查对应目录是否存在（避免无关目录干扰）
  while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      if [ -d "${CUSTOM_NODES_DIR}/${node_name}" ]; then
        echo "$repo_url"
      fi
    fi
  done < <(read_nodes_list) | sort
}

# 同步节点：通过git clone/pull管理，不使用子模块
sync_nodes() {
  log_terminal "开始同步nodes_list到custom_nodes..."
  log_detail "INFO" "同步节点流程启动（非子模块模式）"

  # 获取清单和现有节点的仓库列表
  local nodes_list=$(read_nodes_list)
  local existing_nodes=$(read_existing_nodes)

  # 临时文件存储列表（用于对比）
  echo "$nodes_list" > /tmp/nodes_list.txt
  echo "$existing_nodes" > /tmp/existing_nodes.txt

  # 1. 处理新增节点（清单有，本地无）
  log_terminal "检查新增节点..."
  comm -23 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      # 克隆仓库（不使用子模块，直接作为普通目录）
      if git clone "$repo_url" "$node_dir" >/dev/null 2>&1; then
        # 移除节点目录内的.git文件夹（避免嵌套Git仓库，可选）
        rm -rf "${node_dir}/.git"
        log_terminal "✅ 新增节点: $node_name"
        log_detail "INFO" "克隆节点成功: $repo_url → $node_dir"
      else
        log_terminal "⚠️ 新增节点失败: $node_name"
        log_detail "ERROR" "克隆节点失败: $repo_url"
      fi
    fi
  done

  # 2. 处理更新节点（清单和本地都有）
  log_terminal "检查节点更新..."
  comm -12 /tmp/nodes_list.txt /tmp/existing_nodes.txt | while read -r repo_url; do
    if [ -n "$repo_url" ]; then
      node_name=$(basename "$repo_url" .git)
      node_dir="${CUSTOM_NODES_DIR}/${node_name}"

      # 进入节点目录拉取最新代码（若保留.git文件夹则可更新）
      if [ -d "${node_dir}/.git" ]; then
        cd "$node_dir" && git pull origin main >/dev/null 2>&1 && {
          log_detail "INFO" "更新节点成功: $node_name"
        } || {
          log_terminal "⚠️ 节点更新失败: $node_name"
          log_detail "WARN" "拉取节点更新失败: $repo_url"
        }
      else
        log_detail "INFO" "节点无.git目录，跳过更新: $node_name"
      fi
    fi
  done

  # 3. 处理删除节点（本地有，清单无）
  log_terminal "检查需删除的节点..."
  # 找出custom_nodes中存在但不在清单中的节点目录
  find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name ".*" | while read -r node_dir; do
    node_name=$(basename "$node_dir")
    # 检查该节点是否在nodes_list中
    if ! grep -q "/${node_name}\.git" "$NODE_LIST_FILE" && \
       ! grep -q "/${node_name}$" "$NODE_LIST_FILE"; then
      # 不在清单中，删除目录
      rm -rf "$node_dir"
      log_terminal "✅ 移除节点: $node_name"
      log_detail "INFO" "删除节点目录: $node_dir"
    fi
  done

  # 4. 提交节点变更到外层仓库（作为普通文件）
  cd "$WORKSPACE_DIR" && {
    git add "$CUSTOM_NODES_DIR"
    git commit -m "同步nodes_list节点（$(date +'%Y-%m-%d')）" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1 && log_terminal "✅ 节点变更已推送到远程"
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
