using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace FpgaMedia {
    internal partial class MainForm {
        TextBox captionAudio, captionText, captionPcm, captionName, captionOutput, captionEngine, captionModel, captionLog;
        ComboBox captionEncoding, captionLanguage, captionFont, captionResultText, captionColor;
        Label captionFontPreview;
        RadioButton captionFromAudio, captionFromText;
        CheckBox captionSimplified;
        string lastCaptionOutput;
        internal Action<string> CaptionNotice = null;
        void BuildCaptionPage() {
            TabPage tab = new TabPage("字幕 → CAP") { BackColor = Color.White, Padding = new Padding(14), AutoScroll = true };
            tabs.TabPages.Add(tab);
            TableLayoutPanel grid = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 3, Padding = new Padding(4) };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 122));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 118));
            tab.Controls.Add(grid);
            Label intro = Label("03  生成字幕，或校对文字后重新转换", 12, true); grid.Controls.Add(intro, 0, 0); grid.SetColumnSpan(intro, 3);
            FlowLayoutPanel modes = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false };
            captionFromAudio = new RadioButton { Text = "音频 → 文本 + CAP", Checked = true, AutoSize = true, Margin = new Padding(0, 3, 30, 3) };
            captionFromText = new RadioButton { Text = "文本 → CAP", AutoSize = true, Margin = new Padding(0, 3, 0, 3) };
            modes.Controls.Add(captionFromAudio); modes.Controls.Add(captionFromText); grid.Controls.Add(modes, 0, 1); grid.SetColumnSpan(modes, 3);
            editors.Add(captionFromAudio); editors.Add(captionFromText);
            captionAudio = CaptionPath(grid, 2, "输入音频", "captionAudio", "音乐|*.mp3;*.wav;*.m4a;*.flac;*.pcm", false);
            captionAudio.Multiline = true; captionAudio.ScrollBars = ScrollBars.Vertical;
            captionAudio.WordWrap = false; captionAudio.AcceptsReturn = true; captionAudio.MinimumSize = new Size(0, 64);
            captionText = CaptionPath(grid, 3, "输入文本", "captionText", "字幕原稿|*.txt;*.srt", false);
            captionPcm = CaptionPath(grid, 4, "对应PCM", "captionPcm", "配音PCM|*.pcm", false);
            FlowLayoutPanel options = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false };
            captionName = new TextBox { Text = "01", Width = 72, Name = "captionName" };
            captionEncoding = new ComboBox { Width = 100, DropDownStyle = ComboBoxStyle.DropDownList };
            captionEncoding.Items.AddRange(new object[] { "UTF-8", "GBK", "UTF-16" }); captionEncoding.SelectedIndex = 0;
            captionLanguage = new ComboBox { Width = 90, DropDownStyle = ComboBoxStyle.DropDownList };
            captionLanguage.Items.AddRange(new object[] { "中文", "英文", "自动检测" }); captionLanguage.SelectedIndex = 0;
            captionSimplified = new CheckBox { Text = "简体输出", Checked = true, AutoSize = true };
            options.Controls.Add(Label("输出名 / 起始号", 9, false)); options.Controls.Add(captionName);
            options.Controls.Add(Label("文本编码", 9, false)); options.Controls.Add(captionEncoding);
            options.Controls.Add(captionLanguage); options.Controls.Add(captionSimplified);
            grid.Controls.Add(options, 0, 5); grid.SetColumnSpan(options, 3);
            editors.Add(captionName); editors.Add(captionEncoding); editors.Add(captionLanguage); editors.Add(captionSimplified);
            FlowLayoutPanel fontRow = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false };
            captionFont = new ComboBox { Name = "captionFont", Width = 220, DropDownStyle = ComboBoxStyle.DropDownList };
            using (System.Drawing.Text.InstalledFontCollection installed = new System.Drawing.Text.InstalledFontCollection()) {
                System.Collections.Generic.List<string> names = new System.Collections.Generic.List<string>();
                foreach (FontFamily family in installed.Families) if (family.IsStyleAvailable(FontStyle.Regular)) names.Add(family.Name);
                names.Sort(StringComparer.CurrentCulture); captionFont.Items.AddRange(names.ToArray());
            }
            using (Font defaultFont = new Font("SimHei", 16, FontStyle.Regular, GraphicsUnit.Pixel)) captionFont.SelectedItem = defaultFont.Name;
            if (captionFont.SelectedIndex < 0 && captionFont.Items.Count > 0) captionFont.SelectedIndex = 0;
            captionFontPreview = Label("四羊方尊 · 字幕预览", 10, false);
            captionFontPreview.BackColor = Color.FromArgb(24, 33, 43); captionFontPreview.Padding = new Padding(4);
            captionColor = new ComboBox { Name = "captionColor", Width = 160, DropDownStyle = ComboBoxStyle.DropDownList };
            captionColor.Items.AddRange(CaptionCompiler.ColorNames); captionColor.SelectedIndex = 0;
            captionColor.SelectedIndexChanged += delegate { UpdateCaptionFontPreview(); };
            captionFont.SelectedIndexChanged += delegate { UpdateCaptionFontPreview(); };
            fontRow.Controls.Add(Label("字幕字体", 9, false)); fontRow.Controls.Add(captionFont);
            fontRow.Controls.Add(Label("字幕颜色", 9, false)); fontRow.Controls.Add(captionColor); fontRow.Controls.Add(captionFontPreview);
            grid.Controls.Add(fontRow, 0, 6); grid.SetColumnSpan(fontRow, 3); editors.Add(captionFont); editors.Add(captionColor); UpdateCaptionFontPreview();
            captionOutput = CaptionPath(grid, 7, "输出位置", "captionOutput", null, true);
            captionOutput.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FPGA素材输出", "字幕");
            captionEngine = CaptionPath(grid, 8, "离线识别程序", "captionEngine", "whisper-cli|whisper-cli.exe", false);
            captionModel = CaptionPath(grid, 9, "识别模型", "captionModel", "Whisper模型|*.bin", false);
            captionEngine.Text = CaptionWorkflow.FindRecognizer(); captionModel.Text = CaptionWorkflow.DefaultModel;
            Label note = Label("输入音频可一次多选，或每行填写一个路径；批量按起始编号排队生成PCM、TXT、SRT和CAP，共用所选字体与颜色。\n原色生成兼容旧固件的CAP v1；其余7色生成CAP v2，需要板端支持CAP v2字幕配色。失败记录后继续，完成后可选择校对文件。\n16×16单行字幕，每份CAP最多64句、每句32字。文本模式须选择对应PCM，每次新建结果目录，原稿与旧结果保留。", 9, false);
            note.MaximumSize = new Size(880, 100); grid.Controls.Add(note, 0, 10); grid.SetColumnSpan(note, 3);
            FlowLayoutPanel actions = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false };
            Button edit = Button("打开生成的TXT校对", delegate { OpenCaptionText(); }, false);
            Button reuse = Button("用上次TXT重新转CAP", delegate { ReuseCaptionText(); }, false);
            captionResultText = new ComboBox { Name = "captionResultText", Width = 100, DropDownStyle = ComboBoxStyle.DropDownList };
            actions.Controls.Add(Label("校对文件", 9, false)); actions.Controls.Add(captionResultText); editors.Add(captionResultText);
            actions.Controls.Add(edit); actions.Controls.Add(reuse); editors.Add(edit); editors.Add(reuse);
            grid.Controls.Add(actions, 0, 11); grid.SetColumnSpan(actions, 3);
            captionLog = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
                Height = 82, BackColor = Color.FromArgb(247, 249, 250), Name = "captionLog", Text = "选择方式和输入文件后，点击底部“生成字幕文件”。音频识别在本机运行。" };
            grid.Controls.Add(captionLog, 0, 12); grid.SetColumnSpan(captionLog, 3);
            captionFromAudio.CheckedChanged += delegate { UpdateCaptionMode(); };
            captionFromText.CheckedChanged += delegate { UpdateCaptionMode(); };
            captionPcm.TextChanged += delegate { UpdateCounts(); };
            captionAudio.TextChanged += delegate { UpdateCounts(); };
            captionText.TextChanged += delegate {
                try {
                    string paired = Path.ChangeExtension(captionText.Text.Trim().Trim('"'), ".PCM");
                    if (File.Exists(paired)) captionPcm.Text = paired;
                } catch (ArgumentException) { }
                UpdateCounts();
            };
            UpdateCaptionMode();
        }
        void UpdateCaptionFontPreview() {
            if (captionFontPreview == null || captionFont.SelectedItem == null) return;
            Font previous = captionFontPreview.Font;
            captionFontPreview.Font = new Font((string)captionFont.SelectedItem, 16, FontStyle.Regular, GraphicsUnit.Pixel);
            int colorId = captionColor == null || captionColor.SelectedIndex < 0 ? 0 : captionColor.SelectedIndex;
            int rgb = CaptionCompiler.ColorValues[colorId];
            captionFontPreview.ForeColor = Color.FromArgb(255, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255);
            if (previous != null) previous.Dispose();
        }
        TextBox CaptionPath(TableLayoutPanel grid, int row, string title, string name, string filter, bool directory) {
            grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Label label = Label(title, 10, true); label.Margin = new Padding(0, 9, 0, 4); grid.Controls.Add(label, 0, row);
            TextBox field = new TextBox { Name = name, Dock = DockStyle.Fill, Margin = new Padding(0, 5, 8, 5) };
            Button browse = Button("浏览…", delegate {
                if (directory) {
                    using (FolderInputDialog dialog = new FolderInputDialog(field.Text)) if (dialog.ShowDialog(this) == DialogResult.OK) field.Text = dialog.SelectedPath;
                } else using (OpenFileDialog dialog = new OpenFileDialog { Filter = filter, CheckFileExists = true, Multiselect = name == "captionAudio" })
                    if (dialog.ShowDialog(this) == DialogResult.OK) {
                        if (name == "captionAudio") field.Lines = dialog.FileNames;
                        else field.Text = dialog.FileName;
                    }
            }, false);
            if (name == "captionAudio") browse.Text = "多选…";
            grid.Controls.Add(field, 1, row); grid.Controls.Add(browse, 2, row); editors.Add(field); editors.Add(browse);
            field.Leave += delegate { field.Text = field.Text.Trim().Trim('"'); };
            return field;
        }
        void UpdateCaptionMode() {
            if (captionAudio == null || captionPcm == null || captionFromAudio == null) return;
            bool audio = captionFromAudio.Checked;
            captionAudio.Enabled = audio && cancellation == null; captionName.Enabled = audio && cancellation == null;
            captionText.Enabled = !audio && cancellation == null; captionPcm.Enabled = !audio && cancellation == null;
            captionEncoding.Enabled = !audio && cancellation == null;
            captionEngine.Enabled = audio && cancellation == null; captionModel.Enabled = audio && cancellation == null;
            captionLanguage.Enabled = audio && cancellation == null; captionSimplified.Enabled = audio && cancellation == null;
            UpdateCounts();
        }
        bool CaptionReady() {
            return captionFromAudio != null && (captionFromAudio.Checked ? !string.IsNullOrWhiteSpace(captionAudio.Text) :
                !string.IsNullOrWhiteSpace(captionText.Text) && !string.IsNullOrWhiteSpace(captionPcm.Text));
        }
        string[] CaptionAudioInputs() {
            List<string> inputs = new List<string>(); HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string line in captionAudio.Lines) {
                string path = line.Trim().Trim('"');
                if (path.Length > 0 && seen.Add(path)) inputs.Add(path);
            }
            return inputs.ToArray();
        }
        void StartCaption() {
            if (cancellation != null) return;
            bool audio = captionFromAudio.Checked;
            string input = (audio ? captionAudio.Text : captionText.Text).Trim().Trim('"');
            string pcm = captionPcm.Text.Trim().Trim('"'), name = captionName.Text, output = captionOutput.Text;
            string engine = captionEngine.Text.Trim().Trim('"'), model = captionModel.Text.Trim().Trim('"');
            string encoding = (string)captionEncoding.SelectedItem, language = captionLanguage.SelectedIndex == 0 ? "zh" : captionLanguage.SelectedIndex == 1 ? "en" : "auto";
            bool simplify = captionSimplified.Checked; string fontName = (string)captionFont.SelectedItem;
            byte colorId = (byte)captionColor.SelectedIndex;
            string[] inputs = audio ? CaptionAudioInputs() : new string[] { input };
            bool batch = audio && inputs.Length > 1;
            if (inputs.Length == 0 || (!batch && !File.Exists(inputs[0]))) { MessageBox.Show(this, "找不到输入文件，请检查路径。", "字幕输入"); return; }
            if (batch) {
                try { CaptionWorkflow.BatchNames(name, inputs.Length); }
                catch (Exception ex) { MessageBox.Show(this, ex.Message, "批量编号"); return; }
            }
            if (audio && (!File.Exists(engine) || !File.Exists(model))) { MessageBox.Show(this, "离线识别组件缺失。请保留EXE旁的speech目录，或手动选择识别程序和模型。", "字幕识别"); return; }
            SaveConfiguration(true); cancellation = new CancellationTokenSource(); CancellationToken token = cancellation.Token;
            foreach (Control c in editors) c.Enabled = false;
            startButton.Enabled = false; cancelButton.Enabled = true; openButton.Enabled = false; progress.Value = 0; captionLog.Clear();
            Action<string> update = delegate(string message) { Ui(delegate { status.Text = message; captionLog.AppendText(message + Environment.NewLine); }); };
            Task.Factory.StartNew(delegate {
                string folder = null, failure = null; bool stopped = false; CaptionBatchResult result = null;
                try {
                    if (batch) {
                        result = CaptionWorkflow.AudioBatchToCap(inputs, name, output, engine, model, language, simplify, token, update,
                            delegate(int value) { Ui(delegate { progress.Value = value; }); }, fontName, colorId);
                        folder = result.Folder; stopped = result.Cancelled;
                    } else folder = audio ? CaptionWorkflow.AudioToCap(inputs[0], name, output, engine, model, language, simplify, token, update, fontName, colorId) :
                            CaptionWorkflow.TextToCap(input, pcm, output, encoding, token, update, fontName, colorId);
                } catch (Exception ex) { failure = ex.Message; stopped = ex is OperationCanceledException; folder = ex.Data["resultFolder"] as string; }
                Ui(delegate {
                    if (folder != null) { lastCaptionOutput = folder; RefreshCaptionResults(); }
                    foreach (Control c in editors) c.Enabled = true;
                    cancellation.Dispose(); cancellation = null; cancelButton.Enabled = false; UpdateCaptionMode(); UpdateResultButton();
                    status.Text = result != null ? (stopped ? "字幕批量转换已取消" : "字幕批量转换完成") + " · 成功 " + result.Successes + "，失败 " + result.Failures :
                        failure == null ? "字幕文件生成完成，请校对TXT后复制配套PCM/CAP。" : stopped ? "已取消；已生成内容保留。" : "字幕未完成：" + failure;
                    captionLog.AppendText(status.Text + Environment.NewLine + (folder ?? ""));
                    if (!stopped && failure == null) progress.Value = 100;
                    string summary = status.Text + (folder == null ? "" : "\n\n结果位置：\n" + folder);
                    if (CaptionNotice != null) CaptionNotice(summary);
                    else MessageBox.Show(this, summary, "字幕结果", MessageBoxButtons.OK,
                        failure == null && !stopped && (result == null || result.Failures == 0) ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
                });
            }, CancellationToken.None, TaskCreationOptions.None, TaskScheduler.Default);
        }
        void RefreshCaptionResults() {
            captionResultText.Items.Clear();
            if (lastCaptionOutput == null || !Directory.Exists(lastCaptionOutput)) return;
            string[] paths = Directory.GetFiles(lastCaptionOutput, "*.txt"); Array.Sort(paths, StringComparer.OrdinalIgnoreCase);
            foreach (string path in paths) {
                string stem = Path.GetFileNameWithoutExtension(path);
                if (System.Text.RegularExpressions.Regex.IsMatch(stem, @"\A[A-Z0-9_-]{1,8}\z")) captionResultText.Items.Add(Path.GetFileName(path));
            }
            if (captionResultText.Items.Count > 0) captionResultText.SelectedIndex = 0;
        }
        string LastTimedText() {
            if (lastCaptionOutput == null || !Directory.Exists(lastCaptionOutput)) return null;
            if (captionResultText.SelectedItem != null) {
                string selected = Path.Combine(lastCaptionOutput, (string)captionResultText.SelectedItem);
                if (File.Exists(selected)) return selected;
            }
            foreach (string path in Directory.GetFiles(lastCaptionOutput, "*.txt")) {
                string stem = Path.GetFileNameWithoutExtension(path);
                if (System.Text.RegularExpressions.Regex.IsMatch(stem, @"\A[A-Z0-9_-]{1,8}\z")) return path;
            }
            return null;
        }
        void OpenCaptionText() {
            string path = LastTimedText();
            if (path == null) { MessageBox.Show(this, "还没有生成可校对的TXT。", "字幕文本"); return; }
            try { Process.Start(new ProcessStartInfo("notepad.exe", CaptionWorkflow.Quote(path)) { UseShellExecute = false }); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "打开文本失败"); }
        }
        void ReuseCaptionText() {
            string text = LastTimedText();
            if (text == null) { MessageBox.Show(this, "请先生成音频字幕，或手动选择文本与对应PCM。", "重新生成"); return; }
            string pcm = Path.ChangeExtension(text, ".PCM"); captionText.Text = text;
            if (File.Exists(pcm)) captionPcm.Text = pcm;
            captionEncoding.SelectedIndex = 0; captionFromText.Checked = true;
        }
        internal void PrepareCaptionPreview() { PreparePreview(null); tabs.SelectedIndex = 2; LayoutTree(this); Application.DoEvents(); }
    }
}
