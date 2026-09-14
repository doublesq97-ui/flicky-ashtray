using FlickyAshtray.Core;
using System.Drawing;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace FlickyAshtray.Windows;

internal sealed class AppController : IDisposable
{
    private readonly AppState state = new();
    private readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly PetWindow petWindow;
    private readonly StatusWindow statusWindow;
    private readonly ControlPanelWindow controlPanel;
    private readonly Forms.NotifyIcon notifyIcon;
    private readonly Forms.ToolStripMenuItem countItem = new();
    private readonly Forms.ToolStripMenuItem undoItem = new("撤销今日上一根");
    private bool exiting;

    public AppController()
    {
        petWindow = new PetWindow(state);
        statusWindow = new StatusWindow(state);
        controlPanel = new ControlPanelWindow(state);

        petWindow.HoverChanged += (_, inside) => statusWindow.PetHoverChanged(inside, petWindow);
        petWindow.OpenControlPanelRequested += (_, _) => ShowControlPanel();
        petWindow.HideRequested += (_, _) => HidePet();
        controlPanel.DoneRequested += (_, _) =>
        {
            controlPanel.Hide();
            ShowPet();
        };

        state.StateChanged += StateChanged;
        clock.Tick += (_, _) => state.RefreshClock();

        countItem.Enabled = false;
        undoItem.Click += (_, _) => state.UndoToday();
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(countItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("显示桌宠", null, (_, _) => ShowPet());
        menu.Items.Add("查看记录与设置…", null, (_, _) => ShowControlPanel());
        menu.Items.Add("记一根", null, (_, _) => state.AddRecord());
        menu.Items.Add(undoItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("打开数据文件夹", null, (_, _) => OpenDataFolder());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出 Flicky Ashtray", null, (_, _) => Exit());

        notifyIcon = new Forms.NotifyIcon
        {
            Icon = ResolveIcon(),
            Text = "Flicky Ashtray",
            ContextMenuStrip = menu,
            Visible = true
        };
        notifyIcon.DoubleClick += (_, _) => ShowControlPanel();
    }

    public void Start()
    {
        clock.Start();
        RefreshAll();
        if (state.PersistenceMessage is not null || state.IsOnboardingPresented)
        {
            controlPanel.ShowPanel();
        }
        else
        {
            ShowPet();
        }
    }

    public void Dispose()
    {
        clock.Stop();
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
    }

    private void StateChanged(object? sender, EventArgs e)
    {
        if (!Application.Current.Dispatcher.CheckAccess())
        {
            Application.Current.Dispatcher.Invoke(RefreshAll);
            return;
        }

        RefreshAll();
        if (state.PersistenceMessage is not null)
        {
            ShowControlPanel();
        }
    }

    private void RefreshAll()
    {
        var snapshot = state.Snapshot;
        countItem.Text = $"今天 {snapshot.Count} / {snapshot.Limit} 根";
        undoItem.Enabled = state.CanUndoToday;
        notifyIcon.Text = $"Flicky Ashtray · 今天 {snapshot.Count}/{snapshot.Limit} 根";
        petWindow.Refresh();
        statusWindow.Refresh();
        controlPanel.RefreshView();
    }

    private void ShowPet()
    {
        petWindow.ShowPet();
        statusWindow.HideImmediately();
    }

    private void HidePet()
    {
        statusWindow.HideImmediately();
        petWindow.Hide();
    }

    private void ShowControlPanel()
    {
        statusWindow.HideImmediately();
        controlPanel.ShowPanel();
    }

    private void OpenDataFolder()
    {
        var folder = Path.GetDirectoryName(state.DataFilePath)!;
        Directory.CreateDirectory(folder);
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{folder}\"",
                UseShellExecute = true
            });
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "无法打开数据文件夹", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void Exit()
    {
        if (exiting)
        {
            return;
        }

        exiting = true;
        controlPanel.CloseForExit();
        statusWindow.Close();
        petWindow.Close();
        Application.Current.Shutdown();
    }

    private static Icon ResolveIcon()
    {
        try
        {
            var executable = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(executable))
            {
                var icon = Icon.ExtractAssociatedIcon(executable);
                if (icon is not null)
                {
                    return icon;
                }
            }
        }
        catch
        {
        }

        return SystemIcons.Information;
    }
}
