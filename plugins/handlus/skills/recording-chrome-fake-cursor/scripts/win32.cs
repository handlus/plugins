// win32.cs - Windows side of the Chrome window recording (recording-chrome-fake-cursor skill).
// Loaded by rec.ps1 with Add-Type (C# 5, .NET Framework 4.x compiler that ships with Windows PowerShell 5.1).
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
    public static string LastError = "";
    public static int RunFfmpeg(string exe, string args, int timeoutMs)
    {
        var psi = new ProcessStartInfo(exe, args);
        psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
        psi.RedirectStandardInput = true; psi.CreateNoWindow = true;
        var err = new StringBuilder();
        var p = new Process(); p.StartInfo = psi;
        p.ErrorDataReceived += delegate (object s, DataReceivedEventArgs e) { if (e.Data != null) lock (err) err.AppendLine(e.Data); };
        p.Start();
        p.BeginErrorReadLine();
        bool started = false;
        var sw = Stopwatch.StartNew();
        string line;
        while ((line = p.StandardOutput.ReadLine()) != null)
        {
            if (!started && line.StartsWith("frame="))
            {
                long n; if (long.TryParse(line.Substring(6).Trim(), out n) && n > 0)
                {
                    started = true;
                    Console.WriteLine("rec_started " + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                    Console.Out.Flush();
                }
            }
            if (sw.ElapsedMilliseconds > timeoutMs) { try { p.StandardInput.Write("q"); p.StandardInput.Flush(); } catch { } }
        }
        if (!p.WaitForExit(Math.Max(15000, timeoutMs))) { try { p.Kill(); } catch { } }
        p.WaitForExit();
        lock (err) LastError = err.ToString();
        return p.ExitCode;
    }
}
