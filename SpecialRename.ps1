Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.CSharp

$source = @"
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SpecialRename
{
    public sealed class HotkeyForm : Form
    {
        private const int HotkeyId = 9001;
        private const int WmHotkey = 0x0312;
        private const uint ModControl = 0x0002;
        private const uint VkF1 = 0x70;

        private readonly TextBox nameBox;
        private readonly Label statusLabel;
        private readonly NotifyIcon notifyIcon;
        private string targetName = "target";

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        public HotkeyForm()
        {
            Text = "Special Rename";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            ClientSize = new Size(420, 178);

            var label = new Label
            {
                Text = "Target name",
                Location = new Point(18, 18),
                Size = new Size(380, 22)
            };
            Controls.Add(label);

            nameBox = new TextBox
            {
                Location = new Point(18, 44),
                Size = new Size(380, 24),
                Text = targetName
            };
            Controls.Add(nameBox);

            var saveButton = new Button
            {
                Text = "Start hotkey",
                Location = new Point(18, 82),
                Size = new Size(110, 30)
            };
            saveButton.Click += (sender, args) => StartHotkey();
            Controls.Add(saveButton);

            var hideButton = new Button
            {
                Text = "Hide",
                Location = new Point(138, 82),
                Size = new Size(80, 30)
            };
            hideButton.Click += (sender, args) => Hide();
            Controls.Add(hideButton);

            statusLabel = new Label
            {
                Text = "Enter a target name, click Start hotkey, then select one item in File Explorer and press Ctrl+F1.",
                Location = new Point(18, 126),
                Size = new Size(380, 38)
            };
            Controls.Add(statusLabel);

            notifyIcon = new NotifyIcon
            {
                Text = "Special Rename",
                Icon = SystemIcons.Application,
                Visible = true
            };
            notifyIcon.DoubleClick += (sender, args) =>
            {
                Show();
                WindowState = FormWindowState.Normal;
                Activate();
            };

            Shown += (sender, args) => nameBox.Focus();
            FormClosing += (sender, args) =>
            {
                StopHotkey();
                notifyIcon.Dispose();
            };
        }

        private void StartHotkey()
        {
            var name = nameBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(name))
            {
                MessageBox.Show("Choose a target name first.", "Special Rename");
                return;
            }

            if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
            {
                MessageBox.Show("The target name contains characters Windows cannot use in file names.", "Special Rename");
                return;
            }

            StopHotkey();
            targetName = name;

            if (RegisterHotKey(Handle, HotkeyId, ModControl, VkF1))
            {
                statusLabel.Text = "Active: select one item in File Explorer and press Ctrl+F1. Target name: " + name;
                Hide();
                return;
            }

            MessageBox.Show("Ctrl+F1 is already in use by another app.", "Special Rename");
        }

        private void StopHotkey()
        {
            if (IsHandleCreated)
            {
                UnregisterHotKey(Handle, HotkeyId);
            }
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == WmHotkey && message.WParam.ToInt32() == HotkeyId)
            {
                RenameSelectedExplorerItem();
                return;
            }

            base.WndProc(ref message);
        }

        private void RenameSelectedExplorerItem()
        {
            string selectedPath = null;
            string destination = null;

            try
            {
                selectedPath = GetSelectedExplorerPath();
                if (string.IsNullOrWhiteSpace(selectedPath))
                {
                    ShowBalloon("No File Explorer selection", "Select exactly one file or folder in the active File Explorer window.");
                    return;
                }

                var isDirectory = Directory.Exists(selectedPath);
                var oldName = Path.GetFileName(selectedPath);
                var directory = isDirectory ? Directory.GetParent(selectedPath).FullName : Path.GetDirectoryName(selectedPath);
                var newName = targetName;

                if (!isDirectory && string.IsNullOrEmpty(Path.GetExtension(newName)))
                {
                    newName += Path.GetExtension(selectedPath);
                }

                destination = Path.Combine(directory, newName);
                if (string.Equals(selectedPath, destination, StringComparison.OrdinalIgnoreCase))
                {
                    ShowBalloon("Already renamed", "The selected item already has the target name.");
                    return;
                }

                if (File.Exists(destination) || Directory.Exists(destination))
                {
                    ShowBalloon("Rename skipped", "An item named '" + newName + "' already exists in this folder.");
                    return;
                }

                if (isDirectory)
                {
                    Directory.Move(selectedPath, destination);
                }
                else
                {
                    File.Move(selectedPath, destination);
                }

                ShowBalloon("Renamed", "'" + oldName + "' became '" + newName + "'.");
            }
            catch (UnauthorizedAccessException)
            {
                ShowBalloon(
                    "Access denied",
                    "Windows blocked the rename. Try a normal folder like Desktop, close the file if it is open, or run the app as administrator."
                );
            }
            catch (IOException ex)
            {
                ShowBalloon("Rename failed", "The file may be open or locked. " + ex.Message);
            }
            catch (Exception ex)
            {
                var pathText = string.IsNullOrWhiteSpace(selectedPath) ? "" : " Path: " + selectedPath;
                ShowBalloon("Rename failed", ex.Message + pathText);
            }
        }

        private static string GetSelectedExplorerPath()
        {
            var foregroundHwnd = GetForegroundWindow().ToInt64();
            var shellType = Type.GetTypeFromProgID("Shell.Application");
            dynamic shell = Activator.CreateInstance(shellType);

            foreach (dynamic window in shell.Windows())
            {
                try
                {
                    if ((long)window.HWND != foregroundHwnd)
                    {
                        continue;
                    }

                    dynamic selectedItems = window.Document.SelectedItems();
                    if ((int)selectedItems.Count != 1)
                    {
                        return null;
                    }

                    return (string)selectedItems.Item(0).Path;
                }
                catch
                {
                    continue;
                }
            }

            return null;
        }

        private void ShowBalloon(string title, string message)
        {
            notifyIcon.BalloonTipTitle = title;
            notifyIcon.BalloonTipText = message;
            notifyIcon.ShowBalloonTip(3000);
        }
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies @(
    "System.Windows.Forms",
    "System.Drawing",
    "Microsoft.CSharp"
)

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::Run([SpecialRename.HotkeyForm]::new())
