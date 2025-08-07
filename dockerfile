# syntax=docker/dockerfile:1.6

# ==================== 基础镜像 ====================
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel

# ==================== 环境变量 ====================
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    COMFYUI_HOME=/workspace/ComfyUI \
    WORKSPACE=/workspace \
    ENV_NAME=py312 \
    CONDA_DIR=/opt/conda \
    PYTHONWARNINGS=ignore::UserWarning \
    PIP_ROOT_USER_ACTION=ignore

# ==================== 系统依赖与基础配置 ====================
RUN set -eux && \
    # 配置apt非交互模式并屏蔽警告
    echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90noninteractive && \
    echo 'DPkg::Options "--force-confold";' >> /etc/apt/apt.conf.d/90noninteractive && \
    # 更换国内镜像源
    sed -i 's|archive.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    # 配置时区
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # 重定向apt输出以屏蔽警告（核心优化）
    (apt update -qq && apt upgrade -qq) >/dev/null 2>&1 && \
    # 安装依赖时同样屏蔽输出
    DEBIAN_FRONTEND=noninteractive apt install -qq --no-install-recommends \
        git git-lfs curl wget axel unzip zip tar \
        nano vim-tiny htop btop tmux \
        net-tools iputils-ping procps lsof \
        build-essential gcc g++ libgl1-mesa-glx \
        libgl1 libglib2.0-0 libblas3 liblapack3 \
        ffmpeg unrar patool crudini >/dev/null 2>&1 && \
    # 清理缓存
    apt clean -qq && \
    rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* && \
    # 初始化Git LFS
    git lfs install --force

# ==================== Conda环境配置 ====================
RUN set -eux && \
    # 升级conda到最新版本以消除警告
    conda update -n base -c defaults conda -y && \
    # 创建多版本Python环境（预安装pip基础工具）
    conda create -n py312 python=3.12 pip -y && \
    conda create -n py311 python=3.11 pip -y && \
    conda create -n py310 python=3.10 pip -y && \
    # 配置conda自动初始化
    conda init bash && \
    # 清理conda缓存
    conda clean -a -y
    
# ==================== 安装跨环境通用依赖 ====================
SHELL ["/bin/bash", "-lic"]  # 使用登录shell确保conda初始化生效

# 为每个环境安装PyTorch和核心依赖
RUN --mount=type=cache,target=/root/.cache/pip \
    # 处理py312环境
    conda activate py312 && \
    pip install --no-cache-dir --upgrade pip && \
    pip install torch==2.7.1+cu128 torchvision==0.22.1+cu128 torchaudio==2.7.1+cu128 \
        --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir diffusers==0.34.0 && \
    # 处理py311环境
    conda activate py311 && \
    pip install --no-cache-dir --upgrade pip && \
    pip install torch==2.7.1+cu128 torchvision==0.22.1+cu128 torchaudio==2.7.1+cu128 \
        --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir diffusers==0.34.0 && \
    # 处理py310环境
    conda activate py310 && \
    pip install --no-cache-dir --upgrade pip && \
    pip install torch==2.7.1+cu128 torchvision==0.22.1+cu128 torchaudio==2.7.1+cu128 \
        --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir diffusers==0.34.0 && \
    # 验证默认环境
    conda activate $ENV_NAME && \
    python -c "import torch, diffusers; print(f'PyTorch {torch.__version__} | Diffusers {diffusers.__version__}')"

# ==================== 安装code-server及插件 ====================
RUN set -eux && \
    curl -fsSL https://code-server.dev/install.sh | sh && \
    code-server --install-extension redhat.vscode-yaml \
                --install-extension dbaeumer.vscode-eslint \
                --install-extension eamodio.gitlens \
                --install-extension tencent-cloud.coding-copilot

# ==================== ComfyUI模型路径配置 ====================
RUN set -eux && \
    mkdir -p $COMFYUI_HOME && \
    tee $COMFYUI_HOME/extra_model_paths.yaml > /dev/null <<EOF
comfyui:
    base_path: /workspace/ComfyUI
    checkpoints: models/checkpoints/
    clip: models/clip/
    clip_vision: models/clip_vision/
    configs: models/configs/
    controlnet: models/controlnet/
    diffusion_models: |
        models/diffusion_models
        models/unet
    embeddings: models/embeddings/
    loras: models/loras/
    upscale_models: models/upscale_models/
    vae: models/vae/
EOF

# ==================== VS Code终端配置 ====================
RUN set -eux && \
    mkdir -p /root/.vscode-server/data/Machine /root/.local/share/code-server/Machine
RUN tee /root/.vscode-server/data/Machine/settings.json > /dev/null <<'EOF'
{
    "terminal.integrated.defaultProfile.linux": "BaseTerminal",
    "terminal.integrated.profiles.linux": {
        "BaseTerminal": {
            "path": "/bin/bash",
            "args": ["-li"],
            "icon": "terminal",
            "name": "基础终端"
        },
        "Py312Env": {
            "path": "/bin/bash",
            "args": ["-li", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py312 && bash -li"],
            "icon": "code",
            "name": "Python 3.12"
        },
        "Py311Env": {
            "path": "/bin/bash",
            "args": ["-li", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py311 && bash -li"],
            "icon": "code",
            "name": "Python 3.11"
        },
        "Py310Env": {
            "path": "/bin/bash",
            "args": ["-li", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py310 && bash -li"],
            "icon": "code",
            "name": "Python 3.10"
        },
        "SystemMonitor": {
            "path": "btop",
            "icon": "dashboard",
            "name": "系统监控 btop"
        }
    },
    "workbench.activityBar.location": "hidden",
    "window.menuBarVisibility": "classic"
}
EOF
RUN cp /root/.vscode-server/data/Machine/settings.json /root/.local/share/code-server/Machine/settings.json

# ==================== Bash alias 与提示 ====================
RUN set -eux && \
    > /root/.bashrc &&  # 清空历史配置，避免冲突 \
    # 基础别名（不自动激活任何环境） \
    echo 'alias py312="conda activate py312"' >> /root/.bashrc && \
    echo 'alias py311="conda activate py311"' >> /root/.bashrc && \
    echo 'alias py310="conda activate py310"' >> /root/.bashrc && \
    echo 'alias conda-list="conda env list"' >> /root/.bashrc && \
    echo 'alias monitor="btop"' >> /root/.bashrc && \
    # 仅加载conda基础配置，不默认激活环境（避免覆盖终端选择） \
    echo 'source /opt/conda/etc/profile.d/conda.sh' >> /root/.bashrc && \
    # 提示信息：仅首次启动显示一次 \
    echo 'if [ -z "$PROMPT_INIT" ]; then' >> /root/.bashrc && \
    echo '  echo "👉 环境切换：py312/py311/py310 | 查看环境：conda-list | 监控：monitor"' >> /root/.bashrc && \
    echo '  export PROMPT_INIT=1' >> /root/.bashrc && \
    echo 'fi' >> /root/.bashrc
    
# ==================== 容器启动配置 ====================
COPY assets/main/entrypoint.sh $WORKSPACE/assets/main/entrypoint.sh
RUN chmod +x $WORKSPACE/assets/main/entrypoint.sh

# 配置环境变量优先级
ENV PATH="$CONDA_DIR/envs/$ENV_NAME/bin:$CONDA_DIR/bin:$PATH" \
    CONDA_DEFAULT_ENV=$ENV_NAME

HEALTHCHECK --interval=30s --timeout=10s CMD curl -f http://localhost:8188 || exit 1

ENTRYPOINT ["$WORKSPACE/assets/main/entrypoint.sh"]
    