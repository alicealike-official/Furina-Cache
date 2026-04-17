```
my_verif_env/                # 验证环境根目录
|-- docs/                    # 文档目录
|   |-- cpu/                 # CPU 相关文档
|   |-- cache/               # Cache 相关文档
|   |-- ahb3/                # AHB3 相关文档
|   `-- top/                 # 顶层环境文档
|-- src/                     # 源代码目录
|   |-- common/              # 公共组件(跨子系统共享)
|   |   |-- component        # 公共组件(如时钟模块的driver和agent)
|   |   |-- interface/       # 公共接口(如时钟/复位)
|   |   |-- config/          # 公共配置类
|   |   |-- define/          # common definition
|   |   |-- pkg/             # 公共包(如类型定义、宏)
|   |   |-- model/           # 公共参考模型(目前只包含mem)
|   |   `-- utils/           # 公共工具类
|   |-- cpu/                 # CPU 子系统
|   |   |-- component/       # CPU 验证组件
|   |   |-- sequence/        # CPU 测试序列(包含tr)
|   |   |-- model/           # CPU 行为模型(可选)
|   |   |-- coverage/        # CPU 覆盖率模型
|   |   |-- interface/       # CPU 接口
|   |   `-- pkg/             # CPU 专用包
|   |-- cache/               # Cache 子系统
|   |   |-- component/       # Cache 验证组件
|   |   |-- sequence/        # Cache 测试序列(包含tr)
|   |   |-- model/           # Cache 行为模型(可选)
|   |   |-- coverage/        # Cache 覆盖率模型
|   |   |-- interface/       # Cache 接口
|   |   `-- pkg/             # Cache 专用包
|   |-- ahb3/                # AHB3 子系统
|   |   |-- component/       # AHB3 组件
|   |   |-- sequence/        # AHB3 测试序列(包含tr)
|   |   |-- monitor/         # AHB3 监视器
|   |   |-- coverage/        # AHB3 覆盖率模型
|   |   |-- interface/       # AHB3 接口
|   |   `-- pkg/             # AHB3 专用包
|   `-- top/                 # 顶层环境
|       |-- env/             # 顶层环境类(整合 CPU、Cache、AHB3)
|       |-- sequence/        # 顶层虚拟序列
|       `-- config/          # 顶层环境配置
|-- test/                    # 测试用例目录
|   |-- cpu/                 # CPU 单独测试
|   |-- cache/               # Cache 单独测试
|   |-- ahb3/                # AHB3 单独测试
|   `-- integration/         # 集成测试(CPU + Cache + AHB3)
|-- sim/                     # 仿真脚本目录
|   |-- Makefile             # 顶层构建脚本
|   |-- cpu.mk               # CPU 测试构建脚本
|   |-- cache.mk             # Cache 测试构建脚本
|   |-- ahb3.mk              # AHB3 测试构建脚本
|   `-- integration.mk       # 集成测试构建脚本
|-- tb/                      # 测试平台目录
|   |-- top.sv               # 顶层测试平台(例化 DUT、接口、验证环境)
`-- README.md                # 项目说明
```