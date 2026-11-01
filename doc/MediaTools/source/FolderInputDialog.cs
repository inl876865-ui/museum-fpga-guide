using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace FpgaMedia {
    internal sealed class FolderInputDialog : Form {
        readonly TextBox path;
        readonly Label error;
        public string SelectedPath { get; private set; }
        public FolderInputDialog(string initial) {
            Text = "添加文件夹"; ClientSize = new Size(650, 205);
            StartPosition = FormStartPosition.CenterParent; FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            Font = new Font("Microsoft YaHei UI", 10); BackColor = Color.White;
            Controls.Add(new Label { Text = "输入或粘贴文件夹路径", AutoSize = true,
                Font = new Font(Font, FontStyle.Bold), Location = new Point(20, 18) });
            path = new TextBox { Text = initial ?? "", Location = new Point(20, 50), Width = 462 };
            Controls.Add(path);
            Button paste = new Button { Text = "粘贴", Location = new Point(492, 48), Size = new Size(60, 31) };
            paste.Click += delegate {
                try { if (Clipboard.ContainsText()) path.Text = Clipboard.GetText(); }
                catch (System.Runtime.InteropServices.ExternalException) { error.Text = "剪贴板暂时不可用，可按 Ctrl+V 或直接输入。"; }
                path.Focus();
            };
            Controls.Add(paste);
            Button browse = new Button { Text = "浏览…", Location = new Point(562, 48), Size = new Size(68, 31) };
            browse.Click += delegate {
                using (FolderBrowserDialog dialog = new FolderBrowserDialog { Description = "选择素材文件夹" }) {
                    try { string value = NormalizePath(path.Text); if (Directory.Exists(value)) dialog.SelectedPath = value; }
                    catch (ArgumentException) { }
                    if (dialog.ShowDialog(this) == DialogResult.OK) path.Text = dialog.SelectedPath;
                }
            };
            Controls.Add(browse);
            Controls.Add(new Label { Text = "例如：D:\\素材\\音乐    或    \\\\服务器\\共享\\图片\n只添加本层文件；不读取子文件夹。",
                Location = new Point(20, 88), AutoSize = true, ForeColor = Color.DimGray });
            error = new Label { Location = new Point(20, 132), AutoSize = false, Width = 610,
                Height = 22, ForeColor = Color.Firebrick }; Controls.Add(error);
            Button add = new Button { Text = "添加此文件夹", Location = new Point(396, 164), Size = new Size(134, 31) };
            add.Click += delegate {
                try {
                    SelectedPath = ResolveFolder(path.Text); DialogResult = DialogResult.OK; Close();
                } catch (Exception ex) {
                    error.Text = ex.Message; path.Focus();
                }
            };
            Controls.Add(add);
            Button cancel = new Button { Text = "取消", Location = new Point(540, 164), Size = new Size(90, 31), DialogResult = DialogResult.Cancel };
            Controls.Add(cancel); AcceptButton = add; CancelButton = cancel;
            Shown += delegate { path.Focus(); path.SelectAll(); };
        }
        internal static string NormalizePath(string value) {
            string text = (value ?? "").Trim();
            if (text.Length >= 2 && text[0] == '"' && text[text.Length - 1] == '"') text = text.Substring(1, text.Length - 2);
            if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("请先输入文件夹路径。");
            Uri uri;
            if (text.StartsWith("file:", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(text, UriKind.Absolute, out uri) && uri.IsFile)
                text = uri.LocalPath;
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(text));
        }
        internal static string ResolveFolder(string value) {
            string full = NormalizePath(value);
            if (!Directory.Exists(full)) throw new IOException("文件夹不存在或无法访问，请检查路径和网络连接。");
            return full;
        }
    }
}
