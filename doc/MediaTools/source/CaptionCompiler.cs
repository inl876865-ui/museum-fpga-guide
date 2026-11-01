using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace FpgaMedia {
    internal sealed class CaptionCue {
        public string Text;
        public uint Start, End;
        public CaptionCue(string text, uint start, uint end) { Text = text; Start = start; End = end; }
    }
    internal sealed class CaptionDocument {
        public bool Timed;
        public readonly List<CaptionCue> Cues = new List<CaptionCue>();
    }
    internal static class CaptionCompiler {
        internal const int MaxCues = 64, MaxCharacters = 32, SampleRate = 48000;
        // Palette IDs and RGB values match the board-side caption_overlay RTL.
        internal static readonly string[] ColorNames = { "原色（兼容旧固件）", "白色", "黄色", "青色", "绿色", "红色", "蓝色", "粉色" };
        internal static readonly int[] ColorValues = { 0xE8EEF2, 0xFFFFFF, 0xFFFF00, 0x00FFFF, 0x00FF00, 0xFF0000, 0x3399FF, 0xFF66CC };
        internal static void ValidateColor(byte colorId) {
            if (colorId > 7) throw new InvalidDataException("字幕颜色编号须为0～7。");
        }
        internal static string ColorDescription(byte colorId) {
            ValidateColor(colorId);
            return ColorNames[colorId] + " #" + ColorValues[colorId].ToString("X6") +
                (colorId == 0 ? "（CAP v1，兼容旧固件）" : "（CAP v2，需要板端支持字幕配色）");
        }
        const string TimePattern = @"\d{2}:\d{2}:\d{2}[,.]\d{3}";
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
        static extern uint GetGlyphIndicesW(IntPtr dc, string text, int count, ushort[] indices, uint flags);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);

        internal static string AudioName(string value) {
            value = value.Trim().ToUpperInvariant();
            if (!Regex.IsMatch(value, @"\A[A-Z0-9_-]{1,8}\z"))
                throw new InvalidDataException("配音短名须为1～8位英文字母、数字、下划线或短横线，例如01；不含扩展名。");
            return value;
        }
        internal static uint PcmLength(string path) {
            if (!File.Exists(path) || !string.Equals(Path.GetExtension(path), ".PCM", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("请选择对应的48kHz、16位单声道裸PCM文件。");
            long length = new FileInfo(path).Length;
            if (length <= 0 || length > uint.MaxValue || length % 2 != 0)
                throw new InvalidDataException("PCM长度须为正偶数，且不超过4GB。");
            return (uint)length;
        }
        internal static void ValidateText(string text, int number) {
            if (string.IsNullOrWhiteSpace(text) || text.Length > MaxCharacters)
                throw new InvalidDataException("第" + number + "句须有1～32个字符；请分句，不能截断文字。");
            if (Regex.IsMatch(text, "<[^>]*>")) throw new InvalidDataException("第" + number + "句含富文本标记，请改成纯文字。");
            foreach (char c in text) {
                UnicodeCategory category = char.GetUnicodeCategory(c);
                if (char.IsControl(c) || char.IsSurrogate(c) || category == UnicodeCategory.Format ||
                    category == UnicodeCategory.OtherNotAssigned || category == UnicodeCategory.NonSpacingMark ||
                    category == UnicodeCategory.SpacingCombiningMark || category == UnicodeCategory.EnclosingMark)
                    throw new InvalidDataException("第" + number + "句含不支持的字符U+" + ((int)c).ToString("X4") + "。");
            }
        }
        internal static uint ParseTime(string value) {
            Match m = Regex.Match(value, @"\A(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\z");
            if (!m.Success) throw new InvalidDataException("时间格式须为00:00:00,000：" + value);
            long h = long.Parse(m.Groups[1].Value), min = long.Parse(m.Groups[2].Value), sec = long.Parse(m.Groups[3].Value), ms = long.Parse(m.Groups[4].Value);
            long samples = ((h * 3600 + min * 60 + sec) * 1000 + ms) * 48;
            if (min >= 60 || sec >= 60 || samples > uint.MaxValue) throw new InvalidDataException("时间超出范围：" + value);
            return (uint)samples;
        }
        internal static string Time(uint samples) {
            long ms = samples / 48;
            return string.Format(CultureInfo.InvariantCulture, "{0:00}:{1:00}:{2:00},{3:000}", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000);
        }
        internal static string ReadText(string path, string encoding) {
            if (new FileInfo(path).Length > 1048576) throw new InvalidDataException("字幕原稿超过1MB，请检查文件。");
            Encoding selected = encoding == "GBK" ? Encoding.GetEncoding(936, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback) :
                encoding == "UTF-16" ? (Encoding)new UnicodeEncoding(false, true, true) : new UTF8Encoding(false, true);
            // StreamReader BOM auto-detection is intentionally disabled: an explicit
            // encoding selection never silently falls back to a different encoding.
            byte[] data = File.ReadAllBytes(path);
            try { return selected.GetString(data).TrimStart('\uFEFF').Replace("\r\n", "\n").Replace('\r', '\n'); }
            catch (DecoderFallbackException) { throw new InvalidDataException("原稿与所选" + encoding + "编码不符。请选择正确编码；原文件未修改。"); }
        }
        internal static CaptionDocument Parse(string path, uint pcmBytes, string audioName, string encoding) {
            string text = ReadText(path, encoding);
            CaptionDocument doc = new CaptionDocument();
            if (string.Equals(Path.GetExtension(path), ".srt", StringComparison.OrdinalIgnoreCase)) {
                doc.Timed = true;
                foreach (string block in Regex.Split(text.Trim('\n'), @"\n[ \t]*\n+")) {
                    string[] lines = block.Split('\n');
                    if (lines.Length < 3 || lines[0].Trim() != (doc.Cues.Count + 1).ToString(CultureInfo.InvariantCulture))
                        throw new InvalidDataException("SRT须有连续序号、时间行及正文。");
                    Match m = Regex.Match(lines[1], @"\A\s*(" + TimePattern + @")\s*-->\s*(" + TimePattern + @")\s*\z");
                    if (!m.Success) throw new InvalidDataException("SRT第" + (doc.Cues.Count + 1) + "段时间格式错误。");
                    doc.Cues.Add(new CaptionCue(string.Join(" ", lines, 2, lines.Length - 2), ParseTime(m.Groups[1].Value), ParseTime(m.Groups[2].Value)));
                }
            } else {
                List<string> lines = new List<string>();
                foreach (string line in text.Split('\n')) {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    if (line.StartsWith("#")) {
                        if (line.StartsWith("# PCM_NAME=") && line.Substring(11).Trim() != audioName)
                            throw new InvalidDataException("文本中PCM_NAME与所选PCM短名不一致，请选择原配音。");
                        if (line.StartsWith("# PCM_BYTES=") && line.Substring(12).Trim() != pcmBytes.ToString(CultureInfo.InvariantCulture))
                            throw new InvalidDataException("文本中PCM_BYTES与所选PCM长度不一致，请选择原配音。");
                        continue;
                    }
                    lines.Add(line);
                    if (line.Contains("-->")) doc.Timed = true;
                }
                uint position = 0;
                foreach (string line in lines) {
                    if (doc.Timed) {
                        Match m = Regex.Match(line, @"\A\s*(" + TimePattern + @")\s*-->\s*(" + TimePattern + @")[ \t]+(.+)\z");
                        if (!m.Success) throw new InvalidDataException("带时间轴TXT每行须为“开始 --> 结束 空格 正文”，不能混用无时间行。");
                        doc.Cues.Add(new CaptionCue(m.Groups[3].Value, ParseTime(m.Groups[1].Value), ParseTime(m.Groups[2].Value)));
                    } else {
                        uint duration = checked((uint)((516 + line.Length * 24 + 48) * 1600));
                        doc.Cues.Add(new CaptionCue(line, position, checked(position + duration))); position = checked(position + duration);
                    }
                }
            }
            Validate(doc, pcmBytes); return doc;
        }
        internal static void Validate(CaptionDocument doc, uint pcmBytes) {
            if (doc.Cues.Count < 1 || doc.Cues.Count > MaxCues) throw new InvalidDataException("当前固件每个CAP支持1～64句；识别文本已保留，请分段配音或缩减句数。");
            uint previous = 0;
            for (int i = 0; i < doc.Cues.Count; i++) {
                CaptionCue cue = doc.Cues[i]; ValidateText(cue.Text, i + 1);
                if (cue.End <= cue.Start || cue.Start < previous || (doc.Timed && (cue.End - cue.Start < 4800 || cue.End > pcmBytes / 2)))
                    throw new InvalidDataException("第" + (i + 1) + "句时间须顺序、不重叠、至少100ms且不超过配音时长。");
                previous = cue.End;
            }
        }
        internal static uint Crc(byte[] bytes, int start, int length) {
            uint crc = 0xFFFFFFFF;
            for (int i = start; i < start + length; i++) {
                crc ^= bytes[i]; for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320 : 0);
            }
            return crc ^ 0xFFFFFFFF;
        }
        internal static byte[] Bitmap(string text) { return Bitmap(text, "SimHei"); }
        internal static byte[] Bitmap(string text, string fontName) {
            using (FontFamily family = new FontFamily(fontName))
            using (Font font = new Font(family, 16, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Bitmap canvas = new Bitmap(72, 72, PixelFormat.Format24bppRgb))
            using (Graphics g = Graphics.FromImage(canvas)) {
                IntPtr hf = font.ToHfont(), dc = g.GetHdc(), old = IntPtr.Zero;
                try {
                    old = SelectObject(dc, hf); ushort[] glyph = new ushort[text.Length];
                    if (GetGlyphIndicesW(dc, text, text.Length, glyph, 1) == 0xFFFFFFFF) throw new InvalidDataException("无法检查字体字符。");
                    for (int i = 0; i < text.Length; i++) if (glyph[i] == 0xFFFF || glyph[i] == 0)
                        throw new InvalidDataException("所选字体缺少字符“" + text[i] + "”，不能用空白字替代。");
                } finally { if (old != IntPtr.Zero) SelectObject(dc, old); g.ReleaseHdc(dc); DeleteObject(hf); }
                byte[] result = new byte[text.Length * 72];
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                using (StringFormat format = (StringFormat)StringFormat.GenericTypographic.Clone()) {
                    format.FormatFlags |= StringFormatFlags.NoWrap | StringFormatFlags.MeasureTrailingSpaces;
                    for (int i = 0; i < text.Length; i++) {
                        g.Clear(Color.Black); g.DrawString(text[i].ToString(), font, Brushes.White, new PointF(16, 16), format); g.Flush();
                        int left = 72, top = 72, right = -1, bottom = -1;
                        for (int y = 0; y < 72; y++) for (int x = 0; x < 72; x++) if (canvas.GetPixel(x, y).R >= 128) {
                            left = Math.Min(left, x); top = Math.Min(top, y); right = Math.Max(right, x); bottom = Math.Max(bottom, y);
                        }
                        if (right < 0) { if (!char.IsWhiteSpace(text[i])) throw new InvalidDataException("字符无法绘制：“" + text[i] + "”。"); continue; }
                        int width = right - left + 1, height = bottom - top + 1;
                        if (width > 16 || height > 16) throw new InvalidDataException("字符超过16×16字格：“" + text[i] + "”。");
                        // Preserve FCAPv1's24px storage grid. Native16px ink is
                        // expanded by3/2; the new FPGA samples0,1,3,4,...22 and
                        // recovers every native pixel exactly,without changing CRCs/schema.
                        for (int sy = 0; sy < 24; sy++) for (int sx = 0; sx < 24; sx++) {
                            int nx = (2 * sx + 1) / 3 - (16 - width) / 2;
                            int ny = (2 * sy + 1) / 3 - (16 - height) / 2;
                            if (nx >= 0 && nx < width && ny >= 0 && ny < height && canvas.GetPixel(left + nx, top + ny).R >= 128) {
                                int px = i * 24 + sx;
                                result[sy * text.Length * 3 + px / 8] |= (byte)(1 << (7 - px % 8));
                            }
                        }
                    }
                }
                return result;
            }
        }
        internal static byte[] Compile(CaptionDocument doc, string name, uint pcmBytes) { return Compile(doc, name, pcmBytes, "SimHei"); }
        internal static byte[] Compile(CaptionDocument doc, string name, uint pcmBytes, string fontName, byte colorId = 0) {
            ValidateColor(colorId); name = AudioName(name); Validate(doc, pcmBytes);
            using (MemoryStream entries = new MemoryStream()) using (MemoryStream payload = new MemoryStream()) {
                BinaryWriter index = new BinaryWriter(entries); uint offset = (uint)(48 + doc.Cues.Count * 32);
                foreach (CaptionCue cue in doc.Cues) {
                    byte[] bitmap = Bitmap(cue.Text, fontName); uint width = (uint)cue.Text.Length * 24, duration = cue.End - cue.Start;
                    uint step = doc.Timed ? (uint)(((((ulong)Math.Max(0L, (long)width - 516)) << 32) + duration / 2) / duration) : (uint)(((1UL << 32) + 800) / 1600);
                    index.Write(cue.Start); index.Write(cue.End); index.Write((ushort)width); index.Write((byte)24); index.Write((byte)0);
                    index.Write(offset); index.Write((uint)bitmap.Length); index.Write(Crc(bitmap, 0, bitmap.Length)); index.Write(step); index.Write((uint)colorId);
                    payload.Write(bitmap, 0, bitmap.Length); offset += (uint)bitmap.Length;
                }
                if (offset > 149552) throw new InvalidDataException("CAP超过149552字节上限。");
                using (MemoryStream result = new MemoryStream()) {
                    BinaryWriter writer = new BinaryWriter(result); byte[] indices = entries.ToArray();
                    writer.Write(Encoding.ASCII.GetBytes("FCAP")); writer.Write((ushort)(colorId == 0 ? 1 : 2)); writer.Write((ushort)(doc.Timed ? 1 : 0));
                    writer.Write(offset); writer.Write((ushort)doc.Cues.Count); writer.Write((byte)24); writer.Write((byte)1);
                    writer.Write(48000U); writer.Write(pcmBytes); writer.Write(Encoding.ASCII.GetBytes(name.PadRight(8)));
                    writer.Write(48U); writer.Write((uint)(48 + indices.Length)); writer.Write(Crc(indices, 0, indices.Length));
                    byte[] head = result.ToArray(); writer.Write(Crc(head, 0, head.Length)); writer.Write(indices); writer.Write(payload.ToArray());
                    return result.ToArray();
                }
            }
        }
        internal static void WriteText(string folder, string name, uint pcmBytes, CaptionDocument doc) {
            StringBuilder text = new StringBuilder("# FPGA字幕文本 v1\r\n# PCM_NAME=" + name + "\r\n# PCM_BYTES=" + pcmBytes + "\r\n");
            StringBuilder srt = new StringBuilder(), plain = new StringBuilder();
            for (int i = 0; i < doc.Cues.Count; i++) {
                CaptionCue cue = doc.Cues[i]; plain.AppendLine(cue.Text);
                if (doc.Timed) {
                    text.AppendLine(Time(cue.Start) + " --> " + Time(cue.End) + "\t" + cue.Text);
                    srt.AppendLine((i + 1).ToString(CultureInfo.InvariantCulture)); srt.AppendLine(Time(cue.Start) + " --> " + Time(cue.End)); srt.AppendLine(cue.Text); srt.AppendLine();
                } else text.AppendLine(cue.Text);
            }
            WriteNew(Path.Combine(folder, name + ".txt"), new UTF8Encoding(true).GetBytes(text.ToString()));
            WriteNew(Path.Combine(folder, name + "_纯文本.txt"), new UTF8Encoding(true).GetBytes(plain.ToString()));
            if (doc.Timed) WriteNew(Path.Combine(folder, name + ".srt"), new UTF8Encoding(true).GetBytes(srt.ToString()));
        }
        internal static void WriteNew(string path, byte[] data) {
            if (File.Exists(path)) throw new IOException("结果已存在，不能覆盖：" + path);
            string pending = path + ".writing_" + Guid.NewGuid().ToString("N");
            using (FileStream file = new FileStream(pending, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                file.Write(data, 0, data.Length); file.Flush(true);
            }
            File.Move(pending, path);
        }
    }
}
