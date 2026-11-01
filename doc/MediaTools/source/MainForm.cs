using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace FpgaMedia {
    internal sealed class MediaPage {
        public bool Audio;
        public ListView List;
        public PictureBox Preview;
        public ComboBox ImageMode, ImageFormat;
        public NumericUpDown ImageWidth, ImageHeight;
        public Label ImageSpec;
        public Label Info;
        public Color Background = Color.Black;
    }
    internal partial class MainForm : Form {
        readonly Color Ink = Color.FromArgb(25, 45, 61), Accent = Color.FromArgb(0, 128, 117);
        readonly List<Control> editors = new List<Control>();
        MediaPage audioPage, imagePage;
        TabControl tabs;
        TextBox outputPath;
        TextBox imageOutputPath;
        TextBox inputPath, imageInputPath;
        Button startButton, cancelButton, openButton;
        ProgressBar progress;
        Label status, counts;
        string lastOutput;
        string lastImageOutput;
        string lastFolder;
        System.Threading.CancellationTokenSource cancellation;
        internal Action<string> ResultNotice = null;
        public MainForm() {
            Rectangle area = Screen.PrimaryScreen.WorkingArea;
            Text = "FPGA 素材转换工具";
            Size = new Size(Math.Min(1060, area.Width - 32), Math.Min(880, area.Height - 32));
            MinimumSize = new Size(Math.Min(980, area.Width - 32), Math.Min(700, area.Height - 32));
            StartPosition = FormStartPosition.CenterScreen; AutoScaleMode = AutoScaleMode.Dpi;
            Font = new Font("Microsoft YaHei UI", 10); BackColor = Color.FromArgb(242, 245, 247);
            BuildLayout(); FormClosing += HandleClose; UpdateCounts(); InitializeConfiguration();
        }
        Button Button(string text, EventHandler click, bool primary) {
            Button b = new Button { Text = text, AutoSize = true, Height = 34,
                FlatStyle = FlatStyle.Flat, BackColor = primary ? Accent : Color.White,
                ForeColor = primary ? Color.White : Ink, Padding = new Padding(9, 2, 9, 2),
                Cursor = Cursors.Hand, Margin = new Padding(0, 0, 7, 0) };
            b.FlatAppearance.BorderColor = primary ? Accent : Color.FromArgb(215, 222, 226);
            b.Click += click; return b;
        }
        Label Label(string text, int size, bool bold) {
            return new Label { Text = text, AutoSize = true, ForeColor = Ink,
                Font = new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular),
                Margin = new Padding(0, 0, 0, 9) };
        }
        void BuildLayout() {
            TableLayoutPanel shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3 };
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 102));
            shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 110)); Controls.Add(shell);
            Panel header = new Panel { Dock = DockStyle.Fill, BackColor = Ink, Padding = new Padding(24) };
            Label title = Label("FPGA 素材转换", 22, true); title.ForeColor = Color.White;
            title.Location = new Point(24, 16); header.Controls.Add(title);
            Label subtitle = Label("准备音乐、图片和字幕，再复制到 TF 卡", 10, false);
            subtitle.ForeColor = Color.FromArgb(195, 213, 224); subtitle.Location = new Point(27, 62); header.Controls.Add(subtitle);
            Button help = Button("使用说明", delegate { ShowHelp(); }, false);
            Button saveConfig = Button("保存配置", delegate {
                if (SaveConfiguration(true)) status.Text = "配置已保存，下次打开自动恢复。";
            }, false);
            saveConfig.Name = "saveConfigButton";
            header.Resize += delegate {
                help.Location = new Point(header.ClientSize.Width - help.Width - 24, 34);
                saveConfig.Location = new Point(help.Left - saveConfig.Width - 10, 34);
            };
            help.Location = new Point(904, 34); saveConfig.Location = new Point(786, 34);
            header.Controls.Add(help); header.Controls.Add(saveConfig);
            shell.Controls.Add(header, 0, 0);
            tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(24, 10), Margin = new Padding(20, 16, 20, 8) };
            audioPage = BuildPage(true); imagePage = BuildPage(false); BuildCaptionPage(); shell.Controls.Add(tabs, 0, 1);
            TableLayoutPanel bottom = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3,
                BackColor = Color.White, Padding = new Padding(24, 12, 24, 12) };
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 374));
            counts = Label("", 10, true); bottom.Controls.Add(counts, 0, 0);
            FlowLayoutPanel actions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
            openButton = Button("打开结果", delegate { OpenResults(); }, false); openButton.Enabled = false;
            cancelButton = Button("取消", delegate { if (cancellation != null) cancellation.Cancel(); }, false);
            cancelButton.Enabled = false;
            startButton = Button("开始转换全部", delegate { StartBatch(); }, true);
            actions.Controls.Add(openButton); actions.Controls.Add(cancelButton); actions.Controls.Add(startButton);
            bottom.Controls.Add(actions, 1, 0); bottom.SetRowSpan(actions, 3);
            progress = new ProgressBar { Dock = DockStyle.Fill, Height = 12, Margin = new Padding(0, 5, 16, 5) };
            bottom.Controls.Add(progress, 0, 1);
            status = Label("先添加文件，再选择图片设置或字幕字体。", 9, false);
            status.AutoSize = false; status.Dock = DockStyle.Fill; bottom.Controls.Add(status, 0, 2);
            shell.Controls.Add(bottom, 0, 2);
            tabs.SelectedIndexChanged += delegate { ShowCurrentPaths(); UpdateResultButton(); UpdateCounts(); };
            tabs.SelectedIndex = 0;
            ShowCurrentPaths(); UpdateResultButton();
        }
        MediaPage BuildPage(bool audio) {
            MediaPage page = new MediaPage { Audio = audio };
            TabPage tab = new TabPage(audio ? "音乐 → PCM" : "图片 → 缩放 / 格式") { BackColor = Color.White, Padding = new Padding(14) };
            tabs.TabPages.Add(tab);
            TableLayoutPanel content = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4 };
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 43));
            content.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            content.RowStyles.Add(new RowStyle(SizeType.Absolute, 126)); tab.Controls.Add(content);
            content.Controls.Add(Label(audio ? "01  添加音乐，按播放顺序排列（转换数量不限）" :
                "02  添加图片，按展示顺序排列（转换数量不限）", 12, true), 0, 0);
            FlowLayoutPanel toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
            Button[] tools = {
                Button("添加文件", delegate { AddFiles(page, false); }, true),
                Button("添加文件夹", delegate { AddFiles(page, true); }, false),
                Button("移除选中", delegate { RemoveSelected(page); }, false),
                Button("清空", delegate { page.List.Items.Clear(); RefreshPage(page); }, false),
                Button("上移 ↑", delegate { MoveSelected(page, -1); }, false),
                Button("下移 ↓", delegate { MoveSelected(page, 1); }, false)
            };
            foreach (Button b in tools) { editors.Add(b); toolbar.Controls.Add(b); } content.Controls.Add(toolbar, 0, 1);
            TableLayoutPanel columns = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
            columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            columns.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290)); content.Controls.Add(columns, 0, 2);
            page.List = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true,
                HideSelection = false, MultiSelect = false, AllowDrop = true, ShowItemToolTips = true,
                BorderStyle = BorderStyle.FixedSingle, Margin = new Padding(0, 0, 14, 0) };
            page.List.Columns.Add("原文件", 258); page.List.Columns.Add("输出名称", 105); page.List.Columns.Add("状态", 127);
            page.List.SelectedIndexChanged += delegate { UpdatePreview(page); };
            page.List.DragEnter += delegate(object sender, DragEventArgs e) {
                if (cancellation == null && e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy;
            };
            page.List.DragDrop += delegate(object sender, DragEventArgs e) {
                if (cancellation == null) AddPaths(page, (string[])e.Data.GetData(DataFormats.FileDrop));
            };
            columns.Controls.Add(page.List, 0, 0);
            FlowLayoutPanel detail = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
                WrapContents = false, AutoScroll = true, BackColor = Color.FromArgb(247, 249, 250), Padding = new Padding(10) };
            columns.Controls.Add(detail, 1, 0);
            if (audio) {
                detail.Controls.Add(Label("为开发板准备好音乐", 12, true));
                detail.Controls.Add(Label("输出 48 kHz · 16 位 · 单声道\n裸 PCM，小端序，无文件头", 10, false));
                detail.Controls.Add(Label("名称依次生成 01.PCM、02.PCM…\n工具不限制转换数量。", 10, false));
                detail.Controls.Add(Label("支持 MP3 / WAV / M4A / FLAC\n无需选择采样率，也无需手填地址。", 9, false));
                detail.Controls.Add(Label("将文件拖入左侧也可以添加。", 9, false));
            } else {
                detail.Controls.Add(Label("图片尺寸与格式", 11, true));
                FlowLayoutPanel sizeRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Width = 250 };
                page.ImageWidth = new NumericUpDown { Name = "imageWidth", Minimum = 1, Maximum = 32767, Value = 640, Width = 96 };
                page.ImageHeight = new NumericUpDown { Name = "imageHeight", Minimum = 1, Maximum = 32767, Value = 480, Width = 96 };
                sizeRow.Controls.Add(page.ImageWidth); sizeRow.Controls.Add(Label("×", 10, false)); sizeRow.Controls.Add(page.ImageHeight);
                detail.Controls.Add(sizeRow); editors.Add(page.ImageWidth); editors.Add(page.ImageHeight);
                page.ImageFormat = new ComboBox { Name = "imageFormat", Width = 240, DropDownStyle = ComboBoxStyle.DropDownList };
                page.ImageFormat.Items.AddRange(new object[] { "BMP", "PNG", "JPG" }); page.ImageFormat.SelectedIndex = 0;
                detail.Controls.Add(page.ImageFormat); editors.Add(page.ImageFormat);
                Button board = Button("开发板：640×480 BMP", delegate { page.ImageWidth.Value = 640; page.ImageHeight.Value = 480; page.ImageFormat.SelectedIndex = 0; }, false);
                editors.Add(board); detail.Controls.Add(board);
                page.ImageSpec = Label("", 9, false); page.ImageSpec.MaximumSize = new Size(240, 80);
                detail.Controls.Add(page.ImageSpec);
                page.Preview = new PictureBox { Size = new Size(240, 180), BackColor = Color.Black, SizeMode = PictureBoxSizeMode.Zoom };
                page.ImageMode = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240,
                    DrawMode = DrawMode.OwnerDrawFixed, ItemHeight = 24 };
                page.ImageMode.Items.AddRange(new object[] { "完整显示 · 等比留边", "填满画面 · 居中裁剪", "拉伸全屏 · 可能变形" });
                page.ImageMode.DrawItem += delegate(object sender, DrawItemEventArgs e) {
                    int index = e.Index >= 0 ? e.Index : page.ImageMode.SelectedIndex;
                    e.DrawBackground();
                    if (index >= 0) TextRenderer.DrawText(e.Graphics, page.ImageMode.Items[index].ToString(),
                        page.ImageMode.Font, e.Bounds, Ink, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
                    e.DrawFocusRectangle();
                };
                page.ImageMode.SelectedIndex = 0; page.ImageMode.SelectedIndexChanged += delegate { UpdatePreview(page); };
                editors.Add(page.ImageMode); detail.Controls.Add(page.ImageMode);
                Button color = Button("选择留边 / 透明底色", delegate { ChooseColor(page); }, false);
                editors.Add(color); detail.Controls.Add(color);
                detail.Controls.Add(page.Preview);
                page.ImageWidth.ValueChanged += delegate { RefreshPage(page); };
                page.ImageHeight.ValueChanged += delegate { RefreshPage(page); };
                page.ImageFormat.SelectedIndexChanged += delegate { RefreshPage(page); };
                UpdateImageSpec(page);
            }
            page.Info = Label(audio ? "选中一首音乐查看文件信息。" : "选中一张图片查看转换效果。", 9, false);
            page.Info.MaximumSize = new Size(240, 70); detail.Controls.Add(page.Info);
            BuildPositions(page, content); return page;
        }
        void BuildPositions(MediaPage page, TableLayoutPanel content) {
            TableLayoutPanel output = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 3,
                Padding = new Padding(0, 10, 0, 0) };
            output.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
            output.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
            output.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            output.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            output.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            output.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            output.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 126));
            output.Controls.Add(Label("输入位置", 11, true), 0, 0);
            TextBox input = new TextBox { Dock = DockStyle.Fill };
            if (page.Audio) inputPath = input; else imageInputPath = input;
            output.Controls.Add(input, 1, 0); editors.Add(input);
            input.KeyDown += delegate(object sender, KeyEventArgs e) {
                if (e.KeyCode == Keys.Enter && cancellation == null) { e.SuppressKeyPress = true; AddInputFolder(); }
            };
            Button inputBrowse = Button("浏览…", delegate { AddFiles(page, true); }, false);
            inputBrowse.AutoSize = false; inputBrowse.Width = 84; inputBrowse.Padding = new Padding(0);
            Button inputAdd = Button("添加到列表", delegate { AddInputFolder(); }, true);
            editors.Add(inputBrowse); editors.Add(inputAdd);
            output.Controls.Add(inputBrowse, 2, 0); output.Controls.Add(inputAdd, 3, 0);
            output.Controls.Add(Label("输出位置", 11, true), 0, 1);
            TextBox destination = new TextBox { Dock = DockStyle.Fill,
                Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FPGA素材输出", page.Audio ? "音乐" : "图片") };
            if (page.Audio) outputPath = destination; else imageOutputPath = destination;
            output.Controls.Add(destination, 1, 1); output.SetColumnSpan(destination, 2); editors.Add(destination);
            Button browse = Button("更改位置", delegate { ChooseOutput(destination); }, false);
            editors.Add(browse); output.Controls.Add(browse, 3, 1);
            Label note = Label("粘贴输入路径后点“添加到列表”；本页单独保存输入、输出位置，每次结果单独保存。", 9, false);
            output.Controls.Add(note, 1, 2); output.SetColumnSpan(note, 3); content.Controls.Add(output, 0, 3);
        }
        internal void PreparePreview(string image) {
            tabs.SelectedIndex = 1;
            if (!string.IsNullOrEmpty(image)) AddPaths(imagePage, new string[] { image });
            Queue<Control> controls = new Queue<Control>(); controls.Enqueue(this);
            while (controls.Count > 0) {
                Control c = controls.Dequeue(); IntPtr handle = c.Handle;
                foreach (Control child in c.Controls) controls.Enqueue(child);
            }
            LayoutTree(this); UpdatePreview(imagePage);
            // Initialize native combo/list painting for an off-screen QA render.
            ShowInTaskbar = false; Opacity = 0; StartPosition = FormStartPosition.Manual;
            Location = new Point(-20000, -20000); Show(); Application.DoEvents();
        }
        static void LayoutTree(Control control) {
            control.PerformLayout();
            foreach (Control child in control.Controls) LayoutTree(child);
        }
    }
}
