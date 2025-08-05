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
source /opt/conda/etc/profile.d/conda.sh || { log "错误: 无法加载 Conda 配置"; exit 1; }
conda activate "$ENV_NAME" || { log "错误: 激活环境 $ENV_NAME 失败"; exit 1; }

# 输出环境信息（写入日志）
log "===== 环境信息 ====="
python --version 2>&1 | tee -a "$SYSTEM_LOG" || { log "错误: Python 未安装"; exit 1; }
log "Conda 环境: $(conda info --base)/envs/$ENV_NAME"
log "PyTorch 版本: $(python -c "import torch; print(torch.__version__)")"
log "CUDA 可用: $(python -c "import torch; print(torch.cuda.is_available())")"

# 启动 ComfyUI（适配目录结构）
COMFYUI_MAIN="/workspace/ComfyUI/main.py"
log "===== 检查 ComfyUI 主程序: $COMFYUI_MAIN ====="
if [ ! -f "$COMFYUI_MAIN" ]; then
  log "错误: 未找到 ComfyUI 主程序 $COMFYUI_MAIN"
  exit 1
fi

# 启动服务（输出直接追加到system.log）
log "===== 启动 ComfyUI 服务 ====="
nohup python "$COMFYUI_MAIN" --listen 0.0.0.0 --port 8188 >> "$SYSTEM_LOG" 2>&1 &
log "ComfyUI 已启动，输出将写入 $SYSTEM_LOG"

# 健康检查（循环检测）
log "===== 等待服务就绪 ====="
for i in {1..30}; do
  if curl -s -f http://localhost:8188 > /dev/null; then
    log "ComfyUI 服务已就绪（http://localhost:8188）"
    break
  fi
  if [ $i -eq 30 ]; then
    log "错误: 服务启动超时（最后10行日志如下）"
    tail -n 10 "$SYSTEM_LOG" | tee -a "$SYSTEM_LOG"  # 输出最新日志到system.log
    exit 1
  fi
  sleep 2
done

# 保持容器运行（监听system.log）
log "===== 容器启动完成，持续监听日志 ====="
tail -f "$SYSTEM_LOG"