param([switch]$SmokeTest, [switch]$StartExpanded)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$markup = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PromptSprite.xaml'))
$reader = [Xml.XmlNodeReader]::new($markup)
$window = [Windows.Markup.XamlReader]::Load($reader)
$controls = @{}
foreach ($name in 'Shell','SpriteBody','DockTab','Handle','Heading','Mascot','PetScale','PetTilt','EyeLids','Badge','CompactName','Caption','Details','DropSurface','Settings','Browser','Collapse','Quit','Source','Input','Mode','Generate','Browse','CaptureRegion','Status','LinkFallback','OpenSource','PasteImage','Recovery','FixLogin','Retry','ResultType','Output','Copy') {
    $controls[$name] = $window.FindName($name)
}

$script:files = @()
$script:clipboardImage = $null
$script:screenRecording = $null
$script:spriteBrowser = $null
$script:job = $null
$script:dragStart = $null
$script:expanded = $false
$script:dockSide = ''
$script:recordingOrPicking = $false
$script:lastSpriteUse = [DateTime]::UtcNow
$expandedWidth = 420
$compactWidth = $controls.Shell.Width
$window.WindowStartupLocation = 'Manual'
$window.Left = [Windows.SystemParameters]::WorkArea.Right - 130
$window.Top = [Windows.SystemParameters]::WorkArea.Top + 95

function Reset-SpriteIdle { $script:lastSpriteUse = [DateTime]::UtcNow }

function Get-SpriteScreen {
    Add-Type -AssemblyName System.Windows.Forms
    $point = $window.PointToScreen([Windows.Point]::new(0,0))
    $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($window)
    $middle = [Drawing.Point]::new([int]($point.X+$window.ActualWidth*$dpi.DpiScaleX/2),
        [int]($point.Y+$window.ActualHeight*$dpi.DpiScaleY/2))
    @{ Point=$point; Dpi=$dpi; Middle=$middle; Area=[Windows.Forms.Screen]::FromPoint($middle).WorkingArea }
}

function Move-SpriteToEdge($Screen,[string]$Side,[double]$Width,[double]$Height) {
    $area = $Screen.Area
    $x = if ($Side -eq 'left') { $area.Left } else { $area.Right-$Width*$Screen.Dpi.DpiScaleX }
    $y = [Math]::Max([double]$area.Top,[Math]::Min([double]$Screen.Point.Y,$area.Bottom-$Height*$Screen.Dpi.DpiScaleY))
    $window.Left += ($x-$Screen.Point.X)/$Screen.Dpi.DpiScaleX
    $window.Top += ($y-$Screen.Point.Y)/$Screen.Dpi.DpiScaleY
}

function Show-DockedSprite {
    if (!$script:dockSide) { return }
    $side = $script:dockSide
    $screen = Get-SpriteScreen
    $script:dockSide = ''
    $controls.DockTab.Visibility = 'Collapsed'
    $controls.SpriteBody.Visibility = 'Visible'
    $controls.Shell.CornerRadius = [Windows.CornerRadius]::new(27)
    $controls.Shell.Width = $compactWidth
    Move-SpriteToEdge $screen $side $compactWidth 126
    Reset-SpriteIdle
}

