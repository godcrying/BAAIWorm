#!/usr/bin/env bash
# BAAIWorm neuronXcore demo 启动脚本
# 用法: ./run_demo.sh [其他参数...]
# 说明: 窗口会先黑屏一段时间（初始化神经元网络+虫体 FEM，通常 10-60s），
#       初始化完成后才进入渲染循环显示画面。按 space 播放/暂停。
set -e
cd "$(dirname "$0")"

# 混合显卡（AMD 核显 + NVIDIA 独显）:强制 GL 走 NVIDIA，否则 CUDA-GL 互操作失败→黑屏
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# 让内嵌的 Python(system libpython3.14)找到 worm venv 依赖 + build 的 interact.so + 项目根
export PYTHONPATH="/data/lee/Git-clone/BAAIWorm/worm/lib/python3.14/site-packages:/data/lee/Git-clone/BAAIWorm/build:/data/lee/Git-clone/BAAIWorm/"

exec ./neuronXcore -data ../eworm/ghost_in_mesh_sim/data/tuned/video_offline/video_offline_neuronX "$@"
