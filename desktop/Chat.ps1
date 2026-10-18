# Native WPF chat surface. Conversation and pet actions are supplied by the host.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$script:chatWindow = $null
$script:chatHistory = New-Object 'System.Collections.Generic.List[object]'
$script:chatSending = $false
$script:chatTestMode = $false

function Add-PetChatBubble([string]$Role, [string]$Text, [switch]$Replay) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if (-not $Replay) {
        $script:chatHistory.Add([PSCustomObject]@{ Role = $Role; Text = $Text })
        while ($script:chatHistory.Count -gt 120) { $script:chatHistory.RemoveAt(0) }
    }
    if ($null -eq $script:chatWindow -or -not $script:chatWindow.IsLoaded) { return }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $isUser = $Role -eq 'user'
    $row.HorizontalAlignment = if ($isUser) { 'Right' } else { 'Left' }
    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = if ($isUser) { '你' } else { '伊蕾娜' }
    $name.FontSize = 11
    $name.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9C8EAA')
    $name.Margin = [System.Windows.Thickness]::new(5, 0, 5, 4)
    $name.HorizontalAlignment = if ($isUser) { 'Right' } else { 'Left' }
    [void]$row.Children.Add($name)
    $bubble = New-Object System.Windows.Controls.Border
    $bubble.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $bubble.Padding = [System.Windows.Thickness]::new(13, 10, 13, 10)
    $bubble.MaxWidth = 320
    $bubble.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($isUser) { '#EAE2F7' } else { '#FFFFFF' }))
    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = $Text
    $body.TextWrapping = 'Wrap'
    $body.FontSize = 14
    $body.LineHeight = 23
    $body.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#55465F')
    $bubble.Child = $body
    [void]$row.Children.Add($bubble)
    [void]$script:chatMessages.Children.Add($row)
    while ($script:chatMessages.Children.Count -gt 120) { $script:chatMessages.Children.RemoveAt(0) }
    $script:chatScroll.ScrollToEnd()
}

function Add-PetChatReply([string]$Text, [string]$Status = '') {
    Add-PetChatBubble -Role 'pet' -Text $Text
    if ($script:chatWindow -and $script:chatWindow.IsLoaded -and $Status) { $script:chatStatus.Text = $Status }
}

function Send-PetChatMessage([string]$Text) {
    if ($script:chatSending) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { $script:chatInput.Focus() | Out-Null; return }
    $Text = $Text.Trim()
    if ($Text.Length -gt 600) { $Text = $Text.Substring(0, 600) }
    $script:chatSending = $true
    $script:chatSend.IsEnabled = $false
    $script:chatInput.Clear()
    Add-PetChatBubble -Role 'user' -Text $Text
    try {
        if ($script:chatTestMode) {
            $script:chatTestCalls.Add($Text)
            $reply = [PSCustomObject]@{ Text = ('收到：' + $Text); Action = 'test'; Status = '测试回应' }
        } else { $reply = Invoke-PetConversation -Text $Text }
        if ($null -ne $reply -and $reply.Status -and $script:chatWindow) { $script:chatStatus.Text = [string]$reply.Status }
        if ($null -ne $reply -and -not [string]::IsNullOrWhiteSpace([string]$reply.Text)) {
            Add-PetChatReply -Text ([string]$reply.Text) -Status ([string]$reply.Status)
        }
    } catch {
        Add-PetChatReply -Text '刚刚走神了一小下……再跟我说一次，好不好？' -Status '刚刚没接住这句话，可以再试一次'
        Write-Warning ('桌宠互动失败：' + $_.Exception.Message)
    } finally {
        $script:chatSending = $false
        if ($script:chatWindow -and $script:chatWindow.IsLoaded) {
            $script:chatSend.IsEnabled = $true
            $script:chatInput.Focus() | Out-Null
        }
    }
}

