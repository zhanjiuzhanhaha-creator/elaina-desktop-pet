param([switch]$SelfTest, [switch]$Preview, [switch]$SleepPreview, [switch]$HoverPreview, [switch]$ClickPreview, [switch]$HeadPatPreview, [switch]$FocusPreview, [switch]$Dev, [switch]$Smoke, [switch]$OpenChat)
$ErrorActionPreference = 'Stop'
# One visible pet per account and desktop session; previews and checks stay independent.
if (-not ($SelfTest -or $Preview -or $SleepPreview -or $HoverPreview -or $ClickPreview -or $HeadPatPreview -or $FocusPreview)) {
    $accountSid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:singleInstanceMutex=[System.Threading.Mutex]::new($false,('Local\ElainaDesktopPet-v2-'+$accountSid+$(if ($Dev) { '-dev' } else { '' })))
    try { $ownsPet=$script:singleInstanceMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsPet=$true }
    if (-not $ownsPet) { $script:singleInstanceMutex.Dispose(); exit 0 }
}
# ============================================================
# v2 · 配置与记忆（config.json）
# ============================================================
$script:configPath = Join-Path $PSScriptRoot 'config.json'
$script:isolatedRun = $SelfTest -or $Preview -or $SleepPreview -or $HoverPreview -or $ClickPreview -or $HeadPatPreview -or $FocusPreview -or $Smoke -or $Dev
if ($script:isolatedRun) { $script:configPath = Join-Path $env:TEMP ('elaina-check-' + [guid]::NewGuid().ToString('N') + '.json') }
$script:configExisted = Test-Path -LiteralPath $script:configPath
$script:config = $null
function Load-PetConfig {
    $loaded = $null
    if ($script:configExisted) {
        foreach ($candidate in @($script:configPath, ($script:configPath + '.bak'))) {
            try {
                $loaded = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($loaded -isnot [PSCustomObject]) { throw 'Invalid configuration object' }
                break
            } catch { $loaded = $null }
        }
    }
    if ($null -eq $loaded) { $loaded = [PSCustomObject]@{} }
    $defaults = @{
        Nickname = ''; QuietMode = $false; DemoMode = $false; FocusMinutes = 25
        TotalMinutes = 0; Sessions = 0; Stars = 0
        FirstSeen = ''; LastSeen = ''
        OwnedItems = @(); Goals = @(); Left = -1; Top = -1; NapDay = ''
    }
    foreach ($key in $defaults.Keys) {
        if ($null -eq $loaded.PSObject.Properties[$key]) {
            $loaded | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key]
        }
    }
    foreach ($key in @('TotalMinutes','Sessions','Stars','FocusMinutes')) {
        $number = 0
        if (-not [int]::TryParse([string]$loaded.$key, [ref]$number) -or $number -lt 0) { $number = $defaults[$key] }
        $loaded.$key = $number
    }
    if ($loaded.FocusMinutes -notin @(15,25,45,60)) { $loaded.FocusMinutes = 25 }
    foreach ($key in @('Left','Top')) {
        $number = 0.0
        if (-not [double]::TryParse([string]$loaded.$key, [ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) { $number = -1 }
        $loaded.$key = $number
    }
    foreach ($key in @('QuietMode','DemoMode')) { if ($loaded.$key -isnot [bool]) { $loaded.$key = $false } }
    $loaded.OwnedItems = @($loaded.OwnedItems | Where-Object { $_ -in @('rug-sakura','rug-star','mug','plant','starlamp') } | Select-Object -Unique)
    $loaded.Goals = @($loaded.Goals | Where-Object { $_ -is [PSCustomObject] -and $_.Text -is [string] -and $_.Done -is [bool] } | Select-Object -First 8)
    $script:config = $loaded
}
function Save-PetConfig {
    try {
        $json = $script:config | ConvertTo-Json -Depth 6
        $pending = $script:configPath + '.tmp'
        [IO.File]::WriteAllText($pending, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $script:configPath) {
            [IO.File]::Replace($pending, $script:configPath, ($script:configPath + '.bak'))
        } else { [IO.File]::Move($pending, $script:configPath) }
    } catch { Write-Warning ('记录保存失败：' + $_.Exception.Message) }
}
Load-PetConfig
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$script:art = @{}
foreach ($name in @('idle', 'hover', 'click', 'blink', 'half', 'mouth-layer', 'core-mask', 'tuft', 'strand', 'hover-tuft', 'hover-strand', 'click-ear-left', 'click-ear-right', 'click-ear-left-up', 'click-ear-right-up', 'click-tuft', 'click-tuft-up', 'click-core-mask', 'click-core', 'pat-press', 'pat-release', 'pat-pillow', 'pat-head-mask', 'pat-rig-mask', 'paw-cursor')) {
    $file = Join-Path $PSScriptRoot "assets/$name.png"
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object System.Uri($file)
    $bitmap.EndInit()
    $bitmap.Freeze()
    $script:art[$name] = $bitmap
}
$script:art['click'] = $script:art['click-core']
$window = New-Object System.Windows.Window
$window.Title = '伊蕾娜 · 陪伴版 v2'
$window.Width = 360
$window.Height = 380
$window.WindowStyle = 'None'
$window.ResizeMode = 'NoResize'
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
# 位置记忆：有合法保存位置就用它，否则回到右下角（开发实例错开位置，避免与正式版重叠）
$defaultLeft = [System.Windows.SystemParameters]::WorkArea.Right - 350
$defaultTop = [System.Windows.SystemParameters]::WorkArea.Bottom - 360
if ($Dev) { $defaultLeft = $defaultLeft - 130 }
$savedLeft = [double]$script:config.Left
$savedTop = [double]$script:config.Top
$virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
$virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
$validPos = -not ($savedLeft -eq -1 -and $savedTop -eq -1) -and $savedLeft -ge $virtualLeft -and $savedTop -ge $virtualTop -and ($savedLeft + $window.Width) -le ($virtualLeft + [System.Windows.SystemParameters]::VirtualScreenWidth) -and ($savedTop + $window.Height) -le ($virtualTop + [System.Windows.SystemParameters]::VirtualScreenHeight)
$window.Left = if ($validPos) { $savedLeft } else { $defaultLeft }
$window.Top = if ($validPos) { $savedTop } else { $defaultTop }
$surface = New-Object System.Windows.Controls.Grid
$surface.Width = 280
$surface.Height = 280
$surface.Background = [System.Windows.Media.Brushes]::Transparent
$surface.VerticalAlignment = 'Center'
$surface.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.94)
$pose = New-Object System.Windows.Media.TransformGroup
$breath = New-Object System.Windows.Media.ScaleTransform(1, 1)
$tilt = New-Object System.Windows.Media.RotateTransform
$lift = New-Object System.Windows.Media.TranslateTransform
$pose.Children.Add($breath)
$pose.Children.Add($tilt)
$pose.Children.Add($lift)
$handoffScale = New-Object System.Windows.Media.ScaleTransform(1,1)
$handoffRotate = New-Object System.Windows.Media.RotateTransform
$handoffShift = New-Object System.Windows.Media.TranslateTransform
$pose.Children.Add($handoffScale)
$pose.Children.Add($handoffRotate)
$pose.Children.Add($handoffShift)
$glanceRotate = New-Object System.Windows.Media.RotateTransform
$pose.Children.Add($glanceRotate)
$surface.RenderTransform = $pose
function New-SpriteLayer($name) {
    $layer = New-Object System.Windows.Controls.Image
    $layer.Source = $script:art[$name]
    $layer.Stretch = 'Uniform'
    $layer.IsHitTestVisible = $false
    return $layer
}
$tuft = New-SpriteLayer 'tuft'
$strand = New-SpriteLayer 'strand'
$tuft.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.21)
$strand.RenderTransformOrigin = New-Object System.Windows.Point(0.23, 0.32)
$tuftRotate = New-Object System.Windows.Media.RotateTransform
$strandRotate = New-Object System.Windows.Media.RotateTransform
$glanceTuft = New-Object System.Windows.Media.RotateTransform
$tuftPose = New-Object System.Windows.Media.TransformGroup
$tuftPose.Children.Add($tuftRotate)
$tuftPose.Children.Add($glanceTuft)
$tuft.RenderTransform = $tuftPose
$strand.RenderTransform = $strandRotate
$image = New-SpriteLayer 'idle'
$coreMask = New-Object System.Windows.Media.ImageBrush($script:art['core-mask'])
$mouth = New-SpriteLayer 'mouth-layer'
$mouth.Opacity = 0
foreach ($layer in @($strand, $tuft, $image, $mouth)) { $surface.Children.Add($layer) | Out-Null }
$sleepMarks = New-Object System.Windows.Controls.Canvas
$sleepMarks.IsHitTestVisible = $false
$sleepMarks.Visibility = 'Hidden'
$sleepFloat = New-Object System.Windows.Media.TranslateTransform
$sleepMarks.RenderTransform = $sleepFloat
foreach ($mark in @(@('z',204,25,16), @('z',224,11,21), @('Z',246,-4,26))) {
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $mark[0]
    $label.FontFamily = New-Object System.Windows.Media.FontFamily('Comic Sans MS')
    $label.FontSize = $mark[3]
    $label.FontWeight = 'Bold'
    $label.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9288BF')
    $label.RenderTransform = New-Object System.Windows.Media.RotateTransform(-12)
    [System.Windows.Controls.Canvas]::SetLeft($label, $mark[1])
    [System.Windows.Controls.Canvas]::SetTop($label, $mark[2])
    $sleepMarks.Children.Add($label) | Out-Null
}
$surface.Children.Add($sleepMarks) | Out-Null
$patHead = New-Object System.Windows.Controls.Grid
$patHead.IsHitTestVisible = $false
$patHead.Visibility = 'Hidden'
$patCore = New-SpriteLayer 'hover'
$patCore.OpacityMask = New-Object System.Windows.Media.ImageBrush($script:art['pat-rig-mask'])
$patTuft = New-SpriteLayer 'hover-tuft'
$patStrand = New-SpriteLayer 'hover-strand'
$patTuftRotate = New-Object System.Windows.Media.RotateTransform
$patStrandRotate = New-Object System.Windows.Media.RotateTransform
$patTuft.RenderTransform = $patTuftRotate
$patTuft.RenderTransformOrigin = New-Object System.Windows.Point(0.5,0.21)
$patStrand.RenderTransform = $patStrandRotate
$patStrand.RenderTransformOrigin = New-Object System.Windows.Point(0.23,0.32)
$patHead.Children.Add($patCore) | Out-Null
$patHead.Children.Add($patTuft) | Out-Null
$patHead.Children.Add($patStrand) | Out-Null
$patPillow = New-SpriteLayer 'pat-pillow'
$patPillow.Visibility = 'Hidden'
$surface.Children.Add($patHead) | Out-Null
$surface.Children.Add($patPillow) | Out-Null
$patPose = New-Object System.Windows.Media.TransformGroup
$patScale = New-Object System.Windows.Media.ScaleTransform(1,1)
$patRotate = New-Object System.Windows.Media.RotateTransform
$patShift = New-Object System.Windows.Media.TranslateTransform
$patPose.Children.Add($patScale)
$patPose.Children.Add($patRotate)
$patPose.Children.Add($patShift)
$patHead.RenderTransform = $patPose
$patHead.RenderTransformOrigin = New-Object System.Windows.Point(0.5,0.70)
$script:pettingZone = $false
# Explicit dimensions prevent Windows from shrinking the cursor to its default size.
Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public sealed class PetCursorHandle : SafeHandleZeroOrMinusOneIsInvalid {
    public PetCursorHandle(IntPtr value) : base(true) { SetHandle(value); }
    [DllImport("user32.dll")] static extern bool DestroyCursor(IntPtr cursor);
    protected override bool ReleaseHandle() { return DestroyCursor(handle); }
}
public static class PetCursorLoader {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int width, int height, uint flags);
    public static PetCursorHandle Load(string path, int size) {
        IntPtr value = LoadImage(IntPtr.Zero, path, 2, size, size, 0x10);
        if (value == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        return new PetCursorHandle(value);
    }
}
'@
$pawHandle = [PetCursorLoader]::Load((Join-Path $PSScriptRoot 'assets/paw-cursor.cur'),144)
$pawCursor = [System.Windows.Interop.CursorInteropHelper]::Create($pawHandle)

