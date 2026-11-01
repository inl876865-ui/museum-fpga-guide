using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace FpgaMedia {
    internal partial class MainForm {
        static readonly string[] AudioExtensions = { ".mp3", ".wav", ".m4a", ".flac" };
        static readonly string[] ImageExtensions = { ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff" };
        void AddFiles(MediaPage page, bool folder) {
            if (folder) {
                using (FolderInputDialog dialog = new FolderInputDialog(string.IsNullOrWhiteSpace((page.Audio ? inputPath : imageInputPath).Text) ? lastFolder : (page.Audio ? inputPath : imageInputPath).Text)) {
                    if (dialog.ShowDialog(this) == DialogResult.OK) { lastFolder = dialog.SelectedPath; (page.Audio ? inputPath : imageInputPath).Text = dialog.SelectedPath; AddPaths(page, new string[] { dialog.SelectedPath }); }
                }
            } else {
                using (OpenFileDialog dialog = new OpenFileDialog { Multiselect = true,
                    Title = page.Audio ? "选择音乐文件" : "选择图片文件",
                    Filter = page.Audio ? "音乐文件|*.mp3;*.wav;*.m4a;*.flac" :
                        "图片文件|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff" }) {
                    if (dialog.ShowDialog(this) == DialogResult.OK) { (page.Audio ? inputPath : imageInputPath).Text = Path.GetDirectoryName(dialog.FileNames[0]); AddPaths(page, dialog.FileNames); }
                }
            }
        }
        void AddPaths(MediaPage page, string[] paths) {
            List<string> expanded = new List<string>();
            try {
                foreach (string p in paths) {
                    if (Directory.Exists(p)) {
                        (page.Audio ? inputPath : imageInputPath).Text = Path.GetFullPath(p);
                        string[] files = Directory.GetFiles(p); Array.Sort(files, StringComparer.OrdinalIgnoreCase);
                        expanded.AddRange(files);
                    } else expanded.Add(p);
                }
                int added = 0;
                HashSet<string> existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (ListViewItem item in page.List.Items) existing.Add((string)item.Tag);
                string[] extensions = page.Audio ? AudioExtensions : ImageExtensions;
                foreach (string p in expanded) {
                    string full = Path.GetFullPath(p);
                    if (!File.Exists(full) || Array.IndexOf(extensions, Path.GetExtension(full).ToLowerInvariant()) < 0) continue;
                    if (!existing.Add(full)) continue;
                    ListViewItem entry = new ListViewItem(new string[] { Path.GetFileName(full), "", "待转换" });
                    entry.Tag = full; entry.ToolTipText = full; page.List.Items.Add(entry); added++;
                }
                RefreshPage(page);
                if (page.List.Items.Count > 0 && page.List.SelectedItems.Count == 0) page.List.Items[0].Selected = true;
                if (added == 0) MessageBox.Show(this, "没有新增可转换文件。请检查文件格式，已添加的同一文件会自动跳过。",
                    "添加提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            } catch (Exception ex) { MessageBox.Show(this, "无法添加文件：\n" + ex.Message, "添加失败"); }
        }
        string OutputName(MediaPage page, int index) {
            return page.Audio ? (index + 1).ToString("D2") + ".PCM" : "PIC" + (index + 1) + "." + (string)page.ImageFormat.SelectedItem;
        }
        void RefreshPage(MediaPage page) {
            if (!page.Audio) UpdateImageSpec(page);
            for (int i = 0; i < page.List.Items.Count; i++) {
                page.List.Items[i].SubItems[1].Text = OutputName(page, i);
                page.List.Items[i].SubItems[2].Text = "待转换";
            }
            UpdateCounts(); UpdatePreview(page);
        }
        void RemoveSelected(MediaPage page) {
            if (page.List.SelectedItems.Count > 0) page.List.Items.Remove(page.List.SelectedItems[0]);
            RefreshPage(page);
        }
        void MoveSelected(MediaPage page, int direction) {
            if (page.List.SelectedItems.Count == 0) return;
            ListViewItem item = page.List.SelectedItems[0]; int index = item.Index + direction;
            if (index < 0 || index >= page.List.Items.Count) return;
            page.List.Items.Remove(item); page.List.Items.Insert(index, item);
            item.Selected = true; item.EnsureVisible(); RefreshPage(page);
        }
        void UpdateCounts() {
            if (counts == null || audioPage == null || imagePage == null) return;
            counts.Text = "音乐 " + audioPage.List.Items.Count + " 首     ·     图片 " + imagePage.List.Items.Count + " 张";
            startButton.Text = tabs.SelectedIndex == 2 ? "生成字幕文件" : "开始转换全部";
            if (cancellation == null) startButton.Enabled = tabs.SelectedIndex == 2 ? CaptionReady() : audioPage.List.Items.Count + imagePage.List.Items.Count > 0;
        }
        void UpdateImageSpec(MediaPage page) {
            if (page.ImageSpec == null) return;
            string format = (string)page.ImageFormat.SelectedItem;
            bool board = page.ImageWidth.Value == 640 && page.ImageHeight.Value == 480 && format == "BMP";
            page.ImageSpec.Text = page.ImageWidth.Value + " × " + page.ImageHeight.Value + " · " + format +
                (board ? " · 可用于当前开发板" : " · 自定义图片输出") + "\n开发板素材请使用640×480、24位BMP。";
        }
        void UpdatePreview(MediaPage page) {
            if (page.Info == null) return;
            if (page.Preview != null && page.Preview.Image != null) {
                Image previous = page.Preview.Image; page.Preview.Image = null; previous.Dispose();
            }
            if (page.List.SelectedItems.Count == 0) {
                page.Info.Text = page.Audio ? "选中一首音乐查看文件信息。" : "选中一张图片查看转换效果。"; return;
            }
            string path = (string)page.List.SelectedItems[0].Tag;
            try {
                long bytes = new FileInfo(path).Length;
                if (page.Audio) page.Info.Text = Path.GetFileName(path) + "\n" + (bytes / 1048576.0).ToString("0.00") + " MB";
                else {
                    using (Image original = Image.FromFile(path)) page.Info.Text = "原图 " + original.Width + " × " + original.Height +
                        "\nGIF / TIFF 使用首帧；透明区域使用所选底色。";
                    int width = (int)page.ImageWidth.Value, height = (int)page.ImageHeight.Value;
                    ImageConverter.ValidateSize(width, height);
                    double scale = Math.Min(240.0 / width, 180.0 / height);
                    page.Preview.Image = ImageConverter.Render(path, page.ImageMode.SelectedIndex, page.Background,
                        Math.Max(1, (int)Math.Round(width * scale)), Math.Max(1, (int)Math.Round(height * scale)));
                }
            } catch (Exception ex) { page.Info.Text = "无法预览：" + ex.Message; }
        }
        void ChooseColor(MediaPage page) {
            using (ColorDialog dialog = new ColorDialog { Color = page.Background, FullOpen = true }) {
                if (dialog.ShowDialog(this) == DialogResult.OK) { page.Background = dialog.Color; UpdatePreview(page); configurationDirty = true; SaveConfiguration(); }
            }
        }
        void ShowCurrentPaths() {
            bool music = tabs.SelectedIndex == 0;
            inputPath.Visible = music; imageInputPath.Visible = !music;
            outputPath.Visible = music; imageOutputPath.Visible = !music;
            (music ? inputPath : imageInputPath).BringToFront();
            (music ? outputPath : imageOutputPath).BringToFront();
        }
        void AddInputFolder() {
            MediaPage page = tabs.SelectedIndex == 0 ? audioPage : imagePage;
            TextBox box = page.Audio ? inputPath : imageInputPath;
            try { lastFolder = FolderInputDialog.ResolveFolder(box.Text); box.Text = lastFolder; AddPaths(page, new string[] { lastFolder }); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "输入位置不可用", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }
        void ChooseOutput() { ChooseOutput(tabs.SelectedIndex == 0 ? outputPath : imageOutputPath); }
        void ChooseOutput(TextBox target) {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog {
                Description = target == outputPath ? "选择音乐输出位置" : "选择图片输出位置",
                SelectedPath = target.Text }) {
                if (dialog.ShowDialog(this) == DialogResult.OK) target.Text = dialog.SelectedPath;
            }
        }
        void UpdateResultButton() {
            if (openButton == null) return;
            if (tabs.SelectedIndex == 2) {
                openButton.Text = "打开字幕结果"; openButton.Enabled = cancellation == null && lastCaptionOutput != null && Directory.Exists(lastCaptionOutput); return;
            }
            bool picture = (tabs.SelectedIndex == 1 && lastImageOutput != null) || lastOutput == null;
            string folder = picture ? lastImageOutput : lastOutput;
            openButton.Text = picture ? "打开图片结果" : "打开音乐结果";
            openButton.Enabled = cancellation == null && folder != null && Directory.Exists(folder);
        }
        void OpenResults() {
            if (tabs.SelectedIndex == 2) {
                if (lastCaptionOutput != null && Directory.Exists(lastCaptionOutput))
                    try { Process.Start(new ProcessStartInfo(lastCaptionOutput) { UseShellExecute = true }); }
                    catch (Exception ex) { MessageBox.Show(this, ex.Message, "打开结果失败"); }
                return;
            }
            bool picture = (tabs.SelectedIndex == 1 && lastImageOutput != null) || lastOutput == null;
            string folder = picture ? lastImageOutput : lastOutput;
            if (folder == null || !Directory.Exists(folder)) return;
            try { Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true }); }
            catch (Exception ex) { MessageBox.Show(this, "无法打开文件夹：\n" + ex.Message, "打开失败"); }
        }
        void ShowHelp() {
            MessageBox.Show(this,
                "字幕音频支持一次多选，或每行一个路径；多段按起始编号排队生成PCM、TXT、SRT和CAP，共用所选字体。\n" +
                "批量结果在同一个目录，文件对应表标明原音频；可选择校对文件，再用对应PCM重新生成CAP。\n" +
                "字幕支持原色、白、黄、青、绿、红、蓝、粉；原色兼容旧固件，其余颜色需要板端支持CAP v2字幕配色。\n" +
                "普通TXT每行一句为非定时字幕；需要同步配音请使用带时间轴TXT/SRT。16×16像素单行显示，每份CAP最多64句，每句32字；长句请在原稿分句。\n\n" +
                "1. 在音乐/图片标签页填写输入位置，点“添加到列表”或按回车；也可浏览选择、拖入素材。\n" +
                "2. 用上移、下移调整顺序；图片可自定宽高及BMP/PNG/JPG，选择留边、裁剪或拉伸。\n" +
                "3. 在音乐、图片标签页分别选择各自输出位置；每次只显示当前页的一栏。点击“开始转换全部”。\n" +
                "4. 转换后打开结果，将本次生成的 .PCM 和 .BMP 文件复制到 FAT32 TF 卡根目录。\n\n" +
                "工具转换数量不限；当前开发板仍识别最多8首歌曲、32张图片。复制时选择板端支持的文件。\n" +
                "已有卡若含其他同编号文件，请先核对；不要混合不同批次的同名结果。\n" +
                "路径、图片尺寸/格式/方式/底色及字幕字体自动保存；也可点击顶部“保存配置”。重新打开自动恢复。\n" +
                "结果文件夹含文件对照表，方便按原名称查找。工具不格式化卡，也不修改原素材。",
                "四步准备素材", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        void HandleClose(object sender, FormClosingEventArgs e) {
            SaveConfiguration(true);
            if (cancellation != null) {
                e.Cancel = true;
                if (MessageBox.Show(this, "正在转换。是否取消当前任务？取消后再关闭窗口。", "正在转换",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) cancellation.Cancel();
            } else if (imagePage.Preview.Image != null) imagePage.Preview.Image.Dispose();
        }
    }
}
