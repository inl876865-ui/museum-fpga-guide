using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace FpgaMedia {
    // Windows Media Foundation COM ABI, from Microsoft mfapi/mfobjects/mfreadwrite.
    internal static class NativeAudio {
        const uint AudioStream = 0xFFFFFFFD, AllStreams = 0xFFFFFFFE;
        static readonly Guid Major = new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
        static readonly Guid Subtype = new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
        static readonly Guid Audio = new Guid("73647561-0000-0010-8000-00aa00389b71");
        static readonly Guid Pcm = new Guid("00000001-0000-0010-8000-00aa00389b71");
        static readonly Guid Rate = new Guid("5faeeae7-0290-4c31-9e8a-c534f68d9dba");
        static readonly Guid Channels = new Guid("37e48bf5-645e-4c5b-89de-ada9e29b696a");
        static readonly Guid Bits = new Guid("f2deb57f-40fa-4764-aa33-ed4f2d1ff669");
        static readonly Guid Alignment = new Guid("322de230-9eeb-43bd-ab7a-ff412251541d");
        static readonly Guid ByteRate = new Guid("1aab75c8-cfef-451c-ab95-ac034b8e1731");
        static readonly Guid Duration = new Guid("6c990d33-bb8e-477a-8598-0d5d96fcd88a");
        [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p, uint flags);
        [DllImport("ole32.dll")] static extern void CoUninitialize();
        [DllImport("mfplat.dll")] static extern int MFStartup(uint version, uint flags);
        [DllImport("mfplat.dll")] static extern int MFShutdown();
        [DllImport("mfplat.dll")] static extern int MFCreateMediaType(out IntPtr mediaType);
        [DllImport("mfreadwrite.dll", CharSet = CharSet.Unicode)]
        static extern int MFCreateSourceReaderFromURL(string path, IntPtr attributes, out IntPtr reader);
        [StructLayout(LayoutKind.Explicit, Size = 24)]
        struct PropVariant {
            [FieldOffset(0)] public ushort Type;
            [FieldOffset(8)] public long Value;
        }
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int SetGuid(IntPtr p, ref Guid key, ref Guid value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int SetUInt(IntPtr p, ref Guid key, uint value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetUInt(IntPtr p, ref Guid key, out uint value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int SelectStream(IntPtr p, uint stream, int selected);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int SetType(IntPtr p, uint stream, IntPtr reserved, IntPtr type);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetCurrentType(IntPtr p, uint stream, out IntPtr type);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int Read(IntPtr p, uint stream, uint control, out uint actual, out uint flags,
                          out long timestamp, out IntPtr sample);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetBuffer(IntPtr p, out IntPtr buffer);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int LockBuffer(IntPtr p, out IntPtr data, out uint maximum, out uint length);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int UnlockBuffer(IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetAttribute(IntPtr p, uint stream, ref Guid key, out PropVariant value);

        static T Method<T>(IntPtr p, int slot) where T : class {
            IntPtr table = Marshal.ReadIntPtr(p);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(
                Marshal.ReadIntPtr(table, slot * IntPtr.Size), typeof(T));
        }
        static void Check(int code) {
            if (code < 0) Marshal.ThrowExceptionForHR(code);
        }
        static void Release(ref IntPtr p) {
            if (p != IntPtr.Zero) { Marshal.Release(p); p = IntPtr.Zero; }
        }
        static void SetNumber(IntPtr type, Guid key, uint value) {
            Check(Method<SetUInt>(type, 21)(type, ref key, value));
        }
        static uint Number(IntPtr type, Guid key) {
            uint value; Check(Method<GetUInt>(type, 7)(type, ref key, out value)); return value;
        }

        public static long Convert(string source, string target, CancellationToken cancel, Action<int> progress) {
            IntPtr reader = IntPtr.Zero, type = IntPtr.Zero, actualType = IntPtr.Zero;
            bool com = false, platform = false;
            try {
                int initialized = CoInitializeEx(IntPtr.Zero, 0);
                // A WinForms/CLI STA may already be initialized; use that apartment.
                if (initialized != unchecked((int)0x80010106)) { Check(initialized); com = true; }
                Check(MFStartup(0x20070, 0)); platform = true;
                Check(MFCreateSourceReaderFromURL(source, IntPtr.Zero, out reader));
                Check(Method<SelectStream>(reader, 4)(reader, AllStreams, 0));
                Check(Method<SelectStream>(reader, 4)(reader, AudioStream, 1));
                Check(MFCreateMediaType(out type));
                Guid key = Major, value = Audio;
                Check(Method<SetGuid>(type, 24)(type, ref key, ref value));
                key = Subtype; value = Pcm;
                Check(Method<SetGuid>(type, 24)(type, ref key, ref value));
                SetNumber(type, Rate, 48000); SetNumber(type, Channels, 1);
                SetNumber(type, Bits, 16); SetNumber(type, Alignment, 2);
                SetNumber(type, ByteRate, 96000);
                Check(Method<SetType>(reader, 7)(reader, AudioStream, IntPtr.Zero, type));
                Check(Method<GetCurrentType>(reader, 6)(reader, AudioStream, out actualType));
                if (Number(actualType, Rate) != 48000 || Number(actualType, Channels) != 1 ||
                    Number(actualType, Bits) != 16 || Number(actualType, Alignment) != 2)
                    throw new InvalidDataException("Windows 未能生成指定的 48 kHz 单声道 16 位格式。");
                PropVariant duration; key = Duration;
                int durationResult = Method<GetAttribute>(reader, 12)(reader, 0xFFFFFFFF, ref key, out duration);
                long totalTime = durationResult >= 0 && duration.Type == 21 ? duration.Value : 0;
                long written = 0; int lastProgress = -1, emptySamples = 0;
                Read read = Method<Read>(reader, 9);
                using (FileStream output = new FileStream(target, FileMode.CreateNew, FileAccess.Write)) {
                    while (true) {
                        cancel.ThrowIfCancellationRequested();
                        uint stream, flags; long time; IntPtr sample;
                        Check(read(reader, AudioStream, 0, out stream, out flags, out time, out sample));
                        try {
                            if ((flags & 1) != 0) throw new InvalidDataException("音频解码失败。");
                            if ((flags & 0x20) != 0) throw new InvalidDataException("音频中途改变格式，已停止转换。");
                            if (sample != IntPtr.Zero) {
                                emptySamples = 0; IntPtr buffer = IntPtr.Zero;
                                try {
                                    Check(Method<GetBuffer>(sample, 41)(sample, out buffer));
                                    IntPtr data; uint max, length;
                                    Check(Method<LockBuffer>(buffer, 3)(buffer, out data, out max, out length));
                                    try {
                                        if (length % 2 != 0) throw new InvalidDataException("音频样本未按16位对齐。");
                                        byte[] bytes = new byte[length]; Marshal.Copy(data, bytes, 0, bytes.Length);
                                        output.Write(bytes, 0, bytes.Length); written += length;
                                        if (written > uint.MaxValue - 1L)
                                            throw new InvalidDataException("音频超过当前播放器的4 GB文件上限。");
                                    } finally { Check(Method<UnlockBuffer>(buffer, 4)(buffer)); }
                                } finally { Release(ref buffer); }
                                int percent = totalTime > 0 ? (int)Math.Min(99, Math.Max(0, time * 100 / totalTime)) : 0;
                                if (percent != lastProgress) { progress(percent); lastProgress = percent; }
                            } else if (++emptySamples > 10000) throw new InvalidDataException("音频长时间未提供有效数据。");
                            if ((flags & 2) != 0) break;
                        } finally { Release(ref sample); }
                    }
                }
                if (written == 0) throw new InvalidDataException("文件没有可用音频。");
                progress(100); return written;
            } catch (COMException ex) {
                throw new InvalidDataException("Windows 无法解码这份音频。请确认文件未损坏且没有播放保护。错误码：0x" +
                    ex.ErrorCode.ToString("X8"), ex);
            } catch (DllNotFoundException ex) {
                throw new InvalidOperationException("此 Windows 缺少媒体组件。N/KN 版需先启用微软 Media Feature Pack。", ex);
            } finally {
                Release(ref actualType); Release(ref type); Release(ref reader);
                if (platform) MFShutdown(); if (com) CoUninitialize();
            }
        }
    }
}