$clickEarLeft = New-SpriteLayer 'click-ear-left'
$clickEarRight = New-SpriteLayer 'click-ear-right'
$clickEarLeftUp = New-SpriteLayer 'click-ear-left-up'
$clickEarRightUp = New-SpriteLayer 'click-ear-right-up'
$clickTuft = New-SpriteLayer 'click-tuft'
$clickTuftUp = New-SpriteLayer 'click-tuft-up'
$clickParts = @($clickEarLeft, $clickEarRight, $clickEarLeftUp, $clickEarRightUp, $clickTuft, $clickTuftUp)
$leftEarRotate = New-Object System.Windows.Media.RotateTransform
$rightEarRotate = New-Object System.Windows.Media.RotateTransform
foreach ($part in @($clickEarLeft,$clickEarLeftUp)) { $part.RenderTransformOrigin = New-Object System.Windows.Point(0.24,0.31); $part.RenderTransform = $leftEarRotate }
foreach ($part in @($clickEarRight,$clickEarRightUp)) { $part.RenderTransformOrigin = New-Object System.Windows.Point(0.76,0.31); $part.RenderTransform = $rightEarRotate }
$uprightPose = New-Object System.Windows.Media.TransformGroup
$uprightRotate = New-Object System.Windows.Media.RotateTransform
$uprightScale = New-Object System.Windows.Media.ScaleTransform(1,1)
$uprightPose.Children.Add($uprightScale)
$uprightPose.Children.Add($uprightRotate)
$clickTuftUp.RenderTransformOrigin = New-Object System.Windows.Point(0.5,0.22)
$clickTuftUp.RenderTransform = $uprightPose
foreach ($part in $clickParts) { $part.Visibility = 'Hidden'; $surface.Children.Insert(0,$part) }
$clickCoreMask = New-Object System.Windows.Media.ImageBrush($script:art['click-core-mask'])
$clickEffects = New-Object System.Windows.Controls.Canvas
$clickEffects.IsHitTestVisible = $false
$clickEffects.Visibility = 'Hidden'
$effectItems = @()
foreach ($spec in @(
    @('♥',-22,92,28,'#ED8FB4'), @('✦',269,90,31,'#EDC45D'),
    @('♥',-13,183,24,'#E88AB2'), @('✧',265,210,25,'#B8A0EB'),
    @('✦',36,-12,26,'#F0CE77'), @('✧',224,-10,26,'#BFA7EF'),
    @('●',-24,145,14,'#97D9E7'), @('●',283,151,14,'#EAA5CD'),
    @('♥',83,-21,20,'#EB95BC'), @('✦',182,-24,22,'#F2C863'),
    @('✧',16,239,22,'#BCA5EF'), @('●',250,257,15,'#A1DDE3'),
    @('♥',-14,44,21,'#F0A0C1'), @('♥',271,43,22,'#EC8BB3'),
    @('♥',-19,233,22,'#ECA0C7'), @('♥',275,184,22,'#ED8FAE'),
    @('♥',126,-26,19,'#EEA3CD'), @('♥',215,263,20,'#E99BC3')
)) {
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $spec[0]
    $label.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Symbol')
    $label.FontSize = $spec[3]
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($spec[4])
    $label.Foreground = $brush
    $label.Opacity = 0
    $label.RenderTransformOrigin = New-Object System.Windows.Point(0.5,0.5)
    $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $glow.Color = $brush.Color
    $glow.BlurRadius = 9
    $glow.ShadowDepth = 0
    $glow.Opacity = 0.65
    $label.Effect = $glow
    $motion = New-Object System.Windows.Media.TransformGroup
    $scale = New-Object System.Windows.Media.ScaleTransform(1,1)
    $turn = New-Object System.Windows.Media.RotateTransform
    $float = New-Object System.Windows.Media.TranslateTransform
    $motion.Children.Add($scale)
    $motion.Children.Add($turn)
    $motion.Children.Add($float)
    $label.RenderTransform = $motion
    [System.Windows.Controls.Canvas]::SetLeft($label,$spec[1])
    [System.Windows.Controls.Canvas]::SetTop($label,$spec[2])
    $clickEffects.Children.Add($label) | Out-Null
    $effectItems += [PSCustomObject]@{ Label=$label; Float=$float; Scale=$scale; Turn=$turn; Direction=$(if ($spec[1] -lt 140) { -1 } else { 1 }); Rise=$(if ($spec[2] -lt 0) { 12 } else { 25 }) }
}
$surface.Children.Add($clickEffects) | Out-Null

