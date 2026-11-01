# FPGA媒体素材处理工具

## 用途

为博物馆多媒体智能导览讲解系统制作BMP图片、PCM讲解音频和CAP字幕。
本目录包含媒体转换程序、C#源码、构建脚本及语音识别运行库。提交包不附带大体积语音识别模型；仅“音频→文本+CAP”的自动识别步骤需要另行补充模型。

```text
MediaTools/
├─ README.md
├─ build.ps1
├─ source/                         C#源码
└─ bin/
   ├─ FPGA_Media_Converter.exe
   └─ speech/
      ├─ ggml-small.bin            可选：按下文补充的离线多语言模型
      ├─ Release/                  whisper-cli与CPU运行库
      ├─ licenses/                 第三方许可
      └─ THIRD_PARTY_NOTICES.txt
```

## 运行环境

Windows 10/11 x64，使用.NET Framework及Windows媒体组件。双击 `bin/FPGA_Media_Converter.exe` 启动。
`speech`必须与可执行程序保持相邻；模型、运行库及CPU后端文件共同构成离线音频识别依赖。
图片转换、音频转换和已有文本转CAP无需语音识别模型，可直接运行。

## 补充语音识别模型

如需将讲解音频自动识别为文字和字幕，先补充 `ggml-small.bin`：

1. 可从配套完整离线运行包复制该文件，也可根据 [whisper.cpp 模型说明](https://github.com/ggml-org/whisper.cpp/tree/master/models) 获取预转换的 `small` 多语言模型。
2. 将文件放在 `bin/speech/ggml-small.bin`，保持与随附识别程序及运行库的目录关系。中文讲解应使用多语言模型，不使用仅英文的 `.en` 模型。
3. 启动工具，确认模型路径指向该文件，再执行“音频→文本+CAP”。识别结果仍需人工校对。

未补充模型时，请使用图片转换、音频转换或“文本→CAP”；FPGA 板端播放不需要该模型。
随附运行库和第三方许可应继续保留。无需为图片、音频及已有字幕转换安装新的语音识别组件。

## 基本操作

1. 图片素材：进入“图片→缩放/格式”，选择图片。开发板推荐输出640×480、24位无压缩BMP；保留等比留边、居中裁剪和拉伸选项。
2. 讲解音频：进入音频页，选择原始音频并转换为无文件头的48 kHz、16位有符号小端、单声道PCM。
3. 自动字幕：补充上述模型后，进入“字幕→CAP”，选择“音频→文本+CAP”，选择一个或多个讲解音频，设置输出名或起始号、字体、颜色和输出目录，再生成文件。
4. 字幕校对：打开生成的TXT/SRT，结合实际音频检查文字、分句和时间；修改后使用“用上次TXT重新转CAP”，与对应PCM配套输出。
5. 已有文本：选择“文本→CAP”，提供定时TXT或SRT及对应PCM，生成板端可读取的CAP。

图片按PIC1.BMP、PIC2.BMP等编号组织；讲解音频与字幕使用对应短文件名，例如01.PCM与01.CAP。
同编号PCM与CAP配套复制到FAT32卡根目录，TXT/SRT用于校对，不作为板端读取文件。
字幕每句最多32字、每文件最多64句；显示字格为16×16像素。原色输出CAP v1，其他七种颜色输出CAP v2，本工程支持这两种格式。
自动识别结果应人工校对；每次转换在用户选择的输出目录中生成新的结果目录。

## 从源码构建

在本目录使用PowerShell执行：

```powershell
.\build.ps1
```

脚本使用系统已有的.NET Framework C#编译器，默认生成 `bin/FPGA_Media_Converter_Rebuilt.exe`，不覆盖随附程序。
需要自定义输出时使用 `-Output` 指定新的文件路径。重新构建的程序运行音频识别时，同样需要相邻的 `speech` 目录。
