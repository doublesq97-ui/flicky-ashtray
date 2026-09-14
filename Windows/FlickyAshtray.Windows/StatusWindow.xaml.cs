using FlickyAshtray.Core;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace FlickyAshtray.Windows;

public partial class StatusWindow : Window
{
    private readonly AppState state;
    private readonly DispatcherTimer hideTimer = new() { Interval = TimeSpan.FromMilliseconds(220) };
    private bool pinned;
    private PetWindow? anchor;

    public StatusWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        hideTimer.Tick += (_, _) =>
        {
            hideTimer.Stop();
            if (!pinned)
            {
                Hide();
            }
        };
    }

    public void PetHoverChanged(bool inside, PetWindow pet)
    {
        hideTimer.Stop();
        anchor = pet;
        if (inside)
        {
            ShowFor(pet);
        }
        else if (!pinned)
        {
            hideTimer.Start();
        }
    }

    public void Refresh()
    {
        var snapshot = state.Snapshot;
        StatusText.Text = state.StatusMessage;
        CountText.Text = $"今天 {snapshot.Count} / {snapshot.Limit} 根 · {CountDetail(snapshot)}";
        CountText.Foreground = FindBrush(snapshot.IsOverLimit ? "DangerBrush" : "SecondaryTextBrush");
        FeedbackText.Text = state.PositiveFeedback ?? string.Empty;
        FeedbackText.Visibility = state.PositiveFeedback is null ? Visibility.Collapsed : Visibility.Visible;
        PinButton.Content = pinned ? "📍" : "📌";
        PinButton.ToolTip = pinned ? "取消固定今日状态" : "固定今日状态";
        if (IsVisible && anchor is not null)
        {
            PositionRelativeTo(anchor);
        }
    }

    public void HideImmediately()
    {
        hideTimer.Stop();
        pinned = false;
        anchor = null;
        if (IsVisible)
        {
            Hide();
        }
        Refresh();
    }

    private void ShowFor(PetWindow pet)
    {
        Refresh();
        PositionRelativeTo(pet);
        if (!IsVisible)
        {
            Opacity = SystemParameters.ClientAreaAnimation ? 0 : 1;
            Show();
            if (SystemParameters.ClientAreaAnimation)
            {
                BeginAnimation(OpacityProperty, new System.Windows.Media.Animation.DoubleAnimation(1, TimeSpan.FromMilliseconds(100)));
            }
        }
    }

    private void PositionRelativeTo(PetWindow pet)
    {
        var left = pet.Left + pet.Width - Width;
        var top = pet.Top - Height - 2;
        var virtualLeft = SystemParameters.VirtualScreenLeft;
        var virtualTop = SystemParameters.VirtualScreenTop;
        var virtualRight = virtualLeft + SystemParameters.VirtualScreenWidth;
        var virtualBottom = virtualTop + SystemParameters.VirtualScreenHeight;
        if (top < virtualTop)
        {
            top = pet.Top + pet.Height + 2;
        }

        Left = Math.Clamp(left, virtualLeft, Math.Max(virtualLeft, virtualRight - Width));
        Top = Math.Clamp(top, virtualTop, Math.Max(virtualTop, virtualBottom - Height));
    }

    private void PinButton_Click(object sender, RoutedEventArgs e)
    {
        hideTimer.Stop();
        pinned = !pinned;
        if (!pinned)
        {
            Hide();
        }

        Refresh();
    }

    private void Window_MouseEnter(object sender, MouseEventArgs e) => hideTimer.Stop();

    private void Window_MouseLeave(object sender, MouseEventArgs e)
    {
        if (!pinned)
        {
            hideTimer.Start();
        }
    }

    private Brush FindBrush(string key) => (Brush)Application.Current.FindResource(key);

    private static string CountDetail(DaySnapshot snapshot)
    {
        if (snapshot.IsOverLimit) return $"超过 {snapshot.Count - snapshot.Limit} 根";
        if (snapshot.Remaining == 0) return "已到上限";
        return $"还剩 {snapshot.Remaining} 根";
    }
}
