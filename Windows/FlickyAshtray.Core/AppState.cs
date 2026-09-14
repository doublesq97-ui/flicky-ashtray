using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace FlickyAshtray.Core;

public sealed class AppState : INotifyPropertyChanged
{
    private readonly StoreRepository repository;

    public AppState(StoreRepository? repository = null)
    {
        this.repository = repository ?? new StoreRepository();
        var result = this.repository.Load();
        Store = result.Store ?? new SmokeStore { FirstRunDone = true };
        IsPersistenceReadOnly = !result.IsWritable;
        PersistenceMessage = result.Message;
        IsOnboardingPresented = result.IsWritable && !Store.FirstRunDone;
        Now = DateTimeOffset.UtcNow;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? StateChanged;

    public SmokeStore Store { get; private set; }
    public DateTimeOffset Now { get; private set; }
    public bool IsOnboardingPresented { get; private set; }
    public bool IsPersistenceReadOnly { get; }
    public string? PersistenceMessage { get; private set; }
    public string DataFilePath => repository.FilePath;
    public DaySnapshot Snapshot => SmokingLogic.Snapshot(Store, Now);
    public WeeklyChallengeProgress? WeeklyProgress => SmokingLogic.WeeklyChallengeProgress(Store, Now);
    public bool CanUndoToday => SmokingLogic.CanUndoRecord(Store, Now);
    public bool HasResetHistory => Store.ResetEvents.Count > 0;

    public string StatusMessage
    {
        get
        {
            var value = Snapshot;
            if (value.Count == 0) return "😌 今天还很干净";
            if (value.Count == 1 && value.Limit > 1) return "🙂 今天还是没忍住呀";
            if (value.Count == value.Limit && value.Limit > 0) return "🫶 明天就比今天少一根吧";
            if (value.Count > value.Limit) return "🥺 不是说要戒烟吗？";
            if (value.Count == value.VisibleFullAt) return "😮‍💨 害，你看又抽了这么多";
            if (value.Count > value.VisibleFullAt) return "😟 行了行了，别抽了";
            return "🙂 默默记着，下一根晚一点";
        }
    }

    public string? PositiveFeedback
    {
        get
        {
            var gaps = Snapshot.Records.Where(record => record.GapMinutes is not null).Select(record => record.GapMinutes!.Value).ToArray();
            if (gaps.Length >= 2)
            {
                var improvement = gaps[^1] - gaps[^2];
                if (improvement >= 10)
                {
                    return $"🌿 这一根比上次多等了 {improvement} 分钟";
                }
            }

            var progress = WeeklyProgress;
            if (progress is not null)
            {
                return progress.IsAchieved
                    ? "🌸 7 天目标已经开花了"
                    : $"🌱 7 天目标：已守住 {progress.AchievedDays} 天";
            }

            return null;
        }
    }

    public int MaximumAchievableDays(WeeklyCadence cadence) =>
        SmokingLogic.MaximumAchievableDays(Store, Now, cadence);

    public bool AddRecord()
    {
        RefreshClock();
        return Commit(SmokingLogic.AddingRecord(Store, Now));
    }

    public bool UndoToday()
    {
        RefreshClock();
        if (!SmokingLogic.CanUndoRecord(Store, Now))
        {
            return false;
        }

        return Commit(SmokingLogic.UndoingLastRecord(Store, Now));
    }

    public bool ResetHistory(string reason)
    {
        RefreshClock();
        return Commit(SmokingLogic.ResettingHistory(Store, Now, reason));
    }

    public bool CompleteOnboarding(int limit)
    {
        var next = StoreCopies.DeepCopy(Store);
        next.Settings.DailyLimit = limit;
        next.FirstRunDone = true;
        next.Normalize();
        if (!Commit(next))
        {
            return false;
        }

        IsOnboardingPresented = false;
        NotifyAll();
        StateChanged?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public bool UpdateSettings(int limit, int dayStartHour, double petScale, PetStyle petStyle)
    {
        var next = StoreCopies.DeepCopy(Store);
        next.Settings.DailyLimit = limit;
        next.Settings.DayStartHour = dayStartHour;
        next.Settings.PetScale = petScale;
        next.Settings.PetStyle = petStyle;
        next.Normalize();
        return Commit(next);
    }

    public bool StartWeeklyChallenge(int targetDays, string reward, WeeklyCadence cadence)
    {
        RefreshClock();
        var maximum = MaximumAchievableDays(cadence);
        if (maximum <= 0)
        {
            return false;
        }

        var next = StoreCopies.DeepCopy(Store);
        next.WeeklyChallenge = new WeeklyChallenge
        {
            StartedAt = Now,
            TargetDays = Math.Clamp(targetDays, 1, maximum),
            Reward = reward,
            Cadence = cadence,
            PeriodStart = SmokingLogic.WeeklyPeriodStart(Now, cadence, Store.Settings.DayStartHour),
            DailyLimit = Store.Settings.DailyLimit,
            DayStartHour = Store.Settings.DayStartHour,
            TimeZoneIdentifier = TimeZoneSupport.LocalIanaIdentifier()
        };
        next.Normalize();
        return Commit(next);
    }

    public bool UpdateWeeklyChallenge(int targetDays, string reward)
    {
        RefreshClock();
        var progress = WeeklyProgress;
        if (progress is null || progress.IsFinished || progress.MaximumAchievableDays <= 0 || Store.WeeklyChallenge is null)
        {
            return false;
        }

        var next = StoreCopies.DeepCopy(Store);
        next.WeeklyChallenge!.TargetDays = Math.Clamp(targetDays, 1, progress.MaximumAchievableDays);
        next.WeeklyChallenge.Reward = reward;
        next.Normalize();
        return Commit(next);
    }

    public void RefreshClock()
    {
        Now = DateTimeOffset.UtcNow;
        NotifyAll();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private bool Commit(SmokeStore proposed)
    {
        if (IsPersistenceReadOnly)
        {
            PersistenceMessage ??= "记录当前处于只读保护状态，本次操作没有写入。";
            NotifyAll();
            StateChanged?.Invoke(this, EventArgs.Empty);
            return false;
        }

        proposed.Normalize();
        try
        {
            repository.Save(proposed);
        }
        catch (Exception error)
        {
            PersistenceMessage = $"保存失败，本次操作没有记入，原记录保持不变：{error.Message}";
            NotifyAll();
            StateChanged?.Invoke(this, EventArgs.Empty);
            return false;
        }

        Store = proposed;
        PersistenceMessage = null;
        NotifyAll();
        StateChanged?.Invoke(this, EventArgs.Empty);
        return true;
    }

    private void NotifyAll()
    {
        OnPropertyChanged(nameof(Store));
        OnPropertyChanged(nameof(Now));
        OnPropertyChanged(nameof(Snapshot));
        OnPropertyChanged(nameof(WeeklyProgress));
        OnPropertyChanged(nameof(CanUndoToday));
        OnPropertyChanged(nameof(StatusMessage));
        OnPropertyChanged(nameof(PositiveFeedback));
        OnPropertyChanged(nameof(PersistenceMessage));
        OnPropertyChanged(nameof(IsOnboardingPresented));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
