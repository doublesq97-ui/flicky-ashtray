using Microsoft.Win32;
using System.Windows;
using System.Windows.Media;

namespace FlickyAshtray.Windows;

internal static class ThemeManager
{
    public static bool IsDarkMode()
    {
        if (SystemParameters.HighContrast)
        {
            return false;
        }

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch
        {
            return false;
        }
    }

    public static void ApplyCurrentTheme(ResourceDictionary resources)
    {
        var colors = IsDarkMode()
            ? new Dictionary<string, string>
            {
                ["WindowBackgroundBrush"] = "#FF141815",
                ["SurfaceBrush"] = "#FF1D241F",
                ["RaisedSurfaceBrush"] = "#FF303B33",
                ["PrimaryTextBrush"] = "#FFF1F5F2",
                ["SecondaryTextBrush"] = "#FFAEBAB1",
                ["TertiaryTextBrush"] = "#FF7E8D82",
                ["BorderBrush"] = "#FF39463D",
                ["AccentBrush"] = "#FF6CC589",
                ["AccentSoftBrush"] = "#FF233C2B",
                ["DangerBrush"] = "#FFFF7777",
                ["DangerSoftBrush"] = "#FF402627"
            }
            : new Dictionary<string, string>
            {
                ["WindowBackgroundBrush"] = "#FFF6F8FB",
                ["SurfaceBrush"] = "#FFFFFFFF",
                ["RaisedSurfaceBrush"] = "#FFF1F5FA",
                ["PrimaryTextBrush"] = "#FF18202B",
                ["SecondaryTextBrush"] = "#FF52606C",
                ["TertiaryTextBrush"] = "#FF7A8794",
                ["BorderBrush"] = "#FFD6DFE9",
                ["AccentBrush"] = "#FF3478F6",
                ["AccentSoftBrush"] = "#FFE5EFFF",
                ["DangerBrush"] = "#FFD43A3A",
                ["DangerSoftBrush"] = "#FFFFECEC"
            };

        foreach (var pair in colors)
        {
            resources[pair.Key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(pair.Value));
        }
    }
}
