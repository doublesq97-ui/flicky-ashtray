using System.Threading;
using System.Windows;

namespace FlickyAshtray.Windows;

public partial class App : Application
{
    private Mutex? singleInstance;
    private AppController? controller;
    private bool ownsSingleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        singleInstance = new Mutex(true, "Local\\FlickyAshtray.Windows.SingleInstance", out ownsSingleInstance);
        if (!ownsSingleInstance)
        {
            MessageBox.Show(
                "Flicky Ashtray 已经在运行。请从任务栏托盘找到它。",
                "Flicky Ashtray",
                MessageBoxButton.OK,
                MessageBoxImage.Information
            );
            Shutdown();
            return;
        }

        ThemeManager.ApplyCurrentTheme(Resources);
        controller = new AppController();
        controller.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        controller?.Dispose();
        if (ownsSingleInstance)
        {
            singleInstance?.ReleaseMutex();
        }
        singleInstance?.Dispose();
        base.OnExit(e);
    }
}
