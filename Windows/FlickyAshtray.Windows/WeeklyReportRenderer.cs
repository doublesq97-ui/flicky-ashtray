using FlickyAshtray.Core;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace FlickyAshtray.Windows;

internal static class WeeklyReportRenderer
{
    private const double Width = 760;
    private const double Height = 860;
    private const double Scale = 2;

    public static void SavePng(WeeklyReport report, string destination, bool dark)
    {
        var palette = dark ? Palette.Dark : Palette.Light;
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.PushTransform(new ScaleTransform(Scale, Scale));
            DrawCard(context, report, palette);
            context.Pop();
        }

        var bitmap = new RenderTargetBitmap(
            (int)(Width * Scale),
            (int)(Height * Scale),
            96 * Scale,
            96 * Scale,
            PixelFormats.Pbgra32
        );
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));

        var directory = Path.GetDirectoryName(destination);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporary = destination + $".{Guid.NewGuid():N}.tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                encoder.Save(stream);
                stream.Flush(true);
            }

            File.Move(temporary, destination, true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    private static void DrawCard(DrawingContext context, WeeklyReport report, Palette colors)
    {
        context.DrawRoundedRectangle(colors.Background, new Pen(colors.Border, 1), new Rect(0.5, 0.5, Width - 1, Height - 1), 32, 32);
        DrawImage(context, new Rect(40, 34, 54, 44));
        DrawText(context, "Flicky Ashtray", 108, 35, 15, FontWeights.SemiBold, colors.Primary);
        DrawText(context, "本周小结", 108, 56, 31, FontWeights.Bold, colors.Primary);
        DrawText(context, report.GeneratedAt.ToLocalTime().ToString("yyyy年M月d日", CultureInfo.GetCultureInfo("zh-CN")), 530, 43, 14, FontWeights.SemiBold, colors.Primary, 190, TextAlignment.Right);
        DrawText(context, "最近 7 个计数日", 530, 67, 12, FontWeights.Normal, colors.Secondary, 190, TextAlignment.Right);

        DrawText(context, report.Encouragement, 40, 118, 23, FontWeights.SemiBold, colors.Primary, 680);

        var comparison = report.ReductionFromPreviousPeriod switch
        {
            > 0 => $"少 {report.ReductionFromPreviousPeriod} 根",
            < 0 => $"多 {-report.ReductionFromPreviousPeriod} 根",
            _ => "持平"
        };
        DrawMetric(context, colors, new Rect(40, 186, 216, 118), "本期记录", $"{report.TotalCount} 根", $"每日上限 {report.DailyLimit} 根");
        DrawMetric(context, colors, new Rect(272, 186, 216, 118), "比前 7 天", comparison, $"同期 {report.PreviousTotalCount} 根，同一时点");
        DrawMetric(context, colors, new Rect(504, 186, 216, 118), "最长间隔", report.LongestGapMinutes is null ? "暂无" : SmokingLogic.FormattedGap(report.LongestGapMinutes.Value), "按原始时间戳计算");

        var trendRect = new Rect(40, 326, 680, 264);
        context.DrawRoundedRectangle(colors.Surface, null, trendRect, 22, 22);
        DrawText(context, "每天的节奏", 62, 348, 15, FontWeights.SemiBold, colors.Primary);
        DrawTrend(context, report, colors, new Rect(62, 388, 636, 172));

        var progressRect = new Rect(40, 612, 680, 100);
        context.DrawRoundedRectangle(colors.Surface, null, progressRect, 22, 22);
        context.DrawEllipse(colors.AccentSoft, null, new Point(85, 662), 25, 25);
        DrawText(context, "♥", 77, 651, 20, FontWeights.Bold, colors.Accent);
        DrawText(context, $"完成日守约 {report.WithinLimitDays} / {report.CompletedDayCount}", 126, 636, 16, FontWeights.SemiBold, colors.Primary);
        DrawText(context, "今天仍在进行，不提前给它下结论。", 126, 664, 13, FontWeights.Normal, colors.Secondary);

        DrawText(context, "🔒 数据只保存在这台 Windows 电脑上", 40, 798, 11.5, FontWeights.Normal, colors.Secondary);
        DrawText(context, "下一根，再晚一点。", 520, 798, 11.5, FontWeights.Normal, colors.Secondary, 200, TextAlignment.Right);
    }

    private static void DrawMetric(DrawingContext context, Palette colors, Rect rect, string title, string value, string detail)
    {
        context.DrawRoundedRectangle(colors.Surface, null, rect, 20, 20);
        DrawText(context, title, rect.X + 18, rect.Y + 16, 11.5, FontWeights.SemiBold, colors.Secondary);
        DrawText(context, value, rect.X + 18, rect.Y + 44, 23, FontWeights.Bold, colors.Primary, rect.Width - 36);
        DrawText(context, detail, rect.X + 18, rect.Y + 88, 10.5, FontWeights.Normal, colors.Tertiary, rect.Width - 36);
    }

    private static void DrawTrend(DrawingContext context, WeeklyReport report, Palette colors, Rect rect)
    {
        var maximum = Math.Max(1, Math.Max(report.DailyLimit, report.Days.Max(day => day.CigaretteCount)));
        var slot = rect.Width / report.Days.Count;
        var trackTop = rect.Top + 20;
        var trackHeight = 112d;
        var barWidth = 22d;
        for (var index = 0; index < report.Days.Count; index++)
        {
            var day = report.Days[index];
            var center = rect.X + slot * index + slot / 2;
            DrawText(context, day.CigaretteCount.ToString(CultureInfo.InvariantCulture), center - 20, rect.Y, 10.5, FontWeights.SemiBold, colors.Secondary, 40, TextAlignment.Center);
            context.DrawRoundedRectangle(colors.Track, null, new Rect(center - barWidth / 2, trackTop, barWidth, trackHeight), 11, 11);
            var valueHeight = Math.Max(day.CigaretteCount == 0 ? 4 : 10, trackHeight * Math.Min(1, (double)day.CigaretteCount / maximum));
            context.DrawRoundedRectangle(
                day.IsCurrentCountingDay ? colors.Accent : colors.AccentMuted,
                null,
                new Rect(center - barWidth / 2, trackTop + trackHeight - valueHeight, barWidth, valueHeight),
                11,
                11
            );
            var local = day.Start.ToLocalTime();
            DrawText(context, ChineseWeekday(local.DayOfWeek), center - 20, trackTop + trackHeight + 8, 10.5, day.IsCurrentCountingDay ? FontWeights.Bold : FontWeights.Normal, colors.Primary, 40, TextAlignment.Center);
            DrawText(context, local.Day.ToString(CultureInfo.InvariantCulture), center - 20, trackTop + trackHeight + 28, 9.5, FontWeights.Normal, colors.Secondary, 40, TextAlignment.Center);
        }
    }

    private static void DrawImage(DrawingContext context, Rect rect)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri("pack://application:,,,/Assets/ashtray.png");
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            context.DrawImage(image, rect);
        }
        catch
        {
            context.DrawEllipse(Brushes.SlateGray, null, new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2), rect.Width / 2, rect.Height / 3);
        }
    }

    private static void DrawText(
        DrawingContext context,
        string value,
        double x,
        double y,
        double size,
        FontWeight weight,
        Brush brush,
        double maxWidth = double.PositiveInfinity,
        TextAlignment alignment = TextAlignment.Left
    )
    {
        var formatted = new FormattedText(
            value,
            CultureInfo.GetCultureInfo("zh-CN"),
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, weight, FontStretches.Normal),
            size,
            brush,
            1
        )
        {
            TextAlignment = alignment
        };
        if (!double.IsPositiveInfinity(maxWidth))
        {
            formatted.MaxTextWidth = Math.Max(1, maxWidth);
        }

        context.DrawText(formatted, new Point(x, y));
    }

    private static string ChineseWeekday(DayOfWeek value) => value switch
    {
        DayOfWeek.Monday => "一",
        DayOfWeek.Tuesday => "二",
        DayOfWeek.Wednesday => "三",
        DayOfWeek.Thursday => "四",
        DayOfWeek.Friday => "五",
        DayOfWeek.Saturday => "六",
        _ => "日"
    };

    private sealed record Palette(
        Brush Background,
        Brush Surface,
        Brush Track,
        Brush Primary,
        Brush Secondary,
        Brush Tertiary,
        Brush Accent,
        Brush AccentMuted,
        Brush AccentSoft,
        Brush Border
    )
    {
        public static Palette Light { get; } = new(
            Solid("#F7F9FC"), Solid("#FFFFFF"), Solid("#E0E8F1"), Solid("#18202B"),
            Solid("#525E6C"), Solid("#778492"), Solid("#3478F6"), Solid("#6D9DE8"),
            Solid("#E5EFFF"), Solid("#D6DFE9")
        );

        public static Palette Dark { get; } = new(
            Solid("#141815"), Solid("#1D241F"), Solid("#303B33"), Solid("#F1F5F2"),
            Solid("#AEBAB1"), Solid("#7E8D82"), Solid("#6CC589"),
            Solid("#529A69"), Solid("#233C2B"), Solid("#39463D")
        );

        private static SolidColorBrush Solid(string value)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(value));
            brush.Freeze();
            return brush;
        }
    }
}
