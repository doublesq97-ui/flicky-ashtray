using FlickyAshtray.Core;

var tests = new (string Name, Action Run)[]
{
    ("08:00 日切把凌晨记录归入前一天", CountingDayStartsAtEight),
    ("DST 春季与秋季计数日长度正确", DstDayLengths),
    ("增加记录并限制每个计数日只撤销一次", AddAndUndoOnce),
    ("烟灰状态阈值与每日上限一致", AshLevelThresholds),
    ("自然周目标不补算已过去日期", NaturalWeekCapacity),
    ("周报不提前评价当前计数日", WeeklyReportKeepsTodayOpen),
    ("v8 JSON 与 macOS 字段和枚举兼容", JsonShapeMatchesMac),
    ("主记录与备份同时提交", RepositoryWritesPrimaryAndBackup),
    ("损坏主记录只读恢复备份", CorruptPrimaryRecoversReadOnly),
    ("当前结构缺字段时只读恢复备份", MissingCurrentFieldRecoversReadOnly),
    ("未知桌宠枚举不会被静默重置", UnknownPetStyleIsCorrupt),
    ("无版本号的现代结构不会冒充旧数据", VersionlessModernShapeIsCorrupt),
    ("未来版本不会被降级覆盖", FutureVersionIsProtected),
    ("未来版本备份不会被当前主记录覆盖", FutureBackupIsProtected)
};

var failed = 0;
foreach (var test in tests)
{
    try
    {
        test.Run();
        Console.WriteLine($"PASS  {test.Name}");
    }
    catch (Exception error)
    {
        failed += 1;
        Console.Error.WriteLine($"FAIL  {test.Name}\n      {error.Message}");
    }
}

Console.WriteLine($"\n{tests.Length - failed}/{tests.Length} Windows core checks passed.");
return failed == 0 ? 0 : 1;

static void CountingDayStartsAtEight()
{
    var zone = TimeZoneSupport.Resolve("Asia/Shanghai");
    var policy = new CountingDayPolicy(8, zone);
    var instant = new DateTimeOffset(2026, 9, 14, 2, 0, 0, TimeSpan.FromHours(8));
    var range = policy.RangeContaining(instant);
    Equal(new DateTimeOffset(2026, 9, 13, 8, 0, 0, TimeSpan.FromHours(8)).ToUniversalTime(), range.Start);
    Equal(new DateTimeOffset(2026, 9, 14, 8, 0, 0, TimeSpan.FromHours(8)).ToUniversalTime(), range.End);
}

static void DstDayLengths()
{
    var zone = TimeZoneSupport.Resolve("America/Los_Angeles");
    var spring = new CountingDayPolicy(0, zone).RangeContaining(
        new DateTimeOffset(2026, 3, 8, 12, 0, 0, TimeSpan.FromHours(-7))
    );
    Equal(23d, spring.Duration.TotalHours);

    var fall = new CountingDayPolicy(0, zone).RangeContaining(
        new DateTimeOffset(2026, 11, 1, 12, 0, 0, TimeSpan.FromHours(-8))
    );
    Equal(25d, fall.Duration.TotalHours);
}

static void AddAndUndoOnce()
{
    var now = new DateTimeOffset(2026, 9, 14, 10, 0, 0, TimeSpan.Zero);
    var store = new SmokeStore { FirstRunDone = true };
    store = SmokingLogic.AddingRecord(store, now.AddMinutes(-30));
    store = SmokingLogic.AddingRecord(store, now);
    True(SmokingLogic.CanUndoRecord(store, now));
    store = SmokingLogic.UndoingLastRecord(store, now);
    Equal(1, store.Records.Count);
    True(!SmokingLogic.CanUndoRecord(store, now));
    var unchanged = SmokingLogic.UndoingLastRecord(store, now);
    Equal(1, unchanged.Records.Count);
}

static void AshLevelThresholds()
{
    var now = DateTimeOffset.UtcNow;
    var store = new SmokeStore
    {
        FirstRunDone = true,
        Settings = new AppSettings { DailyLimit = 8 },
        Records = Enumerable.Range(0, 8).Select(index => now.AddMinutes(-index)).ToList()
    };
    var snapshot = SmokingLogic.Snapshot(store, now);
    Equal(AshLevel.OverLimit, snapshot.AshLevel);
    store.Records.Add(now.AddMinutes(-20));
    store.Records.Add(now.AddMinutes(-21));
    store.Records.Add(now.AddMinutes(-22));
    store.Records.Add(now.AddMinutes(-23));
    Equal(AshLevel.Filthy, SmokingLogic.Snapshot(store, now).AshLevel);
}

static void NaturalWeekCapacity()
{
    var zone = TimeZoneSupport.Resolve("Asia/Shanghai");
    var now = new DateTimeOffset(2026, 9, 17, 12, 0, 0, TimeSpan.FromHours(8)); // Thursday
    var store = new SmokeStore { FirstRunDone = true };
    Equal(4, SmokingLogic.MaximumAchievableDays(store, now, WeeklyCadence.CalendarWeekMonday, zone));
    Equal(7, SmokingLogic.MaximumAchievableDays(store, now, WeeklyCadence.RollingSevenDays, zone));
}

static void WeeklyReportKeepsTodayOpen()
{
    var now = DateTimeOffset.UtcNow;
    var store = new SmokeStore
    {
        FirstRunDone = true,
        Records = [now.AddHours(-1)]
    };
    var report = SmokingLogic.WeeklyReport(store, now);
    True(report.Days[^1].IsCurrentCountingDay);
    True(!report.Days[^1].IsComplete);
    True(!report.Days[^1].IsWithinLimit);
}

