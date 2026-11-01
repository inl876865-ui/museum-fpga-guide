using System;
using System.Drawing;
using System.Windows.Forms;

namespace FpgaMedia {
    internal partial class MainForm {
        Timer configurationTimer;
        bool configurationEnabled, configurationDirty;
        void InitializeConfiguration() {
            try {
                ConverterSettings value = SettingsStore.Load();
                if (value != null) {
                    if (value.MusicInput != null) inputPath.Text = value.MusicInput;
                    if (value.MusicOutput != null) outputPath.Text = value.MusicOutput;
                    if (value.ImageInput != null) imageInputPath.Text = value.ImageInput;
                    if (value.ImageOutput != null) imageOutputPath.Text = value.ImageOutput;
                    imagePage.ImageWidth.Value = Math.Max(1, Math.Min(32767, value.ImageWidth));
                    imagePage.ImageHeight.Value = Math.Max(1, Math.Min(32767, value.ImageHeight));
                    imagePage.ImageFormat.SelectedItem = value.ImageFormat;
                    if (imagePage.ImageFormat.SelectedIndex < 0) imagePage.ImageFormat.SelectedIndex = 0;
                    try {
                        using (FontFamily family = new FontFamily(value.CaptionFont ?? "SimHei"))
                            if (captionFont.Items.Contains(family.Name)) captionFont.SelectedItem = family.Name;
                    } catch (ArgumentException) { }
                    imagePage.ImageMode.SelectedIndex = value.ImageMode >= 0 && value.ImageMode <= 2 ? value.ImageMode : 0;
                    Color color = Color.FromArgb(value.BackgroundArgb);
                    imagePage.Background = Color.FromArgb(255, color.R, color.G, color.B);
                    if (value.CaptionAudio != null) captionAudio.Text = value.CaptionAudio;
                    if (value.CaptionText != null) captionText.Text = value.CaptionText;
                    if (value.CaptionPcm != null) captionPcm.Text = value.CaptionPcm;
                    if (value.CaptionOutput != null) captionOutput.Text = value.CaptionOutput;
                    if (value.CaptionName != null) captionName.Text = value.CaptionName;
                    if (value.CaptionEngine != null && System.IO.File.Exists(value.CaptionEngine)) captionEngine.Text = value.CaptionEngine;
                    if (value.CaptionModel != null && System.IO.File.Exists(value.CaptionModel)) captionModel.Text = value.CaptionModel;
                    captionEncoding.SelectedIndex = value.CaptionEncoding >= 0 && value.CaptionEncoding < 3 ? value.CaptionEncoding : 0;
                    captionLanguage.SelectedIndex = value.CaptionLanguage >= 0 && value.CaptionLanguage < 3 ? value.CaptionLanguage : 0;
                    captionColor.SelectedIndex = value.CaptionColor >= 0 && value.CaptionColor < 8 ? value.CaptionColor : 0;
                    captionFromText.Checked = value.CaptionFromText; captionFromAudio.Checked = !value.CaptionFromText;
                    captionSimplified.Checked = value.CaptionSimplified;
                    tabs.SelectedIndex = value.ActiveTab >= 0 && value.ActiveTab <= 2 ? value.ActiveTab : 0;
                    ShowCurrentPaths(); UpdatePreview(imagePage);
                    status.Text = "已恢复上次配置，可直接添加素材。";
                }
            } catch (Exception) { status.Text = "配置无法读取，暂用默认设置；重新设置后可保存。"; }
            configurationTimer = new Timer { Interval = 350 };
            configurationTimer.Tick += delegate { SaveConfiguration(); };
            configurationEnabled = true;
            foreach (TextBox field in new TextBox[] { inputPath, outputPath, imageInputPath, imageOutputPath, captionAudio, captionText, captionPcm, captionOutput, captionName, captionEngine, captionModel }) {
                field.TextChanged += delegate { ScheduleConfigurationSave(); };
                field.Leave += delegate { SaveConfiguration(); };
            }
            imagePage.ImageMode.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            imagePage.ImageWidth.ValueChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            imagePage.ImageHeight.ValueChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            imagePage.ImageFormat.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionFont.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionColor.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            tabs.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionEncoding.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionLanguage.SelectedIndexChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionFromText.CheckedChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            captionSimplified.CheckedChanged += delegate { configurationDirty = true; SaveConfiguration(); };
            Disposed += delegate { if (configurationTimer != null) configurationTimer.Dispose(); };
        }
        void ScheduleConfigurationSave() {
            if (!configurationEnabled) return;
            configurationDirty = true; configurationTimer.Stop(); configurationTimer.Start();
        }
        bool SaveConfiguration(bool force = false) {
            if (!configurationEnabled) return false;
            configurationTimer.Stop();
            if (!configurationDirty && !force) return true;
            try {
                SettingsStore.Save(new ConverterSettings {
                    MusicInput = inputPath.Text, MusicOutput = outputPath.Text,
                    ImageInput = imageInputPath.Text, ImageOutput = imageOutputPath.Text,
                    ImageWidth = (int)imagePage.ImageWidth.Value, ImageHeight = (int)imagePage.ImageHeight.Value,
                    ImageFormat = (string)imagePage.ImageFormat.SelectedItem, CaptionFont = (string)captionFont.SelectedItem,
                    ImageMode = imagePage.ImageMode.SelectedIndex, BackgroundArgb = imagePage.Background.ToArgb(),
                    ActiveTab = tabs.SelectedIndex,
                    CaptionAudio = captionAudio.Text, CaptionText = captionText.Text, CaptionPcm = captionPcm.Text,
                    CaptionOutput = captionOutput.Text, CaptionName = captionName.Text, CaptionEngine = captionEngine.Text, CaptionModel = captionModel.Text,
                    CaptionEncoding = captionEncoding.SelectedIndex, CaptionLanguage = captionLanguage.SelectedIndex, CaptionColor = captionColor.SelectedIndex,
                    CaptionFromText = captionFromText.Checked, CaptionSimplified = captionSimplified.Checked
                });
                configurationDirty = false; return true;
            } catch (Exception ex) {
                status.Text = "配置保存失败：" + ex.Message; return false;
            }
        }
    }
}
