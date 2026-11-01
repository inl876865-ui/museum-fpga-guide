# 工程说明

## 原始目录

```text
46565/
├─ README.md
├─ doc/
│  ├─ README.md
│  ├─ MediaTools/                  媒体素材处理工具
│  └─ APUG092_HDMI1.4b_Transmitter_V1.0.docx
└─ src/
   ├─ td_project/
   │  ├─ HDMI1.4b_Transmitter_v1.0.al
   │  ├─ al_ip/
   │  ├─ flow/
   │  └─ HDMI1.4b_Transmitter_v1.0_Runs/
   │     ├─ syn_1/
   │     ├─ phy_1/
   │     └─ best_result/
   └─ user_source/
      ├─ constraints_source/
      ├─ hdl_source/
      └─ ip_source/
```

`src`沿用原工程的目录层级与命名，包含原有RTL、IP、头文件、存储初始化数据、工具脚本及构建输出。
工程文件的源文件清单和编译参数保持原样，直接引用的文件均随工程保留。

## 打开与编译

请将完整 `46565` 目录解压到不含中文的路径，例如 `F:/FPGA/submit/46565`。工程文件及其各级父目录均应使用英文、数字等 ASCII 字符；不要直接在压缩包内打开工程。

使用 Tang Dynasty 打开 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`，确认器件为 EG4S20BG256、顶层为 top。保留随工程提供的自定义布局布线脚本，依次执行综合、布局布线和码流生成。使用已有 IP 封装文件，无需重新生成 IP。

保持 `src/td_project`、`src/user_source` 及其子目录的相对位置。布局脚本通过运行目录的相对路径读取 `flow/preflight_cluster_soft.tcl`，该辅助脚本已随包提供。移动工程时应整体移动 `46565`，避免只复制 `.al` 文件或遗漏初始化数据。SDRAM 模块通过相对路径读取随包的 `include/global_def.v`，无需依赖原工程所在磁盘目录。

完整构建入口为 `src/td_project/flow/build_verified_full.tcl`。在TD Tcl控制台按实际路径执行，例如：

```tcl
source {F:/FPGA/submit/46565/src/td_project/flow/build_verified_full.tcl}
```

原有综合、布局布线、物理约束、时序检查和码流生成配置均随工程保留。
`HDMI1.4b_Transmitter_v1.0_Runs`保留原有综合及物理实现结果，配套码流仍位于 `best_result`。

## 运行条件

通过HDMI B连接支持HDMI音视频的显示设备，为HX4S20C开发板提供5 V供电，并插入包含BMP图片、PCM讲解音频和CAP字幕的FAT32 TF卡。
音频格式为48 kHz、16位有符号小端单声道PCM。配置码流通过开发板USB-JTAG接口与配套下载工具加载，Flash固化按开发板提供的操作流程完成。

图片、音频、字幕、菜单与时钟等功能由同一工程实现；具体硬件连接和操作方式参照作品技术文档。

## 媒体素材处理工具

队伍编号：46565。工具位于 `MediaTools/`；运行入口为 `MediaTools/bin/FPGA_Media_Converter.exe`，操作与构建说明见 `MediaTools/README.md`。
