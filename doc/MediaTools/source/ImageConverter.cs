using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace FpgaMedia {
    internal static class ImageConverter {
        internal static void ValidateSize(int width, int height) {
            if (width < 1 || height < 1 || width > 32767 || height > 32767 || (long)width * height > 64000000)
                throw new InvalidDataException("宽高须为1～32767，且总像素不超过6400万；请减小尺寸。");
        }
        internal static string NormalizeFormat(string format) {
            string value = (format ?? "BMP").ToUpperInvariant();
            if (value == "JPEG") value = "JPG";
            if (value != "BMP" && value != "PNG" && value != "JPG") throw new InvalidDataException("请选择BMP、PNG或JPG格式。");
            return value;
        }
        public static Bitmap Render(string source, int mode, Color background) { return Render(source, mode, background, 640, 480); }
        public static Bitmap Render(string source, int mode, Color background, int width, int height) {
            ValidateSize(width, height);
            using (Image image = Image.FromFile(source)) {
                // Only the first frame/page is converted. Honor camera rotation metadata.
                try {
                    if (Array.IndexOf(image.PropertyIdList, 0x0112) >= 0) {
                        int orientation = image.GetPropertyItem(0x0112).Value[0];
                        RotateFlipType[] rotate = { RotateFlipType.RotateNoneFlipNone,
                            RotateFlipType.RotateNoneFlipNone, RotateFlipType.RotateNoneFlipX,
                            RotateFlipType.Rotate180FlipNone, RotateFlipType.Rotate180FlipX,
                            RotateFlipType.Rotate90FlipX, RotateFlipType.Rotate90FlipNone,
                            RotateFlipType.Rotate270FlipX, RotateFlipType.Rotate270FlipNone };
                        if (orientation > 0 && orientation < rotate.Length) image.RotateFlip(rotate[orientation]);
                    }
                } catch (ArgumentException) { }
                Bitmap output = new Bitmap(width, height, PixelFormat.Format24bppRgb);
                try {
                    using (Graphics g = Graphics.FromImage(output)) {
                        g.Clear(background); g.CompositingQuality = CompositingQuality.HighQuality;
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        double scale = mode == 1 ? Math.Max((double)width / image.Width, (double)height / image.Height) :
                            Math.Min((double)width / image.Width, (double)height / image.Height);
                        float w = mode == 2 ? width : (float)(image.Width * scale);
                        float h = mode == 2 ? height : (float)(image.Height * scale);
                        RectangleF dest = new RectangleF((width - w) / 2, (height - h) / 2, w, h);
                        using (ImageAttributes attributes = new ImageAttributes()) {
                            attributes.SetWrapMode(WrapMode.TileFlipXY);
                            g.DrawImage(image, Rectangle.Round(dest), 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attributes);
                        }
                    }
                    return output;
                } catch { output.Dispose(); throw; }
            }
        }
        public static void Convert(string source, string target, int mode, Color background) { Convert(source, target, mode, background, 640, 480, "BMP"); }
        public static void Convert(string source, string target, int mode, Color background, int width, int height, string format) {
            string kind = NormalizeFormat(format);
            ImageFormat encoder = kind == "PNG" ? ImageFormat.Png : kind == "JPG" ? ImageFormat.Jpeg : ImageFormat.Bmp;
            using (Bitmap bitmap = Render(source, mode, background, width, height))
                using (FileStream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write)) bitmap.Save(output, encoder);
            Validate(target, width, height, kind);
        }
        public static void Validate(string path) { Validate(path, 640, 480, "BMP"); }
        public static void Validate(string path, int width, int height, string format) {
            string kind = NormalizeFormat(format); ValidateSize(width, height);
            if (kind != "BMP") {
                using (Image image = Image.FromFile(path)) {
                    Guid expected = kind == "PNG" ? ImageFormat.Png.Guid : ImageFormat.Jpeg.Guid;
                    if (image.Width != width || image.Height != height || image.RawFormat.Guid != expected)
                        throw new InvalidDataException("图片格式或尺寸校验失败。");
                }
                return;
            }
            using (BinaryReader r = new BinaryReader(File.OpenRead(path))) {
                byte[] h = r.ReadBytes(54);
                long stride = ((long)width * 3 + 3) / 4 * 4;
                if (h.Length != 54 || h[0] != 'B' || h[1] != 'M' ||
                    BitConverter.ToInt32(h, 18) != width || BitConverter.ToInt32(h, 22) != height ||
                    BitConverter.ToUInt16(h, 26) != 1 || BitConverter.ToUInt16(h, 28) != 24 ||
                    BitConverter.ToInt32(h, 30) != 0 || BitConverter.ToInt32(h, 14) < 40 ||
                    BitConverter.ToUInt32(h, 10) < 54 || r.BaseStream.Length != BitConverter.ToUInt32(h, 2) ||
                    BitConverter.ToUInt32(h, 10) + stride * height > r.BaseStream.Length)
                    throw new InvalidDataException("BMP格式或尺寸校验失败。");
            }
        }
    }
}
