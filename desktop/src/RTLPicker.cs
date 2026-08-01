// RTL Picker -- desktop companion (Windows), native build.
//
// Same behaviour as the PowerShell version, compiled to a real .exe so there is
// no powershell.exe sitting in Task Manager, no console flash on launch, and no
// multi-second Add-Type compile at startup.
//
//   Ctrl+Alt+D        read the selection in an RTL window  (works ANYWHERE)
//   Ctrl+Alt+R        wrap the selected text as RTL        (editable fields)
//   Ctrl+Alt+L        strip direction marks back out       (editable fields)
//   Ctrl+Alt+B        wrap whatever is on the clipboard
//   Ctrl+Alt+Shift+R  native paragraph direction -> RTL    (Word/WordPad/Outlook)
//   Ctrl+Alt+Shift+L  native paragraph direction -> LTR    (Word/WordPad/Outlook)
//
// Built by tools/build-exe.ps1. Targets C# 5 / .NET Framework 4.x, which is what
// the in-box csc.exe supports -- no string interpolation or ?. operators here.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace RtlPicker
{
    // ------------------------------------------------------------------ native

    internal static class Native
    {
        [DllImport("user32.dll")]
        private static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("kernel32.dll")]
        internal static extern bool AttachConsole(int processId);

        private const uint KEYUP = 0x0002;

        internal const byte VK_CONTROL = 0x11;
        internal const byte VK_SHIFT = 0x10;
        internal const byte VK_LSHIFT = 0xA0;
        internal const byte VK_RSHIFT = 0xA1;
        internal const byte VK_MENU = 0x12;

        private static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
        private static void Up(byte vk) { keybd_event(vk, 0, KEYUP, UIntPtr.Zero); }

        /// The hotkey chord is still physically held when we fire; synthesizing a
        /// new chord on top of Ctrl+Alt produces garbage unless we clear it first.
        internal static void ReleaseModifiers()
        {
            Up(VK_MENU); Up(VK_CONTROL); Up(VK_SHIFT); Up(VK_LSHIFT); Up(VK_RSHIFT);
            Thread.Sleep(40);
        }

        /// Windows' built-in paragraph direction shortcut. RichEdit only.
        internal static void SetParagraphDirection(bool rightToLeft)
        {
            ReleaseModifiers();
            byte shift = rightToLeft ? VK_RSHIFT : VK_LSHIFT;
            Down(VK_CONTROL); Down(shift);
            Thread.Sleep(25);
            Up(shift); Up(VK_CONTROL);
        }

        internal static void CtrlKey(byte vk)
        {
            Down(VK_CONTROL); Down(vk);
            Thread.Sleep(25);
            Up(vk); Up(VK_CONTROL);
        }

        /// Used only for the log, so a failed action can be traced to a target.
        internal static string DescribeForegroundWindow()
        {
            IntPtr h = GetForegroundWindow();
            if (h == IntPtr.Zero) return "(none)";
            StringBuilder title = new StringBuilder(256);
            StringBuilder cls = new StringBuilder(256);
            GetWindowText(h, title, title.Capacity);
            GetClassName(h, cls, cls.Capacity);
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            string name = "?";
            try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }
            catch { }
            return name + " [" + cls + "] \"" + title + "\"";
        }
    }

    internal class HotkeyWindow : NativeWindow, IDisposable
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private const int WM_HOTKEY = 0x0312;
        private readonly List<int> registered = new List<int>();

        public event Action<int> HotkeyPressed;

        public HotkeyWindow() { CreateHandle(new CreateParams()); }

        // MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_NOREPEAT 0x4000
        public bool Register(int id, uint modifiers, uint vk)
        {
            bool ok = RegisterHotKey(Handle, id, modifiers | 0x4000, vk);
            if (ok && !registered.Contains(id)) registered.Add(id);
            return ok;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                Action<int> handler = HotkeyPressed;
                if (handler != null) handler((int)m.WParam);
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            foreach (int id in registered) UnregisterHotKey(Handle, id);
            registered.Clear();
            DestroyHandle();
        }
    }

    // ------------------------------------------------------------------- bidi

    internal static class Bidi
    {
        internal const char RLE = '\u202B'; // right-to-left embedding
        internal const char PDF = '\u202C'; // pop directional formatting

        private static readonly char[] Marks = new char[]
        {
            '\u202A', '\u202B', '\u202C', '\u202D', '\u202E',
            '\u200E', '\u200F', '\u2066', '\u2067', '\u2068', '\u2069'
        };

        // U+0590-U+08FF is one contiguous run of RTL scripts (Hebrew, Arabic,
        // Syriac, Thaana, N'Ko, Samaritan, Mandaic), plus presentation forms.
        private static readonly Regex RtlRe =
            new Regex("[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]", RegexOptions.Compiled);

        private static readonly Regex LtrRe =
            new Regex("[A-Za-z\u00C0-\u02AF\u0370-\u04FF\u1E00-\u1FFF\u3040-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]",
                RegexOptions.Compiled);

        internal static bool IsMark(char c)
        {
            for (int i = 0; i < Marks.Length; i++) if (Marks[i] == c) return true;
            return false;
        }

        internal static string Unwrap(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            StringBuilder sb = new StringBuilder(text.Length);
            foreach (char c in text) if (!IsMark(c)) sb.Append(c);
            return sb.ToString();
        }

        internal static string Wrap(string text, bool perLine)
        {
            if (string.IsNullOrEmpty(text)) return text;
            string clean = Unwrap(text);
            if (!perLine) return RLE + clean + PDF;

            string[] parts = Regex.Split(clean, "(\r\n|\r|\n)");
            StringBuilder sb = new StringBuilder(clean.Length + 8);
            foreach (string part in parts)
            {
                if (part.Length == 0 || part == "\r\n" || part == "\r" || part == "\n") sb.Append(part);
                else sb.Append(RLE).Append(part).Append(PDF);
            }
            return sb.ToString();
        }

        internal static int CountMarks(string text)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int n = 0;
            foreach (char c in text) if (IsMark(c)) n++;
            return n;
        }

        /// Counts strong characters on both sides rather than trusting the first
        /// one, so "The city of <arabic> has many people" stays left-to-right.
        internal static bool IsRightToLeft(string text, double threshold)
        {
            if (string.IsNullOrEmpty(text) || text.Trim().Length == 0) return false;
            int rtl = RtlRe.Matches(text).Count;
            int ltr = LtrRe.Matches(text).Count;
            if (rtl + ltr == 0) return false;
            return ((double)rtl / (rtl + ltr)) >= threshold;
        }

        /// Length, existing mark count, and an escaped head -- so non-Latin text
        /// survives the log file and odd values are obvious.
        internal static string Describe(string text)
        {
            if (text == null) return "<null>";
            if (text.Length == 0) return "<empty>";
            int take = Math.Min(36, text.Length);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < take; i++)
            {
                char c = text[i];
                if (c < 32 || c > 126) sb.Append("\\u").Append(((int)c).ToString("X4"));
                else sb.Append(c);
            }
            return string.Format("len={0} marks={1} head='{2}'", text.Length, CountMarks(text), sb);
        }
    }

    // -------------------------------------------------------------------- log

    internal static class Log
    {
        internal static readonly string Dir =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RTLPicker");

        internal static readonly string File = Path.Combine(Dir, "rtlpicker.log");

        internal static void Write(string message)
        {
            try
            {
                if (!Directory.Exists(Dir)) Directory.CreateDirectory(Dir);
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)
                              + "  " + message + Environment.NewLine;
                System.IO.File.AppendAllText(File, line, Encoding.UTF8);
            }
            catch { }
        }
    }

    // -------------------------------------------------------------- clipboard

    internal static class Clip
    {
        internal static string GetText()
        {
            for (int i = 0; i < 8; i++)
            {
                try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; }
                catch { Thread.Sleep(60); }
            }
            return null;
        }

        internal static bool SetText(string text)
        {
            for (int i = 0; i < 8; i++)
            {
                // The clipboard is shared and lockable -- another app may hold it.
                try { Clipboard.SetText(text); return true; }
                catch { Thread.Sleep(60); }
            }
            return false;
        }

        internal static void Clear()
        {
            for (int i = 0; i < 8; i++)
            {
                try { Clipboard.Clear(); return; }
                catch { Thread.Sleep(60); }
            }
        }
    }

    // ------------------------------------------------------------------ toast

    /// Never steals focus -- taking it would break the selection we are about to
    /// copy. Also replaces balloon tips, which Windows notification settings
    /// silently swallow, which is exactly how a tool ends up looking broken.
    internal class ToastForm : Form
    {
        private readonly Label title = new Label();
        private readonly Label body = new Label();
        // Qualified: System.Threading is also in scope and has its own Timer.
        private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                return cp;
            }
        }

        internal ToastForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.FromArgb(20, 22, 26);
            Size = new Size(360, 78);

            title.ForeColor = Color.White;
            title.Font = new Font("Segoe UI Semibold", 10f);
            title.Location = new Point(14, 12);
            title.Size = new Size(332, 20);
            Controls.Add(title);

            body.ForeColor = Color.FromArgb(154, 163, 174);
            body.Font = new Font("Segoe UI", 8.5f);
            body.Location = new Point(14, 34);
            body.Size = new Size(332, 34);
            Controls.Add(body);

            timer.Interval = 1800;
            timer.Tick += delegate { timer.Stop(); Hide(); };
        }

        internal void Show(string titleText, string bodyText)
        {
            title.Text = titleText;
            body.Text = bodyText;
            Rectangle area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Right - Width - 18, area.Bottom - Height - 18);
            Show();
            BringToFront();
            timer.Stop();
            timer.Start();
        }
    }

    // ----------------------------------------------------------------- reader

    /// The answer to read-only text. Claude's replies, a rendered page and a chat
    /// transcript cannot be edited, so rather than trying to change them we show
    /// a copy here, laid out right-to-left. The source app is never touched.
    internal class ReaderForm : Form
    {
        private readonly RichTextBox box = new RichTextBox();
        private readonly System.Windows.Forms.Timer fade = new System.Windows.Forms.Timer();
        private double fadeStep = 0.14;
        private float fontSize = 14f;

        internal ReaderForm()
        {
            Text = "RTL Reader  --  Esc to close";
            Size = new Size(760, 520);
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            KeyPreview = true;
            ShowInTaskbar = false;
            Opacity = 0;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { }

            box.Dock = DockStyle.Fill;
            box.ReadOnly = true;
            box.BorderStyle = BorderStyle.None;
            box.BackColor = Color.White;
            box.Font = new Font("Segoe UI", fontSize);
            box.ScrollBars = RichTextBoxScrollBars.Vertical;
            Controls.Add(box);

            FlowLayoutPanel bar = new FlowLayoutPanel();
            bar.Dock = DockStyle.Bottom;
            bar.Height = 40;
            bar.Padding = new Padding(6, 5, 6, 5);
            Controls.Add(bar);

            bar.Controls.Add(MakeButton("A-", 36, delegate { SetFontSize(fontSize - 2); }));
            bar.Controls.Add(MakeButton("A+", 36, delegate { SetFontSize(fontSize + 2); }));
            // Escape hatch for the times the ratio test guesses wrong.
            bar.Controls.Add(MakeButton("RTL / LTR", 80, delegate
            {
                box.RightToLeft = box.RightToLeft == RightToLeft.Yes ? RightToLeft.No : RightToLeft.Yes;
            }));
            bar.Controls.Add(MakeButton("Copy", 60, delegate
            {
                Clip.SetText(box.SelectionLength > 0 ? box.SelectedText : box.Text);
            }));
            bar.Controls.Add(MakeButton("Close", 60, delegate { FadeOut(); }));

            Label hint = new Label();
            hint.Text = "Esc closes.  + / - resize.";
            hint.AutoSize = true;
            hint.ForeColor = Color.Gray;
            hint.Padding = new Padding(10, 7, 0, 0);
            bar.Controls.Add(hint);

            KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Escape) { FadeOut(); e.Handled = true; }
                else if (e.KeyCode == Keys.Oemplus || e.KeyCode == Keys.Add) { SetFontSize(fontSize + 2); e.Handled = true; }
                else if (e.KeyCode == Keys.OemMinus || e.KeyCode == Keys.Subtract) { SetFontSize(fontSize - 2); e.Handled = true; }
            };

            // Keep the instance so position, size and font survive between reads.
            FormClosing += delegate(object s, FormClosingEventArgs e)
            {
                if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; FadeOut(); }
            };

            fade.Interval = 15;
            fade.Tick += delegate
            {
                double o = Opacity + fadeStep;
                if (fadeStep > 0 && o >= 1) { o = 1; fade.Stop(); }
                else if (fadeStep < 0 && o <= 0) { o = 0; fade.Stop(); Hide(); }
                Opacity = o;
            };
        }

        private Button MakeButton(string text, int width, EventHandler onClick)
        {
            Button b = new Button();
            b.Text = text;
            b.Width = width;
            b.Height = 26;
            b.Click += onClick;
            return b;
        }

        private void SetFontSize(float size)
        {
            fontSize = Math.Max(9f, Math.Min(32f, size));
            box.Font = new Font("Segoe UI", fontSize);
        }

        private void FadeOut()
        {
            fadeStep = -Math.Abs(fadeStep);
            fade.Start();
        }

        internal void ShowText(string text, double threshold)
        {
            // Strip embedded control marks; the window's own direction drives layout.
            string clean = Bidi.Unwrap(text);
            box.Text = clean;
            box.Select(0, 0);
            box.RightToLeft = Bidi.IsRightToLeft(clean, threshold) ? RightToLeft.Yes : RightToLeft.No;

            fadeStep = Math.Abs(fadeStep);
            Opacity = 0;
            Show();
            Activate();
            fade.Start();
        }
    }

    // ---------------------------------------------------------------- compose

    internal class ComposeForm : Form
    {
        private readonly TextBox box = new TextBox();
        private readonly Func<string, string> wrap;

        internal ComposeForm(Func<string, string> wrapper, Action<string, string> toast)
        {
            wrap = wrapper;
            Text = "RTL Picker -- compose";
            Size = new Size(560, 340);
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { }

            box.Multiline = true;
            box.ScrollBars = ScrollBars.Vertical;
            box.Dock = DockStyle.Fill;
            box.RightToLeft = RightToLeft.Yes;
            box.Font = new Font("Segoe UI", 13f);
            box.Text = "\u0627\u0643\u062A\u0628 \u0647\u0646\u0627";
            Controls.Add(box);

            FlowLayoutPanel bar = new FlowLayoutPanel();
            bar.Dock = DockStyle.Bottom;
            bar.Height = 44;
            bar.Padding = new Padding(6);
            Controls.Add(bar);

            Button copyRtl = new Button();
            copyRtl.Text = "Copy as RTL";
            copyRtl.Width = 110;
            copyRtl.Click += delegate
            {
                if (Clip.SetText(wrap(box.Text))) toast("Copied as RTL", "Paste it into any app.");
            };
            bar.Controls.Add(copyRtl);

            Button copyPlain = new Button();
            copyPlain.Text = "Copy plain";
            copyPlain.Width = 90;
            copyPlain.Click += delegate { Clip.SetText(Bidi.Unwrap(box.Text)); };
            bar.Controls.Add(copyPlain);

            Button paste = new Button();
            paste.Text = "Paste";
            paste.Width = 70;
            paste.Click += delegate
            {
                string t = Clip.GetText();
                if (!string.IsNullOrEmpty(t)) box.Text = Bidi.Unwrap(t);
            };
            bar.Controls.Add(paste);

            Button clear = new Button();
            clear.Text = "Clear";
            clear.Width = 70;
            clear.Click += delegate { box.Clear(); };
            bar.Controls.Add(clear);

            Label hint = new Label();
            hint.Text = "Type here, then Copy as RTL.";
            hint.AutoSize = true;
            hint.ForeColor = Color.Gray;
            hint.Padding = new Padding(10, 8, 0, 0);
            bar.Controls.Add(hint);

            FormClosing += delegate(object s, FormClosingEventArgs e)
            {
                if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
            };
        }
    }

    // ----------------------------------------------------------------- action

    internal class KeyOption
    {
        internal string Keys;
        internal uint Vk;
        internal KeyOption(string keys, uint vk) { Keys = keys; Vk = vk; }
    }

    internal class HotAction
    {
        internal int Id;
        internal string Name;
        internal string Keys;
        internal uint Mods;
        internal uint Vk;
        internal KeyOption[] Fallbacks;
        internal Action Run;
    }

    // -------------------------------------------------------------- tray app

    internal class TrayApp : ApplicationContext
    {
        private const double Threshold = 0.25;

        private readonly NotifyIcon notify = new NotifyIcon();
        private readonly ContextMenuStrip menu = new ContextMenuStrip();
        private readonly HotkeyWindow hotkeys = new HotkeyWindow();
        private readonly ToastForm toast = new ToastForm();
        private readonly Dictionary<int, HotAction> byId = new Dictionary<int, HotAction>();

        private ReaderForm reader;
        private ComposeForm compose;
        private bool wrapPerLine = true;

        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValue = "RTL Picker";

        internal TrayApp()
        {
            HotAction[] actions = BuildActions();
            foreach (HotAction a in actions) byId[a.Id] = a;

            List<string> failed = new List<string>();
            List<string> rebound = new List<string>();
            RegisterAll(actions, failed, rebound);

            hotkeys.HotkeyPressed += delegate(int id)
            {
                try
                {
                    HotAction a;
                    if (byId.TryGetValue(id, out a)) a.Run();
                }
                catch (Exception ex)
                {
                    Log.Write("error: " + ex.Message);
                    toast.Show("RTL Picker error", ex.Message);
                }
            };

            BuildMenu(actions);

            notify.Icon = LoadIcon();
            notify.Text = "RTL Picker";
            notify.ContextMenuStrip = menu;
            notify.MouseUp += delegate(object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left) menu.Show(Cursor.Position);
            };
            notify.Visible = true;

            Log.Write("--- started (native) ---");
            string readerKey = byId[6].Keys;
            if (failed.Count > 0)
                toast.Show("Some shortcuts are taken", string.Join(", ", failed.ToArray()) + " -- another app owns them.");
            else if (rebound.Count > 0)
                toast.Show("Shortcut changed", string.Join("; ", rebound.ToArray()));
            else
                toast.Show("RTL Picker is running", "Select text, press " + readerKey + " to read it in RTL.");
        }

        private static Icon LoadIcon()
        {
            try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { return SystemIcons.Application; }
        }

        private HotAction[] BuildActions()
        {
            return new HotAction[]
            {
                // First because it is the one that works on text you cannot edit.
                new HotAction { Id = 6, Name = "Read selection in RTL", Keys = "Ctrl+Alt+D", Mods = 3, Vk = 0x44,
                    Fallbacks = new KeyOption[] { new KeyOption("Ctrl+Alt+Q", 0x51), new KeyOption("Ctrl+Alt+Y", 0x59) },
                    Run = ReadSelection },
                new HotAction { Id = 1, Name = "Wrap selection as RTL", Keys = "Ctrl+Alt+R", Mods = 3, Vk = 0x52,
                    Fallbacks = new KeyOption[] { new KeyOption("Ctrl+Alt+G", 0x47) },
                    Run = delegate { TransformSelection(WrapText, "Wrapped as RTL"); } },
                new HotAction { Id = 2, Name = "Remove direction marks", Keys = "Ctrl+Alt+L", Mods = 3, Vk = 0x4C,
                    Fallbacks = new KeyOption[] { new KeyOption("Ctrl+Alt+K", 0x4B) },
                    Run = delegate { TransformSelection(Bidi.Unwrap, "Marks removed"); } },
                new HotAction { Id = 3, Name = "Wrap clipboard as RTL", Keys = "Ctrl+Alt+B", Mods = 3, Vk = 0x42,
                    Fallbacks = new KeyOption[] { new KeyOption("Ctrl+Alt+Z", 0x5A) },
                    Run = delegate { ConvertClipboard(WrapText, "Clipboard wrapped as RTL"); } },
                new HotAction { Id = 4, Name = "Paragraph -> RTL (Word only)", Keys = "Ctrl+Alt+Shift+R", Mods = 7, Vk = 0x52,
                    Fallbacks = new KeyOption[0],
                    Run = delegate { SetParagraph(true, "Paragraph set to RTL"); } },
                new HotAction { Id = 5, Name = "Paragraph -> LTR (Word only)", Keys = "Ctrl+Alt+Shift+L", Mods = 7, Vk = 0x4C,
                    Fallbacks = new KeyOption[0],
                    Run = delegate { SetParagraph(false, "Paragraph set to LTR"); } }
            };
        }

        /// Global hotkeys are first-come-first-served across the machine, so any
        /// fixed choice will collide on somebody's setup. Fall back rather than
        /// losing the action, and report which key actually won.
        private void RegisterAll(HotAction[] actions, List<string> failed, List<string> rebound)
        {
            foreach (HotAction a in actions)
            {
                bool ok = hotkeys.Register(a.Id, a.Mods, a.Vk);
                if (!ok)
                {
                    Log.Write(a.Keys + " is taken by another app; trying fallbacks");
                    foreach (KeyOption fb in a.Fallbacks)
                    {
                        if (hotkeys.Register(a.Id, a.Mods, fb.Vk))
                        {
                            rebound.Add(a.Name + ": " + fb.Keys);
                            a.Keys = fb.Keys;
                            ok = true;
                            break;
                        }
                    }
                }
                if (ok) Log.Write("registered " + a.Keys + " -> " + a.Name);
                else { failed.Add(a.Keys); Log.Write("FAILED to register " + a.Name + " -- all candidate keys are taken"); }
            }
        }

        private void BuildMenu(HotAction[] actions)
        {
            ToolStripMenuItem readClip = new ToolStripMenuItem("Read clipboard in RTL");
            readClip.Font = new Font(menu.Font, FontStyle.Bold);
            readClip.Click += delegate { ReadClipboard(); };
            menu.Items.Add(readClip);

            ToolStripMenuItem composeItem = new ToolStripMenuItem("Compose in RTL...");
            composeItem.Click += delegate { ShowCompose(); };
            menu.Items.Add(composeItem);

            menu.Items.Add(new ToolStripSeparator());

            foreach (HotAction a in actions)
            {
                HotAction captured = a; // one closure per item, not one shared
                ToolStripMenuItem item = new ToolStripMenuItem(a.Name);
                item.ShortcutKeyDisplayString = a.Keys;
                item.Click += delegate { captured.Run(); };
                menu.Items.Add(item);
            }

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem perLine = new ToolStripMenuItem("Wrap each line separately");
            perLine.CheckOnClick = true;
            perLine.Checked = wrapPerLine;
            perLine.ToolTipText = "On: every line becomes its own RTL run. Off: one run for the whole selection.";
            perLine.Click += delegate { wrapPerLine = perLine.Checked; };
            menu.Items.Add(perLine);

            ToolStripMenuItem startup = new ToolStripMenuItem("Start with Windows");
            startup.CheckOnClick = true;
            startup.Checked = IsRunAtStartup();
            startup.Click += delegate
            {
                try { SetRunAtStartup(startup.Checked); }
                catch (Exception ex)
                {
                    toast.Show("Could not update startup", ex.Message);
                    startup.Checked = IsRunAtStartup();
                }
            };
            menu.Items.Add(startup);

            ToolStripMenuItem openLog = new ToolStripMenuItem("Open log");
            openLog.Click += delegate
            {
                try { System.Diagnostics.Process.Start("notepad.exe", Log.File); }
                catch { }
            };
            menu.Items.Add(openLog);

            ToolStripMenuItem about = new ToolStripMenuItem("How it works...");
            about.Click += delegate
            {
                StringBuilder sb = new StringBuilder();
                foreach (HotAction a in actions) sb.AppendLine(a.Keys.PadRight(18) + a.Name);
                sb.AppendLine();
                sb.AppendLine("Read selection copies what you highlighted and shows it in a");
                sb.AppendLine("right-to-left window. It changes nothing in the other app, so it");
                sb.AppendLine("is the one that works on replies and pages you cannot edit.");
                sb.AppendLine();
                sb.AppendLine("Wrap / Remove edit the text itself with invisible Unicode direction");
                sb.AppendLine("marks. Those need an editable box, and the direction stays with the");
                sb.AppendLine("text when you send it.");
                sb.AppendLine();
                sb.AppendLine("The 'Word only' shortcuts send Windows' native paragraph command,");
                sb.AppendLine("which Chromium and Electron ignore.");
                MessageBox.Show(sb.ToString(), "RTL Picker", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            menu.Items.Add(about);

            ToolStripMenuItem exit = new ToolStripMenuItem("Exit");
            exit.Click += delegate { ExitApp(); };
            menu.Items.Add(exit);
        }

        private string WrapText(string t) { return Bidi.Wrap(t, wrapPerLine); }

        // ------------------------------------------------------------ actions

        /// Copy the selection, transform it, paste it back, then restore whatever
        /// the user had on the clipboard.
        private void TransformSelection(Func<string, string> transform, string label)
        {
            string target = Native.DescribeForegroundWindow();
            Log.Write("action '" + label + "' -> " + target);

            Native.ReleaseModifiers();
            string original = Clip.GetText();
            Clip.Clear();
            Native.CtrlKey(0x43); // Ctrl+C

            // Electron can take a while to service the copy; poll for a second.
            string selected = null;
            for (int i = 0; i < 20; i++)
            {
                Thread.Sleep(50);
                selected = Clip.GetText();
                if (!string.IsNullOrEmpty(selected)) break;
            }
            Log.Write("  copied: " + Bidi.Describe(selected));

            if (string.IsNullOrEmpty(selected))
            {
                if (original != null) Clip.SetText(original);
                Log.Write("  -> nothing captured; the app did not answer Ctrl+C");
                toast.Show("Nothing selected", "Select the text first, then press the shortcut.");
                return;
            }

            if (selected.Trim().Length == 0)
            {
                if (original != null) Clip.SetText(original);
                Log.Write("  -> selection is whitespace only");
                toast.Show("Nothing to change", "The selection has no text in it.");
                return;
            }

            string result = transform(selected);
            Log.Write("  result: " + Bidi.Describe(result));

            // C# string == is ordinal. A culture-sensitive compare would report
            // these equal, because bidi controls carry zero collation weight --
            // that bug shipped once in the PowerShell build and silently threw
            // away every transform.
            if (string.Equals(result, selected, StringComparison.Ordinal))
            {
                if (original != null) Clip.SetText(original);
                Log.Write("  -> unchanged; text was already in that state");
                toast.Show("Already in that state", "Ctrl+Alt+L removes the marks first.");
                return;
            }

            if (!Clip.SetText(result))
            {
                Log.Write("  -> clipboard write failed");
                toast.Show("Clipboard busy", "Another app is holding the clipboard. Try again.");
                return;
            }

            Native.CtrlKey(0x56); // Ctrl+V
            Thread.Sleep(300);

            if (original != null) Clip.SetText(original);
            Log.Write("  -> pasted " + selected.Length + " chars into " + target);
            toast.Show(label, selected.Length + " characters. Nothing changed? The box may be read-only.");
        }

        private void ConvertClipboard(Func<string, string> transform, string label)
        {
            string text = Clip.GetText();
            if (string.IsNullOrEmpty(text) || text.Trim().Length == 0)
            {
                toast.Show("Clipboard is empty", "Copy some text first.");
                return;
            }
            if (Clip.SetText(transform(text)))
            {
                Log.Write("clipboard converted: " + label);
                toast.Show(label, "Paste it anywhere.");
            }
        }

        private void SetParagraph(bool rtl, string label)
        {
            Log.Write("native direction (" + label + ") -> " + Native.DescribeForegroundWindow());
            Native.SetParagraphDirection(rtl);
            toast.Show(label, "Only works in Word, WordPad and Outlook.");
        }

        /// Copies the selection and shows it in the reader. Never pastes, so the
        /// source app is untouched -- which is what makes it work on text you
        /// cannot edit.
        private void ReadSelection()
        {
            string target = Native.DescribeForegroundWindow();
            Log.Write("action 'Read selection' -> " + target);

            Native.ReleaseModifiers();
            string original = Clip.GetText();
            Clip.Clear();
            Native.CtrlKey(0x43); // Ctrl+C

            string selected = null;
            for (int i = 0; i < 20; i++)
            {
                Thread.Sleep(50);
                selected = Clip.GetText();
                if (!string.IsNullOrEmpty(selected)) break;
            }
            Log.Write("  copied: " + Bidi.Describe(selected));

            // Nothing is pasted, so the clipboard goes back immediately.
            if (original != null) Clip.SetText(original);

            if (string.IsNullOrEmpty(selected) || selected.Trim().Length == 0)
            {
                Log.Write("  -> nothing captured");
                toast.Show("Nothing selected", "Select some text in the reply first.");
                return;
            }

            Log.Write("  -> opened reader with " + selected.Length + " chars");
            ShowReader(selected);
        }

        private void ReadClipboard()
        {
            string text = Clip.GetText();
            if (string.IsNullOrEmpty(text) || text.Trim().Length == 0)
            {
                toast.Show("Clipboard is empty", "Copy some text first.");
                return;
            }
            ShowReader(text);
        }

        private void ShowReader(string text)
        {
            if (reader == null || reader.IsDisposed) reader = new ReaderForm();
            reader.ShowText(text, Threshold);
        }

        private void ShowCompose()
        {
            if (compose == null || compose.IsDisposed)
                compose = new ComposeForm(WrapText, delegate(string t, string b) { toast.Show(t, b); });
            compose.Show();
            compose.Activate();
        }

        // ------------------------------------------------------------ startup

        private static bool IsRunAtStartup()
        {
            try
            {
                using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue(RunValue) != null;
            }
            catch { return false; }
        }

        private static void SetRunAtStartup(bool enabled)
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (k == null) return;
                if (enabled) k.SetValue(RunValue, "\"" + Application.ExecutablePath + "\"");
                else if (k.GetValue(RunValue) != null) k.DeleteValue(RunValue);
            }
        }

        private void ExitApp()
        {
            notify.Visible = false;
            Log.Write("--- stopped ---");
            hotkeys.Dispose();
            notify.Dispose();
            ExitThread();
        }
    }

    // ---------------------------------------------------------------- program

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Length > 0 && args[0].Equals("--selftest", StringComparison.OrdinalIgnoreCase))
                return SelfTest();

            // A second copy would fight the first for the same global hotkeys.
            bool isNew;
            using (Mutex mutex = new Mutex(true, "RtlPicker.SingleInstance", out isNew))
            {
                if (!isNew)
                {
                    MessageBox.Show("RTL Picker is already running -- look for it in the system tray.",
                        "RTL Picker", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp());
                return 0;
            }
        }

        private static int SelfTest()
        {
            Native.AttachConsole(-1); // so results land in the calling console
            string arabic = "\u0645\u0631\u062D\u0628\u0627";
            string sample = "Hello world\n" + arabic;
            string wrapped = Bidi.Wrap(sample, true);

            List<string> names = new List<string>();
            List<bool> results = new List<bool>();

            names.Add("wrap adds bidi marks"); results.Add(wrapped.Length > sample.Length);
            names.Add("wrap is per line"); results.Add(Bidi.CountMarks(wrapped) == 4);
            names.Add("unwrap round-trips"); results.Add(string.Equals(Bidi.Unwrap(wrapped), sample, StringComparison.Ordinal));
            names.Add("double wrap is stable"); results.Add(string.Equals(Bidi.Wrap(wrapped, true), wrapped, StringComparison.Ordinal));
            names.Add("wrapped differs (ordinal)"); results.Add(!string.Equals(wrapped, sample, StringComparison.Ordinal));
            // Guards the bug that shipped in the PowerShell build.
            names.Add("culture compare is unsafe"); results.Add(string.Equals(wrapped, sample, StringComparison.CurrentCulture));
            names.Add("detects arabic as rtl"); results.Add(Bidi.IsRightToLeft(sample, 0.25));
            names.Add("detects english as ltr"); results.Add(!Bidi.IsRightToLeft("plain english sentence here", 0.25));
            names.Add("ignores stray rtl word"); results.Add(!Bidi.IsRightToLeft("The city of \u0627\u0644\u0642\u0627\u0647\u0631\u0629 has many people in it", 0.25));
            names.Add("foreground window read"); results.Add(!string.IsNullOrEmpty(Native.DescribeForegroundWindow()));

            int failed = 0;
            StringBuilder report = new StringBuilder();
            for (int i = 0; i < names.Count; i++)
            {
                report.AppendLine((results[i] ? "  ok    " : "  FAIL  ") + names[i]);
                if (!results[i]) failed++;
            }
            report.AppendLine(failed == 0 ? "all checks passed" : failed + " check(s) failed");

            Console.Write(report.ToString());
            // A winexe has no console of its own, so AttachConsole output is lost
            // whenever the caller redirects. Always leave a file behind too.
            try
            {
                if (!Directory.Exists(Log.Dir)) Directory.CreateDirectory(Log.Dir);
                System.IO.File.WriteAllText(Path.Combine(Log.Dir, "selftest.txt"), report.ToString(), Encoding.UTF8);
            }
            catch { }
            return failed;
        }
    }
}
