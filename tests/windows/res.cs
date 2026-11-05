// res.cs - change the runner's display resolution and display scale (tests only)
using System; using System.Runtime.InteropServices;
public static class Res {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
  public static string Modes() { var sb = new System.Text.StringBuilder(); var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); for (int i = 0; EnumDisplaySettings(null, i, ref dm); i++) sb.Append(dm.dmPelsWidth + "x" + dm.dmPelsHeight + " "); return sb.ToString(); }
  public static int Set(int w, int h) { var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); EnumDisplaySettings(null, -1, ref dm); dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x80000 | 0x100000; return ChangeDisplaySettings(ref dm, 0); }

  // Display scale, live, the way the Settings app does it (DisplayConfigSetDeviceInfo type -4, not in the SDK headers).
  // Scale steps are relative to the recommended one: rel 0 = recommended, +1 = next step up.
  static readonly int[] Steps = { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };
  [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
  [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint np, byte[] paths, ref uint nm, byte[] modes, IntPtr topo);
  [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(byte[] packet);
  [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(byte[] packet);
  static byte[] Source() {
    uint np, nm; GetDisplayConfigBufferSizes(2, out np, out nm);
    var paths = new byte[np * 72]; var modes = new byte[nm * 64];
    int r = QueryDisplayConfig(2, ref np, paths, ref nm, modes, IntPtr.Zero);
    if (r != 0 || np == 0) throw new Exception("QueryDisplayConfig " + r);
    var src = new byte[12]; Array.Copy(paths, 0, src, 0, 12); return src;   // adapter LUID (8) + source id (4) of the first path
  }
  // Returns "min cur max recommended" in percent
  public static string Scale() {
    var p = new byte[32]; var src = Source();
    BitConverter.GetBytes(-3).CopyTo(p, 0); BitConverter.GetBytes(32).CopyTo(p, 4); Array.Copy(src, 0, p, 8, 12);
    int r = DisplayConfigGetDeviceInfo(p); if (r != 0) return "get failed " + r;
    int min = BitConverter.ToInt32(p, 20), cur = BitConverter.ToInt32(p, 24), max = BitConverter.ToInt32(p, 28);
    int rec = Math.Abs(min);
    Func<int, string> pc = i => (i >= 0 && i < Steps.Length) ? Steps[i].ToString() : "?";
    return "min=" + pc(rec + min) + " cur=" + pc(rec + cur) + " max=" + pc(rec + max) + " recommended=" + pc(rec);
  }
  public static int SetScale(int percent) {
    var p = new byte[32]; var src = Source();
    BitConverter.GetBytes(-3).CopyTo(p, 0); BitConverter.GetBytes(32).CopyTo(p, 4); Array.Copy(src, 0, p, 8, 12);
    int r = DisplayConfigGetDeviceInfo(p); if (r != 0) return r;
    int rec = Math.Abs(BitConverter.ToInt32(p, 20));
    int want = Array.IndexOf(Steps, percent); if (want < 0) return -1;
    var q = new byte[24];
    BitConverter.GetBytes(-4).CopyTo(q, 0); BitConverter.GetBytes(24).CopyTo(q, 4); Array.Copy(src, 0, q, 8, 12);
    BitConverter.GetBytes(want - rec).CopyTo(q, 20);
    return DisplayConfigSetDeviceInfo(q);
  }
}
