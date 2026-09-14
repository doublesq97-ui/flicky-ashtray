using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace FlickyAshtray.Core;

public enum StoreLoadStatus
{
    Missing,
    Loaded,
    Migrated,
    Corrupt,
    UnsupportedFutureVersion
}

public enum StoreLoadSource
{
    Primary,
    Backup
}

public sealed record StoreLoadResult(
    StoreLoadStatus Status,
    SmokeStore? Store,
    StoreLoadSource? Source,
    bool IsWritable,
    string? Message,
    int? SourceVersion = null
);

public sealed class StoreRepository
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    public StoreRepository(string? filePath = null)
    {
        FilePath = filePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Flicky Ashtray",
            "store.json"
        );
    }

    public string FilePath { get; }
    public string BackupPath => FilePath + ".bak";

    public StoreLoadResult Load()
    {
        var primary = Inspect(FilePath);
        return primary.Kind switch
        {
            InspectionKind.Missing => LoadWithoutPrimary(),
            InspectionKind.Readable => FinishReadableLoad(primary, StoreLoadSource.Primary),
            InspectionKind.Future => new StoreLoadResult(
                StoreLoadStatus.UnsupportedFutureVersion,
                null,
                StoreLoadSource.Primary,
                false,
                $"记录文件来自更新版本（v{primary.Version}）。当前 Windows 版不会降级或覆盖它。",
                primary.Version
            ),
            _ => RecoverReadOnlyFromBackup(primary.Message ?? "记录文件无法读取。")
        };
    }

    public void Save(SmokeStore store)
    {
        var primary = Inspect(FilePath);
        if (primary.Kind == InspectionKind.Corrupt)
        {
            throw new IOException($"记录文件无法安全读取，已拒绝覆盖：{primary.Message}");
        }

        if (primary.Kind == InspectionKind.Future)
        {
            throw new IOException($"记录文件来自更新版本（v{primary.Version}），已拒绝降级覆盖。");
        }

        var backup = Inspect(BackupPath);
        if (primary.Kind == InspectionKind.Readable && backup.Kind == InspectionKind.Future)
        {
            throw new IOException($"备份来自更新版本 v{backup.Version}，当前主记录不能证明它可被安全替换。");
        }

        if (primary.Kind == InspectionKind.Missing && File.Exists(BackupPath))
        {
            throw new IOException("主记录缺失时不会盲目覆盖现有备份；请重启应用，让它先验证并恢复备份。");
        }

        Commit(store);
    }

    public static string SerializeForCompatibilityCheck(SmokeStore store)
    {
        var copy = StoreCopies.DeepCopy(store);
        copy.Normalize();
        return JsonSerializer.Serialize(copy, JsonOptions);
    }

    private StoreLoadResult LoadWithoutPrimary()
    {
        var backup = Inspect(BackupPath);
        switch (backup.Kind)
        {
            case InspectionKind.Missing:
                return new StoreLoadResult(
                    StoreLoadStatus.Missing,
                    new SmokeStore(),
                    null,
                    true,
                    null
                );
            case InspectionKind.Readable:
                try
                {
                    Commit(backup.Store!, allowExistingBackupWithoutPrimary: true);
                    return new StoreLoadResult(
                        backup.Version < SmokeStore.CurrentVersion ? StoreLoadStatus.Migrated : StoreLoadStatus.Loaded,
                        backup.Store,
                        StoreLoadSource.Backup,
                        true,
                        "主记录曾缺失，已从最后可用备份安全恢复。",
                        backup.Version
                    );
                }
                catch (Exception error)
                {
                    return new StoreLoadResult(
                        backup.Version < SmokeStore.CurrentVersion ? StoreLoadStatus.Migrated : StoreLoadStatus.Loaded,
                        backup.Store,
                        StoreLoadSource.Backup,
                        false,
                        $"记录已从备份安全读取，但恢复写回失败；当前只读：{error.Message}",
                        backup.Version
                    );
                }
            case InspectionKind.Future:
                return new StoreLoadResult(
                    StoreLoadStatus.UnsupportedFutureVersion,
                    null,
                    StoreLoadSource.Backup,
                    false,
                    $"主记录缺失，但备份来自更新版本（v{backup.Version}）。当前版本不会覆盖它。",
                    backup.Version
                );
            default:
                return new StoreLoadResult(
                    StoreLoadStatus.Corrupt,
                    null,
                    StoreLoadSource.Backup,
                    false,
                    $"主记录缺失，且备份无法读取。原文件保持不变，当前只读：{backup.Message}"
                );
        }
    }

    private StoreLoadResult FinishReadableLoad(Inspection inspection, StoreLoadSource source)
    {
        if (inspection.Version >= SmokeStore.CurrentVersion)
        {
            return new StoreLoadResult(
                StoreLoadStatus.Loaded,
                inspection.Store,
                source,
                true,
                null,
                inspection.Version
            );
        }

        var snapshotPath = FilePath + $".v{inspection.Version}.pre-migration.bak";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            if (!File.Exists(snapshotPath))
            {
                using var snapshot = new FileStream(snapshotPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
                snapshot.Write(inspection.Bytes!);
                snapshot.Flush(true);
            }
            else if (!File.ReadAllBytes(snapshotPath).SequenceEqual(inspection.Bytes!))
            {
                throw new IOException($"v{inspection.Version} 迁移留档已存在且内容不同。");
            }

            Commit(inspection.Store!);
            return new StoreLoadResult(
                StoreLoadStatus.Migrated,
                inspection.Store,
                source,
                true,
                $"记录已从 v{inspection.Version} 安全迁移到 v{SmokeStore.CurrentVersion}。",
                inspection.Version
            );
        }
        catch (Exception error)
        {
            return new StoreLoadResult(
                StoreLoadStatus.Migrated,
                inspection.Store,
                source,
                false,
                $"记录已安全读取，但迁移写回失败；当前只读：{error.Message}",
                inspection.Version
            );
        }
    }

    private StoreLoadResult RecoverReadOnlyFromBackup(string primaryReason)
    {
        var backup = Inspect(BackupPath);
        return backup.Kind switch
        {
            InspectionKind.Readable => new StoreLoadResult(
                StoreLoadStatus.Corrupt,
                backup.Store,
                StoreLoadSource.Backup,
                false,
                $"主记录文件无法读取，已从最后可用备份恢复查看。原文件保持不变，当前只读：{primaryReason}"
            ),
            InspectionKind.Future => new StoreLoadResult(
                StoreLoadStatus.Corrupt,
                null,
                StoreLoadSource.Primary,
                false,
                $"主记录无法读取，备份来自更新版本（v{backup.Version}）。当前只读，且不会覆盖任一文件。"
            ),
            InspectionKind.Corrupt => new StoreLoadResult(
                StoreLoadStatus.Corrupt,
                null,
                StoreLoadSource.Primary,
                false,
                $"主记录与备份都无法读取，原文件均保持不变。主文件：{primaryReason}；备份：{backup.Message}"
            ),
            _ => new StoreLoadResult(
                StoreLoadStatus.Corrupt,
                null,
                StoreLoadSource.Primary,
                false,
                $"主记录文件无法读取，且没有可用备份。原文件保持不变，当前只读：{primaryReason}"
            )
        };
    }

    private void Commit(SmokeStore store, bool allowExistingBackupWithoutPrimary = false)
    {
        var normalized = StoreCopies.DeepCopy(store);
        normalized.Normalize();
        var bytes = JsonSerializer.SerializeToUtf8Bytes(normalized, JsonOptions);
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);

        byte[]? primaryBefore = File.Exists(FilePath) ? File.ReadAllBytes(FilePath) : null;
        byte[]? backupBefore = File.Exists(BackupPath) ? File.ReadAllBytes(BackupPath) : null;
        if (primaryBefore is null && backupBefore is not null && !allowExistingBackupWithoutPrimary)
        {
            throw new IOException("主记录缺失时不会盲目覆盖现有备份。");
        }

        WriteAtomic(FilePath, bytes);
        try
        {
            WriteAtomic(BackupPath, bytes);
        }
        catch
        {
            Restore(FilePath, primaryBefore);
            Restore(BackupPath, backupBefore);
            throw;
        }
    }

    private Inspection Inspect(string path)
    {
        if (!File.Exists(path))
        {
            return Inspection.Missing();
        }

        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception error)
        {
            return Inspection.Corrupt($"无法读取文件：{error.Message}");
        }

        try
        {
            var node = JsonNode.Parse(bytes)?.AsObject()
                ?? throw new JsonException("JSON 根节点必须是对象。");
            var version = node["version"]?.GetValue<int>() ?? 1;
            if (version < 1)
            {
                return Inspection.Corrupt($"版本号 {version} 无效。");
            }

            if (version > SmokeStore.CurrentVersion)
            {
                return Inspection.Future(version, bytes);
            }

            if (node["version"] is null && HasModernShape(node))
            {
                return Inspection.Corrupt("现代记录结构缺少版本号，无法安全推断迁移来源。");
            }

            ValidateRequiredShape(node, version);
            PrepareLegacyNode(node, version);
            var store = node.Deserialize<SmokeStore>(JsonOptions)
                ?? throw new JsonException("记录结构为空。");
            store.Normalize();
            return Inspection.Readable(store, version, bytes);
        }
        catch (Exception error)
        {
            return Inspection.Corrupt($"记录结构无法解码：{error.Message}", bytes);
        }
    }

    private static bool HasModernShape(JsonObject root)
    {
        var settings = root["settings"] as JsonObject;
        return settings?["petScale"] is not null
            || settings?["petStyle"] is not null
            || root["weeklyChallenge"] is not null
            || root["undoneCountingDays"] is not null
            || root["undoEvents"] is not null
            || root["resetEvents"] is not null;
    }

    private static void ValidateRequiredShape(JsonObject root, int sourceVersion)
    {
        var settings = RequireObject(root, "settings");
        RequireInteger(settings, "dailyLimit");
        RequireInteger(settings, "dayStartHour");
        RequireArray(root, "records");
        RequireBoolean(root, "firstRunDone");

        if (sourceVersion >= 7)
        {
            RequireNumber(settings, "petScale");
        }

        if (sourceVersion >= 8)
        {
            RequireString(settings, "petStyle");
        }

        if (sourceVersion >= 3)
        {
            RequireArray(root, "undoneCountingDays");
        }

        if (sourceVersion == 4 || sourceVersion >= 5)
        {
            RequireArray(root, "undoEvents");
        }

        if (sourceVersion >= 5)
        {
            RequireArray(root, "resetEvents");
        }

        if (root["weeklyChallenge"] is JsonObject challenge)
        {
            RequireString(challenge, "startedAt");
            if (sourceVersion >= 7)
            {
                RequireString(challenge, "id");
                RequireInteger(challenge, "targetDays");
                RequireString(challenge, "reward");
                RequireString(challenge, "cadence");
                RequireString(challenge, "periodStart");
                RequireInteger(challenge, "dailyLimit");
                RequireInteger(challenge, "dayStartHour");
                RequireString(challenge, "timeZoneIdentifier");
            }
        }
        else if (root["weeklyChallenge"] is not null)
        {
            throw new JsonException("weeklyChallenge 必须是对象或 null。");
        }

        if (root["resetEvents"] is JsonArray resetEvents)
        {
            foreach (var item in resetEvents)
            {
                var reset = item as JsonObject ?? throw new JsonException("resetEvents 包含无效项目。");
                RequireString(reset, "id");
                RequireString(reset, "occurredAt");
                RequireString(reset, "reason");
                RequireInteger(reset, "clearedRecordCount");
            }
        }

        if (sourceVersion >= 5 && root["undoEvents"] is JsonArray undoEvents)
        {
            foreach (var item in undoEvents)
            {
                var undo = item as JsonObject ?? throw new JsonException("undoEvents 包含无效项目。");
                RequireString(undo, "occurredAt");
                if (sourceVersion >= 6)
                {
                    RequireString(undo, "originalStart");
                    RequireString(undo, "originalEnd");
                    RequireInteger(undo, "dayStartHour");
                }
                else
                {
                    var hasFrozenRange = IsString(undo["originalStart"]) && IsString(undo["originalEnd"]);
                    var hasLegacyStart = IsString(undo["countingDayStart"]);
                    if (!hasFrozenRange && !hasLegacyStart)
                    {
                        throw new JsonException("v5 undoEvent 缺少可识别的原始计数日边界。");
                    }
                }
            }
        }
    }

    private static JsonObject RequireObject(JsonObject parent, string name) =>
        parent[name] as JsonObject ?? throw new JsonException($"缺少对象字段：{name}。");

    private static JsonArray RequireArray(JsonObject parent, string name) =>
        parent[name] as JsonArray ?? throw new JsonException($"缺少数组字段：{name}。");

    private static void RequireString(JsonObject parent, string name)
    {
        if (!IsString(parent[name]))
        {
            throw new JsonException($"缺少字符串字段：{name}。");
        }
    }

    private static void RequireInteger(JsonObject parent, string name)
    {
        if (parent[name] is not JsonValue value || !value.TryGetValue<int>(out _))
        {
            throw new JsonException($"缺少整数字段：{name}。");
        }
    }

    private static void RequireNumber(JsonObject parent, string name)
    {
        if (parent[name] is not JsonValue value || !value.TryGetValue<double>(out _))
        {
            throw new JsonException($"缺少数字字段：{name}。");
        }
    }

    private static void RequireBoolean(JsonObject parent, string name)
    {
        if (parent[name] is not JsonValue value || !value.TryGetValue<bool>(out _))
        {
            throw new JsonException($"缺少布尔字段：{name}。");
        }
    }

    private static bool IsString(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<string>(out _);

    private static void PrepareLegacyNode(JsonObject root, int sourceVersion)
    {
        root["version"] = sourceVersion;
        var settings = root["settings"] as JsonObject ?? new JsonObject();
        root["settings"] = settings;
        settings["petScale"] ??= 1.0;
        settings["petStyle"] ??= "ashtray";
        if (sourceVersion < 3)
        {
            root["undoneCountingDays"] = new JsonArray();
        }
        if (sourceVersion < 5)
        {
            root["resetEvents"] = new JsonArray();
        }

        var dayStartHour = settings["dayStartHour"]?.GetValue<int>() ?? 0;
        if (sourceVersion <= 3)
        {
            root["undoEvents"] = new JsonArray();
            return;
        }

        if (sourceVersion == 4 && root["undoEvents"] is JsonArray legacyDates)
        {
            var converted = new JsonArray();
            foreach (var item in legacyDates)
            {
                if (item is null || !DateTimeOffset.TryParse(item.GetValue<string>(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var occurredAt))
                {
                    continue;
                }

                var range = new CountingDayPolicy(dayStartHour).RangeContaining(occurredAt);
                converted.Add(NewUndoNode(occurredAt, range.Start, range.End, dayStartHour));
            }

            root["undoEvents"] = converted;
        }
        else if (sourceVersion is 5 or 6 && root["undoEvents"] is JsonArray legacyEvents)
        {
            foreach (var item in legacyEvents.OfType<JsonObject>())
            {
                item["dayStartHour"] ??= dayStartHour;
                item["originalStart"] ??= item["countingDayStart"]?.DeepClone();
                if (item["originalEnd"] is null
                    && DateTimeOffset.TryParse(item["originalStart"]?.GetValue<string>(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var start))
                {
                    item["originalEnd"] = start.AddDays(1).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
                }
            }
        }
        else
        {
            root["undoEvents"] ??= new JsonArray();
        }
    }

    private static JsonObject NewUndoNode(
        DateTimeOffset occurredAt,
        DateTimeOffset originalStart,
        DateTimeOffset originalEnd,
        int dayStartHour
    ) => new()
    {
        ["occurredAt"] = occurredAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
        ["originalStart"] = originalStart.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
        ["originalEnd"] = originalEnd.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
        ["dayStartHour"] = dayStartHour
    };

    private static void WriteAtomic(string path, byte[] bytes)
    {
        var temporary = path + $".{Guid.NewGuid():N}.tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }

            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    private static void Restore(string path, byte[]? bytes)
    {
        if (bytes is null)
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }

            return;
        }

        WriteAtomic(path, bytes);
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        options.Converters.Add(new UtcDateTimeOffsetConverter());
        return options;
    }

    private enum InspectionKind
    {
        Missing,
        Readable,
        Corrupt,
        Future
    }

    private sealed record Inspection(
        InspectionKind Kind,
        SmokeStore? Store,
        int Version,
        byte[]? Bytes,
        string? Message
    )
    {
        public static Inspection Missing() => new(InspectionKind.Missing, null, 0, null, null);
        public static Inspection Readable(SmokeStore store, int version, byte[] bytes) => new(InspectionKind.Readable, store, version, bytes, null);
        public static Inspection Corrupt(string message, byte[]? bytes = null) => new(InspectionKind.Corrupt, null, 0, bytes, message);
        public static Inspection Future(int version, byte[] bytes) => new(InspectionKind.Future, null, version, bytes, null);
    }

    private sealed class UtcDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            if (DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed))
            {
                return parsed.ToUniversalTime();
            }

            throw new JsonException($"无效的 ISO 8601 日期：{value}");
        }

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
    }
}