$transitionOverlay = New-Object System.Windows.Controls.Image
$transitionOverlay.Width = 280
$transitionOverlay.Height = 280
$transitionOverlay.Stretch = 'Fill'
$transitionOverlay.IsHitTestVisible = $false
$transitionOverlay.Opacity = 0
$stage = New-Object System.Windows.Controls.Grid
$petScene = New-Object System.Windows.Controls.Grid
$stage.Children.Add($petScene) | Out-Null
$inputRoot = New-Object System.Windows.Controls.Grid
$inputRoot.Width = 280
$inputRoot.Height = 280
$inputRoot.VerticalAlignment = 'Center'
$inputRoot.Background = [System.Windows.Media.Brushes]::Transparent
$inputRoot.Children.Add($surface) | Out-Null
$petScene.Children.Add($inputRoot) | Out-Null
$petScene.Children.Add($transitionOverlay) | Out-Null
$window.Content = $stage
# ============================================================
# v2 · 气泡台词系统
# ============================================================
$bubbleBorder = New-Object System.Windows.Controls.Border
$bubbleBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFF9F0')
$bubbleBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E9D7F2')
$bubbleBorder.BorderThickness = New-Object System.Windows.Thickness(1.2)
$bubbleBorder.CornerRadius = New-Object System.Windows.CornerRadius(12)
$bubbleBorder.Padding = New-Object System.Windows.Thickness(12, 7, 12, 7)
$bubbleBorder.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
$bubbleBorder.HorizontalAlignment = 'Center'
$bubbleBorder.VerticalAlignment = 'Top'
$bubbleBorder.MaxWidth = 330
$bubbleBorder.IsHitTestVisible = $false
$bubbleBorder.Opacity = 0
$bubbleShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$bubbleShadow.BlurRadius = 10
$bubbleShadow.ShadowDepth = 0
$bubbleShadow.Opacity = 0.25
$bubbleShadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#B9A6C9')
$bubbleBorder.Effect = $bubbleShadow
$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$bubbleText.FontSize = 13
$bubbleText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#5D4B72')
$bubbleText.TextWrapping = 'Wrap'
$bubbleText.TextAlignment = 'Center'
$bubbleBorder.Child = $bubbleText
$bubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
$bubbleTimer.Add_Tick({
    $bubbleTimer.Stop()
    $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeOut.From = 1
    $fadeOut.To = 0
    $fadeOut.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(500))
    $bubbleBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
})
function Show-Bubble([string]$Text, [double]$Seconds = 4) {
    if ($script:config.QuietMode) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $bubbleText.Text = $Text
    $bubbleTimer.Stop()
    $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeIn.From = 0
    $fadeIn.To = 1
    $fadeIn.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
    $bubbleBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
    $bubbleTimer.Interval = [TimeSpan]::FromMilliseconds([int]($Seconds * 1000))
    $bubbleTimer.Start()
}
# 专注倒计时指示器（安静模式隐藏）
$focusIndicator = New-Object System.Windows.Controls.Border
$focusIndicator.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F1EAF9')
$focusIndicator.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D9C8EC')
$focusIndicator.BorderThickness = New-Object System.Windows.Thickness(1)
$focusIndicator.CornerRadius = New-Object System.Windows.CornerRadius(9)
$focusIndicator.Padding = New-Object System.Windows.Thickness(10, 3, 10, 3)
$focusIndicator.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
$focusIndicator.HorizontalAlignment = 'Center'
$focusIndicator.VerticalAlignment = 'Top'
$focusIndicator.IsHitTestVisible = $false
$focusIndicator.Opacity = 0.9
$focusIndicator.Visibility = 'Hidden'
$focusIndicatorText = New-Object System.Windows.Controls.TextBlock
$focusIndicatorText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$focusIndicatorText.FontSize = 11.5
$focusIndicatorText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6A5A8E')
$focusIndicatorText.Text = '◐ 25:00'
$focusIndicator.Child = $focusIndicatorText
$topPanel = New-Object System.Windows.Controls.StackPanel
$topPanel.VerticalAlignment = 'Top'
$topPanel.HorizontalAlignment = 'Center'
$topPanel.IsHitTestVisible = $false
$topPanel.Children.Add($bubbleBorder) | Out-Null
$topPanel.Children.Add($focusIndicator) | Out-Null
$stage.Children.Add($topPanel) | Out-Null
function Update-FocusIndicator {
    if (-not $script:focused) { $focusIndicator.Visibility = 'Hidden'; return }
    if ($script:config.QuietMode) { $focusIndicator.Visibility = 'Hidden'; return }
    $focusIndicator.Visibility = 'Visible'
    if ($script:focusPaused) {
        $focusIndicatorText.Text = '◐ 已暂停'
    } else {
        $m = [int][Math]::Floor($script:focusRemaining / 60)
        $s = $script:focusRemaining % 60
        $focusIndicatorText.Text = '◐ ' + $m + ':' + ('{0:D2}' -f $s)
    }
}
# ============================================================
# v2 · 小窝装饰（纯 WPF 绘制，无需新素材）
# ============================================================
$script:decorCanvas = New-Object System.Windows.Controls.Canvas
$script:decorCanvas.IsHitTestVisible = $false
$stage.Children.Insert(0, $script:decorCanvas)
$script:decorCatalog = @(
    [PSCustomObject]@{ Id = 'rug-sakura'; Name = '樱花粉地毯'; Cost = 2; Type = 'rug' },
    [PSCustomObject]@{ Id = 'rug-star';   Name = '星空蓝地毯'; Cost = 3; Type = 'rug' },
    [PSCustomObject]@{ Id = 'mug';        Name = '暖茶马克杯'; Cost = 2; Type = 'item' },
    [PSCustomObject]@{ Id = 'plant';      Name = '绿萝盆栽';   Cost = 3; Type = 'item' },
    [PSCustomObject]@{ Id = 'starlamp';   Name = '星星小夜灯'; Cost = 5; Type = 'item' }
)
function New-RugElement([string]$Color) {
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 190
    $e.Height = 46
    $e.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $e.Opacity = 0.6
    [System.Windows.Controls.Canvas]::SetLeft($e, 85)
    [System.Windows.Controls.Canvas]::SetTop($e, 308)
    return $e
}
function New-MugElement {
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = 70
    $c.Height = 70
    $body = New-Object System.Windows.Controls.Border
    $body.Width = 27
    $body.Height = 30
    $body.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $body.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8FB8E0')
    [System.Windows.Controls.Canvas]::SetLeft($body, 4)
    [System.Windows.Controls.Canvas]::SetTop($body, 30)
    $c.Children.Add($body) | Out-Null
    $handle = New-Object System.Windows.Shapes.Ellipse
    $handle.Width = 14
    $handle.Height = 18
    $handle.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#7EA8D2')
    $handle.StrokeThickness = 3
    [System.Windows.Controls.Canvas]::SetLeft($handle, 27)
    [System.Windows.Controls.Canvas]::SetTop($handle, 34)
    $c.Children.Add($handle) | Out-Null
    $steam1 = New-Object System.Windows.Shapes.Ellipse
    $steam1.Width = 8
    $steam1.Height = 14
    $steam1.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#BBD6F0')
    $steam1.StrokeThickness = 2
    $steam1.Opacity = 0.75
    [System.Windows.Controls.Canvas]::SetLeft($steam1, 8)
    [System.Windows.Controls.Canvas]::SetTop($steam1, 12)
    $c.Children.Add($steam1) | Out-Null
    $steam2 = New-Object System.Windows.Shapes.Ellipse
    $steam2.Width = 7
    $steam2.Height = 12
    $steam2.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#BBD6F0')
    $steam2.StrokeThickness = 2
    $steam2.Opacity = 0.65
    [System.Windows.Controls.Canvas]::SetLeft($steam2, 19)
    [System.Windows.Controls.Canvas]::SetTop($steam2, 3)
    $c.Children.Add($steam2) | Out-Null
    return $c
}
function New-PlantElement {
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = 70
    $c.Height = 70
    $pot = New-Object System.Windows.Controls.Border
    $pot.Width = 16
    $pot.Height = 16
    $pot.CornerRadius = New-Object System.Windows.CornerRadius(2)
    $pot.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C97B5A')
    [System.Windows.Controls.Canvas]::SetLeft($pot, 20)
    [System.Windows.Controls.Canvas]::SetTop($pot, 50)
    $c.Children.Add($pot) | Out-Null
    $rim = New-Object System.Windows.Controls.Border
    $rim.Width = 22
    $rim.Height = 5
    $rim.CornerRadius = New-Object System.Windows.CornerRadius(2)
    $rim.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#B06A4C')
    [System.Windows.Controls.Canvas]::SetLeft($rim, 17)
    [System.Windows.Controls.Canvas]::SetTop($rim, 47)
    $c.Children.Add($rim) | Out-Null
    $stem = New-Object System.Windows.Shapes.Rectangle
    $stem.Width = 2
    $stem.Height = 22
    $stem.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#7BB661')
    [System.Windows.Controls.Canvas]::SetLeft($stem, 27)
    [System.Windows.Controls.Canvas]::SetTop($stem, 28)
    $c.Children.Add($stem) | Out-Null
    foreach ($leaf in @(@(16,30,-35,'#8FC77A'), @(30,26,30,'#7BB661'), @(24,22,-8,'#A3D18C'))) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = 16
        $e.Height = 9
        $e.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($leaf[3])
        $rt = New-Object System.Windows.Media.RotateTransform($leaf[2])
        $e.RenderTransform = $rt
        $e.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        [System.Windows.Controls.Canvas]::SetLeft($e, $leaf[0])
        [System.Windows.Controls.Canvas]::SetTop($e, $leaf[1])
        $c.Children.Add($e) | Out-Null
    }
    return $c
}
function New-StarlampElement {
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = 50
    $c.Height = 80
    $line = New-Object System.Windows.Shapes.Line
    $line.X1 = 25; $line.Y1 = 0; $line.X2 = 25; $line.Y2 = 24
    $line.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C9BFE8')
    $line.StrokeThickness = 1.5
    $c.Children.Add($line) | Out-Null
    $star = New-Object System.Windows.Shapes.Polygon
    $star.Points = New-Object System.Windows.Media.PointCollection
    foreach ($p in '0,-10 -2.47,-3.4 9.51,-3.09 -3.99,1.3 -5.88,8.09 0,4.2 5.88,8.09 3.99,1.3 -9.51,-3.09 2.47,-3.4'.Split(' ')) {
        $xy = $p.Split(',')
        $pt = New-Object System.Windows.Point
        $pt.X = [double]$xy[0] + 14
        $pt.Y = [double]$xy[1] + 34
        $star.Points.Add($pt) | Out-Null
    }
    $star.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFD97A')
    $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $glow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#FFD97A')
    $glow.BlurRadius = 12
    $glow.ShadowDepth = 0
    $glow.Opacity = 0.8
    $star.Effect = $glow
    $c.Children.Add($star) | Out-Null
    return $c
}
function Invoke-DecorRefresh {
    $script:decorCanvas.Children.Clear()
    $rugId = 'rug-default'
    foreach ($ownedId in $script:config.OwnedItems) {
        if ($ownedId -in @('rug-sakura','rug-star')) { $rugId = $ownedId }
    }
    $rugColor = if ($rugId -eq 'rug-sakura') { '#F7C6D8' } elseif ($rugId -eq 'rug-star') { '#A8B8E8' } else { '#EFE7DA' }
    $script:decorCanvas.Children.Add((New-RugElement $rugColor)) | Out-Null
    foreach ($item in $script:decorCatalog) {
        if ($item.Type -ne 'item') { continue }
        if ($script:config.OwnedItems -notcontains $item.Id) { continue }
        $el = $null
        switch ($item.Id) {
            'mug' { $el = New-MugElement; [System.Windows.Controls.Canvas]::SetLeft($el, 300); [System.Windows.Controls.Canvas]::SetTop($el, 250) }
            'plant' { $el = New-PlantElement; [System.Windows.Controls.Canvas]::SetLeft($el, 6); [System.Windows.Controls.Canvas]::SetTop($el, 258) }
            'starlamp' { $el = New-StarlampElement; [System.Windows.Controls.Canvas]::SetLeft($el, 308); [System.Windows.Controls.Canvas]::SetTop($el, 2) }
        }
        if ($null -ne $el) { $script:decorCanvas.Children.Add($el) | Out-Null }
    }
}
function Begin-IdleTransition([double]$Milliseconds = 800) {
    if ($surface.ActualWidth -le 0 -or $surface.ActualHeight -le 0) { return }
    if ($window.ActualWidth -ge 280 -and $window.ActualHeight -ge 280) {
        $captureWidth = [int][Math]::Ceiling($window.ActualWidth)
        $captureHeight = [int][Math]::Ceiling($window.ActualHeight)
        $rawSnapshot = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($captureWidth, $captureHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        # Only the pet belongs in a pose transition; UI and decor must not leave ghosts.
        $rawSnapshot.Render($petScene)
        $cropX = [int][Math]::Round(($captureWidth - 280) / 2)
        $cropY = [int][Math]::Round(($captureHeight - 280) / 2)
    } else {
        $rawSnapshot = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(280, 280, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $rawSnapshot.Render($surface)
        $cropX = 0
        $cropY = 0
    }
    $snapshot = New-Object System.Windows.Media.Imaging.CroppedBitmap($rawSnapshot, (New-Object System.Windows.Int32Rect($cropX, $cropY, 280, 280)))
    $snapshot.Freeze()
    $transitionOverlay.Source = $snapshot
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 1
    $fade.To = 0
    $fade.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($Milliseconds))
    $fade.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
    $fade.EasingFunction.EasingMode = 'EaseInOut'
    $fade.FillBehavior = 'Stop'
    $transitionOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    # Carry the current pose into the next animation rather than jumping to neutral.
    $previousPose = @(($breath.ScaleX*$handoffScale.ScaleX), ($breath.ScaleY*$handoffScale.ScaleY),
        ($tilt.Angle+$handoffRotate.Angle+$glanceRotate.Angle), ($lift.Y+$handoffShift.Y))
    $tracks = @(@($handoffScale,[System.Windows.Media.ScaleTransform]::ScaleXProperty,$previousPose[0],1),
        @($handoffScale,[System.Windows.Media.ScaleTransform]::ScaleYProperty,$previousPose[1],1),
        @($handoffRotate,[System.Windows.Media.RotateTransform]::AngleProperty,$previousPose[2],0),
        @($handoffShift,[System.Windows.Media.TranslateTransform]::YProperty,$previousPose[3],0))
    foreach ($track in $tracks) {
        $carry = New-Object System.Windows.Media.Animation.DoubleAnimation
        $carry.From = $track[2]; $carry.To = $track[3]
        $carry.Duration = $fade.Duration
        $carry.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $carry.EasingFunction.EasingMode = 'EaseInOut'
        $carry.FillBehavior = 'Stop'
        $track[0].BeginAnimation($track[1],$carry)
    }
}
$script:clicked = $false
$script:over = $false
$script:state = ''
$script:blinking = $false
$script:blinkPhase = 0
$script:doubleBlink = $false
$script:secondBlink = $false
$blinkTimer = New-Object System.Windows.Threading.DispatcherTimer
$mouthTimer = New-Object System.Windows.Threading.DispatcherTimer
$idleFormTimer = New-Object System.Windows.Threading.DispatcherTimer
$idleFormTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
$script:lastIdleForm = -1
$script:idleForm = -1
function Get-NextIdleForm {
    if ($script:idleBag.Count -eq 0) {
        $order = @(0,1,2,3,4 | Get-Random -Count 5)
        if ($order[0] -eq $script:lastIdleForm) { $first = $order[0]; $order[0] = $order[1]; $order[1] = $first }
        foreach ($item in $order) { $script:idleBag.Enqueue($item) }
    }
    $script:lastIdleForm = $script:idleBag.Dequeue()
    return $script:lastIdleForm
}
function Animate-IdleGesture($target, $property, [double]$rest, [double]$peak, [double]$follow) {
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $timeScale = $script:idleDuration / 3.0
    foreach ($point in @(@(0,$rest), @((0.95*$timeScale),$peak), @((2.05*$timeScale),$follow), @($script:idleDuration,$rest))) {
        $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($point[0]))
        $key.Value = $point[1]
        $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $key.EasingFunction.EasingMode = 'EaseInOut'
        $animation.KeyFrames.Add($key) | Out-Null
    }
    $animation.FillBehavior = 'HoldEnd'
    $target.BeginAnimation($property, $animation)
}
function Invoke-IdleForm {
    if ($script:state -ne 'idle') { return }
    if ($idleFormTimer.IsEnabled) { Begin-IdleTransition }
    $blinkTimer.Stop()
    $mouthTimer.Stop()
    $script:blinkPhase = 0
    $script:blinking = $false
    $script:secondBlink = $false
    $script:idleForm = Get-NextIdleForm
    $script:idleDuration = if ($script:idleForm -in @(2,4)) { 5 } else { 3 }
    $idleFormTimer.Interval = [TimeSpan]::FromSeconds($script:idleDuration)
    $image.Source = $script:art['idle']
    $mouth.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $mouth.Opacity = 0
    $sleepMarks.Visibility = 'Hidden'
    # Five equally frequent gestures; each ends at neutral for a smooth handoff.
    $profiles = @(@(1.98,9.075,3.30), @(-2.5575,10.56,4.2075), @(1.815,9.075,3.3825), @(-2.31,11.055,4.3725), @(1.5675,4.29,1.5675))
    $profile = $profiles[$script:idleForm]
    Animate-IdleGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1 1.0429 1.0148
    Animate-IdleGesture $lift ([System.Windows.Media.TranslateTransform]::YProperty) 0 -2.805 -0.7425
    Animate-IdleGesture $tilt ([System.Windows.Media.RotateTransform]::AngleProperty) 0 $profile[0] (-0.35*$profile[0])
    Animate-IdleGesture $tuftRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 (-$profile[1]) ($profile[1]*0.7)
    Animate-IdleGesture $strandRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 $profile[2] (-$profile[2]*0.6)
    if ($script:idleForm -eq 4) {
        $image.Source = $script:art['blink']
        $mouth.Opacity = 1
        $sleepMarks.Visibility = 'Visible'
        Animate-IdleGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1 1.033 1.0099
        Animate-IdleGesture $lift ([System.Windows.Media.TranslateTransform]::YProperty) 0 2.8875 0.7425
        Animate-IdleGesture $sleepFloat ([System.Windows.Media.TranslateTransform]::YProperty) 0 -8.25 -3.3
        Animate-IdleGesture $sleepMarks ([System.Windows.UIElement]::OpacityProperty) 0.65 1.2275 0.8975
        return
    }
    $script:doubleBlink = $script:idleForm -eq 3
    $blinkTimer.Interval = [TimeSpan]::FromMilliseconds($(if ($script:idleForm -eq 1) { 1650 } else { 750 }))
    $blinkTimer.Start()
    if ($script:idleForm -eq 2) {
        $mouthTimer.Interval = [TimeSpan]::FromMilliseconds(60)
        $mouthTimer.Start()
    }
}
function Start-IdleMotion {
    $tuft.Source = $script:art['tuft']
    $strand.Source = $script:art['strand']
    $image.OpacityMask = $coreMask
    $tuft.Visibility = 'Visible'
    $strand.Visibility = 'Visible'
    $mouth.Visibility = 'Visible'
    Invoke-IdleForm
    $idleFormTimer.Start()
}
function Stop-IdleMotion([switch]$KeepTransition) {
    $patHead.Visibility = 'Hidden'
    $patPillow.Visibility = 'Hidden'
    $image.Visibility = 'Visible'
    $patTuftRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $patStrandRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $patScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$null)
    $patScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$null)
    $patRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $patShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty,$null)
    $patShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$null)
    $image.RenderTransform = [System.Windows.Media.Transform]::Identity
    $image.RenderTransformOrigin = New-Object System.Windows.Point(0.5,0.5)

    foreach ($part in $clickParts) {
        $part.Visibility = 'Hidden'
        $part.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$null)
    }
    $leftEarRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $rightEarRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $uprightRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    $uprightScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$null)
    $clickEffects.Visibility = 'Hidden'
    foreach ($effect in $effectItems) {
        $effect.Label.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$null)
        $effect.Float.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$null)
        $effect.Float.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty,$null)
        $effect.Scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$null)
        $effect.Scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$null)
        $effect.Turn.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$null)
    }
    if (-not $KeepTransition) {
        $transitionOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $transitionOverlay.Opacity = 0
    }
    $idleFormTimer.Stop()
    $blinkTimer.Stop()
    $mouthTimer.Stop()
    $glanceTimer.Stop()
    $glanceRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $glanceTuft.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $script:blinking = $false
    $script:blinkPhase = 0
    $script:doubleBlink = $false
    $script:secondBlink = $false
    $breath.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $breath.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $tilt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $lift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $tuftRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $strandRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
    $mouth.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $mouth.Opacity = 0
    $sleepMarks.Visibility = 'Hidden'
    $sleepMarks.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $sleepFloat.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
    $image.OpacityMask = $null
    $tuft.Visibility = 'Hidden'
    $strand.Visibility = 'Hidden'
    $mouth.Visibility = 'Hidden'
}
function Animate-HoverGesture($target, $property, [double]$rest, [double]$peak, [double]$follow) {
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($point in @(@(0,$rest), @(0.70,$peak), @(1.85,$peak), @(3.2,$follow), @(4.2,$rest))) {
        $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($point[0]))
        $key.Value = $point[1]
        $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $key.EasingFunction.EasingMode = 'EaseInOut'
        $animation.KeyFrames.Add($key) | Out-Null
    }
    $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $target.BeginAnimation($property, $animation)
}
function Start-GentleHoverMotion {
    $image.OpacityMask = $coreMask
    $tuft.Source = $script:art['hover-tuft']
    $strand.Source = $script:art['hover-strand']
    $tuft.Visibility = 'Visible'
    $strand.Visibility = 'Visible'
    Animate-HoverGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1 1.0224 1.0078
    Animate-HoverGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1 1.0291 1.0101
    Animate-HoverGesture $tilt ([System.Windows.Media.RotateTransform]::AngleProperty) 0 2.296 -0.896
    Animate-HoverGesture $lift ([System.Windows.Media.TranslateTransform]::YProperty) 0 -2.912 -0.84
    Animate-HoverGesture $tuftRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 -7.28 4.48
    Animate-HoverGesture $strandRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 2.8 -1.456
}
function Animate-PatGesture($target, $property, [double]$rest, [double]$pressed, [double]$released) {
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($point in @(@(0,$rest),@(0.48,$pressed),@(0.95,$released),@(1.50,$rest),@(1.98,$pressed),@(2.45,$released),@(3.20,$rest))) {
        $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($point[0]))
        $key.Value = $point[1]
        $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $key.EasingFunction.EasingMode = 'EaseInOut'
        $animation.KeyFrames.Add($key) | Out-Null
    }
    $animation.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $target.BeginAnimation($property,$animation)
}
function Start-HeadPatMotion {
    $image.Visibility = 'Hidden'
    $patHead.Visibility = 'Visible'
    $patPillow.Visibility = 'Visible'
    # The artwork stays fixed; WPF interpolates each layer continuously.
    Animate-PatGesture $patScale ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1 1.019 1.0034
    Animate-PatGesture $patScale ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1 0.9608 1.009
    Animate-PatGesture $patRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 -1.904 1.064
    Animate-PatGesture $patShift ([System.Windows.Media.TranslateTransform]::YProperty) 0 3.696 -0.952
    Animate-PatGesture $patShift ([System.Windows.Media.TranslateTransform]::XProperty) 0 1.232 -0.784
    Animate-PatGesture $patTuftRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 21.28 -8.96
    Animate-PatGesture $patStrandRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 5.376 -3.36
}
function Start-HoverMotion {
    if ($script:pettingZone) { Start-HeadPatMotion } else { Start-GentleHoverMotion }
}
function Update-PettingZone([double]$X, [double]$Y) {
    $inside = if ($script:focused) { $false } else { $X -ge 25 -and $X -le 255 -and $Y -ge 0 -and $Y -le 125 }
    $changed = $inside -ne $script:pettingZone
    $script:pettingZone = $inside
    $inputRoot.Cursor = if ($inside) { $pawCursor } else { $null }
    if ($changed -and $script:state -eq 'hover') {
        Begin-IdleTransition 800
        Stop-IdleMotion -KeepTransition
        $image.Source = $script:art['hover']
        Start-HoverMotion
    }
}
function Animate-ClickTrack($target, $property, $points) {
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($point in $points) {
        $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($point[0]))
        $key.Value = $point[1]
        $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $key.EasingFunction.EasingMode = 'EaseInOut'
        $animation.KeyFrames.Add($key) | Out-Null
    }
    $animation.FillBehavior = 'HoldEnd'
    $target.BeginAnimation($property,$animation)
}
function Start-ClickMotion {
    $script:clickSerial += 1
    $image.OpacityMask = $null
    foreach ($part in $clickParts) { $part.Visibility = 'Visible' }
    $clickEffects.Visibility = 'Visible'
    $perk = @(@(0,0),@(0.20,0),@(0.68,1),@(4.30,1),@(4.88,0),@(5,0))
    $relax = @(@(0,1),@(0.20,1),@(0.68,0),@(4.30,0),@(4.88,1),@(5,1))
    $earPerk = @(@(0,0),@(0.20,0),@(0.68,1),@(5,1))
    $earRelax = @(@(0,1),@(0.20,1),@(0.68,0),@(5,0))
    foreach ($part in @($clickEarLeftUp,$clickEarRightUp)) { Animate-ClickTrack $part ([System.Windows.UIElement]::OpacityProperty) $earPerk }
    foreach ($part in @($clickEarLeft,$clickEarRight)) { Animate-ClickTrack $part ([System.Windows.UIElement]::OpacityProperty) $earRelax }
    Animate-ClickTrack $clickTuftUp ([System.Windows.UIElement]::OpacityProperty) $perk
    Animate-ClickTrack $clickTuft ([System.Windows.UIElement]::OpacityProperty) $relax
    Animate-ClickTrack $leftEarRotate ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,0),@(0.26,-9),@(0.65,5),@(1.1,-4),@(1.7,2),@(2.8,-4),@(3.4,3),@(4.3,-1),@(5,0))
    Animate-ClickTrack $rightEarRotate ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,0),@(0.34,10),@(0.76,-5),@(1.2,4),@(1.8,-2),@(2.9,4),@(3.5,-3),@(4.3,1),@(5,0))
    Animate-ClickTrack $uprightRotate ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,0),@(0.65,-5),@(1.05,4),@(1.6,-2),@(2.8,3),@(3.5,-2),@(4.4,0),@(5,0))
    Animate-ClickTrack $uprightScale ([System.Windows.Media.ScaleTransform]::ScaleYProperty) @(@(0,0.85),@(0.65,1.04),@(1.1,1),@(4.4,1),@(5,0.9))
    Animate-ClickTrack $breath ([System.Windows.Media.ScaleTransform]::ScaleXProperty) @(@(0,1),@(0.22,1.02),@(0.55,0.995),@(1.0,1.01),@(2.2,1),@(3.3,1.012),@(5,1))
    Animate-ClickTrack $breath ([System.Windows.Media.ScaleTransform]::ScaleYProperty) @(@(0,1),@(0.22,0.985),@(0.55,1.025),@(1.0,1.008),@(2.2,1),@(3.3,1.012),@(5,1))
    Animate-ClickTrack $lift ([System.Windows.Media.TranslateTransform]::YProperty) @(@(0,0),@(0.55,-2.5),@(1.1,0),@(2.6,-1),@(3.3,-1.5),@(5,0))
    Animate-ClickTrack $tilt ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,0),@(0.55,-0.9),@(1.1,0.5),@(2.6,-0.5),@(3.3,0.6),@(5,0))
    for ($i=0; $i -lt $effectItems.Count; $i++) {
        $item = $effectItems[$i]
        $delay = ($i%4)*0.10 + [Math]::Floor($i/4)*0.05
        $drift = $item.Direction * (9 + ($i%3)*2)
        $rise = $item.Rise
        Animate-ClickTrack $item.Label ([System.Windows.UIElement]::OpacityProperty) @(@(0,0),@((0.35+$delay),0),@((0.75+$delay),1),@((1.25+$delay),0.95),@((2.1+$delay),0),@((2.3+$delay),0),@((2.8+$delay),0.95),@((3.35+$delay),0.85),@((4.5+$delay),0),@(5,0))
        Animate-ClickTrack $item.Float ([System.Windows.Media.TranslateTransform]::YProperty) @(@(0,0),@((0.35+$delay),0),@((2.1+$delay),(-$rise)),@((2.3+$delay),0),@((4.5+$delay),(-$rise*1.12)),@(5,(-$rise*1.12)))
        Animate-ClickTrack $item.Float ([System.Windows.Media.TranslateTransform]::XProperty) @(@(0,0),@((0.35+$delay),0),@((2.1+$delay),$drift),@((2.3+$delay),0),@((4.5+$delay),($drift*1.1)),@(5,($drift*1.1)))
        $pop = @(@(0,0.55),@((0.35+$delay),0.55),@((0.78+$delay),1.12),@((1.2+$delay),1),@((2.1+$delay),0.75),@((2.3+$delay),0.6),@((2.85+$delay),1.16),@((3.4+$delay),1),@((4.5+$delay),0.8),@(5,0.8))
        Animate-ClickTrack $item.Scale ([System.Windows.Media.ScaleTransform]::ScaleXProperty) $pop
        Animate-ClickTrack $item.Scale ([System.Windows.Media.ScaleTransform]::ScaleYProperty) $pop
        Animate-ClickTrack $item.Turn ([System.Windows.Media.RotateTransform]::AngleProperty) @(@(0,(-9*$item.Direction)),@((2.1+$delay),(12*$item.Direction)),@((2.3+$delay),(-8*$item.Direction)),@((4.5+$delay),(14*$item.Direction)),@(5,(14*$item.Direction)))
    }
}
function Invoke-ClickAction {
    if ($script:focused) {
        Show-Bubble ($clickDuringFocusLines | Get-Random) 3
        return
    }
    $timer.Stop()
    $script:clicked = $true
    if ($script:state -eq 'click') {
        Begin-IdleTransition 800
        Stop-IdleMotion -KeepTransition
        $image.Source = $script:art['click']
        Start-ClickMotion
    } else { Set-PetState }
    $timer.Start()
}
function Complete-ClickAction {
    $timer.Stop()
    $script:clicked = $false
    Set-PetState
}
function Invoke-PetMouth {
    $mouthTimer.Stop()
    if ($script:state -ne 'idle') { return }
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $holdUntil = $script:idleDuration - 0.55
    $openBy = $script:idleDuration - 0.10
    foreach ($point in @(@(0,0), @(0.28,1), @($holdUntil,1), @($openBy,0))) {
        $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
        $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($point[0]))
        $key.Value = $point[1]
        $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
        $key.EasingFunction.EasingMode = 'EaseInOut'
        $animation.KeyFrames.Add($key) | Out-Null
    }
    $animation.FillBehavior = 'Stop'
    $mouth.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)
}
function Invoke-PetBlink {
    $blinkTimer.Stop()
    if ($script:state -eq 'focus') {
        # 专注时只有单次轻眨，间隔随机，像在认真看资料
        switch ($script:blinkPhase) {
            0 { $script:blinkPhase = 1; $image.Source = $script:art['half']; $delay = 130 }
            1 { $script:blinkPhase = 2; $image.Source = $script:art['blink']; $delay = Get-Random -Minimum 140 -Maximum 191 }
            2 { $script:blinkPhase = 3; $image.Source = $script:art['half']; $delay = 150 }
            3 { $script:blinkPhase = 0; $image.Source = $script:art['idle']; $delay = Get-Random -Minimum 3200 -Maximum 6200 }
        }
        $script:blinking = $script:blinkPhase -ne 0
        $blinkTimer.Interval = [TimeSpan]::FromMilliseconds($delay)
        $blinkTimer.Start()
        return
    }
    if ($script:state -ne 'idle' -or $script:idleForm -eq 4) { return }
    switch ($script:blinkPhase) {
        0 {
            if ($script:secondBlink) { $script:secondBlink = $false }
            $script:blinkPhase = 1
            $image.Source = $script:art['half']
            $delay = 140
        }
        1 { $script:blinkPhase = 2; $image.Source = $script:art['blink']; $delay = Get-Random -Minimum 160 -Maximum 201 }
        2 { $script:blinkPhase = 3; $image.Source = $script:art['half']; $delay = 180 }
        3 {
            $script:blinkPhase = 0
            $image.Source = $script:art['idle']
            if ($script:doubleBlink) {
                $script:doubleBlink = $false
                $script:secondBlink = $true
                $delay = 240
            } else { $delay = 3000 }
        }
    }
    $script:blinking = $script:blinkPhase -ne 0
    $blinkTimer.Interval = [TimeSpan]::FromMilliseconds($delay)
    if ($script:blinkPhase -ne 0 -or $script:secondBlink) { $blinkTimer.Start() }
}
$blinkTimer.Add_Tick({ Invoke-PetBlink })
$mouthTimer.Add_Tick({ Invoke-PetMouth })
$idleFormTimer.Add_Tick({ Invoke-IdleForm })
function Set-PetState {
    $previousState = $script:state
    $script:state = if ($script:clicked) { 'click' } elseif ($script:focused) { 'focus' } elseif ($script:over) { 'hover' } else { 'idle' }
    if ($previousState -ne $script:state) {
        $hasPrevious = -not [string]::IsNullOrEmpty($previousState)
        if ($hasPrevious) { Begin-IdleTransition 800 }
        Stop-IdleMotion -KeepTransition:$hasPrevious
        $image.Source = $script:art[$(if ($script:state -eq 'focus') { 'idle' } else { $script:state })]
        if ($script:state -eq 'idle') { Start-IdleMotion }
        if ($script:state -eq 'hover') { Start-HoverMotion }
        if ($script:state -eq 'click') { Start-ClickMotion }
        if ($script:state -eq 'focus') { Start-FocusMotion }
    }
}
# ============================================================
# v2 · 陪伴专注系统
# ============================================================
$script:focused = $false
$script:focusPaused = $false
$script:focusGoal = ''
$script:focusTotalMin = 25
$script:focusRemaining = 0
$script:focusElapsed = 0
$script:focusClock = New-Object System.Diagnostics.Stopwatch
$script:focusDuration = 0
$script:focusEntry = $null
$focusLines = @('好，一起加油！', '我就在这里陪着你。', '收到，我帮你看着时间。')
$pauseLine = '歇一会儿也可以，我等你。'
$resumeLine = '好，我们继续！'
$clickDuringFocusLines = @('我在这里陪你呀~', '专心一点，我帮你看着时间呢。')
$focusTimer = New-Object System.Windows.Threading.DispatcherTimer
$focusTimer.Interval = [TimeSpan]::FromSeconds(1)
function Update-FocusClock {
    $script:focusElapsed = $script:focusClock.Elapsed.TotalSeconds
    $script:focusRemaining = [int][Math]::Max(0, [Math]::Ceiling($script:focusDuration - $script:focusElapsed))
}
$focusTimer.Add_Tick({
    if (-not $script:focused -or $script:focusPaused) { return }
    Update-FocusClock
    Update-FocusIndicator
    if ($script:focusRemaining -le 0) { Complete-FocusSession }
})
$glanceTimer = New-Object System.Windows.Threading.DispatcherTimer
$glanceTimer.Add_Tick({
    if ($script:state -ne 'focus') { return }
    $sign = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
    foreach ($track in @(@($glanceRotate, 3.4), @($glanceTuft, -4.6))) {
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        foreach ($p in @(@(0, 0), @(0.45, ($sign * $track[1])), @(1.5, ($sign * $track[1])), @(2.0, 0))) {
            $key = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
            $key.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($p[0]))
            $key.Value = $p[1]
            $key.EasingFunction = New-Object System.Windows.Media.Animation.SineEase
            $key.EasingFunction.EasingMode = 'EaseInOut'
            $anim.KeyFrames.Add($key) | Out-Null
        }
        $anim.FillBehavior = 'Stop'
        $track[0].BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $anim)
    }
    $glanceTimer.Interval = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 18000 -Maximum 36000))
})
function Start-FocusMotion {
    $image.Source = $script:art['idle']
    $image.OpacityMask = $coreMask
    $tuft.Source = $script:art['tuft']
    $strand.Source = $script:art['strand']
    $tuft.Visibility = 'Visible'
    $strand.Visibility = 'Visible'
    $mouth.Visibility = 'Hidden'
    $mouth.Opacity = 0
    $sleepMarks.Visibility = 'Hidden'
    Animate-HoverGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1 1.021 1.007
    Animate-HoverGesture $breath ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1 1.008 1.003
    Animate-HoverGesture $tilt ([System.Windows.Media.RotateTransform]::AngleProperty) 0 0.84 -0.42
    Animate-HoverGesture $lift ([System.Windows.Media.TranslateTransform]::YProperty) 0 -1.26 -0.42
    Animate-HoverGesture $tuftRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 -2.52 1.26
    Animate-HoverGesture $strandRotate ([System.Windows.Media.RotateTransform]::AngleProperty) 0 1.26 -0.63
    $script:blinkPhase = 0
    $script:blinking = $false
    $script:secondBlink = $false
    $blinkTimer.Interval = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 3200 -Maximum 6200))
    $blinkTimer.Start()
    $glanceTimer.Interval = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 18000 -Maximum 36000))
    $glanceTimer.Start()
    Update-FocusIndicator
}
function Start-FocusSession([int]$Minutes, [string]$Goal) {
    if ($script:focused) { return }
    if ($Minutes -notin @(15,25,45,60)) { $Minutes = [int]$script:config.FocusMinutes }
    $script:focusGoal = $Goal
    $script:focusTotalMin = $Minutes
    $script:focusElapsed = 0
    $script:focusPaused = $false
    $script:focusClock.Restart()
    # 演示模式：分钟换成秒，快速走完整个流程
    $script:focusRemaining = if ($script:config.DemoMode) { $Minutes } else { $Minutes * 60 }
    $script:focusDuration = $script:focusRemaining
    $script:config.FocusMinutes = $Minutes
    $script:focused = $true
    $goalText = if ([string]::IsNullOrWhiteSpace($Goal)) { ('一起专注 ' + $Minutes + ' 分钟') } else { $Goal }
    $entry = [PSCustomObject]@{ Text = $goalText; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Done = $false }
    $script:focusEntry = $entry
    $goals = @($entry) + @($script:config.Goals)
    if ($goals.Count -gt 8) { $goals = @($goals[0..7]) }
    $script:config.Goals = $goals
    Save-PetConfig
    Set-PetState
    Show-Bubble ($focusLines | Get-Random) 3.5
    $focusTimer.Start()
}
function Complete-FocusSession([switch]$Early) {
    if (-not $script:focused) { return }
    $script:focusClock.Stop()
    Update-FocusClock
    $focusTimer.Stop()
    $script:focused = $false
    $script:focusPaused = $false
    $script:focusRemaining = 0
    $elapsed = [Math]::Floor($script:focusElapsed / 60)
    $award = 0
    if ($Early) {
        if ($elapsed -ge 5) { $award = 1 }
    } else {
        $award = 1
        if ($script:focusTotalMin -ge 25) { $award = 2 }
    }
    if ($award -gt 0) { $script:config.Stars = [int]$script:config.Stars + $award }
    if (-not $Early) {
        $script:config.TotalMinutes = [int]$script:config.TotalMinutes + $script:focusTotalMin
        $script:config.Sessions = [int]$script:config.Sessions + 1
    }
    if ($null -ne $script:focusEntry -and -not $Early) { $script:focusEntry.Done = $true }
    Update-FocusIndicator
    Save-PetConfig
    Update-ShopWindow
    if ($Early) {
        Set-PetState
        Show-Bubble '今天也很努力了，休息一下吧。' 4
    } else {
        $script:clicked = $true
        Set-PetState
        $timer.Start()
        if (-not $SelfTest -and -not $script:config.QuietMode) { try { [System.Media.SystemSounds]::Asterisk.Play() | Out-Null } catch { } }
        Show-Bubble ('完成啦！一起专注了 ' + $script:focusTotalMin + ' 分钟，获得 ⭐×' + $award + '！') 6
    }
}
function Invoke-FocusPauseToggle {
    if (-not $script:focused) { return }
    if (-not $script:focusPaused) {
        Update-FocusClock
        if ($script:focusRemaining -le 0) { Complete-FocusSession; return }
        $script:focusClock.Stop()
    } else { $script:focusClock.Start() }
    $script:focusPaused = -not $script:focusPaused
    Show-Bubble $(if ($script:focusPaused) { $pauseLine } else { $resumeLine }) 3
    Update-FocusIndicator
}
# ============================================================
# v2 · 记忆与问候
# ============================================================
function Get-Greeting {
    if (-not $script:configExisted -or [string]::IsNullOrEmpty($script:config.FirstSeen)) {
        $script:config.FirstSeen = Get-Date -Format 'yyyy-MM-dd HH:mm'
        Save-PetConfig
        return '初次见面！我是伊蕾娜。右键我，可以开始一起专注、布置我们的小窝哦。'
    }
    if ($script:config.Goals.Count -gt 0) {
        $lastGoal = $script:config.Goals[0]
        if ($null -ne $lastGoal.PSObject.Properties['Done'] -and -not $lastGoal.Done) {
            return ('你回来啦。上次的「' + $lastGoal.Text + '」做好了吗？')
        }
    }
    if (-not [string]::IsNullOrEmpty($script:config.LastSeen)) {
        try {
            $last = [datetime]::ParseExact($script:config.LastSeen, 'yyyy-MM-dd HH:mm', $null)
            if (((Get-Date) - $last).TotalDays -ge 3) {
                $places = @('雪山脚下的温泉旅馆', '海边的灯塔小镇', '森林深处的魔法书店', '开满向日葵的山坡')
                return ('好久不见！我给你带回一张明信片：' + ($places | Get-Random) + '。')
            }
        } catch { }
    }
    $name = if ([string]::IsNullOrWhiteSpace($script:config.Nickname)) { '' } else { ('，' + $script:config.Nickname) }
    $lines = @(('欢迎回来' + $name + '，今天也一起加油吧。'), ('你来啦' + $name + '。先歇口气，再一起努力。'), ('我在等你呢。今天想先做什么？'))
    return $lines | Get-Random
}
# 午后犯困：13-16 点之间每天一次，待机时小睡片刻
$napTimer = New-Object System.Windows.Threading.DispatcherTimer
$napTimer.Interval = [TimeSpan]::FromSeconds(60)
$napTimer.Add_Tick({
    if ($script:state -ne 'idle') { return }
    $h = (Get-Date).Hour
    if ($h -lt 13 -or $h -gt 16) { return }
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ($script:config.NapDay -eq $today) { return }
    $script:config.NapDay = $today
    Save-PetConfig
    $script:idleBag.Clear()
    $script:idleBag.Enqueue(4)
    Invoke-IdleForm
    Show-Bubble '有点困了…借你的桌面睡一小会儿。' 4
})
# ============================================================
# v2 · 对话框与小窗
# ============================================================
function Show-TextPrompt([string]$Title, [string]$PromptLabel, [string]$Default) {
    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 330
    $w.Height = 185
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'NoResize'
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(16)
    $row1 = New-Object System.Windows.Controls.RowDefinition; $row1.Height = 'Auto'
    $row2 = New-Object System.Windows.Controls.RowDefinition; $row2.Height = 'Auto'
    $row3 = New-Object System.Windows.Controls.RowDefinition; $row3.Height = 'Auto'
    $grid.RowDefinitions.Add($row1); $grid.RowDefinitions.Add($row2); $grid.RowDefinitions.Add($row3)
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $PromptLabel
    $label.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $label.FontSize = 13
    $label.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
    $box = New-Object System.Windows.Controls.TextBox
    $box.Text = $Default
    $box.FontSize = 13
    $box.Height = 30
    $box.VerticalContentAlignment = 'Center'
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = '确定'
    $ok.Width = 76
    $ok.Height = 28
    $ok.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $ok.Add_Click({ $w.DialogResult = $true })
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = '取消'
    $cancel.Width = 76
    $cancel.Height = 28
    $cancel.Add_Click({ $w.DialogResult = $false })
    $buttons.Children.Add($ok) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($label, 0)
    [System.Windows.Controls.Grid]::SetRow($box, 1)
    [System.Windows.Controls.Grid]::SetRow($buttons, 2)
    $grid.Children.Add($label) | Out-Null
    $grid.Children.Add($box) | Out-Null
    $grid.Children.Add($buttons) | Out-Null
    $w.Content = $grid
    $box.Focus() | Out-Null
    if ($w.ShowDialog()) { return $box.Text } else { return $null }
}
function Show-FocusStartWindow {
    $w = New-Object System.Windows.Window
    $w.Title = '开始专注'
    $w.Width = 360
    $w.Height = 285
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'NoResize'
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(16)
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = '今天想一起完成什么？'
    $title.FontSize = 15
    $title.FontWeight = 'Bold'
    $title.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6A5A8E')
    $title.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
    $goalBox = New-Object System.Windows.Controls.TextBox
    $goalBox.FontSize = 13
    $goalBox.Height = 30
    $goalBox.VerticalContentAlignment = 'Center'
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = '例如：写完猜数字程序'
    $hint.FontSize = 11
    $hint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9A8BAF')
    $hint.Margin = New-Object System.Windows.Thickness(2, 4, 0, 10)
    $durLabel = New-Object System.Windows.Controls.TextBlock
    $durLabel.Text = '专注时长'
    $durLabel.FontSize = 12
    $durLabel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
    $combo = New-Object System.Windows.Controls.ComboBox
    $combo.Width = 120
    $combo.HorizontalAlignment = 'Left'
    foreach ($m in @(15, 25, 45, 60)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = ($m.ToString() + ' 分钟')
        $item.Tag = $m
        $combo.Items.Add($item) | Out-Null
        if ($m -eq [int]$script:config.FocusMinutes) { $combo.SelectedItem = $item }
    }
    if ($null -eq $combo.SelectedItem) { $combo.SelectedIndex = 1 }
    $demoHint = New-Object System.Windows.Controls.TextBlock
    $demoHint.FontSize = 11
    $demoHint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C08A5A')
    $demoHint.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $demoHint.TextWrapping = 'Wrap'
    $demoHint.Text = $(if ($script:config.DemoMode) { '⚡ 演示模式已开：分钟会按秒计时。' } else { '' })
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = '开始陪伴'
    $ok.Width = 96
    $ok.Height = 30
    $ok.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = '取消'
    $cancel.Width = 76
    $cancel.Height = 30
    $result = @{ Goal = ''; Minutes = 25 }
    $ok.Add_Click({
        $result.Goal = $goalBox.Text
        $sel = $combo.SelectedItem
        if ($null -ne $sel -and $null -ne $sel.Tag) { $result.Minutes = [int]$sel.Tag }
        $w.DialogResult = $true
    })
    $cancel.Add_Click({ $w.DialogResult = $false })
    $buttons.Children.Add($ok) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    $panel.Children.Add($title) | Out-Null
    $panel.Children.Add($goalBox) | Out-Null
    $panel.Children.Add($hint) | Out-Null
    $panel.Children.Add($durLabel) | Out-Null
    $panel.Children.Add($combo) | Out-Null
    $panel.Children.Add($demoHint) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $w.Content = $panel
    $goalBox.Focus() | Out-Null
    if ($w.ShowDialog()) { Start-FocusSession -Minutes $result.Minutes -Goal $result.Goal }
}
# ============================================================
# v2 · 成长解锁（星星与装饰商店）
# ============================================================
function Unlock-Decoration([string]$Id) {
    $item = $script:decorCatalog | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $item) { return $false }
    if ($script:config.OwnedItems -contains $Id) { return $false }
    if ([int]$script:config.Stars -lt [int]$item.Cost) {
        Show-Bubble '星星还差一点点，再专注一次吧。' 3
        return $false
    }
    $script:config.Stars = [int]$script:config.Stars - [int]$item.Cost
    $script:config.OwnedItems = @($script:config.OwnedItems) + @($Id)
    Save-PetConfig
    Invoke-DecorRefresh
    Update-ShopWindow
    Show-Bubble ('解锁成功：' + $item.Name + '！') 3.5
    return $true
}
$script:shopView = $null
function Use-Decoration([string]$Id) {
    if ($script:config.OwnedItems -notcontains $Id) { return (Unlock-Decoration $Id) }
    if ($Id -notin @('rug-sakura','rug-star')) { return $false }
    # The last rug in ownership order is the one on display. Switching is free.
    $script:config.OwnedItems = @($script:config.OwnedItems | Where-Object { $_ -ne $Id }) + @($Id)
    Save-PetConfig
    Invoke-DecorRefresh
    Update-ShopWindow
    return $true
}
function Update-ShopWindow {
    if ($null -eq $script:shopView) { return }
    $script:shopView.Balance.Text = '⭐ 星星余额：' + $script:config.Stars
    $activeRug = $script:config.OwnedItems | Where-Object { $_ -in @('rug-sakura','rug-star') } | Select-Object -Last 1
    foreach ($row in $script:shopView.Rows) {
        $owned = $script:config.OwnedItems -contains $row.Item.Id
        $canSwitch = $owned -and $row.Item.Type -eq 'rug' -and $activeRug -ne $row.Item.Id
        $enough = [int]$script:config.Stars -ge [int]$row.Item.Cost
        $row.Button.Content = if ($canSwitch) { '使用' } elseif ($owned -and $row.Item.Type -eq 'rug') { '使用中' } elseif ($owned) { '已拥有' } elseif ($enough) { '解锁' } else { '星不够' }
        $row.Button.IsEnabled = $canSwitch -or (-not $owned -and $enough)
    }
}
function Show-ShopWindow {
    $w = New-Object System.Windows.Window
    $w.Title = '伊蕾娜的小窝装扮'
    $w.Width = 360
    $w.Height = 470
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.ShowInTaskbar = $false
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(16)
    $balance = New-Object System.Windows.Controls.TextBlock
    $balance.Text = '⭐ 星星余额：' + $script:config.Stars
    $balance.FontSize = 16
    $balance.FontWeight = 'Bold'
    $balance.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $balance.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A6FA8')
    $hint = New-Object System.Windows.Controls.TextBlock
    $hint.Text = '完成专注就能获得星星。这里是我们一起布置的小角落。'
    $hint.FontSize = 11
    $hint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9A8BAF')
    $hint.TextWrapping = 'Wrap'
    $hint.Margin = New-Object System.Windows.Thickness(0, 4, 0, 12)
    $panel.Children.Add($balance) | Out-Null
    $panel.Children.Add($hint) | Out-Null
    $rows = @()
    foreach ($item in $script:decorCatalog) {
        $row = New-Object System.Windows.Controls.Border
        $row.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#EDE4F5')
        $row.BorderThickness = New-Object System.Windows.Thickness(1)
        $row.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $row.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
        $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        $rowGrid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = 'Auto'
        $rowGrid.ColumnDefinitions.Add($col1); $rowGrid.ColumnDefinitions.Add($col2)
        $nameBlock = New-Object System.Windows.Controls.StackPanel
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $item.Name
        $nameText.FontSize = 13
        $nameText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
        $costText = New-Object System.Windows.Controls.TextBlock
        $costText.Text = ('需要 ' + $item.Cost + ' ⭐')
        $costText.FontSize = 11
        $costText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9A8BAF')
        $nameBlock.Children.Add($nameText) | Out-Null
        $nameBlock.Children.Add($costText) | Out-Null
        $btn = New-Object System.Windows.Controls.Button
        $btn.Width = 74
        $btn.Height = 28
        $btn.VerticalAlignment = 'Center'
        $btn.Tag = $item.Id
        $rowGrid.Children.Add($nameBlock) | Out-Null
        $rowGrid.Children.Add($btn) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
        [System.Windows.Controls.Grid]::SetColumn($btn, 1)
        $row.Child = $rowGrid
        $panel.Children.Add($row) | Out-Null
        $rows += [PSCustomObject]@{ Row = $row; Button = $btn; Item = $item }
    }
    foreach ($r in $rows) {
        $r.Button.Add_Click({
            param($sender, $eventArgs)
            Use-Decoration ([string]$sender.Tag) | Out-Null
        })
    }
    $script:shopView = [PSCustomObject]@{ Balance = $balance; Rows = $rows }
    Update-ShopWindow
    $closeBtn = New-Object System.Windows.Controls.Button
    $closeBtn.Content = '完成'
    $closeBtn.Width = 90
    $closeBtn.Height = 30
    $closeBtn.HorizontalAlignment = 'Right'
    $closeBtn.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    $closeBtn.Add_Click({ $w.DialogResult = $true })
    $panel.Children.Add($closeBtn) | Out-Null
    $w.Content = $panel
    try {
        $w.ShowDialog() | Out-Null
    } finally { $script:shopView = $null }
}
function Show-MemoryPanel {
    $w = New-Object System.Windows.Window
    $w.Title = '我们的记忆'
    $w.Width = 370
    $w.Height = 500
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.ShowInTaskbar = $false
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(16)
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = '💜 关于我们'
    $title.FontSize = 16
    $title.FontWeight = 'Bold'
    $title.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A6FA8')
    $title.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $nickGrid = New-Object System.Windows.Controls.Grid
    $nc1 = New-Object System.Windows.Controls.ColumnDefinition; $nc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $nc2 = New-Object System.Windows.Controls.ColumnDefinition; $nc2.Width = 'Auto'
    $nickGrid.ColumnDefinitions.Add($nc1); $nickGrid.ColumnDefinitions.Add($nc2)
    $nickText = New-Object System.Windows.Controls.TextBlock
    $nickText.FontSize = 13
    $nickText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $nickText.TextWrapping = 'Wrap'
    $nickText.Text = '称呼：' + $(if ([string]::IsNullOrWhiteSpace($script:config.Nickname)) { '还没有，告诉伊蕾娜吧' } else { $script:config.Nickname })
    $nickBtn = New-Object System.Windows.Controls.Button
    $nickBtn.Content = '修改称呼'
    $nickBtn.Width = 84
    $nickBtn.Height = 26
    $nickBtn.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $nickBtn.Add_Click({
        $name = Show-TextPrompt '修改称呼' '希望伊蕾娜怎么称呼你？' $script:config.Nickname
        if ($null -ne $name) {
            $script:config.Nickname = $name.Trim()
            Save-PetConfig
            $nickText.Text = '称呼：' + $(if ([string]::IsNullOrWhiteSpace($script:config.Nickname)) { '还没有，告诉伊蕾娜吧' } else { $script:config.Nickname })
            Show-Bubble $(if ([string]::IsNullOrWhiteSpace($script:config.Nickname)) { '好，那我还是叫你主人吧。' } else { ('记住了！' + $script:config.Nickname + '。') }) 3
        }
    })
    $nickGrid.Children.Add($nickText) | Out-Null
    $nickGrid.Children.Add($nickBtn) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($nickText, 0)
    [System.Windows.Controls.Grid]::SetColumn($nickBtn, 1)
    $panel.Children.Add($title) | Out-Null
    $panel.Children.Add($nickGrid) | Out-Null
    $stats = New-Object System.Windows.Controls.TextBlock
    $stats.FontSize = 13
    $stats.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $stats.TextWrapping = 'Wrap'
    $stats.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    $stats.Text = '累计一起专注：' + $script:config.TotalMinutes + ' 分钟（' + $script:config.Sessions + ' 次）' + [Environment]::NewLine + '星星：' + $script:config.Stars + ' ⭐'
    $panel.Children.Add($stats) | Out-Null
    $ownedNames = @($script:decorCatalog | Where-Object { $script:config.OwnedItems -contains $_.Id } | ForEach-Object { $_.Name })
    $ownedText = New-Object System.Windows.Controls.TextBlock
    $ownedText.FontSize = 13
    $ownedText.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $ownedText.TextWrapping = 'Wrap'
    $ownedText.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
    $ownedText.Text = '已解锁的小物：' + $(if ($ownedNames.Count -eq 0) { '还没有，完成专注来解锁吧' } else { $ownedNames -join '、' })
    $panel.Children.Add($ownedText) | Out-Null
    $goalTitle = New-Object System.Windows.Controls.TextBlock
    $goalTitle.Text = '最近的目标：'
    $goalTitle.FontSize = 13
    $goalTitle.FontWeight = 'Bold'
    $goalTitle.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $goalTitle.Margin = New-Object System.Windows.Thickness(0, 12, 0, 4)
    $panel.Children.Add($goalTitle) | Out-Null
    $goalShown = 0
    foreach ($goal in @($script:config.Goals)) {
        if ($goalShown -ge 3) { break }
        $line = New-Object System.Windows.Controls.TextBlock
        $line.FontSize = 12
        $line.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
        $line.TextWrapping = 'Wrap'
        $line.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6F5F86')
        $line.Text = '· ' + $goal.Text + $(if ($goal.Done) { '  ✓' } else { '  …' })
        $line.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        $panel.Children.Add($line) | Out-Null
        $goalShown += 1
    }
    if ($goalShown -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = '还没有目标。右键“开始专注”写下第一个吧。'
        $empty.FontSize = 12
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#9A8BAF')
        $panel.Children.Add($empty) | Out-Null
    }
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    $clear = New-Object System.Windows.Controls.Button
    $clear.Content = '清空目标记录'
    $clear.Width = 104
    $clear.Height = 28
    $clear.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $clear.Add_Click({
        $script:config.Goals = @()
        Save-PetConfig
        Show-Bubble '目标记录清空啦。' 2.5
        $w.Close()
    })
    $closeBtn = New-Object System.Windows.Controls.Button
    $closeBtn.Content = '关闭'
    $closeBtn.Width = 76
    $closeBtn.Height = 28
    $closeBtn.Add_Click({ $w.Close() })
    $buttons.Children.Add($clear) | Out-Null
    $buttons.Children.Add($closeBtn) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $w.Content = $panel
    $w.ShowDialog() | Out-Null
}
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Complete-ClickAction })
$inputRoot.Add_MouseEnter({
    $point = [System.Windows.Input.Mouse]::GetPosition($inputRoot)
    Update-PettingZone $point.X $point.Y
    $script:over = $true
    Set-PetState
})
$inputRoot.Add_MouseLeave({
    $inputRoot.Cursor = $null
    $script:pettingZone = $false
    $script:over = $false
    Set-PetState
})
$inputRoot.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ClickCount -ge 2) {
        Start-PetChatBackend
        Show-PetChat
        return
    }
    Invoke-ClickAction
    $script:pressedAt = [System.Windows.Input.Mouse]::GetPosition($window)
    $script:pressLeft = $window.Left
    $script:pressTop = $window.Top
    $inputRoot.CaptureMouse() | Out-Null
})
$inputRoot.Add_MouseMove({
    if (-not $inputRoot.IsMouseCaptured) {
        $point = [System.Windows.Input.Mouse]::GetPosition($inputRoot)
        Update-PettingZone $point.X $point.Y
    }
    if ($inputRoot.IsMouseCaptured -and [System.Windows.Input.Mouse]::LeftButton -eq 'Pressed') {
        $p = [System.Windows.Input.Mouse]::GetPosition($window)
        $window.Left += $p.X - $script:pressedAt.X
        $window.Top += $p.Y - $script:pressedAt.Y
        if ($script:clicked -and ([Math]::Abs($window.Left-$script:pressLeft)+[Math]::Abs($window.Top-$script:pressTop)) -ge 6) {
            $timer.Stop(); $script:clicked = $false; Set-PetState
        }
    }
})
$inputRoot.Add_MouseLeftButtonUp({
    if (-not $inputRoot.IsMouseCaptured) { return }
    $inputRoot.ReleaseMouseCapture()
    if ([Math]::Abs($window.Left - $script:pressLeft) + [Math]::Abs($window.Top - $script:pressTop) -ge 6) {
        $timer.Stop()
        $script:clicked = $false
        Set-PetState
    }
})
$menu = New-Object System.Windows.Controls.ContextMenu
$miChat = New-Object System.Windows.Controls.MenuItem
$miChat.Header = '聊聊天 / 互动…'
$miFocus = New-Object System.Windows.Controls.MenuItem
$miFocus.Header = '开始专注…'
$miPause = New-Object System.Windows.Controls.MenuItem
$miPause.Header = '暂停专注'
$miEnd = New-Object System.Windows.Controls.MenuItem
$miEnd.Header = '结束专注'
$miShop = New-Object System.Windows.Controls.MenuItem
$miShop.Header = '小窝装扮…'
$miMemory = New-Object System.Windows.Controls.MenuItem
$miMemory.Header = '我们的记忆…'
$miDemo = New-Object System.Windows.Controls.MenuItem
$miDemo.Header = '演示模式'
$miDemo.IsCheckable = $true
$miQuiet = New-Object System.Windows.Controls.MenuItem
$miQuiet.Header = '安静模式'
$miQuiet.IsCheckable = $true
$miExit = New-Object System.Windows.Controls.MenuItem
$miExit.Header = '退出伊蕾娜'
$sep1 = New-Object System.Windows.Controls.Separator
$sep2 = New-Object System.Windows.Controls.Separator
$sep3 = New-Object System.Windows.Controls.Separator
foreach ($mi in @($miChat, $miFocus, $miPause, $miEnd, $sep1, $miShop, $miMemory, $sep2, $miDemo, $miQuiet, $sep3, $miExit)) { $menu.Items.Add($mi) | Out-Null }
$menu.Add_Opened({
    $miFocus.IsEnabled = -not $script:focused
    $miEnd.IsEnabled = $script:focused
    $miPause.IsEnabled = $script:focused
    $miPause.Header = if ($script:focusPaused) { '继续专注' } else { '暂停专注' }
    $miDemo.IsChecked = [bool]$script:config.DemoMode
    $miQuiet.IsChecked = [bool]$script:config.QuietMode
})
$miFocus.Add_Click({ Show-FocusStartWindow })
$miChat.Add_Click({ Start-PetChatBackend; Show-PetChat })
$miPause.Add_Click({ Invoke-FocusPauseToggle })
$miEnd.Add_Click({ if ($script:focused) { Complete-FocusSession -Early } })
$miShop.Add_Click({ Show-ShopWindow })
$miMemory.Add_Click({ Show-MemoryPanel })
$miDemo.Add_Click({
    $script:config.DemoMode = -not [bool]$script:config.DemoMode
    Save-PetConfig
    Show-Bubble $(if ($script:config.DemoMode) { '演示模式开：专注会按秒计时，方便快速体验。' } else { '演示模式关：恢复正常计时。' }) 3.5
})
function Set-QuietMode([bool]$Enabled) {
    $script:config.QuietMode = $Enabled
    if ($Enabled) {
        $bubbleTimer.Stop()
        $bubbleBorder.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $bubbleBorder.Opacity = 0
    }
    $window.Opacity = if ($script:config.QuietMode) { 0.85 } else { 1 }
    Update-FocusIndicator
    Save-PetConfig
}
$miQuiet.Add_Click({ Set-QuietMode (-not [bool]$script:config.QuietMode) })
$miExit.Add_Click({ $window.Close() })
$inputRoot.ContextMenu = $menu
$window.Add_Closed({
    Stop-PetConversation
    $bubbleTimer.Stop(); $script:focusClock.Stop(); $timer.Stop(); $focusTimer.Stop(); $glanceTimer.Stop(); $napTimer.Stop(); Stop-IdleMotion
    $script:config.Left = [int]$window.Left
    $script:config.Top = [int]$window.Top
    $script:config.LastSeen = Get-Date -Format 'yyyy-MM-dd HH:mm'
    Save-PetConfig
    if ($script:isolatedRun) {
        foreach ($suffix in @('', '.bak', '.tmp')) { Remove-Item -LiteralPath ($script:configPath + $suffix) -ErrorAction SilentlyContinue }
    }
})
. (Join-Path $PSScriptRoot 'Dialogue.ps1')
. (Join-Path $PSScriptRoot 'Chat.ps1')
# v2 运行时初始化
Invoke-DecorRefresh
if ($script:config.QuietMode) { $window.Opacity = 0.85 }
$script:greeted = $false
$window.Add_ContentRendered({
    if (-not $script:greeted) {
        $script:greeted = $true
        $greet = Get-Greeting
        if (-not [string]::IsNullOrEmpty($greet)) { Show-Bubble $greet 5.5 }
        if ($OpenChat) { Start-PetChatBackend; Show-PetChat }
    }
})
if ($Smoke) {
    $window.Add_ContentRendered({
        $script:config.DemoMode = $true
        Start-FocusSession -Minutes 25 -Goal '写 C 语言猜数字程序'
    })
}
$napTimer.Start()
Set-PetState
if ($SelfTest) {
    $surface.Measure((New-Object System.Windows.Size(280, 280)))
    $surface.Arrange((New-Object System.Windows.Rect(0, 0, 280, 280)))
    Begin-IdleTransition
    if ($null -eq $transitionOverlay.Source -or -not $transitionOverlay.HasAnimatedProperties) { throw 'Idle transition failed' }
    $savedBag = $script:idleBag
    $savedLast = $script:lastIdleForm
    $script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
    $previous = -1
    for ($round = 0; $round -lt 20; $round++) {
        $forms = @(1..5 | ForEach-Object { Get-NextIdleForm })
        if (($forms | Sort-Object -Unique).Count -ne 5 -or $forms[0] -eq $previous) { throw 'Equal-weight idle shuffle failed' }
        $previous = $forms[4]
    }
    $script:idleBag = $savedBag
    $script:lastIdleForm = $savedLast
    foreach ($form in 0..4) {
        $script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
        $script:idleBag.Enqueue($form)
        Invoke-IdleForm
        $expectedDuration = if ($form -in @(2,4)) { 5 } else { 3 }
        if ($idleFormTimer.Interval.TotalSeconds -ne $expectedDuration -or $script:idleDuration -ne $expectedDuration) { throw 'Idle duration mismatch' }
    }
    $script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
    $script:idleBag.Enqueue(4)
    Invoke-IdleForm
    if ($image.Source -ne $script:art['blink'] -or $mouth.Opacity -ne 1 -or $sleepMarks.Visibility -ne 'Visible' -or $blinkTimer.IsEnabled -or $mouthTimer.IsEnabled) { throw 'Sleep pose failed' }
    $script:over = $true
    Set-PetState
    if ($image.Source -ne $script:art['hover'] -or $sleepMarks.Visibility -ne 'Hidden') { throw 'Wake on hover failed' }
    $script:idleBag.Enqueue(0)
    $script:over = $false
    Set-PetState
    foreach ($expected in @('half','blink','half','idle')) {
        Invoke-PetBlink
        if ($image.Source -ne $script:art[$expected]) { throw 'Blink transition sequence failed' }
        if ($script:blinkPhase -eq 1 -and $blinkTimer.Interval.TotalMilliseconds -ne 140) { throw 'Blink closing time failed' }
        if ($script:blinkPhase -eq 2 -and ($blinkTimer.Interval.TotalMilliseconds -lt 160 -or $blinkTimer.Interval.TotalMilliseconds -gt 200)) { throw 'Blink hold time failed' }
        if ($script:blinkPhase -eq 3 -and $blinkTimer.Interval.TotalMilliseconds -ne 180) { throw 'Blink reopening time failed' }
    }
    Invoke-PetMouth
    if (-not $mouth.HasAnimatedProperties -or -not $tuftRotate.HasAnimatedProperties -or -not $strandRotate.HasAnimatedProperties) { throw 'Mouth/hair animation failed' }
    foreach ($case in @(@($false,$false,'idle'), @($true,$false,'hover'), @($true,$true,'click'), @($false,$true,'click'), @($false,$false,'idle'))) {
        $script:over = $case[0]; $script:clicked = $case[1]; Set-PetState
        if ($script:state -ne $case[2]) { throw 'State test failed' }
        if ($script:state -ne 'idle' -and $image.Source -ne $script:art[$case[2]]) { throw 'Interaction artwork failed' }
    }
    $enter = New-Object System.Windows.Input.MouseEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0)
    $enter.RoutedEvent = [System.Windows.UIElement]::MouseEnterEvent
    $inputRoot.RaiseEvent($enter)
    if ($script:state -ne 'hover') { throw 'Hover event failed' }
    if (-not $transitionOverlay.HasAnimatedProperties -or $transitionOverlay.IsHitTestVisible) { throw 'Hover transition missing or intercepts input' }
    if ($idleFormTimer.IsEnabled -or $blinkTimer.IsEnabled -or $mouthTimer.IsEnabled -or $mouth.HasAnimatedProperties) { throw 'Idle timers continued during hover' }
    if (-not $breath.HasAnimatedProperties -or -not $tuftRotate.HasAnimatedProperties -or $tuft.Source -ne $script:art['hover-tuft']) { throw 'Hover motion failed' }
    $down = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
    $down.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonDownEvent
    $inputRoot.RaiseEvent($down)
    if ($script:state -ne 'click') { throw 'Immediate press feedback failed' }
    if (-not $leftEarRotate.HasAnimatedProperties -or -not $rightEarRotate.HasAnimatedProperties -or -not $uprightRotate.HasAnimatedProperties -or $clickEffects.Visibility -ne 'Visible') { throw 'Click ears/tuft/effects failed' }
    $inputRoot.ReleaseMouseCapture()
    $leave = New-Object System.Windows.Input.MouseEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0)
    $leave.RoutedEvent = [System.Windows.UIElement]::MouseLeaveEvent
    $inputRoot.RaiseEvent($leave)
    if ($script:state -ne 'click' -or -not $timer.IsEnabled -or $timer.Interval.TotalSeconds -ne 5) { throw 'Remote tap playback interrupted on leave' }
    if ($effectItems.Count -ne 18 -or @($effectItems | Where-Object { $_.Label.Text -eq '♥' }).Count -ne 9 -or -not $effectItems[0].Scale.HasAnimatedProperties -or -not $effectItems[0].Turn.HasAnimatedProperties) { throw 'Rich click effects failed' }
    $serial = $script:clickSerial
    Invoke-ClickAction
    if ($script:clickSerial -ne $serial+1) { throw 'Repeated tap failed to replay' }
    Complete-ClickAction
    if ($script:state -ne 'idle' -or $clickEffects.Visibility -ne 'Hidden') { throw 'Click completion failed' }
    if (-not $idleFormTimer.IsEnabled -or -not $breath.HasAnimatedProperties) { throw 'Idle motion failed to resume' }
    foreach ($from in @('idle','hover','click')) {
        foreach ($to in @('idle','hover','click')) {
            if ($from -eq $to) { continue }
            $script:clicked = $from -eq 'click'; $script:over = $from -eq 'hover'; Set-PetState
            $script:clicked = $to -eq 'click'; $script:over = $to -eq 'hover'; Set-PetState
            if ($script:state -ne $to -or -not $transitionOverlay.HasAnimatedProperties -or -not $handoffRotate.HasAnimatedProperties -or -not $handoffScale.HasAnimatedProperties) { throw "Missing transition: $from -> $to" }
        }
    }
    $script:clicked = $false; $script:over = $true; Set-PetState
    Update-PettingZone 140 55
    if ($inputRoot.Cursor -ne $pawCursor -or $patHead.Visibility -ne 'Visible' -or $patPillow.Visibility -ne 'Visible') { throw 'Crown paw cursor or head pat failed' }
    if ($patCore.Source -ne $script:art['hover'] -or -not $patRotate.HasAnimatedProperties -or -not $patTuftRotate.HasAnimatedProperties -or -not $patStrandRotate.HasAnimatedProperties) { throw 'Continuous head/hair animation failed' }
    if (-not $patPillow.RenderTransform.Value.IsIdentity) { throw 'Fixed pillow failed' }
    Update-PettingZone 140 200
    if ($null -ne $inputRoot.Cursor -or $patHead.Visibility -ne 'Hidden' -or $patPillow.Visibility -ne 'Hidden') { throw 'Paw cursor failed to leave crown' }
    Update-PettingZone 140 55
    Invoke-ClickAction
    if ($patHead.Visibility -ne 'Hidden' -or $patPillow.Visibility -ne 'Hidden' -or $script:state -ne 'click') { throw 'Click failed to interrupt petting' }
    Complete-ClickAction
    if ($patHead.Visibility -ne 'Visible' -or -not $patRotate.HasAnimatedProperties) { throw 'Head pat failed to resume after click' }
    # --- v2 陪伴专注 / 成长解锁 / 轻量记忆 检查 ---
    $script:over = $false; $script:clicked = $false; $script:focused = $false; Set-PetState
    if ($script:state -ne 'idle') { throw 'v2 reset failed' }
    $script:config.DemoMode = $true
    Start-FocusSession -Minutes 25 -Goal '写 C 语言猜数字程序'
    if ($script:state -ne 'focus' -or $script:focusRemaining -ne 25 -or -not $focusTimer.IsEnabled) { throw 'Focus start failed' }
    if ($script:config.Goals.Count -lt 1 -or $script:config.Goals[0].Done -ne $false -or $script:config.Goals[0].Text -ne '写 C 语言猜数字程序') { throw 'Goal recording failed' }
    if (-not $breath.HasAnimatedProperties -or -not $blinkTimer.IsEnabled) { throw 'Focus motion failed' }
    Update-FocusIndicator
    if ($focusIndicator.Visibility -ne 'Visible' -or $focusIndicatorText.Text -notmatch '25') { throw 'Focus indicator failed' }
    Invoke-FocusPauseToggle
    if (-not $script:focusPaused) { throw 'Focus pause failed' }
    Invoke-FocusPauseToggle
    if ($script:focusPaused) { throw 'Focus resume failed' }
    $starsBefore = [int]$script:config.Stars
    $script:config.QuietMode = $true
    Complete-FocusSession
    $script:config.QuietMode = $false
    if ($script:focused -or $script:state -ne 'click') { throw 'Focus completion celebration failed' }
    if ([int]$script:config.Stars -ne $starsBefore + 2) { throw 'Star award failed' }
    if ([int]$script:config.Sessions -ne 1 -or [int]$script:config.TotalMinutes -ne 25) { throw 'Focus stats failed' }
    if ($script:config.Goals[0].Done -ne $true) { throw 'Goal completion flag failed' }
    $script:clicked = $false; Complete-ClickAction
    if ($script:state -ne 'idle') { throw 'Post-celebration idle failed' }
    Start-FocusSession -Minutes 25 -Goal '临时目标'
    # Paused/wall time must not award stars: only active stopwatch time counts.
    $script:focusClock.Stop()
    Invoke-FocusPauseToggle
    Complete-FocusSession -Early
    if ($script:focused) { throw 'Early end failed to leave focus' }
    if ([int]$script:config.Stars -ne $starsBefore + 2) { throw 'Paused early end wrongly awarded stars' }
    $ownedBefore = @($script:config.OwnedItems).Count
    $script:config.Stars = 100
    if (-not (Unlock-Decoration 'mug')) { throw 'Unlock mug failed' }
    if (@($script:config.OwnedItems).Count -ne $ownedBefore + 1 -or [int]$script:config.Stars -ne 98) { throw 'Unlock economy failed' }
    if (Unlock-Decoration 'mug') { throw 'Duplicate unlock allowed' }
    $script:config.Stars = 0
    if (Unlock-Decoration 'starlamp') { throw 'Insufficient stars unlock allowed' }
    if ($script:decorCanvas.Children.Count -lt 2) { throw 'Decor refresh failed' }
    Save-PetConfig
    $script:config.Nickname = '测试昵称'
    Save-PetConfig
    $script:configExisted = $true
    Load-PetConfig
    if ($script:config.Nickname -ne '测试昵称' -or [int]$script:config.Stars -ne 0) { throw 'Config round trip failed' }
    if (-not ($script:config.OwnedItems -contains 'mug')) { throw 'Owned items round trip failed' }
    $script:configExisted = $true
    $script:config.FirstSeen = '2026-01-01 00:00'
    $script:config.LastSeen = '2026-01-01 00:00'
    $script:config.Goals = @()
    $g = Get-Greeting
    if ($g -notmatch '明信片') { throw 'Postcard greeting failed' }
    $script:config.LastSeen = (Get-Date).AddHours(-1).ToString('yyyy-MM-dd HH:mm')
    $script:config.Goals = @([PSCustomObject]@{ Text = '上次目标'; Date = ''; Done = $false })
    $g = Get-Greeting
    if ($g -notmatch '上次目标') { throw 'Goal greeting failed' }
    $script:config.Goals = @()
    $g = Get-Greeting
    if ([string]::IsNullOrEmpty($g)) { throw 'Return greeting failed' }
    Write-Output 'PASS: v1 all modes; v2 focus/pause/complete, stars, unlock economy, decor, config round trip, greetings.'
    $window.Close()
    exit
}
if ($Preview -or $SleepPreview -or $HoverPreview -or $ClickPreview -or $HeadPatPreview -or $FocusPreview) {
    $previewDir = Join-Path $PSScriptRoot $(if ($FocusPreview) { 'preview-focus' } elseif ($HeadPatPreview) { '../../work/headpat-motion-preview' } elseif ($ClickPreview) { '../../work/click-motion-preview' } elseif ($HoverPreview) { '../../work/hover-motion-preview' } else { '../../work/four-idle-preview' })
    New-Item -ItemType Directory -Path $previewDir -Force | Out-Null
    $window.IsHitTestVisible = $false
    $window.ShowActivated = $false
    $window.Left = -10000
    $window.Top = -10000
    if ($HeadPatPreview) { $window.Height = 500 }
    if ($FocusPreview) {
        $script:config.DemoMode = $true
        $script:config.OwnedItems = @('mug', 'plant', 'starlamp', 'rug-sakura')
        Invoke-DecorRefresh
    }
    $window.Show()
    $window.UpdateLayout()
    if ($SleepPreview) {
        $script:idleBag = New-Object 'System.Collections.Generic.Queue[int]'
        $script:idleBag.Enqueue(4)
        Invoke-IdleForm
        $idleFormTimer.Stop()
    }
    $previewCount = if ($FocusPreview) { 100 } elseif ($HeadPatPreview) { 240 } elseif ($ClickPreview) { 75 } elseif ($HoverPreview) { 80 } elseif ($SleepPreview) { 36 } else { 160 }
    $renderWidth = [int][Math]::Ceiling($window.ActualWidth)
    $renderHeight = [int][Math]::Ceiling($window.ActualHeight)
    if ($HeadPatPreview) {
        $previewPaw = New-SpriteLayer 'paw-cursor'
        $previewPaw.Width = 144; $previewPaw.Height = 144
        $previewPaw.HorizontalAlignment = 'Left'; $previewPaw.VerticalAlignment = 'Top'
        $previewPaw.Margin = New-Object System.Windows.Thickness(144,57,0,0)
        $previewPaw.Visibility = 'Hidden'
        $stage.Children.Add($previewPaw) | Out-Null
    }
    $capturedFrames = New-Object 'System.Collections.Generic.List[object]'
    $captureClock = [Diagnostics.Stopwatch]::StartNew()
    $captureLog = New-Object 'System.Collections.Generic.List[object]'
    for ($index = 0; $index -lt $previewCount; $index++) {
        if ($FocusPreview -and $index -eq 4) { Start-FocusSession -Minutes 25 -Goal '写 C 语言猜数字程序' }
        if ($FocusPreview -and $index -eq 60) { Complete-FocusSession }
        if ($HeadPatPreview -and $index -eq 12) { Update-PettingZone 140 55; $script:over=$true; Set-PetState; $previewPaw.Visibility='Visible' }
        if ($HeadPatPreview -and $index -eq 216) { $previewPaw.Visibility='Hidden'; $inputRoot.Cursor=$null; $script:pettingZone=$false; $script:over=$false; Set-PetState }
        if ($ClickPreview -and $index -eq 4) { Invoke-ClickAction }
        if ($ClickPreview -and $index -eq 8) { $script:over = $false; Set-PetState }
        if ($HoverPreview -and $index -eq 4) { $script:over = $true; Set-PetState }
        if ($HoverPreview -and $index -eq 58) { $script:over = $false; Set-PetState }
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $step = New-Object System.Windows.Threading.DispatcherTimer
        $step.Interval = [TimeSpan]::FromMilliseconds($(if ($HeadPatPreview) {16} else {50}))
        $step.Add_Tick({ $step.Stop(); $frame.Continue = $false })
        $step.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        $captureLog.Add([PSCustomObject]@{ milliseconds=$captureClock.ElapsedMilliseconds; headAngle=$patRotate.Angle; tuftAngle=$patTuftRotate.Angle; state=$script:state; leftEarUp=$clickEarLeftUp.Opacity; rightEarUp=$clickEarRightUp.Opacity; relaxedEar=$clickEarLeft.Opacity })
        $render = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($renderWidth, $renderHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $render.Render($window)
        $render.Freeze()
        $capturedFrames.Add($render)
    }
    $window.Close()
    for ($index=0; $index -lt $capturedFrames.Count; $index++) {
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($capturedFrames[$index]))
        $stream = [IO.File]::Create((Join-Path $previewDir ('{0:D3}.png' -f $index)))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    $captureLog | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $previewDir 'timing.json')
    Write-Output "PASS: recorded $previewCount frames from live WPF renderer."
    exit
}
$window.ShowDialog() | Out-Null
