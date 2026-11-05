// win32.cs - Windows side of the Chrome window recording (recording-chrome-fake-cursor skill).
// Loaded by rec.ps1 with Add-Type (C# 5, .NET Framework 4.x compiler that ships with Windows PowerShell 5.1).
//   HandlusRec  displays, Chrome windows, placing a window (Win32)
//   HandlusWgc  records one window with Windows.Graphics.Capture and pipes the frames to ffmpeg, which only encodes.
//               ffmpeg's own gfxcapture needs a D3D11 *video* device, which machines without a GPU driver
//               (virtual machines, cloud PCs, CI runners) do not have; this recorder falls back to the WARP software device.
// Every public method switches the calling thread to per-monitor DPI awareness first, so all coordinates
// are physical pixels (without it Windows hands out scaled, virtualised rectangles on 125% / 150% displays).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class HandlusRec
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L, T, R, B; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFOEX
    {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }

    delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    delegate bool MonitorEnumProc(IntPtr hMon, IntPtr hdc, IntPtr rc, IntPtr l);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int n);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] static extern int DwmGetWindowAttributeInt(IntPtr h, int a, out int v, int n);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfoW(IntPtr h, ref MONITORINFOEX mi);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr h, int t, out uint x, out uint y);

    public class Win
    {
        public long Hwnd; public uint Pid; public string Title; public string Cls;
        public RECT Rect;   // GetWindowRect (includes the invisible resize border, if any)
        public RECT Frame;  // DWM extended frame bounds = what you see
        public bool Visible, Cloaked, Iconic, Zoomed;
        public int X { get { return Frame.L; } }
        public int Y { get { return Frame.T; } }
        public int W { get { return Frame.R - Frame.L; } }
        public int H { get { return Frame.B - Frame.T; } }
    }

    public class Monitor
    {
        public string Name; public bool Primary; public double Scale;
        public RECT Bounds; public RECT Work;
    }

    public static void Dpi()
    {
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch { }   // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
    }

    static RECT FrameOf(IntPtr h, RECT fallback)
    {
        RECT f;
        if (DwmGetWindowAttribute(h, 9, out f, Marshal.SizeOf(typeof(RECT))) == 0) return f;   // DWMWA_EXTENDED_FRAME_BOUNDS
        return fallback;
    }

    public static Win Describe(long hwnd)
    {
        Dpi();
        IntPtr h = new IntPtr(hwnd);
        var t = new StringBuilder(512); GetWindowTextW(h, t, t.Capacity);
        var c = new StringBuilder(256); GetClassNameW(h, c, c.Capacity);
        uint pid; GetWindowThreadProcessId(h, out pid);
        RECT r; GetWindowRect(h, out r);
        int cloak; DwmGetWindowAttributeInt(h, 14, out cloak, 4);   // DWMWA_CLOAKED
        var w = new Win();
        w.Hwnd = hwnd; w.Pid = pid; w.Title = t.ToString(); w.Cls = c.ToString(); w.Rect = r; w.Frame = FrameOf(h, r);
        w.Visible = IsWindowVisible(h); w.Cloaked = cloak != 0; w.Iconic = IsIconic(h); w.Zoomed = IsZoomed(h);
        return w;
    }

    // Top-level windows of a class, front to back (EnumWindows walks the z-order from the top)
    public static List<Win> Windows(string cls)
    {
        Dpi();
        var hs = new List<IntPtr>();
        EnumWindowsProc cb = delegate (IntPtr h, IntPtr l) { hs.Add(h); return true; };
        EnumWindows(cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        var list = new List<Win>();
        foreach (var h in hs)
        {
            var c = new StringBuilder(256); GetClassNameW(h, c, c.Capacity);
            if (cls != null && c.ToString() != cls) continue;
            list.Add(Describe(h.ToInt64()));
        }
        return list;
    }

    public static List<Monitor> Monitors()
    {
        Dpi();
        var hs = new List<IntPtr>();
        MonitorEnumProc cb = delegate (IntPtr m, IntPtr dc, IntPtr rc, IntPtr l) { hs.Add(m); return true; };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        var list = new List<Monitor>();
        foreach (var h in hs)
        {
            var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (!GetMonitorInfoW(h, ref mi)) continue;
            uint dx = 96, dy = 96;
            try { GetDpiForMonitor(h, 0, out dx, out dy); } catch { }
            var m = new Monitor();
            m.Name = (mi.szDevice ?? "").Replace("\\\\.\\", "");
            m.Primary = (mi.dwFlags & 1) != 0; m.Scale = dx / 96.0; m.Bounds = mi.rcMonitor; m.Work = mi.rcWork;
            list.Add(m);
        }
        return list;
    }

    // Put the window so that its VISIBLE frame is exactly x,y,w,h (corrects for invisible resize borders)
    public static string Place(long hwnd, int x, int y, int w, int h)
    {
        Dpi();
        IntPtr hw = new IntPtr(hwnd);
        if (IsIconic(hw) || IsZoomed(hw)) { ShowWindow(hw, 9); Thread.Sleep(300); }   // SW_RESTORE
        const uint SWP_NOZORDER = 0x0004, SWP_SHOWWINDOW = 0x0040, SWP_NOACTIVATE = 0x0010;
        for (int i = 0; i < 3; i++)
        {
            RECT r; GetWindowRect(hw, out r);
            RECT f = FrameOf(hw, r);
            int bl = f.L - r.L, bt = f.T - r.T, br = r.R - f.R, bb = r.B - f.B;
            SetWindowPos(hw, IntPtr.Zero, x - bl, y - bt, w + bl + br, h + bt + bb, SWP_NOZORDER | SWP_SHOWWINDOW | SWP_NOACTIVATE);
            Thread.Sleep(250);
            var now = Describe(hwnd);
            if (now.X == x && now.Y == y && now.W == w && now.H == h) break;
        }
        return Raise(hwnd) ? "fg=yes" : "fg=no";
    }

    // Bring to the front. Windows may refuse (foreground lock) when the caller is not the foreground app;
    // an ALT tap is the documented way to be allowed to set the foreground window.
    public static bool Raise(long hwnd)
    {
        Dpi();
        IntPtr hw = new IntPtr(hwnd);
        SetWindowPos(hw, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);   // HWND_TOP, NOSIZE | NOMOVE | SHOWWINDOW
        BringWindowToTop(hw);
        if (SetForegroundWindow(hw) && GetForegroundWindow() == hw) return true;
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);   // ALT down, up
        SetForegroundWindow(hw);
        Thread.Sleep(150);
        return GetForegroundWindow() == hw;
    }

    // Runs ffmpeg with -progress pipe:1; prints "rec_started <epoch ms>" when the first frame is out.
    // stderr is collected (not printed) and returned through lastError. Returns the exit code.
}

