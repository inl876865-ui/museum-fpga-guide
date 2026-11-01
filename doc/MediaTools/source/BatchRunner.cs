using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace FpgaMedia {
    internal sealed class ConversionJob {
        public string Source, Name;
        public bool Audio;
        public ListViewItem Row;
    }
    internal partial class MainForm {
        void StartBatch() {
            if (cancellation != null) return;
            if (tabs.SelectedIndex == 2) { StartCaption(); return; }
            SaveConfiguration(true);
            List<ConversionJob> jobs = new List<ConversionJob>();
            foreach (MediaPage page in new MediaPage[] { audioPage, imagePage }) {
                for (int i = 0; i < page.List.Items.Count; i++) {
                    ListViewItem item = page.List.Items[i];
                    jobs.Add(new ConversionJob { Source = (string)item.Tag, Name = OutputName(page, i), Audio = page.Audio, Row = item });
                }
            }
            if (jobs.Count == 0) return;

            int imageWidth = (int)imagePage.ImageWidth.Value, imageHeight = (int)imagePage.ImageHeight.Value;
            string imageFormat = (string)imagePage.ImageFormat.SelectedItem;
            if (imagePage.List.Items.Count > 0) {
                try { ImageConverter.ValidateSize(imageWidth, imageHeight); }
                catch (Exception ex) { MessageBox.Show(this, ex.Message, "图片尺寸"); return; }
            }
            string folder = null, imageFolder = null;
            string stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss") + "_" + Guid.NewGuid().ToString("N").Substring(0, 4);
            try {
                if (audioPage.List.Items.Count > 0) folder = PrepareOutput(outputPath.Text, "音乐", stamp);
                if (imagePage.List.Items.Count > 0) imageFolder = PrepareOutput(imageOutputPath.Text, "图片", stamp);
            } catch (Exception ex) { MessageBox.Show(this, "无法保存到该位置：\n" + ex.Message, "输出位置不可用"); return; }
            if (folder != null) lastOutput = folder;
            if (imageFolder != null) lastImageOutput = imageFolder;
            cancellation = new CancellationTokenSource();
            CancellationToken token = cancellation.Token; int imageMode = imagePage.ImageMode.SelectedIndex;
            Color background = imagePage.Background;
            foreach (Control c in editors) c.Enabled = false;
            startButton.Enabled = false; cancelButton.Enabled = true; openButton.Enabled = false;
            progress.Value = 0; status.Text = "正在准备转换……";
            foreach (ConversionJob job in jobs) job.Row.SubItems[2].Text = "等待中";
            Task.Factory.StartNew(delegate { RunJobs(jobs, folder, imageFolder, imageMode, background, token, imageWidth, imageHeight, imageFormat); },
                CancellationToken.None, TaskCreationOptions.None, TaskScheduler.Default);
        }
        static string PrepareOutput(string value, string kind, string stamp) {
            if (string.IsNullOrWhiteSpace(value)) throw new IOException("请选择" + kind + "输出位置。");
            string folder = Path.Combine(FolderInputDialog.NormalizePath(value), "已转换_" + kind + "_" + stamp);
            Directory.CreateDirectory(folder);
            using (FileStream probe = new FileStream(Path.Combine(folder, ".write-check"), FileMode.CreateNew,
                FileAccess.Write, FileShare.None, 1, FileOptions.DeleteOnClose)) { }
            return folder;
        }
        static void WriteReports(string folder, StringBuilder manifest, StringBuilder log, int successes,
            int failures, bool stopped, string kind, int width = 640, int height = 480, string format = "BMP") {
            if (folder == null) return;
            File.WriteAllText(Path.Combine(folder, "文件对照表.csv"), manifest.ToString(), new UTF8Encoding(true));
            File.WriteAllText(Path.Combine(folder, "使用方法.txt"),
                "本文件夹为" + kind + "结果，另一类素材保存在各自选择的输出位置。\r\n" +
                "将需要的 .PCM 和 .BMP 文件分别复制到 FAT32 TF 卡根目录。\r\n" +
                (kind == "图片" ? "本批图片设置：" + width + "×" + height + " " + format + "；开发板图片需640×480、24位无压缩正高度BMP。\r\n" :
                    "音乐：48kHz、16位单声道有符号小端裸PCM。\r\n") +
                "工具转换数量不限；当前开发板仍最多识别8首歌曲和32张图片。\r\n" +
                "本类结果：成功" + successes + "，失败" + failures + (stopped ? "，已取消剩余任务。" : "。") + "\r\n" +
                "对照表保留原文件名称。已有TF卡需核对同名旧素材；不同批次输出不要直接混用。\r\n", Encoding.UTF8);
            if (log.Length > 0) File.WriteAllText(Path.Combine(folder, "转换失败日志.txt"), log.ToString(), Encoding.UTF8);
        }
        void Ui(Action action) {
            if (!IsDisposed && IsHandleCreated) BeginInvoke(action);
        }
        static string Csv(string value) { return "\"" + value.Replace("\"", "\"\"") + "\""; }
        static string Hash(string path) {
            using (SHA256 sha = SHA256.Create()) using (FileStream file = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "");
        }
        void RunJobs(List<ConversionJob> jobs, string folder, string imageFolder, int imageMode, Color background, CancellationToken token, int imageWidth = 640, int imageHeight = 480, string imageFormat = "BMP") {
            int successes = 0, failures = 0, completed = 0, musicOk = 0, musicBad = 0, imageOk = 0, imageBad = 0;
            bool stopped = false;
            StringBuilder manifest = new StringBuilder("输出名称,原文件,结果,文件字节数,音频秒数,SHA256,说明\r\n");
            StringBuilder imageManifest = new StringBuilder(manifest.ToString());
            StringBuilder log = new StringBuilder(), imageLog = new StringBuilder(); string fatal = null;
            try {
                foreach (ConversionJob job in jobs) {
                    if (token.IsCancellationRequested) { stopped = true; break; }
                    int position = completed;
                    Ui(delegate { job.Row.SubItems[2].Text = "转换中"; status.Text = "正在转换 " + job.Name + "  ·  " + Path.GetFileName(job.Source); });
                    StringBuilder records = job.Audio ? manifest : imageManifest;
                    StringBuilder errors = job.Audio ? log : imageLog;
                    string target = Path.Combine(job.Audio ? folder : imageFolder, job.Name), temporary = target + ".partial";
                    try {
                        Action<int> update = delegate(int p) {
                            int overall = (position * 100 + p) / jobs.Count;
                            Ui(delegate { progress.Value = Math.Min(100, overall); job.Row.SubItems[2].Text = p + "%"; });
                        };
                        if (job.Audio) NativeAudio.Convert(job.Source, temporary, token, update);
                        else { token.ThrowIfCancellationRequested(); ImageConverter.Convert(job.Source, temporary, imageMode, background, imageWidth, imageHeight, imageFormat); update(100); }
                        token.ThrowIfCancellationRequested();
                        long bytes = new FileInfo(temporary).Length; string hash = Hash(temporary);
                        File.Move(temporary, target); successes++;
                        if (job.Audio) musicOk++; else imageOk++;
                        string duration = job.Audio ? (bytes / 96000.0).ToString("0.000", System.Globalization.CultureInfo.InvariantCulture) : "";
                        records.AppendLine(Csv(job.Name) + "," + Csv(job.Source) + ",成功," + bytes + "," + duration + "," + hash + ",");
                        Ui(delegate { job.Row.SubItems[2].Text = "成功"; });
                    } catch (OperationCanceledException) {
                        stopped = true; Ui(delegate { job.Row.SubItems[2].Text = "已取消"; }); break;
                    } catch (Exception ex) {
                        failures++; if (job.Audio) musicBad++; else imageBad++;
                        errors.AppendLine(job.Name + " ← " + job.Source + "\r\n" + ex + "\r\n");
                        records.AppendLine(Csv(job.Name) + "," + Csv(job.Source) + ",失败,,,," + Csv(ex.Message));
                        Ui(delegate { job.Row.SubItems[2].Text = "失败（见日志）"; });
                    } finally {
                        // Delete only this task's newly-created unfinished file, never an input/result.
                        if (File.Exists(temporary)) try { File.Delete(temporary); } catch (IOException) { }
                    }
                    completed++;
                }
                WriteReports(folder, manifest, log, musicOk, musicBad, stopped, "音乐");
                WriteReports(imageFolder, imageManifest, imageLog, imageOk, imageBad, stopped, "图片", imageWidth, imageHeight, imageFormat);
            } catch (Exception ex) { fatal = "结果保存失败：" + ex.Message; }
            int ok = successes, bad = failures; bool wasStopped = stopped;
            Ui(delegate {
                foreach (Control c in editors) c.Enabled = true;
                cancellation.Dispose(); cancellation = null; cancelButton.Enabled = false; UpdateResultButton();
                UpdateCounts(); if (!wasStopped && fatal == null) progress.Value = 100;
                foreach (ConversionJob job in jobs) if (job.Row.SubItems[2].Text == "等待中") job.Row.SubItems[2].Text = "未转换";
                status.Text = fatal ?? ((wasStopped ? "任务已取消" : "转换完成") + "  ·  成功 " + ok + "，失败 " + bad);
                string summary = (fatal ?? status.Text) +
                    (folder == null ? "" : "\n\n音乐结果：\n" + folder) +
                    (imageFolder == null ? "" : "\n\n图片结果：\n" + imageFolder) +
                    (bad > 0 ? "\n\n失败原因已保存在转换失败日志中。" : "");
                if (ResultNotice != null) ResultNotice(summary);
                else MessageBox.Show(this, summary, "本次转换结果", MessageBoxButtons.OK,
                    bad > 0 || fatal != null ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
            });
        }
    }
}
