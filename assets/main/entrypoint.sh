#!/bin/bash
set -e

# 定义统一日志文件（整合所有输出）
SYSTEM_LOG="/workspace/assets/logs/system.log"
mkdir -p "$(dirname "$SYSTEM_LOG")"  # 确保日志目录存在

# 日志函数（统一输出到system.log并打印到终端）
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [ENTRYPOINT] $1"
  echo "$msg" | tee -a "$SYSTEM_LOG"
}

# 激活 Conda 环境
log "===== 激活 Conda 环境: $ENV_NAME ====="
if [ -z "$ENV_NAME" ]; then
  log "警告: 未设置 ENV_NAME，默认使用 py312"
  ENV_NAME="py312"
fi

# 加载 Conda 并验证
source /opt/conda/etc/profile.d/conda.sh || { log "错误: 无法加载 Conda 配置"; exit 1; }
if ! command -v conda &> /dev/null; then
  log "错误: Conda 未正确初始化"
  exit 1
fi

# 激活环境并验证
conda activate "$ENV_NAME" || { log "错误: 激活环境 $ENV_NAME 失败"; exit 1; }
log "已激活 Conda 环境: $(conda info --base)/envs/$ENV_NAME"

# 输出环境信息（写入日志）
log "===== 环境信息 ====="
python --version 2>&1 | tee -a "$SYSTEM_LOG" || { log "错误: Python 未安装"; exit 1; }
log "PyTorch 版本: $(python -c "import torch; print(torch.__version__)")"
log "CUDA 可用: $(python -c "import torch; print(torch.cuda.is_available())")"

# 检查并安装 ComfyUI 依赖
COMFYUI_DIR="/workspace/ComfyUI"
REQUIREMENTS="$COMFYUI_DIR/requirements.txt"
log "===== 检查 ComfyUI 依赖: $REQUIREMENTS ====="
if [ -f "$REQUIREMENTS" ]; then
  log "安装 ComfyUI 依赖..."
  pip install --no-cache-dir -r "$REQUIREMENTS" >> "$SYSTEM_LOG" 2>&1 || {
    log "错误: 安装依赖失败"
    exit 1
  }
else
  log "警告: 未找到 $REQUIREMENTS，跳过依赖安装"
fi

# 启动 ComfyUI（适配目录结构）
COMFYUI_MAIN="$COMFYUI_DIR/main.py"
log "===== 检查 ComfyUI 主程序: $COMFYUI_MAIN ====="
if [ ! -f "$COMFYUI_MAIN" ]; then
  log "错误: 未找到 ComfyUI 主程序 $COMFYUI_MAIN"
  exit 1
fi

# 启动服务（作为主进程）
log "===== 启动 ComfyUI 服务 ====="
log "访问地址: http://localhost:8188"
exec python "$COMFYUI_MAIN" --listen 0.0.0.0 --port 8188 >> "$SYSTEM_LOG" 2>&1