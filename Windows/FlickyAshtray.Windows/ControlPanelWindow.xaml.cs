using FlickyAshtray.Core;
using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Navigation;

namespace FlickyAshtray.Windows;

public partial class ControlPanelWindow : Window
{
    private readonly AppState state;
    private bool allowClose;
    private bool editorSync;
    private Guid? loadedChallengeId;
    private bool editingExistingChallenge;

    public ControlPanelWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();

        for (var hour = 0; hour < 24; hour++)
        {
            DayStartCombo.Items.Add($"{hour:00}:00");
        }

        PetStyleCombo.Items.Add(new Choice<PetStyle>("烟灰缸", PetStyle.Ashtray));
        PetStyleCombo.Items.Add(new Choice<PetStyle>("桌面便签", PetStyle.Note));
        CadenceCombo.Items.Add(new Choice<WeeklyCadence>("从今天起 7 天", WeeklyCadence.RollingSevenDays));
        CadenceCombo.Items.Add(new Choice<WeeklyCadence>("自然周 · 周一开始", WeeklyCadence.CalendarWeekMonday));
        CadenceCombo.Items.Add(new Choice<WeeklyCadence>("自然周 · 周日开始", WeeklyCadence.CalendarWeekSunday));
        DataPathText.Text = $"记录位置：{state.DataFilePath}";
        LoadSettingsEditor();
        LoadChallengeEditor(force: true);
        RefreshView();
    }

    public event EventHandler? DoneRequested;

    public void ShowPanel()
    {
        LoadSettingsEditor();
        LoadChallengeEditor(force: true);
        RefreshView();
        if (!IsVisible)
        {
            Show();
        }

        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Activate();
    }

    public void CloseForExit()
    {
        allowClose = true;
        Close();
    }

    public void RefreshView()
    {
        var snapshot = state.Snapshot;
        HeaderSubtitle.Text = state.IsOnboardingPresented
            ? "先定下今天的节奏"
            : DateTime.Now.ToString("M 月 d 日", CultureInfo.GetCultureInfo("zh-CN"));
        PersistenceBanner.Visibility = state.PersistenceMessage is null ? Visibility.Collapsed : Visibility.Visible;
        PersistenceMessage.Text = state.PersistenceMessage ?? string.Empty;
        OnboardingPanel.Visibility = state.IsOnboardingPresented ? Visibility.Visible : Visibility.Collapsed;
        MainPanel.Visibility = state.IsOnboardingPresented ? Visibility.Collapsed : Visibility.Visible;
        DoneButton.Visibility = state.IsOnboardingPresented ? Visibility.Collapsed : Visibility.Visible;
        if (state.IsOnboardingPresented && !editorSync)
        {
            OnboardingLimitSlider.Value = state.Store.Settings.DailyLimit;
        }

        StatusMessageText.Text = state.StatusMessage;
        TodayCountText.Text = $"今天 {snapshot.Count} / {snapshot.Limit} 根";
        TodayCountText.Foreground = FindBrush(snapshot.IsOverLimit ? "DangerBrush" : "PrimaryTextBrush");
        TodayDetailText.Text = snapshot.IsOverLimit
            ? $"超过 {snapshot.Count - snapshot.Limit} 根"
            : $"还剩 {snapshot.Remaining} 根";
        UndoButton.IsEnabled = state.CanUndoToday;
        UndoHelpText.Text = state.CanUndoToday
            ? "每个计数日只允许一次"
            : snapshot.Count == 0 ? "今天还没有可撤销的记录" : "今天的撤销机会已用完";

        TrendChartControl.SetData(snapshot.LastSevenDays, snapshot.Limit);
        RefreshRecords(snapshot);
        RefreshChallenge();
        ResetTitleText.Text = state.HasResetHistory ? "不建议再次重置历史" : "需要清空历史并重新开始？";
        ResetButton.IsEnabled = state.Store.Records.Count > 0 || state.Store.WeeklyChallenge is not null;
        AddRecordButton.IsEnabled = !state.IsPersistenceReadOnly;
        SaveSettingsButton.IsEnabled = !state.IsPersistenceReadOnly && HasUnsavedSettings();
        ChallengeActionButton.IsEnabled = !state.IsPersistenceReadOnly && ChallengeActionButton.IsEnabled;
    }

    private void RefreshRecords(DaySnapshot snapshot)
    {
        RecordsPanel.Children.Clear();
        if (snapshot.Records.Count == 0)
        {
            RecordsPanel.Children.Add(new TextBlock
            {
                Text = "今天还没有记录",
                Foreground = FindBrush("SecondaryTextBrush")
            });
            return;
        }

        foreach (var record in snapshot.Records.TakeLast(8))
        {
            var row = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new TextBlock { Text = $"第 {record.Number} 根" });
            var time = new TextBlock { Text = record.Date.ToLocalTime().ToString("HH:mm"), Margin = new Thickness(10, 0, 0, 0) };
            Grid.SetColumn(time, 1);
            row.Children.Add(time);
            var gap = new TextBlock
            {
                Text = record.GapMinutes is null ? string.Empty : $"距上一根 {SmokingLogic.FormattedGap(record.GapMinutes.Value)}",
                Margin = new Thickness(12, 0, 0, 0),
                Foreground = FindBrush("SecondaryTextBrush")
            };
            Grid.SetColumn(gap, 2);
            row.Children.Add(gap);
            RecordsPanel.Children.Add(row);
        }
    }

    private void RefreshChallenge()
    {
        var progress = state.WeeklyProgress;
        ChallengeFlowerControl.SetProgress(progress);
        LoadChallengeEditor(force: false);

        if (progress is null)
        {
            ChallengeHeadlineText.Text = "给接下来 7 天一个约定";
            ChallengeDetailText.Text = "不追求一次做到完美。先选一周里想守住的天数，以及这一周从哪里开始。";
            ChallengeRewardText.Text = string.Empty;
            ChallengeMetaText.Text = "每天不超过已保存的每日上限";
        }
        else
        {
            ChallengeHeadlineText.Text = progress.IsAchieved
                ? "你做到了，花开了。"
                : progress.IsFinished
                    ? $"这一轮留下了 {progress.AchievedDays} 瓣花。"
                    : $"已经守住 {progress.AchievedDays} 天";
            ChallengeDetailText.Text = ChallengeDetail(progress);
            ChallengeRewardText.Text = string.IsNullOrWhiteSpace(progress.Challenge.Reward)
                ? string.Empty
                : $"🎁 给自己的奖励：{progress.Challenge.Reward}";
            ChallengeMetaText.Text = $"{CadenceTitle(progress.Challenge.Cadence)} · 每天不超过 {progress.DailyLimit} 根 · 日切 {(progress.Challenge.DayStartHour ?? state.Store.Settings.DayStartHour):00}:00";
        }

        RefreshChallengeCapacity();
    }

    private void LoadChallengeEditor(bool force)
    {
        var progress = state.WeeklyProgress;
        var currentId = state.Store.WeeklyChallenge?.Id;
        if (!force && currentId == loadedChallengeId)
        {
            return;
        }

        editorSync = true;
        if (progress is not null && !progress.IsFinished)
        {
            editingExistingChallenge = true;
            ChallengeTargetSlider.Maximum = Math.Max(1, progress.MaximumAchievableDays);
            ChallengeTargetSlider.Value = Math.Clamp(progress.Challenge.TargetDays, 1, Math.Max(1, progress.MaximumAchievableDays));
            RewardBox.Text = progress.Challenge.Reward;
            SelectChoice(CadenceCombo, progress.Challenge.Cadence);
            CadenceCombo.IsEnabled = false;
            ChallengeActionButton.Content = "保存目标";
        }
        else
        {
            editingExistingChallenge = false;
            RewardBox.Text = string.Empty;
            SelectChoice(CadenceCombo, WeeklyCadence.RollingSevenDays);
            CadenceCombo.IsEnabled = true;
            var maximum = Math.Max(1, state.MaximumAchievableDays(WeeklyCadence.RollingSevenDays));
            ChallengeTargetSlider.Maximum = maximum;
            ChallengeTargetSlider.Value = Math.Min(5, maximum);
            ChallengeActionButton.Content = progress is null ? "开始这一周" : "开始新一轮";
        }

        loadedChallengeId = currentId;
        editorSync = false;
        RefreshChallengeCapacity();
    }

    private void RefreshChallengeCapacity()
    {
        if (CadenceCombo.SelectedItem is not Choice<WeeklyCadence> selected)
        {
            return;
        }

        var maximum = editingExistingChallenge && state.WeeklyProgress is { } progress
            ? progress.MaximumAchievableDays
            : state.MaximumAchievableDays(selected.Value);
        editorSync = true;
        ChallengeTargetSlider.Maximum = Math.Max(1, maximum);
        ChallengeTargetSlider.Value = Math.Min(ChallengeTargetSlider.Value, Math.Max(1, maximum));
        editorSync = false;
        ChallengeTargetText.Text = $"{(int)ChallengeTargetSlider.Value} 天";
        CadenceHelpText.Text = selected.Value switch
        {
            WeeklyCadence.RollingSevenDays => "以今天的计数日起点为第一天，连续记录 7 个计数日。",
            WeeklyCadence.CalendarWeekMonday => "按当前自然周计算：周一开始，周日结束。",
            _ => "按当前自然周计算：周日开始，周六结束。"
        };
        ChallengeCapacityText.Text = maximum == 0
            ? "当前这一轮已经没有仍可达的目标天数，原目标不会被自动降低。"
            : $"按已保存上限 {state.Store.Settings.DailyLimit} 根、日切 {state.Store.Settings.DayStartHour:00}:00 计算，本轮最多可设 {maximum} 天。";
        var unsavedCountingSettings = (int)LimitSlider.Value != state.Store.Settings.DailyLimit
            || DayStartCombo.SelectedIndex != state.Store.Settings.DayStartHour;
        ChallengeActionButton.IsEnabled = maximum > 0 && (editingExistingChallenge || !unsavedCountingSettings);
        if (!editingExistingChallenge && unsavedCountingSettings)
        {
            ChallengeCapacityText.Text += " 请先保存每日上限和计数日起点。";
        }
    }

    private void LoadSettingsEditor()
    {
        editorSync = true;
        LimitSlider.Value = state.Store.Settings.DailyLimit;
        DayStartCombo.SelectedIndex = state.Store.Settings.DayStartHour;
        SelectChoice(PetStyleCombo, state.Store.Settings.PetStyle);
        PetScaleSlider.Value = state.Store.Settings.PetScale;
        OnboardingLimitSlider.Value = state.Store.Settings.DailyLimit;
        editorSync = false;
        RefreshSettingsLabels();
    }

    private void RefreshSettingsLabels()
    {
        LimitText.Text = $"{(int)LimitSlider.Value} 根";
        PetScaleText.Text = $"{PetScaleSlider.Value:P0}";
        PetHelpText.Text = $"保存后为 {PetScaleSlider.Value:P0}；最小可缩至 60%，拖动范围与点击区域会一起缩放。";
        SaveSettingsButton.IsEnabled = !state.IsPersistenceReadOnly && HasUnsavedSettings();
        RefreshChallengeCapacity();
    }

    private bool HasUnsavedSettings()
    {
        if (PetStyleCombo.SelectedItem is not Choice<PetStyle> style)
        {
            return false;
        }

        return (int)LimitSlider.Value != state.Store.Settings.DailyLimit
            || DayStartCombo.SelectedIndex != state.Store.Settings.DayStartHour
            || Math.Abs(PetScaleSlider.Value - state.Store.Settings.PetScale) > 0.001
            || style.Value != state.Store.Settings.PetStyle;
    }

    private void DoneButton_Click(object sender, RoutedEventArgs e) => DoneRequested?.Invoke(this, EventArgs.Empty);
    private void AddRecordButton_Click(object sender, RoutedEventArgs e) => state.AddRecord();
    private void UndoButton_Click(object sender, RoutedEventArgs e) => state.UndoToday();

    private void StartUsingButton_Click(object sender, RoutedEventArgs e)
    {
        if (state.CompleteOnboarding((int)OnboardingLimitSlider.Value))
        {
            DoneRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnboardingLimitSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OnboardingLimitText is not null)
        {
            OnboardingLimitText.Text = $"{(int)e.NewValue} 根";
        }
    }

    private void SettingControl_Changed(object sender, RoutedEventArgs e)
    {
        if (!editorSync && IsInitialized)
        {
            RefreshSettingsLabels();
        }
    }

    private void SaveSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (PetStyleCombo.SelectedItem is not Choice<PetStyle> style)
        {
            return;
        }

        if (state.UpdateSettings(
            (int)LimitSlider.Value,
            DayStartCombo.SelectedIndex,
            PetScaleSlider.Value,
            style.Value
        ))
        {
            LoadSettingsEditor();
        }
    }

    private void ChallengeTargetSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (ChallengeTargetText is not null)
        {
            ChallengeTargetText.Text = $"{(int)e.NewValue} 天";
        }
    }

    private void CadenceCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!editorSync && IsInitialized)
        {
            RefreshChallengeCapacity();
        }
    }

    private void ChallengeActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (CadenceCombo.SelectedItem is not Choice<WeeklyCadence> cadence)
        {
            return;
        }

        var succeeded = editingExistingChallenge
            ? state.UpdateWeeklyChallenge((int)ChallengeTargetSlider.Value, RewardBox.Text)
            : state.StartWeeklyChallenge((int)ChallengeTargetSlider.Value, RewardBox.Text, cadence.Value);
        if (succeeded)
        {
            loadedChallengeId = null;
            LoadChallengeEditor(force: true);
            RefreshView();
        }
    }

    private void ExportReportButton_Click(object sender, RoutedEventArgs e)
    {
        var report = SmokingLogic.WeeklyReport(state.Store, state.Now);
        var dialog = new SaveFileDialog
        {
            Title = "生成本周小结",
            Filter = "PNG 图片 (*.png)|*.png",
            AddExtension = true,
            DefaultExt = ".png",
            FileName = $"Flicky-Ashtray-本周小结-{DateTime.Now:yyyy-MM-dd}.png"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            WeeklyReportRenderer.SavePng(report, dialog.FileName, ThemeManager.IsDarkMode());
            ReportMessageText.Foreground = FindBrush("SecondaryTextBrush");
            ReportMessageText.Text = $"已保存：{Path.GetFileName(dialog.FileName)}";
        }
        catch (Exception error)
        {
            ReportMessageText.Foreground = FindBrush("DangerBrush");
            ReportMessageText.Text = $"生成失败：{error.Message}";
        }
    }

    private void ResetButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ResetHistoryWindow(
            !state.HasResetHistory,
            state.Store.Records.Count
        )
        {
            Owner = this
        };
        if (dialog.ShowDialog() == true && dialog.ConfirmedReason is { } reason)
        {
            state.ResetHistory(reason);
        }
    }

    private void Hyperlink_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true });
        e.Handled = true;
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
        }
    }

    private static string ChallengeDetail(WeeklyChallengeProgress progress)
    {
        if (progress.IsAchieved)
        {
            return $"你守住了自己定下的 {progress.Challenge.TargetDays} 天约定。这不是运气，是你一次次把下一根往后放的结果。";
        }

        if (progress.IsFinished)
        {
            return $"没有归零，也没有失败。已经守住的 {progress.AchievedDays} 天，就是下一轮最真实的起点。";
        }

        if (progress.MaximumAchievableDays < progress.Challenge.TargetDays)
        {
            return $"这一轮按目前进度最多能守住 {progress.MaximumAchievableDays} 天；已经做到的不会消失，也可以把目标改成仍然可达的数字。";
        }

        return $"再守住 {progress.DaysStillNeeded} 天就能让这朵花完整开放；今天仍在进行中。";
    }

    private static string CadenceTitle(WeeklyCadence cadence) => cadence switch
    {
        WeeklyCadence.RollingSevenDays => "从今天起 7 天",
        WeeklyCadence.CalendarWeekMonday => "自然周 · 周一开始",
        _ => "自然周 · 周日开始"
    };

    private static void SelectChoice<T>(ComboBox combo, T value) where T : struct, Enum
    {
        combo.SelectedItem = combo.Items.OfType<Choice<T>>().FirstOrDefault(item => EqualityComparer<T>.Default.Equals(item.Value, value));
    }

    private Brush FindBrush(string key) => (Brush)Application.Current.FindResource(key);

    private sealed record Choice<T>(string Label, T Value)
    {
        public override string ToString() => Label;
    }
}
