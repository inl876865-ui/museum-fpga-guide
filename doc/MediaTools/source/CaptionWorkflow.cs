using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace FpgaMedia {
    internal sealed class CaptionBatchResult {
        public string Folder;
        public int Successes, Failures;
        public bool Cancelled;
    }
    internal static class CaptionWorkflow {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern int LCMapStringEx(string locale, uint flags, string source, int count, [Out] char[] destination, int capacity, IntPtr version, IntPtr reserved, IntPtr sort);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateHardLink(string link, string existing, IntPtr security);
        internal static string Simplified(string text) {
            char[] b = new char[text.Length * 2 + 8];
            int count = LCMapStringEx("zh-CN", 0x02000000, text, text.Length, b, b.Length, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (count == 0)
                throw new InvalidOperationException("Windows简体中文转换失败。");
            return new string(b, 0, count);
        }
        internal static string NewResult(string root) {
            if (string.IsNullOrWhiteSpace(root)) throw new IOException("请选择字幕输出位置。");
            string folder = Path.Combine(FolderInputDialog.NormalizePath(root), "已转换_字幕_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + "_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(folder); return folder;
        }
        internal static string FindRecognizer() {
            string root = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "speech");
            foreach (string relative in new string[] { "whisper-cli.exe", "Release\\whisper-cli.exe", "build\\bin\\Release\\whisper-cli.exe" }) {
                string path = Path.Combine(root, relative); if (File.Exists(path)) return path;
            }
            if (Directory.Exists(root)) {
                string[] candidates = Directory.GetFiles(root, "whisper-cli.exe", SearchOption.AllDirectories);
                if (candidates.Length == 1) return candidates[0];
            }
            return Path.Combine(root, "whisper-cli.exe");
        }
        internal static string DefaultModel { get { return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "speech", "ggml-small.bin"); } }
        internal static void MakeWave(string pcm, string wav, CancellationToken token) {
            long samples = new FileInfo(pcm).Length / 2, frames = (samples + 2) / 3;
            using (BinaryReader r = new BinaryReader(File.OpenRead(pcm)))
            using (BinaryWriter w = new BinaryWriter(new FileStream(wav, FileMode.CreateNew, FileAccess.Write))) {
                w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write((uint)(36 + frames * 2)); w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
                w.Write(16U); w.Write((ushort)1); w.Write((ushort)1); w.Write(16000U); w.Write(32000U); w.Write((ushort)2); w.Write((ushort)16);
                w.Write(Encoding.ASCII.GetBytes("data")); w.Write((uint)(frames * 2));
                for (long i = 0; i < samples; ) {
                    if (i % 48000 == 0) token.ThrowIfCancellationRequested();
                    int sum = 0, n = 0;
                    while (n < 3 && i < samples) { sum += r.ReadInt16(); n++; i++; }
                    w.Write((short)(sum / n));
                }
            }
        }
        internal static string Quote(string value) {
            // CommandLineToArgvW quoting, including trailing backslashes; no shell.
            StringBuilder b = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value) {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { b.Append('\\', slashes * 2 + 1); b.Append('"'); slashes = 0; continue; }
                b.Append('\\', slashes); slashes = 0; b.Append(c);
            }
            b.Append('\\', slashes * 2); return b.Append('"').ToString();
        }
        internal static void Recognize(string engine, string model, string wav, string prefix, string language, CancellationToken token, Action<string> status) {
            if (!File.Exists(engine) || !File.Exists(model)) throw new FileNotFoundException("缺少离线识别程序或模型，请选择whisper-cli.exe和多语言模型。文本转CAP不需要识别组件。");
            // This upstream Windows CLI uses narrow argv for model/file names.
            // Keep every CLI path argument ASCII while CreateProcessW supplies
            // the Unicode working directory. A private hard link avoids copying
            // the488MB model on NTFS; other volumes use a cancellable private copy.
            string work = Path.Combine(Path.GetDirectoryName(prefix), "识别中间数据_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            string stagedModel = Path.Combine(work, "model.bin");
            File.Copy(wav, Path.Combine(work, "input.wav"), false);
            try {
                token.ThrowIfCancellationRequested();
                if (!CreateHardLink(stagedModel, Path.GetFullPath(model), IntPtr.Zero)) {
                    using (FileStream input = File.OpenRead(model)) using (FileStream output = new FileStream(stagedModel, FileMode.CreateNew, FileAccess.Write)) {
                        byte[] buffer = new byte[1048576]; int n;
                        while ((n = input.Read(buffer, 0, buffer.Length)) > 0) { token.ThrowIfCancellationRequested(); output.Write(buffer, 0, n); }
                    }
                }
                string[] args = { "-m", "model.bin", "-f", "input.wav", "-l", language, "-t", Math.Min(8, Environment.ProcessorCount).ToString(CultureInfo.InvariantCulture),
                "-ng", "-oj", "-of", "asr", "-ml", "32", "-pp", "-sns" };
            StringBuilder command = new StringBuilder(); foreach (string arg in args) command.Append(Quote(arg)).Append(' ');
            ProcessStartInfo info = new ProcessStartInfo(engine, command.ToString()) { UseShellExecute = false, CreateNoWindow = true,
                WorkingDirectory = work, RedirectStandardError = true, RedirectStandardOutput = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            StringBuilder log = new StringBuilder(); object gate = new object();
            using (Process process = new Process { StartInfo = info }) {
                DataReceivedEventHandler receive = delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data == null) return;
                    lock (gate) { if (log.Length < 8000000) log.AppendLine(e.Data); }
                    if (e.Data.Contains("progress")) status("离线识别：" + e.Data);
                };
                process.OutputDataReceived += receive; process.ErrorDataReceived += receive;
                process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
                try {
                    while (!process.WaitForExit(150)) {
                        if (token.IsCancellationRequested) { process.Kill(); process.WaitForExit(); token.ThrowIfCancellationRequested(); }
                    }
                    process.WaitForExit(); token.ThrowIfCancellationRequested();
                    if (process.ExitCode != 0) throw new InvalidOperationException("离线识别失败（退出码" + process.ExitCode + "），详情见识别日志。");
                } finally {
                    lock (gate) CaptionCompiler.WriteNew(prefix + "_识别日志.txt", new UTF8Encoding(true).GetBytes(log.ToString()));
                }
            }
                string json = Path.Combine(work, "asr.json");
                if (!File.Exists(json)) throw new InvalidDataException("识别器没有输出JSON；请查看识别日志。");
                File.Copy(json, prefix + ".json", false);
            } finally {
                // Only this call's private model link/copy is removed; the user
                // model and all generated wording/audio/logs are retained.
                if (File.Exists(stagedModel)) File.Delete(stagedModel);
            }
        }
        internal static CaptionDocument ParseRecognition(string jsonPath, uint pcmBytes, bool simplify, List<string> notes) {
            if (new FileInfo(jsonPath).Length > 16777216) throw new InvalidDataException("识别JSON过大，请分段处理配音。");
            JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = 16777216 };
            Dictionary<string, object> root = serializer.DeserializeObject(File.ReadAllText(jsonPath, new UTF8Encoding(false, true))) as Dictionary<string, object>;
            if (root == null || !root.ContainsKey("transcription")) throw new InvalidDataException("识别器未返回transcription时间轴。");
            CaptionDocument doc = new CaptionDocument { Timed = true };
            StringBuilder raw = new StringBuilder(); uint last = 0;
            foreach (object value in (IEnumerable)root["transcription"]) {
                Dictionary<string, object> segment = value as Dictionary<string, object>;
                if (segment == null || !segment.ContainsKey("text") || !segment.ContainsKey("offsets")) throw new InvalidDataException("识别段缺少正文或时间。");
                string text = (string)segment["text"]; raw.AppendLine(text);
                text = System.Text.RegularExpressions.Regex.Replace(text, @"\s+", " ").Trim();
                if (simplify) text = Simplified(text);
                if (text.Length == 0) continue;
                Dictionary<string, object> offsets = segment["offsets"] as Dictionary<string, object>;
                long from = Convert.ToInt64(offsets["from"], CultureInfo.InvariantCulture) * 48;
                long to = Convert.ToInt64(offsets["to"], CultureInfo.InvariantCulture) * 48;
                if (from < 0 || to <= from || from >= pcmBytes / 2) throw new InvalidDataException("识别时间轴无效或超出音频；原始JSON已保留。");
                uint start = (uint)from, end = (uint)Math.Min(to, pcmBytes / 2 / 48 * 48L);
                if (start < last) throw new InvalidDataException("识别时段重叠，请校对SRT后再转换。");
                // Engine max-len normally handles this. Retain every character if a
                // backend returns a longer segment, and disclose its estimated split.
                int pieces = (text.Length + 31) / 32;
                if (pieces > 1) notes.Add("识别段超过32字，按字符比例拆为" + pieces + "句；该段内部边界为估算，请校对时间。");
                for (int pos = 0; pos < text.Length; pos += 32) {
                    int count = Math.Min(32, text.Length - pos);
                    uint a = start + (uint)(((ulong)(end - start) * (uint)pos / (uint)text.Length) / 48 * 48);
                    uint b = pos + count == text.Length ? end : start + (uint)(((ulong)(end - start) * (uint)(pos + count) / (uint)text.Length) / 48 * 48);
                    doc.Cues.Add(new CaptionCue(text.Substring(pos, count), a, b));
                }
                last = end;
            }
            CaptionCompiler.WriteNew(Path.Combine(Path.GetDirectoryName(jsonPath), "识别原文.txt"), new UTF8Encoding(true).GetBytes(raw.ToString()));
            // Merge a very short segment rather than inventing an extra100ms or
            // dropping its words. A failure leaves editable timing text for review.
            for (int i = 0; i < doc.Cues.Count; i++) {
                CaptionCue cue = doc.Cues[i];
                if (cue.End - cue.Start >= 4800) continue;
                if (i + 1 < doc.Cues.Count && cue.Text.Length + doc.Cues[i + 1].Text.Length <= 32) {
                    CaptionCue next = doc.Cues[i + 1]; doc.Cues[i] = new CaptionCue(cue.Text + next.Text, cue.Start, next.End); doc.Cues.RemoveAt(i + 1); i--;
                    notes.Add("不足100ms的短识别段已合并到相邻句，文字保持。");
                } else if (i > 0 && cue.Text.Length + doc.Cues[i - 1].Text.Length <= 32) {
                    CaptionCue prev = doc.Cues[i - 1]; doc.Cues[i - 1] = new CaptionCue(prev.Text + cue.Text, prev.Start, cue.End); doc.Cues.RemoveAt(i); i = Math.Max(-1, i - 2);
                    notes.Add("不足100ms的短识别段已合并到相邻句，文字保持。");
                }
            }
            return doc;
        }
        internal static string AudioToCap(string source, string name, string outputRoot, string engine, string model, string language, bool simplify,
            CancellationToken token, Action<string> status, string fontName = "SimHei", byte colorId = 0) {
            return AudioToCapCore(source, name, outputRoot, engine, model, language, simplify, token, status, fontName, null, colorId);
        }
        static string AudioToCapCore(string source, string name, string outputRoot, string engine, string model, string language, bool simplify,
            CancellationToken token, Action<string> status, string fontName, string resultFolder, byte colorId) {
            CaptionCompiler.ValidateColor(colorId); name = CaptionCompiler.AudioName(name);
            if (!File.Exists(source)) throw new FileNotFoundException("找不到输入音频，请重新选择当前文件路径：" + source);
            if (!File.Exists(engine) || !File.Exists(model)) throw new FileNotFoundException("请选择有效的离线识别程序和模型。");
            if (resultFolder != null && Directory.Exists(resultFolder)) throw new IOException("批次工作目录已存在。");
            string folder = resultFolder ?? NewResult(outputRoot), pcm = Path.Combine(folder, name + ".PCM");
            Directory.CreateDirectory(folder);
            string work = Path.Combine(folder, "临时_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            try {
                status("正在生成配套PCM……");
                if (string.Equals(Path.GetExtension(source), ".pcm", StringComparison.OrdinalIgnoreCase)) {
                    CaptionCompiler.PcmLength(source); File.Copy(source, pcm, false);
                } else NativeAudio.Convert(source, pcm, token, delegate(int p) { status("音频转换 " + p + "%"); });
                uint bytes = CaptionCompiler.PcmLength(pcm); token.ThrowIfCancellationRequested();
                string wave = Path.Combine(work, "识别用16k.wav"), prefix = Path.Combine(work, name + "_识别原始");
                MakeWave(pcm, wave, token); status("正在本机离线识别人声……");
                Recognize(engine, model, wave, prefix, language, token, status);
                List<string> notes = new List<string>(); CaptionDocument doc = ParseRecognition(prefix + ".json", bytes, simplify, notes);
                // Text is saved before CAP validation, so a capacity/glyph failure
                // never discards the recognized wording or its timestamps.
                CaptionCompiler.WriteText(folder, name, bytes, doc);
                CaptionCompiler.WriteNew(Path.Combine(folder, "字幕处理说明.txt"), new UTF8Encoding(true).GetBytes(
                    "文字与时间由离线模型识别，请校对。TXT含时间轴，可修改后用文本转CAP重新生成。\r\n字幕颜色：" + CaptionCompiler.ColorDescription(colorId) + "\r\n" + string.Join("\r\n", notes.ToArray())));
                token.ThrowIfCancellationRequested();
                byte[] cap = CaptionCompiler.Compile(doc, name, bytes, fontName, colorId);
                CaptionCompiler.WriteNew(Path.Combine(folder, name + ".CAP"), cap); return folder;
            } catch (Exception ex) {
                // Keep only small diagnostics; never retain recognition WAVs or model links.
                try {
                    string diagnostics = Path.Combine(folder, "诊断信息");
                    foreach (string path in Directory.GetFiles(work, "*", SearchOption.TopDirectoryOnly)) {
                        if (path.EndsWith(".json", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)) {
                            Directory.CreateDirectory(diagnostics); File.Copy(path, Path.Combine(diagnostics, Path.GetFileName(path)), false);
                        }
                    }
                } catch (IOException) { }
                CaptionCompiler.WriteNew(Path.Combine(folder, "未完成说明.txt"), new UTF8Encoding(true).GetBytes(ex.Message + "\r\n本次已生成文件保留；只有完整通过的结果才包含.CAP。"));
                ex.Data["resultFolder"] = folder; throw;
            } finally {
                // work is this call's GUID child; input/model/shared folders are never cleanup targets.
                try {
                    string parent = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    if (Path.GetFullPath(work).StartsWith(parent, StringComparison.OrdinalIgnoreCase) &&
                        Path.GetFileName(work).StartsWith("临时_", StringComparison.Ordinal) && Directory.Exists(work)) Directory.Delete(work, true);
                } catch (IOException ex) { status("临时文件未能清理：" + ex.Message); }
                  catch (UnauthorizedAccessException ex) { status("临时文件未能清理：" + ex.Message); }
            }
        }
        internal static string[] BatchNames(string first, int count) {
            string name = CaptionCompiler.AudioName(first); string[] names = new string[count];
            if (count == 1) { names[0] = name; return names; }
            uint start;
            if (count < 1 || !uint.TryParse(name, NumberStyles.None, CultureInfo.InvariantCulture, out start) ||
                start == 0 || (ulong)start + (ulong)count - 1 > 99999999)
                throw new InvalidDataException("多段音频的起始号须为正整数，例如01；生成的编号不能超过8位。");
            for (int i = 0; i < count; i++) names[i] = ((ulong)start + (uint)i).ToString("D2", CultureInfo.InvariantCulture);
            return names;
        }
        static string BatchCsv(string value) { return "\"" + value.Replace("\"", "\"\"") + "\""; }
        internal static CaptionBatchResult AudioBatchToCap(string[] sources, string first, string outputRoot,
            string engine, string model, string language, bool simplify, CancellationToken token, Action<string> status,
            Action<int> progress, string fontName = "SimHei", byte colorId = 0) {
            CaptionCompiler.ValidateColor(colorId);
            if (sources == null || sources.Length == 0) throw new InvalidDataException("请先选择输入音频。");
            string[] names = BatchNames(first, sources.Length);
            if (!File.Exists(engine) || !File.Exists(model)) throw new FileNotFoundException("请选择有效的离线识别程序和模型。");
            CaptionBatchResult result = new CaptionBatchResult { Folder = NewResult(outputRoot) };
            string staging = Path.Combine(result.Folder, ".batch"); Directory.CreateDirectory(staging);
            StringBuilder manifest = new StringBuilder("编号,原音频,结果,说明\r\n");
            StringBuilder notes = new StringBuilder("同编号PCM与CAP配套复制到FAT32卡根目录；TXT/SRT用于校对。\r\n批次字体：" + fontName + "；字幕颜色：" + CaptionCompiler.ColorDescription(colorId) + "；自动识别文字与时间请播放核对。\r\n");
            int next = 0;
            try {
                for (int i = 0; i < sources.Length; i++) {
                    if (token.IsCancellationRequested) { result.Cancelled = true; break; }
                    string generated = null, name = names[i]; int number = i + 1;
                    status("[" + number + "/" + sources.Length + "] " + name + " ← " + sources[i]);
                    try {
                        generated = AudioToCapCore(sources[i], name, staging, engine, model, language, simplify, token,
                            delegate(string message) { status("[" + number + "/" + sources.Length + "] " + message); }, fontName, Path.Combine(staging, name), colorId);
                        string note = Path.Combine(generated, "字幕处理说明.txt");
                        string detail = File.ReadAllText(note, Encoding.UTF8);
                        string[] files = Directory.GetFiles(generated);
                        // Check every destination before moving any file. The batch directory is private and new.
                        foreach (string file in files) if (file != note && File.Exists(Path.Combine(result.Folder, Path.GetFileName(file))))
                            throw new IOException("批次输出重名：" + Path.GetFileName(file));
                        foreach (string file in files) if (file != note) File.Move(file, Path.Combine(result.Folder, Path.GetFileName(file)));
                        notes.AppendLine(name + "：" + detail); File.Delete(note); Directory.Delete(generated, false); generated = null;
                        result.Successes++; manifest.AppendLine(BatchCsv(name) + "," + BatchCsv(sources[i]) + ",成功,");
                    } catch (Exception ex) {
                        generated = generated ?? ex.Data["resultFolder"] as string;
                        if (generated != null && Directory.Exists(generated)) {
                            string ownRoot = Path.GetFullPath(staging).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                            if (!Path.GetFullPath(generated).StartsWith(ownRoot, StringComparison.OrdinalIgnoreCase)) throw;
                            Directory.Move(generated, Path.Combine(result.Folder, "未完成_" + name));
                        }
                        bool cancelled = ex is OperationCanceledException;
                        if (cancelled) result.Cancelled = true; else result.Failures++;
                        manifest.AppendLine(BatchCsv(name) + "," + BatchCsv(sources[i]) + "," + (cancelled ? "已取消" : "失败") + "," + BatchCsv(ex.Message));
                        notes.AppendLine(name + "：" + ex.Message); status(name + " " + (cancelled ? "已取消" : "失败：" + ex.Message));
                    }
                    next = i + 1; progress(next * 100 / sources.Length);
                    if (result.Cancelled) break;
                }
                for (int i = next; i < sources.Length; i++) manifest.AppendLine(BatchCsv(names[i]) + "," + BatchCsv(sources[i]) + ",未处理,");
                notes.AppendLine("成功" + result.Successes + "，失败" + result.Failures + (result.Cancelled ? "，已取消剩余任务。" : "。"));
                CaptionCompiler.WriteNew(Path.Combine(result.Folder, "文件对应表.csv"), new UTF8Encoding(true).GetBytes(manifest.ToString()));
                CaptionCompiler.WriteNew(Path.Combine(result.Folder, "字幕处理说明.txt"), new UTF8Encoding(true).GetBytes(notes.ToString()));
                return result;
            } catch (Exception ex) { ex.Data["resultFolder"] = result.Folder; throw; }
            finally {
                // Only remove our empty staging directory. Unexpected data stays available for diagnosis.
                if (Directory.Exists(staging) && Directory.GetFileSystemEntries(staging).Length == 0) Directory.Delete(staging, false);
            }
        }
        internal static string TextToCap(string text, string pcm, string outputRoot, string encoding, CancellationToken token, Action<string> status, string fontName = "SimHei", byte colorId = 0) {
            string name = CaptionCompiler.AudioName(Path.GetFileNameWithoutExtension(pcm)); uint bytes = CaptionCompiler.PcmLength(pcm);
            status("校验文本、时间轴及字形……"); CaptionDocument doc = CaptionCompiler.Parse(text, bytes, name, encoding);
            token.ThrowIfCancellationRequested(); byte[] cap = CaptionCompiler.Compile(doc, name, bytes, fontName, colorId);
            string folder = NewResult(outputRoot);
            CaptionCompiler.WriteNew(Path.Combine(folder, name + ".CAP"), cap); CaptionCompiler.WriteText(folder, name, bytes, doc);
            CaptionCompiler.WriteNew(Path.Combine(folder, "字幕处理说明.txt"), new UTF8Encoding(true).GetBytes(
                (doc.Timed ? "定时字幕：时间以所选PCM为零点，随实际音频进度逐句显示。\r\n请将CAP与所选原PCM配套使用。" :
                "普通TXT：每行一句，没有人声时间轴，按旧非定时模式顺序显示并循环。\r\n需要跟随配音时，请使用音频识别生成的带时间轴TXT或SRT。") +
                "\r\n字幕颜色：" + CaptionCompiler.ColorDescription(colorId)));
            return folder;
        }
    }
}
