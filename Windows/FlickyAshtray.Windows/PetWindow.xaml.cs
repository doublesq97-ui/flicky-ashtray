using FlickyAshtray.Core;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using Forms = System.Windows.Forms;

namespace FlickyAshtray.Windows;

public partial class PetWindow : Window
{
    private readonly AppState state;
    private long lastRecordAttempt;
    private bool actionBusy;
    private bool positionInitialized;
    private bool dragging;

    public PetWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        LocationChanged += (_, _) =>
        {
            if (positionInitialized && !dragging)
            {
                WindowPlacementStore.Save(Left, Top);
            }
        };
    }

    public event EventHandler<bool>? HoverChanged;
    public event EventHandler? OpenControlPanelRequested;
    public event EventHandler? HideRequested;

    public void ShowPet()
    {
        Refresh();
        if (!positionInitialized)
        {
            RestorePosition();
            positionInitialized = true;
        }

        ClampToVirtualDesktop();
        if (!IsVisible)
        {
            Show();
        }

        Topmost = true;
    }

    public void Refresh()
    {
        var snapshot = state.Snapshot;
        var settings = state.Store.Settings;
        var isNote = settings.PetStyle == PetStyle.Note;
        var scale = Math.Clamp(settings.PetScale, 0.6, 1);
        var oldRight = Left + Width;
        var oldBottom = Top + Height;
        var oldWidth = Width;
        var oldHeight = Height;
        var baseWidth = isNote ? 218d : 220d;
        var baseHeight = isNote ? 148d : 180d;
        Width = baseWidth * scale;
        Height = baseHeight * scale;
        BaseSurface.Width = baseWidth;
        BaseSurface.Height = baseHeight;
        AshtraySurface.Visibility = isNote ? Visibility.Collapsed : Visibility.Visible;
        NoteSurface.Visibility = isNote ? Visibility.Visible : Visibility.Collapsed;

        if (positionInitialized && (Math.Abs(oldWidth - Width) > 0.5 || Math.Abs(oldHeight - Height) > 0.5))
        {
            Left = oldRight - Width;
            Top = oldBottom - Height;
            ClampToVirtualDesktop();
        }

        if (isNote)
        {
            NoteCountText.Text = $"今天 {snapshot.Count} / {snapshot.Limit}";
            NoteCountText.Foreground = FindBrush(snapshot.IsOverLimit ? "DangerBrush" : "PrimaryTextBrush");
            NoteDetailText.Text = CountDetail(snapshot);
            NoteDetailText.Foreground = FindBrush(snapshot.IsOverLimit ? "DangerBrush" : "SecondaryTextBrush");
            NoteLastRecordText.Text = snapshot.Records.LastOrDefault() is { } latest
                ? $"最近 {latest.Date.ToLocalTime():HH:mm}"
                : "今天还没有记录";
            NoteLastRecordText.Visibility = scale >= 0.75 ? Visibility.Visible : Visibility.Collapsed;
        }
        else
        {
            UpdateAshLayer(snapshot.AshLevel);
        }

        ToolTip = $"{state.StatusMessage}\n今天 {snapshot.Count}/{snapshot.Limit} 根";
    }

    private async void CigaretteButton_Click(object sender, RoutedEventArgs e)
    {
        if (!AcceptRecordAction() || actionBusy)
        {
            return;
        }

        actionBusy = true;
        CigaretteButton.IsEnabled = false;
        if (!SystemParameters.ClientAreaAnimation)
        {
            state.AddRecord();
            actionBusy = false;
            CigaretteButton.IsEnabled = true;
            return;
        }

        AnimateCigarette(118.6, -3, 70);
        await Task.Delay(75);
        AnimateCigarette(124.5, 0, 70);
        await Task.Delay(60);
        state.AddRecord();
        AnimateCigarette(122, 0, 120);
        await Task.Delay(150);
        actionBusy = false;
        CigaretteButton.IsEnabled = true;
    }

    private async void IgniterButton_Click(object sender, RoutedEventArgs e)
    {
        if (!AcceptRecordAction() || actionBusy)
        {
            return;
        }

        actionBusy = true;
        state.AddRecord();
        IgniterEmber.Fill = new SolidColorBrush(Color.FromRgb(235, 62, 62));
        IgniterEmber.Opacity = 1;
        await Task.Delay(SystemParameters.ClientAreaAnimation ? 430 : 140);
        var fade = new DoubleAnimation(0.35, TimeSpan.FromMilliseconds(SystemParameters.ClientAreaAnimation ? 340 : 120));
        IgniterEmber.BeginAnimation(OpacityProperty, fade);
        await Task.Delay(SystemParameters.ClientAreaAnimation ? 340 : 120);
        IgniterEmber.Fill = FindBrush("TertiaryTextBrush");
        actionBusy = false;
    }

    private void AnimateCigarette(double angle, double offsetY, int milliseconds)
    {
        CigaretteRotation.BeginAnimation(
            System.Windows.Media.RotateTransform.AngleProperty,
            new DoubleAnimation(angle, TimeSpan.FromMilliseconds(milliseconds))
        );
        CigaretteTranslation.BeginAnimation(
            System.Windows.Media.TranslateTransform.YProperty,
            new DoubleAnimation(offsetY, TimeSpan.FromMilliseconds(milliseconds))
        );
    }

    private bool AcceptRecordAction()
    {
        var attempt = Environment.TickCount64;
        var previous = lastRecordAttempt;
        lastRecordAttempt = attempt;
        return previous == 0 || attempt - previous > Forms.SystemInformation.DoubleClickTime;
    }

    private void UpdateAshLayer(AshLevel level)
    {
        if (level == AshLevel.Clean)
        {
            AshLayer.Source = null;
            return;
        }

        var (file, width, height, top) = level switch
        {
            AshLevel.Sprinkle => ("ash-sprinkle.png", 82d, 44d, 62d),
            AshLevel.Full => ("ash-full.png", 90d, 56d, 59d),
            AshLevel.OverLimit => ("ash-over.png", 108d, 70d, 50d),
            _ => ("ash-filthy.png", 132d, 88d, 39d)
        };
        AshLayer.Source = new BitmapImage(new Uri($"pack://application:,,,/Assets/{file}"));
        AshLayer.Width = width;
        AshLayer.Height = height;
        Canvas.SetLeft(AshLayer, (220 - width) / 2);
        Canvas.SetTop(AshLayer, top);
    }

    private void HitSurface_MouseEnter(object sender, MouseEventArgs e) => HoverChanged?.Invoke(this, true);
    private void HitSurface_MouseLeave(object sender, MouseEventArgs e) => HoverChanged?.Invoke(this, false);

    private void HitSurface_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || IsInsideButton(e.OriginalSource as DependencyObject))
        {
            return;
        }

        HoverChanged?.Invoke(this, false);
        dragging = true;
        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
        }
        finally
        {
            dragging = false;
            ClampToVirtualDesktop();
            WindowPlacementStore.Save(Left, Top);
        }
    }

    private void HitSurface_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        var menu = new ContextMenu();
        var open = new MenuItem { Header = "查看记录与设置…" };
        open.Click += (_, _) => OpenControlPanelRequested?.Invoke(this, EventArgs.Empty);
        var hide = new MenuItem { Header = "隐藏桌宠" };
        hide.Click += (_, _) => HideRequested?.Invoke(this, EventArgs.Empty);
        menu.Items.Add(open);
        menu.Items.Add(new Separator());
        menu.Items.Add(hide);
        menu.IsOpen = true;
        e.Handled = true;
    }

    private static bool IsInsideButton(DependencyObject? value)
    {
        while (value is not null)
        {
            if (value is Button)
            {
                return true;
            }

            value = VisualTreeHelper.GetParent(value);
        }

        return false;
    }

    private void RestorePosition()
    {
        var placement = WindowPlacementStore.Load();
        if (placement is not null && double.IsFinite(placement.Left) && double.IsFinite(placement.Top))
        {
            Left = placement.Left;
            Top = placement.Top;
            return;
        }

        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 24;
        Top = area.Bottom - Height - 24;
    }

    private void ClampToVirtualDesktop()
    {
        var left = SystemParameters.VirtualScreenLeft;
        var top = SystemParameters.VirtualScreenTop;
        var right = left + SystemParameters.VirtualScreenWidth;
        var bottom = top + SystemParameters.VirtualScreenHeight;
        Left = Math.Clamp(Left, left, Math.Max(left, right - Width));
        Top = Math.Clamp(Top, top, Math.Max(top, bottom - Height));
    }

    private Brush FindBrush(string key) => (Brush)Application.Current.FindResource(key);

    private static string CountDetail(DaySnapshot snapshot)
    {
        if (snapshot.IsOverLimit) return $"超过 {snapshot.Count - snapshot.Limit} 根";
        if (snapshot.Remaining == 0) return "已经到今天的上限";
        return $"还剩 {snapshot.Remaining} 根";
    }
}
