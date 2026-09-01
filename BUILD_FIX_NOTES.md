# BAAIWorm 构建修复说明（Eigen5 / 现代工具链迁移）

> 日期：2026-08-31 ｜ 系统：Arch Linux
> 目的：解决 `cmake ../neuronXcore` 报 "eigen3 相关文件未找到"，并将整个构建迁移到 Eigen 5.0.1 / GCC 16 / OptiX 9.1 / CUDA 12.6 的现代工具链上。

## 结论：无需"迁移到 Eigen5"——系统上装的就是 Eigen 5.0.1

Arch 的 `eigen` 包即 5.0.1，头文件仍位于 `/usr/include/eigen3/Eigen/`，CMake 包名仍叫 `Eigen3`（无独立 "Eigen5" 包名）。配置阶段其实成功，真正的根因是**老代码依赖的 CMake 变量在 config 模式下不被设置**。

## 各问题与修复

### 1. `Eigen/Core: No such file or directory`（include 路径为空）

- **根因**：`find_package(Eigen3)` 在 CMake 4.x 走 config 模式，只创建 imported target `Eigen3::Eigen`，**不会**设置旧 module 模式的 `${EIGEN3_INCLUDE_DIR}`。而 `Metaworm/sim`、`sim/fem`、`render`、`interact` 四处 CMakeLists 都用 `include_directories(${EIGEN3_INCLUDE_DIR})`，该变量为空 → `/usr/include/eigen3` 没进 include 路径。
- **修复**：在每个 `find_package(Eigen3 REQUIRED)` 后补一行，从 target 取回 include 目录：
  ```cmake
  get_target_property(EIGEN3_INCLUDE_DIR Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES)
  ```
- 涉及文件：`Metaworm/sim/CMakeLists.txt`、`Metaworm/sim/fem/CMakeLists.txt`、`Metaworm/render/CMakeLists.txt`、`Metaworm/interact/CMakeLists.txt`

### 2. `#error Eigen requires at least c++14 support`

- **根因**：Eigen 5 要求 C++14，项目用 `-std=gnu++11` 编译含 Eigen 的代码。
- **修复**：`Metaworm/` 下 5 个 CMakeLists 的 `-std=gnu++11` 改为 `-std=gnu++14`（父级 + sim + fem + render + interact）。
- 涉及文件：`Metaworm/CMakeLists.txt`、`Metaworm/sim/CMakeLists.txt`、`Metaworm/sim/fem/CMakeLists.txt`、`Metaworm/render/CMakeLists.txt`、`Metaworm/interact/CMakeLists.txt`

### 3. GCC 13+ 缺少 `<cstdint>` / `<cassert>`（隐式包含被移除）

- **根因**：新 GCC 不再通过其他头文件隐式提供 `uint32_t`、`assert`。
- **修复**：
  - `owl/owl/include/owl/common/owl-common.h`：补 `#include <cstdint>`
  - 在 `Metaworm/CMakeLists.txt`（传播到 sim/fem/render/interact）与 `owl/CMakeLists.txt` 的 `-include cassert`（仅非 Windows），一次覆盖所有使用 `assert` 但缺 include 的文件
- 涉及文件：`owl/owl/include/owl/common/owl-common.h`、`Metaworm/CMakeLists.txt`、`owl/CMakeLists.txt`

### 4. OptiX 6 API → OptiX 9.1（`optixModuleCreateFromPTX` 已移除）

- **根因**：owl 用 OptiX 6 时代的 `optixModuleCreateFromPTX`，OptiX 7 起改名为 `optixModuleCreate`，签名完全一致。
- **修复**：两处直接改名 `optixModuleCreateFromPTX` → `optixModuleCreate`。
- 涉及文件：`owl/owl/ll/Device.cpp`、`owl/owl/Module.cpp`

### 5. CUDA 12.6 nvcc 与 GCC 16 不兼容

- **根因**：nvcc 12.6 官方只支持到 GCC 13；GCC 16 的 libstdc++ 头文件 nvcc 无法解析（`type_traits` 大量报错）。
- **修复**：给 rtn 的 nvcc 指定 gcc-13 为宿主编译器并显式用 C++14：
  ```cmake
  set(CUDA_NVCC_FLAGS "${CUDA_NVCC_FLAGS} -ccbin /usr/bin/g++-13 -std=c++14")
  ```
  > 注意：仅 `-allow-unsupported-compiler` 不够，nvcc 12.6 仍无法解析 GCC 16 的 libstdc++，必须 `-ccbin g++-13`。系统需已安装 `gcc13` 包。
- 涉及文件：`neuronXcore/rtn/CMakeLists.txt`

### 6. 设备端代码 `saturate` / `uint_as_float`

- **根因**：
  - `owl-common.h` 在 `__CUDA_ARCH__` 分支用了 CUDA 并不存在的全局 `::saturate`。
  - `roundedCone.h` 调用 `uint_as_float`，全库无定义；按打包/解包逻辑（8bit 通道 `/255` 归一化），本意是数值转换 `float(x)`。