function Show-PetChat {
    if ($null -ne $script:chatWindow -and $script:chatWindow.IsLoaded) {
        if ($script:chatWindow.WindowState -eq 'Minimized') { $script:chatWindow.WindowState = 'Normal' }
        $script:chatWindow.Activate() | Out-Null
        $script:chatInput.Focus() | Out-Null
        return
    }
    [xml]$markup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="和伊蕾娜说说话" Width="460" Height="590" MinWidth="400" MinHeight="440" Background="#F7F3FB"
 FontFamily="Microsoft YaHei UI" WindowStartupLocation="CenterScreen" ResizeMode="CanResizeWithGrip" ShowInTaskbar="True">
 <Window.Resources>
  <Style TargetType="Button">
   <Setter Property="Background" Value="#EEE5F8"/><Setter Property="Foreground" Value="#6A4C82"/>
   <Setter Property="Padding" Value="12,8"/><Setter Property="BorderThickness" Value="0"/>
   <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border><ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#DDCDED"/></Trigger>
     <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.7"/></Trigger>
     <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>
 <Grid Margin="18,12,18,16">
  <Grid.RowDefinitions><RowDefinition Height="76"/><RowDefinition Height="*"/><RowDefinition Height="140"/></Grid.RowDefinitions>
  <StackPanel Grid.Row="0">
   <TextBlock Text="伊蕾娜的悄悄话" FontSize="23" FontWeight="SemiBold" Foreground="#705684"/>
   <TextBlock x:Name="ChatStatus" Text="来摸摸头，或者和我聊一句吧 ♡" Margin="0,7,0,0" FontSize="12" Foreground="#A48CAC" TextTrimming="CharacterEllipsis"/>
  </StackPanel>
  <ScrollViewer x:Name="ChatScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,5,0">
   <StackPanel x:Name="ChatMessages"/>
  </ScrollViewer>
  <Grid Grid.Row="2" Margin="0,8,0,0">
   <Grid.RowDefinitions><RowDefinition Height="40"/><RowDefinition Height="40"/><RowDefinition Height="*"/></Grid.RowDefinitions>
   <UniformGrid x:Name="ChatQuick" Rows="1" Columns="4" Margin="0,0,0,7">
    <Button Content="摸摸头" Tag="摸摸头" Margin="0,0,5,0" Padding="6,5"/>
    <Button Content="抱抱 ♡" Tag="抱抱" Margin="2,0,3,0" Padding="6,5"/>
    <Button Content="夸夸她" Tag="你真可爱" Margin="3,0,2,0" Padding="6,5"/>
    <Button Content="逗逗她" Tag="逗逗你" Margin="5,0,0,0" Padding="6,5"/>
   </UniformGrid>
   <UniformGrid x:Name="ChatQuickExtra" Grid.Row="1" Rows="1" Columns="3" Margin="0,0,0,7">
    <Button Content="猜拳" Tag="猜拳" Margin="0,0,5,0" Padding="6,5"/>
    <Button Content="晚安 ☾" Tag="晚安" Margin="2,0,3,0" Padding="6,5"/>
    <Button Content="再来一次" Tag="再来" Margin="5,0,0,0" Padding="6,5"/>
   </UniformGrid>
   <Grid Grid.Row="2">
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="78"/></Grid.ColumnDefinitions>
    <Border Background="White" CornerRadius="12" BorderBrush="#E4D8ED" BorderThickness="1" Padding="10,7">
     <TextBox x:Name="ChatInput" MaxLength="600" Background="Transparent" BorderThickness="0" FontSize="14" VerticalContentAlignment="Center" Foreground="#55465F" AcceptsReturn="False" ToolTip="输入一句话，按 Enter 发送"/>
    </Border>
    <Button x:Name="ChatSend" Grid.Column="1" Content="发送 ♡" Margin="8,0,0,0" Padding="6,7"/>
   </Grid>
  </Grid>
 </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader($markup)
    $script:chatWindow = [System.Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    $script:chatInput = $script:chatWindow.FindName('ChatInput')
    $script:chatSend = $script:chatWindow.FindName('ChatSend')
    $script:chatMessages = $script:chatWindow.FindName('ChatMessages')
    $script:chatScroll = $script:chatWindow.FindName('ChatScroll')
    $script:chatStatus = $script:chatWindow.FindName('ChatStatus')
    $script:chatQuick = $script:chatWindow.FindName('ChatQuick')
    $script:chatQuickExtra = $script:chatWindow.FindName('ChatQuickExtra')
    if (-not $script:chatTestMode -and (Get-Command Get-PetRelationship -ErrorAction SilentlyContinue)) {
        $script:chatStatus.Text = [string](Get-PetRelationship)
    }
    $script:chatSend.Add_Click({ Send-PetChatMessage -Text $script:chatInput.Text })
    $script:chatInput.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Return) {
            $eventArgs.Handled = $true
            Send-PetChatMessage -Text $script:chatInput.Text
        }
    })
    foreach ($button in @($script:chatQuick.Children) + @($script:chatQuickExtra.Children)) {
        $button.Add_Click({ param($sender, $eventArgs) Send-PetChatMessage -Text ([string]$sender.Tag) })
    }
    $script:chatWindow.Add_Closed({ $script:chatWindow = $null })
    $petWindow = Get-Variable -Name window -Scope Script -ErrorAction SilentlyContinue
    if ($petWindow -and $petWindow.Value -is [System.Windows.Window] -and $petWindow.Value.IsLoaded -and -not $script:chatTestMode) {
        $script:chatWindow.Owner = $petWindow.Value
    }
    if ($script:chatTestMode) {
        $script:chatWindow.WindowStartupLocation = 'Manual'
        $script:chatWindow.Left = -10000; $script:chatWindow.Top = -10000
        $script:chatWindow.ShowInTaskbar = $false
    }
    $script:chatWindow.Show()
    if ($script:chatHistory.Count -eq 0) {
        Add-PetChatReply '你来啦～我把旁边的位置给你留好了。想摸摸头、抱一下，还是跟我说说今天的事？♡'
    } else {
        foreach ($entry in $script:chatHistory) { Add-PetChatBubble -Role $entry.Role -Text $entry.Text -Replay }
    }
    $script:chatInput.Focus() | Out-Null
}

