using System.Windows;
using System.Windows.Controls;

namespace FlickyAshtray.Windows;

public partial class ResetHistoryWindow : Window
{
    private readonly bool isFirstReset;

    public ResetHistoryWindow(bool isFirstReset, int recordCount)
    {
        this.isFirstReset = isFirstReset;
        InitializeComponent();
        WarningText.Text = isFirstReset
            ? "第一次可以当作重新开始，但以后不要靠清空记录逃开真实情况。认真对待戒烟，也认真对待自己。"
            : "你已经重置过。再次清空会让趋势失去意义，因此只有在确实需要重新开始时才继续。";
        FirstResetCheck.Visibility = isFirstReset ? Visibility.Visible : Visibility.Collapsed;
        RepeatConfirmationPanel.Visibility = isFirstReset ? Visibility.Collapsed : Visibility.Visible;
        FinalWarningText.Text = $"将清空 {recordCount} 条抽烟记录，并结束当前 7 天目标。重置原因会作为本机审计记录保留。";
    }

    public string? ConfirmedReason { get; private set; }

    private void Validation_Changed(object sender, RoutedEventArgs e)
    {
        if (ContinueButton is null)
        {
            return;
        }

        var reasonValid = ReasonBox.Text.Trim().Length >= 4;
        var confirmationValid = isFirstReset
            ? FirstResetCheck.IsChecked == true
            : RepeatConfirmationBox.Text == "认真对待自己";
        ContinueButton.IsEnabled = reasonValid && confirmationValid;
    }

    private void ContinueButton_Click(object sender, RoutedEventArgs e)
    {
        ReasonSummaryText.Text = ReasonBox.Text.Trim();
        ReasonStage.Visibility = Visibility.Collapsed;
        FinalStage.Visibility = Visibility.Visible;
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        FinalCheck.IsChecked = false;
        FinalStage.Visibility = Visibility.Collapsed;
        ReasonStage.Visibility = Visibility.Visible;
    }

    private void FinalCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (ConfirmButton is not null)
        {
            ConfirmButton.IsEnabled = FinalCheck.IsChecked == true;
        }
    }

    private void ConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        ConfirmedReason = ReasonBox.Text.Trim();
        DialogResult = true;
    }
}
