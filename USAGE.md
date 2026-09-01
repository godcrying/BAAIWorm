# BAAIWorm 使用说明

> 依据项目根目录 `README.md` 整理，并针对本机（Arch Linux，见 `BUILD_FIX_NOTES.md`）环境做了适配说明。
> 整理日期：2026-08-31

## 项目组成

- **eworm** — 神经系统模型（NEURON 多房室模型）
- **Metaworm** — 身体与物理环境模型（FEM 有限元）
- **neuronXcore** — 3D 可视化渲染器（`build/neuronXcore`）

三者闭环联动：`neuronXcore`（C++ GUI）→ 加载 `eworm` 生成的神经营养形态数据（`.swc`）→ 通过 `interact.so` 调用 `Metaworm` 仿真 → 渲染播放。

## 1. 构建（已完成）

对应 README "Build" 章节，`build/` 即参考 `build2/`。当前构建产物：

- `build/neuronXcore`（3D 可视化可执行文件）
- `build/interact.so`（Python 可导入的交互仿真库）

## 2. 快速 Demo（开环仿真）—— 已跑通 ✅

演示数据：`eworm/ghost_in_mesh_sim/data/tuned/video_offline/video_offline_neuronX/`（含 `group1.swc/.snp/.vtg`）。

直接跑启动脚本（内含混合显卡 PRIME offload 环境变量）：

```bash
cd /data/lee/Git-clone/BAAIWorm/build
./run_demo.sh
```

**注意**：
- 窗口先黑一段时间是**正常的**：渲染循环 `showAndRun()` 在 main 末尾才启动，之前要完成漫长的初始化（加载 302 神经元 NEURON 模型 + 虫体 FEM），通常 1-2 分钟。等初始化完成才出画面。
- 按 **space** 播放/暂停仿真，`v` 切换神经元/虫体主视图。
- 报 "No module named xxx" 就先 `export PYTHONPATH=/data/lee/Git-clone/BAAIWorm/`。

### 混合显卡必须的环境变量（黑屏的解法之一）

本机是 AMD 核显 + NVIDIA 独显。GL 默认建在 AMD 核显上，而 CUDA/OptiX 跑在 NVIDIA 上，`cudaGraphicsGLRegisterImage` 跨 GPU 互操作会失败导致黑屏。必须强制 GL 走 NVIDIA：

```bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export PYTHONPATH="/data/lee/Git-clone/BAAIWorm/worm/lib/python3.14/site-packages:/data/lee/Git-clone/BAAIWorm/build:/data/lee/Git-clone/BAAIWorm/"
```

（`run_demo.sh` 已包含以上三行。）

## 3. 完整使用流程

### 3a. 仿真与训练（Python 侧）

```bash
# 生成 NMODL 机制库（离子通道模型）
cd eworm/components/mechanism
nrnivmodl modfile          # 找不到命令时在 ~/.local/bin 下找

# 训练神经网络控制身体（eworm_learn 里是离线拟合训练，见 README "Fitting the neural network data"）
cd eworm/ghost_in_mesh_sim
python 02_train_cnn.py

# 导出你的网络形态数据供可视化
python 03_make_morph.py
```

### 3b. 运行你自己的仿真

```bash
./neuronXcore -data [你的神经形态数据目录]   # 目录必须含 .swc 文件
```

- 扰动实验：改 `worm_neural_network.py` 第 58 行对应的函数。
- 离线训练网络：`cd eworm_learn && ./x86_64/special run_eworm_v4.py`（先 `nrnivmodl components/mechanism/modfile`）。

## 4. GUI 操作

| 操作 | 说明 |
|------|------|
| 鼠标（虫体视图） | 右键旋转 / 中键缩放 |
| 鼠标（神经视图） | 左键旋转 / 中键平移 / 右键缩放 |
| `space` | 播放/暂停 |
| `r` | 重置 worm |
| `t` / `w` / `m` | 虫体四面体网格 / 虫体 / 96 条肌肉 |
| `p` / `a` | 游泳轨迹 / 方向箭头 |
| `x` / `c` | 世界坐标轴 / 虫体头部坐标轴 |
| `v` | 切换神经/虫体主视图 |
| `1` / `2` | 截图 / 显示子视图 |
| `q` | 退出 |

## 5. 启动参数

```bash
./neuronXcore -data DIR     # 神经形态数据目录（必须含 .swc）
             -ss DIR        # 截图保存目录（默认 ./screenshots）
             --worm-auto-screenshot
             -win W H       # 窗口尺寸
             -spp SPP       # 神经渲染每像素采样数
             -morp DIR      # 细分神经元形态可视化
             -obj DIR       # 脑切片三角网格可视化
             -curve DIR     # 大规模神经元曲线可视化
```

## 6. 环境依赖备忘（已就绪）

- **Python 虚拟环境**：`worm/`（python 3.14）。已装 `numpy scipy matplotlib tqdm pandas neuron 9.0.2 torch 2.13(+cu13) xlrd seaborn pymp ipython`。
  - NEURON 机制库已编译：`eworm/components/mechanism/x86_64/`（`nrnivmodl modfile`）。
- **数据文件路径**：已把缺失的 C302 肌肉文件与 KeyWorm 状态 JSON 拷贝到 `Metaworm/data/` 和 `build/data/`。`worm_actions_300_220428-144704.json` 仓库本身缺失（非致命，仅影响 KeyWorm 动作回放）。
- **可视化本身不依赖 Python**；只有跑"闭环仿真"（demo）时才需要 Python + `interact.so`。
- 仓库 `requirements.txt` 是 Ubuntu 系统包快照（含 apturl/dbus-python 等无关包），且版本很老（torch 1.12.1 / numpy 1.21）。Arch 上只装实际需要的即可（上述 venv 已装齐）。
- README 测试环境是 Ubuntu 20.04 + CUDA 11.4 + OptiX 7.0；本机为 Arch + CUDA 12.6 + OptiX 9.1 + Eigen 5 + 混合显卡，工具链与显示均已适配（见 `BUILD_FIX_NOTES.md`）。
