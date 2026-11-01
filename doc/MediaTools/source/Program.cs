using System;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace FpgaMedia {
    internal static class Program {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();
        [STAThread]
        static int Main(string[] args) {
            try {
                if (args.Length >= 4 && args[0] == "--caption-text") {
                    CaptionWorkflow.TextToCap(args[1], args[2], args[3], args.Length > 4 ? args[4] : "UTF-8", CancellationToken.None, delegate(string message) { }, args.Length > 5 ? args[5] : "SimHei", args.Length > 6 ? byte.Parse(args[6]) : (byte)0); return 0;
                }
                if (args.Length >= 4 && args[0] == "--caption-audio") {
                    CaptionWorkflow.AudioToCap(args[1], args[2], args[3], args.Length > 4 ? args[4] : CaptionWorkflow.FindRecognizer(),
                        args.Length > 5 ? args[5] : CaptionWorkflow.DefaultModel, "zh", true, CancellationToken.None, delegate(string message) { }, args.Length > 6 ? args[6] : "SimHei", args.Length > 7 ? byte.Parse(args[7]) : (byte)0); return 0;
                }
                if (args.Length >= 3 && args[0] == "--audio") {
                    NativeAudio.Convert(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]),
                        CancellationToken.None, delegate(int p) { }); return 0;
                }
                if (args.Length >= 3 && args[0] == "--image") {
                    ImageConverter.Convert(args[1], args[2], args.Length > 3 ? int.Parse(args[3]) : 0, Color.Black,
                        args.Length > 4 ? int.Parse(args[4]) : 640, args.Length > 5 ? int.Parse(args[5]) : 480, args.Length > 6 ? args[6] : "BMP");
                    return 0;
                }
                SetProcessDPIAware();
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                if (args.Length > 0 && (args[0] == "--preview" || args[0] == "--preview-caption"))
                    SettingsStore.TestPath = Path.Combine(Path.GetTempPath(), "fpga_preview_" + Guid.NewGuid().ToString("N") + ".xml");
                using (MainForm form = new MainForm()) {
                    if (args.Length >= 2 && (args[0] == "--preview" || args[0] == "--preview-caption")) {
                        if (args[0] == "--preview-caption") form.PrepareCaptionPreview();
                        else form.PreparePreview(args.Length > 2 ? args[2] : null);
                        using (Bitmap bitmap = new Bitmap(form.Width, form.Height)) {
                            form.DrawToBitmap(bitmap, new Rectangle(0, 0, form.Width, form.Height));
                            bitmap.Save(args[1]);
                        }
                        return 0;
                    }
                    Application.Run(form);
                }
                return 0;
            } catch (Exception ex) {
                string error = ex.Message + Environment.NewLine + ex.ToString();
                if (args.Length > 0) {
                    File.WriteAllText(Path.Combine(Path.GetTempPath(), "fpga_media_error.txt"), error, Encoding.UTF8);
                } else MessageBox.Show("无法启动媒体转换工具：\n" + ex.Message,
                    "启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