function Set-Expanded([bool]$Expanded) {
    Show-DockedSprite
    Reset-SpriteIdle
    $script:expanded = $Expanded
    $controls.Details.Visibility = if ($Expanded) { 'Visible' } else { 'Collapsed' }
    $controls.Caption.Visibility = if ($Expanded) { 'Collapsed' } else { 'Visible' }
    $controls.CompactName.Visibility = $controls.Caption.Visibility
    $controls.Heading.Visibility = if ($Expanded) { 'Visible' } else { 'Collapsed' }
    $controls.Mascot.HorizontalAlignment = if ($Expanded) { 'Right' } else { 'Center' }
    $controls.Mascot.VerticalAlignment = if ($Expanded) { 'Center' } else { 'Top' }
    $controls.Mascot.Margin = if ($Expanded) { [Windows.Thickness]::new(0,0,17,0) } else { [Windows.Thickness]::new(0,3,0,0) }
    $controls.Handle.Height = if ($Expanded) { 102 } else { 124 }
    $controls.Shell.Width = if ($Expanded) { $expandedWidth } else { $compactWidth }
    if ($Expanded -and $window.IsLoaded) {
        Add-Type -AssemblyName System.Windows.Forms
        $point = $window.PointToScreen([Windows.Point]::new(0, 0))
        $area = [Windows.Forms.Screen]::FromPoint([Drawing.Point]::new([int]$point.X, [int]$point.Y)).WorkingArea
        $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($window)
        $controls.Shell.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $window.Left -= [Math]::Max(0, ($point.X + $expandedWidth * $dpi.DpiScaleX - $area.Right) / $dpi.DpiScaleX)
        $window.Top -= [Math]::Max(0, ($point.Y + $controls.Shell.DesiredSize.Height * $dpi.DpiScaleY - $area.Bottom) / $dpi.DpiScaleY)
    }
}

function Set-SpriteDocked {
    if ($script:dockSide -or !$window.IsLoaded) { return }
    $screen = Get-SpriteScreen
    $side = if ($screen.Middle.X - $screen.Area.Left -lt $screen.Area.Right - $screen.Middle.X) { 'left' } else { 'right' }
    Set-Expanded $false
    $script:dockSide = $side
    $controls.SpriteBody.Visibility = 'Collapsed'
    $controls.DockTab.Visibility = 'Visible'
    $controls.Shell.Width = 19
    $controls.Shell.CornerRadius = if ($side -eq 'left') { [Windows.CornerRadius]::new(0,11,11,0) }
                                  else { [Windows.CornerRadius]::new(11,0,0,11) }
    Move-SpriteToEdge $screen $side 19 60
}

$dockTimer = [Windows.Threading.DispatcherTimer]::new()
$dockTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$dockTimer.Add_Tick({
    if ($script:dockSide -or !$window.IsVisible -or $window.Opacity -lt 1) { return }
    if ($window.IsMouseOver -or $script:dragStart -or $script:job -or $script:recordingOrPicking -or
        $controls.Mode.IsDropDownOpen) {
        Reset-SpriteIdle
        return
    }
    $seconds = ([DateTime]::UtcNow-$script:lastSpriteUse).TotalSeconds
    $delay = if ($window.IsActive -and $controls.Input.IsKeyboardFocused) { 9 } else { 4 }
    if ($seconds -ge $delay) { Set-SpriteDocked }
})
$window.Add_Loaded({ Reset-SpriteIdle; $dockTimer.Start() })
$window.Add_PreviewKeyDown({ Reset-SpriteIdle })
$controls.DockTab.Add_MouseEnter({ Show-DockedSprite })
$controls.DockTab.Add_Click({ Set-Expanded $true })

function Open-CodexLogin {
    try {
        . (Join-Path $PSScriptRoot 'Media.ps1')
        $exe = Get-CodexExecutable
        $state = Invoke-CodexProcess $exe 'login status'
        if ($state.Code -eq 0 -and ($state.Output + $state.Error) -match '(?i)logged in using chatgpt') {
            $controls.Status.Text = 'Codex 已登录，可以用当前素材继续生成。'
            return
        }
        $null = Start-Process -FilePath $exe -ArgumentList 'login' -WindowStyle Normal -PassThru
        $controls.Status.Text = if ($controls.Recovery.Visibility -eq 'Visible') {
            '请在浏览器用 ChatGPT 账号登录，完成后点「用原素材重试」。'
        } else { '请在浏览器用 ChatGPT 账号登录，完成后回这里生成提示词。' }
    } catch {
        $controls.Status.Text = $_.Exception.GetBaseException().Message
    }
}