static void JsonShapeMatchesMac()
{
    var store = new SmokeStore
    {
        FirstRunDone = true,
        Settings = new AppSettings { PetStyle = PetStyle.Note },
        Records = [new DateTimeOffset(2026, 7, 14, 3, 38, 46, TimeSpan.Zero)]
    };
    var json = StoreRepository.SerializeForCompatibilityCheck(store);
    True(json.Contains("\"version\": 8", StringComparison.Ordinal));
    True(json.Contains("\"petStyle\": \"note\"", StringComparison.Ordinal));
    True(json.Contains("2026-07-14T03:38:46.000Z", StringComparison.Ordinal));
}

static void RepositoryWritesPrimaryAndBackup()
{
    WithTemporaryStore((repository, path) =>
    {
        var store = new SmokeStore { FirstRunDone = true, Records = [DateTimeOffset.UtcNow] };
        repository.Save(store);
        True(File.Exists(path));
        True(File.Exists(path + ".bak"));
        True(File.ReadAllBytes(path).SequenceEqual(File.ReadAllBytes(path + ".bak")));
        var loaded = repository.Load();
        True(loaded.IsWritable);
        Equal(1, loaded.Store!.Records.Count);
    });
}

static void CorruptPrimaryRecoversReadOnly()
{
    WithTemporaryStore((repository, path) =>
    {
        repository.Save(new SmokeStore { FirstRunDone = true, Records = [DateTimeOffset.UtcNow] });
        File.WriteAllText(path, "not-json");
        var loaded = repository.Load();
        Equal(StoreLoadStatus.Corrupt, loaded.Status);
        True(!loaded.IsWritable);
        Equal(StoreLoadSource.Backup, loaded.Source);
        Equal(1, loaded.Store!.Records.Count);
    });
}

static void MissingCurrentFieldRecoversReadOnly()
{
    WithTemporaryStore((repository, path) =>
    {
        repository.Save(new SmokeStore { FirstRunDone = true, Records = [DateTimeOffset.UtcNow] });
        File.WriteAllText(path, "{\"version\":8,\"settings\":{\"dailyLimit\":8,\"dayStartHour\":0,\"petScale\":1,\"petStyle\":\"ashtray\"},\"records\":[],\"firstRunDone\":true,\"weeklyChallenge\":null,\"undoneCountingDays\":[],\"undoEvents\":[]}");
        var loaded = repository.Load();
        Equal(StoreLoadStatus.Corrupt, loaded.Status);
        Equal(StoreLoadSource.Backup, loaded.Source);
        True(!loaded.IsWritable);
        Equal(1, loaded.Store!.Records.Count);
    });
}

static void UnknownPetStyleIsCorrupt()
{
    WithTemporaryStore((repository, path) =>
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{\"version\":8,\"settings\":{\"dailyLimit\":8,\"dayStartHour\":0,\"petScale\":1,\"petStyle\":\"spaceship\"},\"records\":[],\"firstRunDone\":true,\"weeklyChallenge\":null,\"undoneCountingDays\":[],\"undoEvents\":[],\"resetEvents\":[]}");
        var loaded = repository.Load();
        Equal(StoreLoadStatus.Corrupt, loaded.Status);
        True(!loaded.IsWritable);
    });
}

static void VersionlessModernShapeIsCorrupt()
{
    WithTemporaryStore((repository, path) =>
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{\"settings\":{\"dailyLimit\":8,\"dayStartHour\":0,\"petScale\":1,\"petStyle\":\"note\"},\"records\":[],\"firstRunDone\":true,\"undoneCountingDays\":[],\"undoEvents\":[],\"resetEvents\":[]}");
        var loaded = repository.Load();
        Equal(StoreLoadStatus.Corrupt, loaded.Status);
        True(!loaded.IsWritable);
    });
}

static void FutureVersionIsProtected()
{
    WithTemporaryStore((repository, path) =>
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{\"version\":999,\"settings\":{},\"records\":[],\"firstRunDone\":true}");
        var loaded = repository.Load();
        Equal(StoreLoadStatus.UnsupportedFutureVersion, loaded.Status);
        True(!loaded.IsWritable);
        True(loaded.Store is null);
    });
}

static void FutureBackupIsProtected()
{
    WithTemporaryStore((repository, path) =>
    {
        var original = new SmokeStore { FirstRunDone = true, Records = [DateTimeOffset.UtcNow] };
        repository.Save(original);
        var futureBytes = System.Text.Encoding.UTF8.GetBytes("{\"version\":999}");
        File.WriteAllBytes(path + ".bak", futureBytes);
        var proposed = SmokingLogic.AddingRecord(original, DateTimeOffset.UtcNow.AddMinutes(1));
        var didThrow = false;
        try
        {
            repository.Save(proposed);
        }
        catch (IOException)
        {
            didThrow = true;
        }

        True(didThrow);
        True(File.ReadAllBytes(path + ".bak").SequenceEqual(futureBytes));
    });
}

static void WithTemporaryStore(Action<StoreRepository, string> action)
{
    var directory = Path.Combine(Path.GetTempPath(), "FlickyAshtrayTests", Guid.NewGuid().ToString("N"));
    var path = Path.Combine(directory, "store.json");
    try
    {
        action(new StoreRepository(path), path);
    }
    finally
    {
        if (Directory.Exists(directory))
        {
            Directory.Delete(directory, true);
        }
    }
}

static void True(bool value)
{
    if (!value) throw new InvalidOperationException("Expected condition to be true.");
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}; received {actual}.");
    }
}
