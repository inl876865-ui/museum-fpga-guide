# 博物馆多媒体智能导览讲解系统

队伍编号：**46565**。

## 工程入口

- 开发板：HX4S20C。
- FPGA：安路 EG4S20BG256。
- 开发环境：Tang Dynasty 6.2.1，构建号6.2.168116。
- 顶层模块：`top`。
- 工程文件：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`。
- 配套码流：`src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/best_result/HDMI1.4b_Transmitter_v1.0.bit`。

工程保留原有目录层级，RTL 逻辑、IP、引脚及时序约束未改变。请将完整 `46565` 目录解压到不含中文的路径，例如 `F:/FPGA/submit/46565`，再打开上述工程文件。详细编译步骤见 `doc/README.md`。

媒体素材处理工具位于 `doc/MediaTools/`，随包提供可执行程序、源码、构建脚本、语音识别运行库和第三方许可。为满足上传大小限制，未附带离线语音识别模型；图片转换、音频转换和已有文本转 CAP 可直接使用。音频自动识别字幕需按 `doc/MediaTools/README.md` 补充模型。