function Open-EmbeddedReference {
    try {
        . (Join-Path $PSScriptRoot 'Media.ps1')
        . (Join-Path $PSScriptRoot 'EmbeddedBrowser.ps1')
        $uri = Get-ReferenceLinks $controls.Input.Text |
            Where-Object { $_.Scheme -in @('http','https') -and !$_.UserInfo } | Select-Object -First 1
        if ($script:spriteBrowser -and !$script:spriteBrowser.Closed) {
            Show-SpriteBrowser $script:spriteBrowser.Window
            if ($uri) {
                $script:spriteBrowser.Address.Text = $uri.AbsoluteUri
                if ($script:spriteBrowser.View.CoreWebView2) {
                    $script:spriteBrowser.View.CoreWebView2.Navigate($uri.AbsoluteUri)
                }
            }
            $controls.Status.Text = '内置浏览器已打开。'
            return
        }
        if (!$uri) { $uri = [Uri]'https://www.douyin.com/' }
        $record = ${function:Start-RegionRecording}
        $script:spriteBrowser = New-SpriteBrowser $window $record $uri
        $controls.Status.Text = '内置浏览器已打开。'
    } catch {
        $controls.Status.Text = $_.Exception.GetBaseException().Message
    }
}

function Set-Files([string[]]$Paths) {
    $script:files = @($Paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 5)
    if ($script:clipboardImage -and $script:clipboardImage -notin $script:files) {
        Remove-Item -LiteralPath $script:clipboardImage -ErrorAction SilentlyContinue
        $script:clipboardImage = $null
    }
    if ($script:screenRecording -and $script:screenRecording -notin $script:files) {
        Remove-Item -LiteralPath $script:screenRecording -ErrorAction SilentlyContinue
        $script:screenRecording = $null
    }
    $controls.Source.Text = if ($script:files.Count) {
        ($script:files | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ' · '
    } else { '拖入图片、视频或文本' }
}

function Start-Generation {
    if ($script:job) { return }
    Set-Expanded $true
    $text = $controls.Input.Text.Trim()
    if (!$script:files.Count -and !$text) { $controls.Status.Text = '先拖入素材，或粘贴链接。'; return }
    $controls.Status.Text = '正在读取素材并生成提示词…'
    $controls.LinkFallback.Visibility = 'Collapsed'
    $controls.Recovery.Visibility = 'Collapsed'
    $controls.Caption.Text = '生成中…'
    $controls.Badge.Visibility = 'Visible'
    $controls.Generate.IsEnabled = $false
    $controls.Browse.IsEnabled = $false
    $controls.CaptureRegion.IsEnabled = $false
    $controls.Input.IsEnabled = $false
    $controls.Mode.IsEnabled = $false
    $controls.Output.Clear()
    $controls.ResultType.Text = ''
    $controls.Copy.IsEnabled = $false
    $worker = [PowerShell]::Create()
    $runspace = [RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $worker.Runspace = $runspace
    $work = {
        param($ModulePath, $Files, $Text, $Mode)
        $ErrorActionPreference = 'Stop'
        . $ModulePath
        try { Invoke-PromptRequest $Files $Text $Mode }
        catch {
            $failure = $_.Exception.GetBaseException()
            @{ Error=$failure.Message; Action=[string]$failure.Data['PromptSpriteAction'] }
        }
    }
    $mode = $controls.Mode.SelectedItem.Content
    $null = $worker.AddScript($work).AddArgument((Join-Path $PSScriptRoot 'Media.ps1')).AddArgument([string[]]$script:files).AddArgument($text).AddArgument($mode)
    $script:job = @{ Worker = $worker; Runspace = $runspace; Result = $worker.BeginInvoke() }
    $poll.Start()
}

function Show-GenerationFailure([string]$Message,[string]$Action) {
    $controls.Status.Text = $Message
    $controls.Caption.Text = '可重试'
    $controls.FixLogin.Visibility = if ($Action -eq 'login') { 'Visible' } else { 'Collapsed' }
    $controls.LinkFallback.Visibility = if ($Action -eq 'browser') { 'Visible' } else { 'Collapsed' }
    $controls.Recovery.Visibility = if ($Action -eq 'browser') { 'Collapsed' } else { 'Visible' }
}

$poll = [Windows.Threading.DispatcherTimer]::new()
$poll.Interval = [TimeSpan]::FromMilliseconds(160)
$poll.Add_Tick({
    if (!$script:job.Result.IsCompleted) { return }
    $poll.Stop()
    try {
        $answer = $script:job.Worker.EndInvoke($script:job.Result) | Select-Object -Last 1
        if (!$answer -or (!$answer.Error -and !$answer.Prompt)) { throw '没有收到提示词。可以用原素材重试。' }
        if ($answer.Error) {
            Show-GenerationFailure $answer.Error $answer.Action
        } else {
            $controls.Output.Text = $answer.Prompt
            $controls.ResultType.Text = $answer.Type
            $controls.Copy.IsEnabled = [bool]$answer.Prompt
            $controls.Status.Text = '素材已保留。可切换类型后重新生成。'
            $controls.Caption.Text = '已生成'
        }
    } catch {
        Show-GenerationFailure $_.Exception.GetBaseException().Message ''
    } finally {
        $script:job.Worker.Dispose()
        $script:job.Runspace.Dispose()
        $script:job = $null
        $controls.Badge.Visibility = 'Collapsed'
        $controls.Generate.IsEnabled = $true
        $controls.Browse.IsEnabled = $true
        $controls.CaptureRegion.IsEnabled = $true
        $controls.Input.IsEnabled = $true
        $controls.Mode.IsEnabled = $true
    }
})

function Invoke-SpriteEase($Target,$Property,[double]$From,[double]$To,[int]$Milliseconds) {
    if (![Windows.SystemParameters]::ClientAreaAnimation) {
        $Target.SetValue($Property,$To)
        return
    }
    $animation = [Windows.Media.Animation.DoubleAnimation]::new($From,$To,[Windows.Duration]::new([TimeSpan]::FromMilliseconds($Milliseconds)))
    $animation.EasingFunction = [Windows.Media.Animation.QuadraticEase]::new()
    $animation.EasingFunction.EasingMode = 'EaseOut'
    $Target.SetValue($Property,$To)
    $animation.FillBehavior = 'Stop'
    $Target.BeginAnimation($Property,$animation)
}

function Invoke-SpriteBlink($Scale) {
    if (![Windows.SystemParameters]::ClientAreaAnimation) { return }
    $blink = [Windows.Media.Animation.DoubleAnimation]::new(1,.16,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(78)))
    $blink.AutoReverse = $true
    $blink.FillBehavior = 'Stop'
    $Scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$blink)
}

