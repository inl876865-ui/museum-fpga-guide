using System;
using System.IO;
using System.Text;
using System.Xml;
using System.Xml.Serialization;

namespace FpgaMedia {
    public sealed class ConverterSettings {
        public int FormatVersion = 1;
        public string MusicInput, MusicOutput, ImageInput, ImageOutput;
        public int ImageWidth = 640, ImageHeight = 480;
        public string ImageFormat = "BMP", CaptionFont = "SimHei";
        public int ImageMode, BackgroundArgb = unchecked((int)0xFF000000), ActiveTab;
        public string CaptionAudio, CaptionText, CaptionPcm, CaptionOutput, CaptionName, CaptionEngine, CaptionModel;
        public int CaptionEncoding, CaptionLanguage, CaptionColor;
        public bool CaptionFromText, CaptionSimplified = true;
    }
    internal static class SettingsStore {
        // Tests use an isolated location; normal customer builds always use LocalAppData.
        internal static string TestPath = null;
        internal static string FilePath {
            get { return TestPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "FpgaMediaConverter", "settings.xml"); }
        }
        internal static ConverterSettings Load() {
            string path = FilePath;
            if (!File.Exists(path)) return null;
            if (new FileInfo(path).Length > 1048576) throw new InvalidDataException("配置文件过大。");
            XmlReaderSettings options = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
            using (XmlReader reader = XmlReader.Create(path, options)) {
                ConverterSettings result = (ConverterSettings)new XmlSerializer(typeof(ConverterSettings)).Deserialize(reader);
                if (result == null || result.FormatVersion != 1) throw new InvalidDataException("配置版本不支持。");
                return result;
            }
        }
        internal static void Save(ConverterSettings value) {
            string path = FilePath;
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                using (FileStream file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 4096, FileOptions.WriteThrough)) {
                    XmlWriterSettings options = new XmlWriterSettings { Encoding = new UTF8Encoding(false), Indent = true, CloseOutput = false };
                    using (XmlWriter writer = XmlWriter.Create(file, options)) new XmlSerializer(typeof(ConverterSettings)).Serialize(writer, value);
                    file.Flush(true);
                }
                // Never truncate the live configuration: replace it only after a complete write.
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
            } finally {
                if (File.Exists(temporary)) try { File.Delete(temporary); } catch (IOException) { }
            }
        }
    }
}