// Records one window with Windows.Graphics.Capture (Windows 10 1903+), the same API the Snipping Tool and OBS use:
// only that window's own pixels, so windows partly over it do not appear. Frames are read back to the CPU and written
// to ffmpeg's stdin as raw BGRA at a steady 60 per second (the last frame is repeated while the page does not change,
// as macOS ScreenCaptureKit does), so the video keeps real time. All COM / WinRT calls go through vtable slots.
public static class HandlusWgc
{
    [StructLayout(LayoutKind.Sequential)]
    struct TEX2D { public uint Width, Height, MipLevels, ArraySize, Format, SampleCount, SampleQuality, Usage, BindFlags, CPUAccessFlags, MiscFlags; }
    [StructLayout(LayoutKind.Sequential)]
    struct MAPPED { public IntPtr pData; public uint RowPitch; public uint DepthPitch; }

    [DllImport("d3d11.dll")] static extern int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags, IntPtr levels, uint nLevels, uint sdk, out IntPtr device, out int level, out IntPtr context);
    [DllImport("d3d11.dll")] static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);
    [DllImport("combase.dll")] static extern int RoGetActivationFactory(IntPtr classId, ref Guid iid, out IntPtr factory);
    [DllImport("combase.dll")] static extern int RoInitialize(int type);
    [DllImport("combase.dll", CharSet = CharSet.Unicode)] static extern int WindowsCreateString(string s, int len, out IntPtr hs);
    [DllImport("combase.dll")] static extern int WindowsDeleteString(IntPtr hs);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int QIFn(IntPtr self, ref Guid iid, out IntPtr ppv);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate uint ReleaseFn(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateForWindowFn(IntPtr self, IntPtr hwnd, ref Guid iid, out IntPtr item);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetLongFn(IntPtr self, out long v);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetByteFn(IntPtr self, out byte v);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int PutByteFn(IntPtr self, byte v);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateFreeThreadedFn(IntPtr self, IntPtr device, int fmt, int buffers, long size, out IntPtr pool);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetPtrFn(IntPtr self, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateSessionFn(IntPtr self, IntPtr item, out IntPtr session);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int NoArgFn(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetInterfaceFn(IntPtr self, ref Guid iid, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void GetDescFn(IntPtr self, out TEX2D d);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateTexture2DFn(IntPtr self, ref TEX2D d, IntPtr init, out IntPtr tex);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void CopyResourceFn(IntPtr self, IntPtr dst, IntPtr src);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int MapFn(IntPtr self, IntPtr res, uint sub, int type, uint flags, out MAPPED m);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate void UnmapFn(IntPtr self, IntPtr res, uint sub);

    static Guid IID_IDXGIDevice = new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
    static Guid IID_IDirect3DDevice = new Guid("a37624ab-8d5f-4650-9d3e-9eaae3d9f42f");
    static Guid IID_ItemInterop = new Guid("3628e81b-3cac-4c60-b7f4-23ce0e0c3356");
    static Guid IID_Item = new Guid("79c3f95b-31f7-4ec2-a464-632ef5d30760");
    static Guid IID_PoolStatics2 = new Guid("589b103f-6bbc-5df5-a991-02e28b3b66d5");
    static Guid IID_SessionStatics = new Guid("2224a540-5974-49aa-b232-0882536f4cb5");
    static Guid IID_Session2 = new Guid("2c39ae40-7d2e-5044-804e-8b6799d4cf9e");
    static Guid IID_Session3 = new Guid("f2cdd966-22ae-5ea1-9596-3a289344c3be");
    static Guid IID_Closable = new Guid("30d5a829-7fa4-4026-83bb-d75bae4ea99e");
    static Guid IID_DxgiAccess = new Guid("a9b3d012-3df2-4ee3-b8d1-8695f457d3c1");
    static Guid IID_Texture2D = new Guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c");

    static T Fn<T>(IntPtr obj, int slot) where T : class
    {
        IntPtr vt = Marshal.ReadIntPtr(obj);
        return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vt, slot * IntPtr.Size), typeof(T));
    }
    static void Check(int hr, string what) { if (hr < 0) throw new Exception(what + " failed (0x" + hr.ToString("x8") + ")"); }
    static IntPtr QI(IntPtr obj, Guid iid) { IntPtr p; int hr = Fn<QIFn>(obj, 0)(obj, ref iid, out p); return hr < 0 ? IntPtr.Zero : p; }
    static void Release(IntPtr obj) { if (obj != IntPtr.Zero) Fn<ReleaseFn>(obj, 2)(obj); }
    static void Close(IntPtr obj)
    {
        if (obj == IntPtr.Zero) return;
        IntPtr c = QI(obj, IID_Closable);
        if (c != IntPtr.Zero) { Fn<NoArgFn>(c, 6)(c); Release(c); }
    }
    static IntPtr Factory(string cls, Guid iid)
    {
        IntPtr hs; Check(WindowsCreateString(cls, cls.Length, out hs), "WindowsCreateString");
        try { IntPtr f; Check(RoGetActivationFactory(hs, ref iid, out f), "RoGetActivationFactory " + cls); return f; }
        finally { WindowsDeleteString(hs); }
    }

    public static string Device = "";       // "hardware" or "warp (software)"
    public static string Stats = "";        // frames written / new frames from Windows / frames written late
    public static string FfmpegError = "";

    // Returns 0 ok, 2 capture failed, 3 ffmpeg failed. Prints "size WxH", "rec_started <epoch ms>", "saved <out>".
    public static int Record(long hwnd, double seconds, string ffmpeg, string encodeArgs, string outPath)
    {
        int rc = 2;
        Exception err = null;
        var t = new Thread(delegate () {
            try { rc = Run(hwnd, seconds, ffmpeg, encodeArgs, outPath); }
            catch (Exception e) { err = e; }
        });
        t.SetApartmentState(ApartmentState.MTA);
        t.Start(); t.Join();
        if (err != null) { Console.Error.WriteLine("STOP: window capture: " + err.Message); return 2; }
        return rc;
    }

    static int Run(long hwnd, double seconds, string ffmpeg, string encodeArgs, string outPath)
    {
        HandlusRec.Dpi();
        RoInitialize(1);
        IntPtr dev = IntPtr.Zero, ctx = IntPtr.Zero, dxgi = IntPtr.Zero, d3dDevice = IntPtr.Zero, item = IntPtr.Zero;
        IntPtr pool = IntPtr.Zero, session = IntPtr.Zero, staging = IntPtr.Zero;
        Process ff = null;
        timeBeginPeriod(1);
        try
        {
            // Is window capture available at all?
            IntPtr ss = Factory("Windows.Graphics.Capture.GraphicsCaptureSession", IID_SessionStatics);
            byte supported; Check(Fn<GetByteFn>(ss, 6)(ss, out supported), "GraphicsCaptureSession.IsSupported"); Release(ss);
            if (supported == 0) throw new Exception("Windows.Graphics.Capture is not supported here (needs Windows 10 1903 or later with a desktop)");

            // D3D11 device: the GPU, or WARP (software) when there is no GPU driver
            int level; int hr = D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out dev, out level, out ctx);
            Device = "hardware";
            if (hr < 0) { Check(D3D11CreateDevice(IntPtr.Zero, 5, IntPtr.Zero, 0x20, IntPtr.Zero, 0, 7, out dev, out level, out ctx), "D3D11CreateDevice (WARP)"); Device = "warp (software)"; }
            dxgi = QI(dev, IID_IDXGIDevice); if (dxgi == IntPtr.Zero) throw new Exception("IDXGIDevice not available");
            IntPtr insp; Check(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out insp), "CreateDirect3D11DeviceFromDXGIDevice");
            d3dDevice = QI(insp, IID_IDirect3DDevice); Release(insp);
            if (d3dDevice == IntPtr.Zero) throw new Exception("IDirect3DDevice not available");

            // Capture item for the window
            IntPtr interop = Factory("Windows.Graphics.Capture.GraphicsCaptureItem", IID_ItemInterop);
            Check(Fn<CreateForWindowFn>(interop, 3)(interop, new IntPtr(hwnd), ref IID_Item, out item), "GraphicsCaptureItem for window " + hwnd);
            Release(interop);
            long size; Check(Fn<GetLongFn>(item, 7)(item, out size), "GraphicsCaptureItem.Size");
            int cw = (int)(size & 0xffffffff), ch = (int)(size >> 32);
            int w = cw & ~1, h = ch & ~1;
            if (w < 16 || h < 16) throw new Exception("window is too small or minimized (" + cw + "x" + ch + ")");

            IntPtr ps = Factory("Windows.Graphics.Capture.Direct3D11CaptureFramePool", IID_PoolStatics2);
            Check(Fn<CreateFreeThreadedFn>(ps, 6)(ps, d3dDevice, 87, 2, size, out pool), "Direct3D11CaptureFramePool.CreateFreeThreaded");
            Release(ps);
            Check(Fn<CreateSessionFn>(pool, 10)(pool, item, out session), "CreateCaptureSession");
            IntPtr s2 = QI(session, IID_Session2);   // no real mouse pointer in the video (Windows 10 2004+)
            if (s2 != IntPtr.Zero) { Fn<PutByteFn>(s2, 7)(s2, 0); Release(s2); }
            IntPtr s3 = QI(session, IID_Session3);   // no yellow frame on screen where Windows allows turning it off (Windows 11)
            if (s3 != IntPtr.Zero) { Fn<PutByteFn>(s3, 7)(s3, 0); Release(s3); }

            // ffmpeg reads raw frames at 60 per second and encodes them
            string args = "-hide_banner -loglevel error -y -f rawvideo -pix_fmt bgra -video_size " + w + "x" + h + " -framerate 60 -i - " + encodeArgs + " \"" + outPath + "\"";
            var psi = new ProcessStartInfo(ffmpeg, args);
            psi.UseShellExecute = false; psi.RedirectStandardInput = true; psi.RedirectStandardError = true; psi.RedirectStandardOutput = true; psi.CreateNoWindow = true;
            var ferr = new StringBuilder();
            FfmpegError = "";
            ff = new Process(); ff.StartInfo = psi;
            ff.ErrorDataReceived += delegate (object o, DataReceivedEventArgs e) { if (e.Data != null) lock (ferr) { ferr.AppendLine(e.Data); FfmpegError = ferr.ToString(); } };
            ff.OutputDataReceived += delegate (object o, DataReceivedEventArgs e) { };
            ff.Start(); ff.BeginErrorReadLine(); ff.BeginOutputReadLine();
            Stream sin = ff.StandardInput.BaseStream;

            Check(Fn<NoArgFn>(session, 6)(session), "StartCapture");
            Console.WriteLine("size " + w + "x" + h + "  device=" + Device);

            byte[] buf = new byte[w * h * 4];
            long total = (long)Math.Round(seconds * 60), written = 0, fresh = 0, late = 0;
            bool have = false;
            var sw = Stopwatch.StartNew();
            long startTicks = 0;
            GetPtrFn tryNext = Fn<GetPtrFn>(pool, 7);
            while (written < total)
            {
                // newest frame from Windows (there is none while the page does not change)
                IntPtr latest = IntPtr.Zero, f;
                while (tryNext(pool, out f) >= 0 && f != IntPtr.Zero) { if (latest != IntPtr.Zero) { Close(latest); Release(latest); } latest = f; }
                if (latest != IntPtr.Zero)
                {
                    IntPtr surf; Check(Fn<GetPtrFn>(latest, 6)(latest, out surf), "frame.Surface");
                    IntPtr acc = QI(surf, IID_DxgiAccess); Release(surf);
                    IntPtr tex; Check(Fn<GetInterfaceFn>(acc, 3)(acc, ref IID_Texture2D, out tex), "IDirect3DDxgiInterfaceAccess"); Release(acc);
                    if (staging == IntPtr.Zero)
                    {
                        TEX2D d; Fn<GetDescFn>(tex, 10)(tex, out d);
                        d.MipLevels = 1; d.ArraySize = 1; d.SampleCount = 1; d.SampleQuality = 0;
                        d.Usage = 3; d.BindFlags = 0; d.CPUAccessFlags = 0x20000; d.MiscFlags = 0;
                        Check(Fn<CreateTexture2DFn>(dev, 5)(dev, ref d, IntPtr.Zero, out staging), "CreateTexture2D (staging)");
                    }
                    Fn<CopyResourceFn>(ctx, 47)(ctx, staging, tex);
                    Release(tex); Close(latest); Release(latest);
                    MAPPED m; Check(Fn<MapFn>(ctx, 14)(ctx, staging, 0, 1, 0, out m), "Map");
                    int row = w * 4;
                    for (int y = 0; y < h; y++) Marshal.Copy(new IntPtr(m.pData.ToInt64() + (long)y * m.RowPitch), buf, y * row, row);
                    Fn<UnmapFn>(ctx, 15)(ctx, staging, 0);
                    fresh++;
                    if (!have) { have = true; startTicks = sw.ElapsedTicks; Console.WriteLine("rec_started " + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()); Console.Out.Flush(); }
                }
                if (!have)
                {
                    if (sw.ElapsedMilliseconds > 5000) throw new Exception("no frame from the window in 5 s (is it minimized or on a disconnected display?)");
                    Thread.Sleep(1); continue;
                }
                // frames due by now on a 60 per second clock; when a write was slow, catch up with repeats
                long due = (long)((sw.ElapsedTicks - startTicks) * 60.0 / Stopwatch.Frequency) + 1;
                if (due > total) due = total;
                if (due - written > 1) late += due - written - 1;
                while (written < due) { sin.Write(buf, 0, buf.Length); written++; }
                Thread.Sleep(1);
            }
            sin.Flush(); sin.Close();
            Close(session); Release(session); session = IntPtr.Zero;
            Close(pool); Release(pool); pool = IntPtr.Zero;
            if (!ff.WaitForExit(120000)) { try { ff.Kill(); } catch { } }
            ff.WaitForExit();
            lock (ferr) FfmpegError = ferr.ToString();
            Stats = "frames " + written + "  new " + fresh + "  late " + late;
            Console.WriteLine(Stats);
            if (ff.ExitCode != 0) { Console.Error.WriteLine("STOP: ffmpeg exit " + ff.ExitCode); Console.Error.WriteLine(FfmpegError.Trim()); return 3; }
            return 0;
        }
        catch (IOException e)
        {
            if (ff != null) { try { ff.WaitForExit(5000); } catch { } }
            Console.Error.WriteLine("STOP: ffmpeg stopped reading the frames (" + e.Message + ")");
            Console.Error.WriteLine(FfmpegError.Trim());
            return 3;
        }
        finally
        {
            timeEndPeriod(1);
            if (ff != null) { try { if (!ff.HasExited) ff.Kill(); } catch { } }
            if (session != IntPtr.Zero) { Close(session); Release(session); }
            if (pool != IntPtr.Zero) { Close(pool); Release(pool); }
            Release(staging); Release(item); Release(d3dDevice); Release(dxgi); Release(ctx); Release(dev);
        }
    }
}
