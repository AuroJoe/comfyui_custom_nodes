# syntax=docker/dockerfile:1.6

# ==================== 基础镜像 ====================
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

# ==================== 环境变量 ====================
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    # 适配你的ComfyUI路径（位于/workspace/ComfyUI）
    COMFYUI_HOME=/workspace/ComfyUI \
    WORKSPACE=/workspace \
    ENV_NAME=py312 \
    CONDA_DIR=/opt/conda \
    PYTHONWARNINGS=ignore::UserWarning \
    PIP_ROOT_USER_ACTION=ignore

# ==================== 系统依赖与 Conda 环境 ====================
RUN set -eux && \
    # 更换镜像源和时区
    sed -i 's|archive.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.cloud.tencent.com|g' /etc/apt/sources.list && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # 安装基础系统工具
    apt update && \
    apt install -y --no-install-recommends \
        git git-lfs curl wget axel unzip zip tar file tree less \
        nano vim htop btop nload jq rsync \
        net-tools iputils-ping procps lsof tmux mlocate nmap \
        build-essential gcc g++ libgl1-mesa-glx openssh-server bash \
        libgl1 libglib2.0-0 \
        libblas3 liblapack3 \
        ffmpeg unrar patool \
        crudini && \
    apt clean && rm -rf /var/lib/apt/lists/* && \
    git lfs install --force && \
    # 创建 Conda 环境（保留py312作为默认）
    conda create -n py312 python=3.12 -y && \
    conda create -n py311 python=3.11 -y && \
    conda create -n py311 python=3.10 -y && \
    echo "source activate py312" > /etc/profile.d/conda_env.sh && \
    # 提前安装Python构建工具
    bash -c "source $CONDA_DIR/etc/profile.d/conda.sh && \
             conda activate py312 && \
             python -m ensurepip --upgrade && \
             pip install --no-cache-dir --force-reinstall pip && \
             pip install --no-cache-dir --upgrade setuptools wheel build setuptools-scm"


# ==================== SHELL（持久进入 Conda） ====================
SHELL ["/bin/bash", "-c"]

# ==================== 安装 Python 依赖 ====================
# 仅使用 py312 原生环境，不安装额外依赖
RUN source $CONDA_DIR/etc/profile.d/conda.sh && \
    conda activate py312 && \
    # 仅确保 pip 基础工具可用（不升级或安装其他库）
    python -m ensurepip --upgrade

# ==================== 安装 code-server 与插件 ====================
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    code-server --install-extension redhat.vscode-yaml \
                --install-extension dbaeumer.vscode-eslint \
                --install-extension eamodio.gitlens \
                --install-extension tencent-cloud.coding-copilot

# ==================== 设置模型路径映射====================
RUN mkdir -p $COMFYUI_HOME && \
    # 模型实际路径为 /workspace/ComfyUI/models，因此 base_path 设为 ComfyUI 目录
    tee $COMFYUI_HOME/extra_model_paths.yaml > /dev/null <<EOF
comfyui:
    base_path: /workspace/ComfyUI  # 模型根目录为 ComfyUI 下的 models，因此 base_path 指向 ComfyUI
    checkpoints: models/checkpoints/  # 完整路径：/workspace/ComfyUI/models/checkpoints/
    clip: models/clip/                # 完整路径：/workspace/ComfyUI/models/clip/
    clip_vision: models/clip_vision/  # 完整路径：/workspace/ComfyUI/models/clip_vision/
    configs: models/configs/          # 完整路径：/workspace/ComfyUI/models/configs/
    controlnet: models/controlnet/    # 完整路径：/workspace/ComfyUI/models/controlnet/
    diffusion_models: |
        models/diffusion_models       # 完整路径：/workspace/ComfyUI/models/diffusion_models/
        models/unet                   # 完整路径：/workspace/ComfyUI/models/unet/
    embeddings: models/embeddings/    # 完整路径：/workspace/ComfyUI/models/embeddings/
    loras: models/loras/              # 完整路径：/workspace/ComfyUI/models/loras/
    upscale_models: models/upscale_models/  # 完整路径：/workspace/ComfyUI/models/upscale_models/
    vae: models/vae/                  # 完整路径：/workspace/ComfyUI/models/vae/
EOF

# ==================== 初始化 Git 仓库与子模块 ====================
WORKDIR $WORKSPACE
RUN git init && \
    git submodule init && \
    git submodule sync && \
    git submodule update --init --recursive

# ==================== 拷贝节点安装脚本 ====================
# 你的节点脚本在/workspace/assets/nodes/，直接使用本地路径（无需复制，通过挂载生效）
# 若需构建时内置，可改为：COPY assets/nodes/ /workspace/assets/nodes/
RUN chmod +x /workspace/assets/nodes/manage_nodes.sh  # 确保脚本可执行

# ==================== 安装自定义节点 ====================
RUN --mount=type=cache,target=/root/.cache/pip \
    source $CONDA_DIR/etc/profile.d/conda.sh && \
    conda activate py312 && \
    echo '验证 Conda 环境 py312 是否正常工作...' && \
    python -c 'import torch, torchvision, diffusers; print(torch.__version__, torchvision.__version__, diffusers.__version__)' && \
    # 执行你的节点管理脚本（路径适配assets/nodes）
    bash /workspace/assets/nodes/manage_nodes.sh

# ==================== VS Code 终端配置====================
RUN mkdir -p /root/.vscode-server/data/Machine /root/.local/share/code-server/Machine && \
    tee /root/.vscode-server/data/Machine/settings.json > /dev/null <<EOF
{
    "terminal.integrated.defaultProfile.linux": "BaseTerminal",  // 默认终端不自动激活环境
    "terminal.integrated.profiles.linux": {
        "BaseTerminal": {
            "path": "/bin/bash",
            "args": ["-l"],  // 仅加载 bash 配置，不自动激活环境
            "icon": "terminal",
            "name": "基础终端（可手动切换环境）"
        },
        "Py312Env": {
            "path": "/bin/bash",
            "args": ["-l", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py312 && exec bash"],
            "icon": "code",
            "name": "Python 3.12 环境"
        },
        "Py311Env": {
            "path": "/bin/bash",
            "args": ["-l", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py311 && exec bash"],
            "icon": "code",
            "name": "Python 3.11 环境"
        },
        "Py310Env": {
            "path": "/bin/bash",
            "args": ["-l", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate py310 && exec bash"],
            "icon": "code",
            "name": "Python 3.10 环境"
        },
        "SystemMonitor": {
            "path": "btop",
            "icon": "dashboard",
            "name": "🖥️ 系统监控 btop"
        }
    },
    "workbench.activityBar.location": "hidden",
    "window.menuBarVisibility": "classic"
}
EOF

RUN cp /root/.vscode-server/data/Machine/settings.json /root/.local/share/code-server/Machine/settings.json


# ==================== Bash 配置====================
RUN echo 'alias monitor="btop"' >> /root/.bashrc && \
    # 三个环境的快速激活别名
    echo 'alias py312="conda activate py312"' >> /root/.bashrc && \
    echo 'alias py311="conda activate py311"' >> /root/.bashrc && \
    echo 'alias py310="conda activate py310"' >> /root/.bashrc && \
    # 查看环境列表的快捷命令
    echo 'alias conda-list="conda env list"' >> /root/.bashrc && \
    # 终端启动时显示切换提示
    echo 'echo "👉 环境切换命令："' >> /root/.bashrc && \
    echo 'echo "   - 切换到 Python 3.12：py312"' >> /root/.bashrc && \
    echo 'echo "   - 切换到 Python 3.11：py311"' >> /root/.bashrc && \
    echo 'echo "   - 切换到 Python 3.10：py310"' >> /root/.bashrc && \
    echo 'echo "   - 查看所有环境：conda-list"' >> /root/.bashrc && \
    # 加载 conda 配置，但不自动激活任何环境
    echo 'source $CONDA_DIR/etc/profile.d/conda.sh' >> /root/.bashrc && \
    echo 'source $CONDA_DIR/etc/profile.d/conda.sh' >> /root/.profile

# ==================== Entrypoint 设置（适配你的assets/main路径） ====================
# 使用你目录中的entrypoint.sh（/workspace/assets/main/entrypoint.sh）
RUN chmod +x /workspace/assets/main/entrypoint.sh

# ==================== 默认进入 Conda 环境 ====================
ENV PATH="/opt/conda/envs/${ENV_NAME}/bin:$PATH"
ENV CONDA_DEFAULT_ENV=$ENV_NAME

# ==================== 健康检查与容器入口 ====================
HEALTHCHECK --interval=30s --timeout=10s CMD curl -f http://localhost:8188 || exit 1
ENTRYPOINT ["/workspace/assets/main/entrypoint.sh"]