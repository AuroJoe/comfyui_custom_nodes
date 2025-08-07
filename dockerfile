# syntax=docker/dockerfile:1.6
# 构建阶段：合并所有依赖安装步骤
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel AS builder
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TZ=Asia/Shanghai \
    COMFYUI_HOME=/workspace/ComfyUI WORKSPACE=/workspace CONDA_DIR=/opt/conda

RUN set -eux && export DEBIAN_FRONTEND=noninteractive && \
    # 源配置+时区+系统工具安装（合并为一个命令链）
    sed -i 's|archive.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt update -qq && apt upgrade -qq -y && \
    apt install -qq -y --no-install-recommends \
        sudo tree procps lsof psmisc net-tools iputils-ping curl wget axel \
        netcat-openbsd telnet vim nano less grep sed jq zip unzip \
        tar gzip bzip2 unrar git git-lfs htop btop tmux build-essential \
        gcc g++ make cmake ffmpeg imagemagick file locate man-db rsync \
        patool crudini && \
    # 系统配置+缓存清理（合并）
    echo "root ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/root && \
    chmod 0440 /etc/sudoers.d/root && updatedb && \
    apt clean -qq && rm -rf /var/lib/apt/lists/* && \
    # Conda环境配置（合并）
    conda update -n base -c defaults conda -y && \
    conda create -n py311 python=3.11 pip -y && \
    conda create -n py310 python=3.10 pip -y && \
    conda init bash && conda clean -a -y && \
    # Python依赖安装（合并）
    . $CONDA_DIR/etc/profile.d/conda.sh && \
    conda activate py311 && pip install --no-cache-dir --upgrade pip && \
    pip install torch==2.7.1+cu128 torchvision==0.22.1+cu128 torchaudio==2.7.1+cu128 \
        --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir diffusers==0.34.0 && \
    conda activate py310 && pip install --no-cache-dir --upgrade pip && \
    pip install torch==2.7.1+cu128 torchvision==0.22.1+cu128 torchaudio==2.7.1+cu128 \
        --index-url https://download.pytorch.org/whl/cu128 && \
    pip install --no-cache-dir diffusers==0.34.0


# 最终阶段：合并运行时配置
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TZ=Asia/Shanghai \
    COMFYUI_HOME=/workspace/ComfyUI WORKSPACE=/workspace ENV_NAME=py311 \
    CONDA_DIR=/opt/conda PYTHONWARNINGS=ignore::UserWarning PIP_ROOT_USER_ACTION=ignore

# 复制必要文件+运行时配置（合并为2个核心RUN）
COPY --from=builder /opt/conda /opt/conda
COPY --from=builder /usr /usr
COPY --from=builder /etc/sudoers.d /etc/sudoers.d
COPY assets/main/entrypoint.sh $WORKSPACE/assets/main/entrypoint.sh

# 修正关键部分（将长命令链按逻辑拆分，确保续行正确）
RUN set -eux && export DEBIAN_FRONTEND=noninteractive && \
    # 系统配置+工具安装+缓存清理（合并）
    sed -i 's|archive.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt update -qq && apt install -qq -y --no-install-recommends \
        sudo tree procps lsof psmisc net-tools iputils-ping curl wget axel \
        netcat-openbsd telnet vim nano less  grep sed jq zip unzip \
        tar gzip bzip2 unrar git git-lfs htop btop tmux ffmpeg imagemagick \
        file locate man-db rsync patool crudini && \
    apt clean -qq && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* && \
    # 权限配置+路径初始化（合并）
    chmod +x $WORKSPACE/assets/main/entrypoint.sh && \
    mkdir -p $COMFYUI_HOME /root/.vscode-server/data/Machine /root/.local/share/code-server/Machine

# 单独处理ComfyUI配置文件（避免长命令链解析错误）
RUN tee $COMFYUI_HOME/extra_model_paths.yaml > /dev/null <<EOF
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

# 单独处理VS Code配置文件
RUN tee /root/.vscode-server/data/Machine/settings.json > /dev/null <<'EOF'
{
    "terminal.integrated.defaultProfile.linux": "BaseTerminal",
    "terminal.integrated.profiles.linux": {
        "BaseTerminal": {"path": "/bin/bash", "args": ["-li"], "icon": "terminal", "name": "基础终端"},
        "Py311Env": {"path": "/bin/bash", "args": ["-li", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py311 && bash -li"], "icon": "code", "name": "Python 3.11"},
        "Py310Env": {"path": "/bin/bash", "args": ["-li", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py310 && bash -li"], "icon": "code", "name": "Python 3.10"},
        "SystemMonitor": {"path": "btop", "icon": "dashboard", "name": "系统监控 btop"}
    },
    "workbench.activityBar.location": "hidden",
    "window.menuBarVisibility": "classic"
}
EOF

# 继续处理剩余配置（合并为一个RUN）
RUN set -eux && \
    cp /root/.vscode-server/data/Machine/settings.json /root/.local/share/code-server/Machine/settings.json && \
    # 安装code-server及插件+缓存清理
    curl -fsSL https://code-server.dev/install.sh | sh && \
    code-server --install-extension redhat.vscode-yaml dbaeumer.vscode-eslint eamodio.gitlens tencent-cloud.coding-copilot && \
    rm -rf /root/.cache/code-server && \
    # Bash配置
    > /root/.bashrc && \
    echo 'alias py311="conda activate py311"' >> /root/.bashrc && \
    echo 'alias py310="conda activate py310"' >> /root/.bashrc && \
    echo 'alias conda-list="conda env list"' >> /root/.bashrc && \
    echo 'alias monitor="btop"' >> /root/.bashrc && \
    echo 'source /opt/conda/etc/profile.d/conda.sh' >> /root/.bashrc && \
    echo 'if [ -z "$PROMPT_INIT" ]; then echo "👉 环境切换：py311/py310 | 查看环境：conda-list | 监控：monitor"; export PROMPT_INIT=1; fi' >> /root/.bashrc

# 环境变量与启动配置
ENV PATH="$CONDA_DIR/envs/$ENV_NAME/bin:$CONDA_DIR/bin:$PATH" CONDA_DEFAULT_ENV=$ENV_NAME
HEALTHCHECK --interval=30s --timeout=10s CMD curl -f http://localhost:8188 || exit 1
ENTRYPOINT ["$WORKSPACE/assets/main/entrypoint.sh"]