- **修复**：
  - `owl/owl/include/owl/common/owl-common.h`：`using ::saturate;` 改为同 host 分支一致的 `inline __both__ float saturate(const float &f) { return min(1.f,max(0.f,f)); }`
  - `neuronXcore/rtn/device/roundedCone.h`：`uint_as_float(x)` → `float(x)`（3 处）

### 7. 主机端 C++11 下 Eigen `constexpr` 冲突

- **根因**：`neuronXcore` 用 `-std=c++11`。C++11 中 `constexpr` 成员函数隐式 `const`，导致 Eigen `derived()` 两个重载冲突，`static_cast` casts away qualifiers。
- **修复**：`neuronXcore/CMakeLists.txt` 的 `--std=c++11` / `-std=c++11` 改为 `--std=c++14` / `-std=c++14`（两处）。

### 8. `tinyobj::index_t` 缺少 `operator<`

- **根因**：`Triangles.cpp` 把 `operator<` 定义在 `namespace std` 内（旧 hack），新版 libstdc++ 不再匹配。
- **修复**：移到 `namespace tinyobj`（ADL 可找到）。
- 涉及文件：`neuronXcore/rtn/Triangles.cpp`

### 9. 运行时黑屏（GL blit 被剔除/照黑）

构建和渲染管线全部正常（OptiX raygen 输出非黑帧），但窗口显示全黑。逐层定位（fbPointer→GL 纹理→blit 全部 dump 对比）后确认：

- **根因**：`TubesViewer::draw()` 覆盖了 `OWLViewer::draw()`，其中 `glDisable(GL_LIGHTING)` 和 `glDisable(GL_DEPTH_TEST)` **都被注释掉了**（基类里有）。而虫体渲染 `SimulationWindow::Display()` 启用了光照和深度测试：
  1. **深度测试开启（主因）** → blit 的纹理 quad 在 z=0（深度 0.5），但窗口默认帧缓冲的深度缓冲从未清理 → quad 被陈旧深度值**剔除** → 全黑。
  2. 光照开启 → quad 无法线被照黑。
- **修复**：取消注释 `glDisable(GL_LIGHTING)` 和 `glDisable(GL_DEPTH_TEST)`（`neuronXcore/rtn/viewer.cpp`）。
- 验证：修复前 glReadPixels 100% 全黑；修复后 mean≈186、0% 黑，与渲染内容一致。

### 10. 混合显卡下 CUDA-GL 互操作失败

- **根因**：本机为 AMD 核显 + NVIDIA 独显（GL 默认建在 AMD 上，CUDA 在 NVIDIA 上，跨 GPU interop 失败）。另外在 Wayland(KDE) 会话下，GLFW 3.4 默认走 Wayland/EGL，`cudaGraphicsGLRegisterImage`（GLX 路径）同样失败。
- **修复（运行期，非代码）**：
  - `owlViewer/OWLViewer.cpp` 的 `initGLFW()` 增加 `glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11)`（强制 X11/GLX，绕开 Wayland/EGL）。
  - 运行时设置 `__NV_PRIME_RENDER_OFFLOAD=1` + `__GLX_VENDOR_LIBRARY_NAME=nvidia`（强制 GLX 走 NVIDIA 独显）。
  - 见 `build/run_demo.sh`（已封装）。

### 11. 缺失数据文件 / Python 侧运行准备

- C302 肌肉文件 `eworm.muscle-220428-152601.txt`：从 `Metaworm/interact/neural_model/wang_sim/data/` 拷贝到 `Metaworm/data/mengdi/` 与 `build/data/mengdi/`。
- KeyWorm 状态 JSON：从 `eworm/ghost_in_mesh_sim/data/state/` 拷贝到 `build/data/state/`。动作 JSON `worm_actions_300_220428-144704.json` 仓库本身缺失（非致命）。
- NEURON 机制库：`cd eworm/components/mechanism && nrnivmodl modfile`。
- Python 依赖装进 `worm/` 虚拟环境（numpy/scipy/matplotlib/tqdm/pandas/neuron/torch 等），numpy 2.x 需修 `np.float`→`float`（`data_factory.py`、`pre_interaction.py`）。

## 构建命令

```bash
cd build
cmake ../neuronXcore \
  -G"Unix Makefiles" \
  -DCUDA_TOOLKIT_ROOT_DIR="/usr/local/cuda" \
  -DOptiX_INCLUDE="/opt/optix-9.1/include/" \
  -DBoost_DIR="/usr/lib/cmake/Boost-1.91.0/BoostConfig.cmake" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
make -j$(nproc)
```

## 验证结果

- 所有目标构建成功：`llowl_static`、`imgui`、`fem`、`owl_static`、`owl_viewer`、`sim`、`interact`、`render`、`neuronXcore`。
- 产物：`build/neuronXcore`（3.3MB 可执行文件）。
- 运行 `./neuronXcore --help` 正常输出用法说明。

## 系统依赖备忘

- `eigen` 5.0.1-2（Arch）
- CUDA 12.6（`/usr/local/cuda`），nvcc 宿主编译器需 `g++-13`（`gcc13` 包）
- OptiX 9.1（`/opt/optix-9.1`）
- Boost 1.91（`/usr/lib/cmake/Boost-1.91.0/BoostConfig.cmake`）