function Reset-PetMotion {
    Invoke-SpriteEase $controls.PetTilt ([Windows.Media.RotateTransform]::AngleProperty) $controls.PetTilt.Angle 0 230
    Invoke-SpriteEase $controls.PetScale ([Windows.Media.ScaleTransform]::ScaleXProperty) $controls.PetScale.ScaleX 1 210
    Invoke-SpriteEase $controls.PetScale ([Windows.Media.ScaleTransform]::ScaleYProperty) $controls.PetScale.ScaleY 1 210
}
$controls.Handle.Add_MouseLeftButtonDown({
    param($sender,$event)
    $position = $window.PointToScreen($event.GetPosition($window))
    $script:dragStart = @{ Pos=$position; Left=$window.Left; Top=$window.Top; Dpi=[Windows.Media.VisualTreeHelper]::GetDpi($window); Dragging=$false; LastX=$position.X }
    $null = $sender.CaptureMouse()
})
$controls.Handle.Add_MouseMove({
    param($sender,$event)
    if ($null -eq $script:dragStart -or $event.LeftButton -ne 'Pressed') { return }
    $position = $window.PointToScreen($event.GetPosition($window))
    $dx = ($position.X-$script:dragStart.Pos.X)/$script:dragStart.Dpi.DpiScaleX
    $dy = ($position.Y-$script:dragStart.Pos.Y)/$script:dragStart.Dpi.DpiScaleY
    if (!$script:dragStart.Dragging -and [Math]::Sqrt($dx*$dx+$dy*$dy) -lt 5) { return }
    $script:dragStart.Dragging = $true
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $controls.PetScale.ScaleX = 1.04
        $controls.PetScale.ScaleY = 1.06
        $angle = [Math]::Max(-11.0,[Math]::Min(11.0,($position.X-$script:dragStart.LastX)*.36))
        $controls.PetTilt.Angle = $controls.PetTilt.Angle*.55+$angle*.45
    }
    $script:dragStart.LastX = $position.X
    $window.Left = $script:dragStart.Left+$dx
    $window.Top = $script:dragStart.Top+$dy
})
$controls.Handle.Add_MouseLeftButtonUp({
    param($sender,$event)
    if ($null -eq $script:dragStart) { return }
    $wasDragging = $script:dragStart.Dragging
    $script:dragStart = $null
    $sender.ReleaseMouseCapture()
    Reset-PetMotion
    if (!$wasDragging) {
        Set-Expanded (!$script:expanded)
        Invoke-SpriteBlink $controls.EyeLids
    }
})
$controls.Handle.Add_LostMouseCapture({
    if ($null -eq $script:dragStart) { return }
    $script:dragStart = $null
    Reset-PetMotion
})
$controls.Handle.Add_MouseLeave({ if (!$script:dragStart) { Reset-PetMotion } })
$blinkTimer = [Windows.Threading.DispatcherTimer]::new()
$blinkTimer.Interval = [TimeSpan]::FromMilliseconds(3400)
$blinkTimer.Add_Tick({
    if ($window.IsVisible -and !$script:dragStart -and $window.Opacity -gt 0) {
        Invoke-SpriteBlink $controls.EyeLids
    }
    $blinkTimer.Interval = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 2900 -Maximum 4900))
})
$window.Add_Loaded({ $blinkTimer.Start() })
$controls.Handle.Add_KeyDown({
    param($sender, $event)
    if ($event.Key -in 'Enter','Space') {
        Set-Expanded (!$script:expanded)
        $event.Handled = $true
    }
})
$dropBorder = $controls.DropSurface.BorderBrush
$shellBorder = $controls.Shell.BorderBrush
$dropHighlight = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(164, 126, 222))