function Test-PetChat {
    if ($script:chatWindow -and $script:chatWindow.IsLoaded) { throw 'Please close the chat window before its self-test.' }
    $savedHistory = $script:chatHistory
    $script:chatHistory = New-Object 'System.Collections.Generic.List[object]'
    $script:chatTestCalls = New-Object 'System.Collections.Generic.List[string]'
    $script:chatTestMode = $true
    try {
        Show-PetChat
        $firstWindow = $script:chatWindow
        Show-PetChat
        if ($script:chatWindow -ne $firstWindow) { throw 'Chat should reuse its window.' }
        $script:chatInput.Text = '发送按钮'
        $script:chatSend.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        foreach ($button in @($script:chatQuick.Children) + @($script:chatQuickExtra.Children)) {
            $button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        }
        $script:chatInput.Text = '回车发送'
        $keyEvent = [System.Windows.Input.KeyEventArgs]::new([System.Windows.Input.Keyboard]::PrimaryDevice, [System.Windows.PresentationSource]::FromVisual($script:chatInput), 0, [System.Windows.Input.Key]::Return)
        $keyEvent.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
        $script:chatInput.RaiseEvent($keyEvent)
        $expected = @('发送按钮', '摸摸头', '抱抱', '你真可爱', '逗逗你', '猜拳', '晚安', '再来', '回车发送')
        if (($script:chatTestCalls -join '|') -ne ($expected -join '|')) { throw ('Incorrect dispatch: ' + ($script:chatTestCalls -join '|')) }
        if (-not $keyEvent.Handled -or $script:chatInput.Text -ne '') { throw 'Enter did not clear and consume the input.' }
        $before = $script:chatHistory.Count
        Send-PetChatMessage '  '
        if ($script:chatHistory.Count -ne $before) { throw 'Blank input should be ignored.' }
        $script:chatWindow.Close()
        Add-PetChatReply '关闭后仍能记住这句'
        Show-PetChat
        if ($script:chatHistory.Count -ne ($before + 1) -or $script:chatMessages.Children.Count -ne $script:chatHistory.Count) { throw 'Chat history was lost or duplicated on reopen.' }
        $script:chatWindow.Close()
        [PSCustomObject]@{ Passed = $true; Sends = $script:chatTestCalls.Count; Reopened = $true; BlankIgnored = $true }
    } finally {
        if ($script:chatWindow -and $script:chatWindow.IsLoaded) { $script:chatWindow.Close() }
        $script:chatHistory = $savedHistory
        $script:chatTestMode = $false
        $script:chatSending = $false
    }
}
