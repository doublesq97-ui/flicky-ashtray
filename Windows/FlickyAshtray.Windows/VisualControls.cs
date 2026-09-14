using FlickyAshtray.Core;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace FlickyAshtray.Windows;

public sealed class TrendChart : FrameworkElement
{
    private IReadOnlyList<DayTotal> days = [];
    private int dailyLimit = 8;

    public void SetData(IReadOnlyList<DayTotal> values, int limit)
    {
        days = values;
        dailyLimit = Math.Max(1, limit);
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (days.Count == 0 || ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        var accent = Brush("AccentBrush", Brushes.DodgerBlue);
        var secondary = Brush("SecondaryTextBrush", Brushes.Gray);
        var track = Brush("RaisedSurfaceBrush", Brushes.LightGray);
        var danger = Brush("DangerBrush", Brushes.IndianRed);
        var pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var chartTop = 20d;
        var chartBottom = Math.Max(chartTop + 20, ActualHeight - 26);
        var chartHeight = chartBottom - chartTop;
        var slot = ActualWidth / days.Count;
        var barWidth = Math.Clamp(slot * 0.42, 12, 28);
        var maximum = Math.Max(dailyLimit, Math.Max(1, days.Max(day => day.Count)));

        for (var index = 0; index < days.Count; index++)
        {
            var day = days[index];
            var center = slot * index + slot / 2;
            var trackRect = new Rect(center - barWidth / 2, chartTop, barWidth, chartHeight);
            drawingContext.DrawRoundedRectangle(track, null, trackRect, barWidth / 2, barWidth / 2);
            var fraction = Math.Clamp((double)day.Count / maximum, 0, 1);
            var height = Math.Max(day.Count == 0 ? 4 : 8, chartHeight * fraction);
            var valueRect = new Rect(center - barWidth / 2, chartBottom - height, barWidth, height);
            drawingContext.DrawRoundedRectangle(day.Count > dailyLimit ? danger : accent, null, valueRect, barWidth / 2, barWidth / 2);

            DrawCenteredText(drawingContext, day.Count.ToString(CultureInfo.InvariantCulture), center, 0, 10.5, secondary, pixelsPerDip);
            DrawCenteredText(drawingContext, day.Date.ToLocalTime().ToString("dd", CultureInfo.InvariantCulture), center, chartBottom + 7, 10.5, secondary, pixelsPerDip);
        }
    }

    private static void DrawCenteredText(
        DrawingContext context,
        string value,
        double centerX,
        double y,
        double size,
        Brush brush,
        double pixelsPerDip
    )
    {
        var text = new FormattedText(
            value,
            CultureInfo.GetCultureInfo("zh-CN"),
            FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"),
            size,
            brush,
            pixelsPerDip
        );
        context.DrawText(text, new Point(centerX - text.Width / 2, y));
    }

    private Brush Brush(string key, Brush fallback) => TryFindResource(key) as Brush ?? fallback;
}

public sealed class ChallengeFlower : FrameworkElement
{
    private IReadOnlyList<ChallengeDayStatus> statuses = Enumerable.Repeat(ChallengeDayStatus.Upcoming, 7).ToArray();
    private bool achieved;

    public void SetProgress(WeeklyChallengeProgress? progress)
    {
        statuses = progress?.Days.Select(day => day.Status).ToArray()
            ?? Enumerable.Repeat(ChallengeDayStatus.Upcoming, 7).ToArray();
        achieved = progress?.IsAchieved == true;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var accent = Brush("AccentBrush", Brushes.DodgerBlue);
        var secondary = Brush("SecondaryTextBrush", Brushes.Gray);

        for (var index = 0; index < Math.Min(7, statuses.Count); index++)
        {
            var fill = statuses[index] switch
            {
                ChallengeDayStatus.Achieved => WithOpacity(accent, 1),
                ChallengeDayStatus.Missed => WithOpacity(secondary, 0.22),
                ChallengeDayStatus.Active => WithOpacity(accent, 0.42),
                ChallengeDayStatus.Upcoming => WithOpacity(secondary, 0.12),
                _ => WithOpacity(secondary, 0.05)
            };
            drawingContext.PushTransform(new RotateTransform(index * (360d / 7d), center.X, center.Y));
            drawingContext.DrawRoundedRectangle(
                fill,
                new Pen(WithOpacity(secondary, statuses[index] == ChallengeDayStatus.Active ? 0.28 : 0.1), 1),
                new Rect(center.X - 15, center.Y - 61, 30, 56),
                15,
                15
            );
            drawingContext.Pop();
        }

        drawingContext.DrawEllipse(achieved ? accent : WithOpacity(secondary, 0.34), null, center, 18, 18);
        var pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var glyph = new FormattedText(
            achieved ? "✓" : "♥",
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI Symbol"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
            14,
            Brushes.White,
            pixelsPerDip
        );
        drawingContext.DrawText(glyph, new Point(center.X - glyph.Width / 2, center.Y - glyph.Height / 2));
    }

    private static Brush WithOpacity(Brush source, double opacity)
    {
        var result = source.Clone();
        result.Opacity = opacity;
        return result;
    }

    private Brush Brush(string key, Brush fallback) => TryFindResource(key) as Brush ?? fallback;
}