function Clear-DropHighlight {
    $controls.DropSurface.BorderBrush = $dropBorder
    $controls.Shell.BorderBrush = $shellBorder
}

$window.Add_PreviewDragLeave({ Clear-DropHighlight })
$window.Add_PreviewDragOver({
    param($sender, $event)
    $valid = $event.Data.GetDataPresent([Windows.DataFormats]::FileDrop) -or $event.Data.GetDataPresent([Windows.DataFormats]::UnicodeText)
    $canDrop = $valid -and !$script:job
    $event.Effects = if ($canDrop) { 'Copy' } else { 'None' }
    if ($canDrop) {
        Reset-SpriteIdle
        $controls.DropSurface.BorderBrush = $dropHighlight
        $controls.Shell.BorderBrush = $dropHighlight
    } else { Clear-DropHighlight }
    $event.Handled = $true
})
$window.Add_PreviewDrop({
    param($sender, $event)
    Clear-DropHighlight
    $event.Handled = $true
    if ($script:job) { return }
    if ($event.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        Set-Files $event.Data.GetData([Windows.DataFormats]::FileDrop)
        $controls.Input.Clear()
    } elseif ($event.Data.GetDataPresent([Windows.DataFormats]::UnicodeText)) {
        Set-Files @()
        $controls.Input.Text = [string]$event.Data.GetData([Windows.DataFormats]::UnicodeText)
    } else { return }
    Start-Generation
})
$controls.Settings.Add_Click({ Open-CodexLogin })
$controls.FixLogin.Add_Click({ Open-CodexLogin })
$controls.Retry.Add_Click({ Start-Generation })
$controls.Browser.Add_Click({ Open-EmbeddedReference })
$controls.OpenSource.Add_Click({ Open-EmbeddedReference })
$controls.PasteImage.Add_Click({
    if ($script:job) { return }
    $path = Join-Path ([IO.Path]::GetTempPath()) ('prompt-sprite-clip-' + [Guid]::NewGuid().ToString('N') + '.png')
    try {
        $image = [Windows.Clipboard]::GetImage()
        if (!$image) { $controls.Status.Text = '剪贴板没有图片。先按 Win + Shift + S 截取视频画面，再点「粘贴截图」。'; return }
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
        $stream = [IO.File]::Create($path)
        try { $encoder.Save($stream) }
        finally { $stream.Dispose() }
        Set-Files @($path)
        $script:clipboardImage = $path
        Start-Generation
    } catch {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        $controls.Status.Text = '无法粘贴这张截图。可以保存为 PNG 后拖入小精灵。'
    }
})
function Start-RegionRecording($Region,$Anchor = $window) {
    if ($script:job) { return }
    $script:recordingOrPicking = $true
    $path = Join-Path ([IO.Path]::GetTempPath()) ('prompt-sprite-recording-' + [Guid]::NewGuid().ToString('N') + '.avi')
    try {
        . (Join-Path $PSScriptRoot 'ScreenCapture.ps1')
        Initialize-RegionRecorder
        $window.Opacity = 0
        $window.IsHitTestVisible = $false
        if (!$region) { $region = Select-VideoRegion $Anchor }
        if (!$region) { return }
        $recording = Record-VideoRegion $Anchor $region $path
        Set-Files @($path)
        $script:screenRecording = $path
        $controls.Source.Text = "区域录屏 · $($recording.Seconds) 秒"
    } catch {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        $controls.Status.Text = $_.Exception.GetBaseException().Message
        return
    } finally {
        $script:recordingOrPicking = $false
        Reset-SpriteIdle
        $window.Opacity = 1
        $window.IsHitTestVisible = $true
        $null = $window.Activate()
    }
    Start-Generation
}
$controls.CaptureRegion.Add_Click({ Start-RegionRecording $null $window })
$controls.Collapse.Add_Click({ Set-Expanded $false })
$controls.Quit.Add_Click({ $window.Close() })
$controls.Generate.Add_Click({ Start-Generation })
$controls.Input.Add_KeyDown({ param($sender,$event) if ($event.Key -eq 'Enter') { Start-Generation } })
$controls.Copy.Add_Click({
    try { [Windows.Clipboard]::SetText($controls.Output.Text); $controls.Status.Text = '已复制到剪贴板' }
    catch { $controls.Status.Text = '剪贴板暂时不可用，可选中文本并手动复制。' }
})
$controls.Browse.Add_Click({
    $picker = [Microsoft.Win32.OpenFileDialog]::new()
    $picker.Multiselect = $true
    $picker.Filter = '参考素材|*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp;*.mp4;*.mov;*.m4v;*.avi;*.wmv;*.webm;*.mkv;*.txt;*.md;*.html;*.svg|所有文件|*.*'
    $script:recordingOrPicking = $true
    try {
        if ($picker.ShowDialog($window)) { Set-Files $picker.FileNames; $controls.Input.Clear(); Start-Generation }
    } finally {
        $script:recordingOrPicking = $false
        Reset-SpriteIdle
    }
})
$window.Add_Closed({
    $dockTimer.Stop()
    $poll.Stop()
    if ($script:job) {
        $script:job.Worker.Dispose()
        $script:job.Runspace.Dispose()
    }
    if ($script:clipboardImage) { Remove-Item -LiteralPath $script:clipboardImage -ErrorAction SilentlyContinue }
    if ($script:screenRecording) { Remove-Item -LiteralPath $script:screenRecording -ErrorAction SilentlyContinue }
})

if ($SmokeTest) {
    if (!$window.Topmost -or !$window.AllowDrop -or $window.ShowInTaskbar -or $controls.Details.Visibility -ne 'Collapsed') { throw 'Widget startup configuration failed' }
    Set-Expanded $true
    if ($controls.Shell.Width -ne $expandedWidth -or $controls.Details.Visibility -ne 'Visible') { throw 'Widget expansion failed' }
    Set-Expanded $false
    Write-Output 'Widget XAML, topmost, drop target and expand/collapse verified'
} else {
    if ($StartExpanded) { $window.Add_Loaded({ Set-Expanded $true }) }
    $null = $window.ShowDialog()
}
