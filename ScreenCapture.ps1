Add-Type -AssemblyName System.Drawing, System.Windows.Forms

function Select-VideoRegion([Windows.Window]$Widget) {
    [xml]$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="选择录屏范围" WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False"
        Topmost="True" AllowsTransparency="True" Background="Transparent" Cursor="Cross"
        FontFamily="Microsoft YaHei UI">
  <Grid x:Name="Surface" Background="#330F0821">
    <Canvas IsHitTestVisible="False">
      <Border x:Name="Outline" BorderBrush="#E4CAFF" BorderThickness="2" Background="#15C5A0FF"
              Visibility="Collapsed"/>
    </Canvas>
    <Border Background="#302342" CornerRadius="13" Padding="17,11" Margin="0,22,0,0"
            HorizontalAlignment="Center" VerticalAlignment="Top" IsHitTestVisible="False">
      <StackPanel>
        <TextBlock Text="拖出一个框，圈住要录制的视频区域" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
        <TextBlock Text="松开后开始录屏 · Ctrl + Shift + F10 停止 · 最长 30 秒" Foreground="#E3D4F4" FontSize="12" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
    $reader = [Xml.XmlNodeReader]::new($layout)
    $overlay = [Windows.Markup.XamlReader]::Load($reader)
    $surface = $overlay.FindName('Surface')
    $outline = $overlay.FindName('Outline')
    $state = @{ Start = $null; Region = $null }
    $overlay.WindowStartupLocation = 'Manual'
    $overlay.Left = $Widget.Left
    $overlay.Top = $Widget.Top
    $overlay.WindowState = 'Maximized'
    $overlay.Add_PreviewKeyDown({
        param($sender,$event)
        if ($event.Key -eq 'Escape') { $overlay.DialogResult = $false }
    }.GetNewClosure())
    $surface.Add_MouseLeftButtonDown({
        param($sender,$event)
        $state.Start = $event.GetPosition($surface)
        $outline.Visibility = 'Visible'
        [Windows.Controls.Canvas]::SetLeft($outline, $state.Start.X)
        [Windows.Controls.Canvas]::SetTop($outline, $state.Start.Y)
        $outline.Width = 0
        $outline.Height = 0
        $null = $surface.CaptureMouse()
    }.GetNewClosure())
    $surface.Add_MouseMove({
        param($sender,$event)
        if ($null -eq $state.Start -or $event.LeftButton -ne 'Pressed') { return }
        $position = $event.GetPosition($surface)
        $x = [Math]::Max(0,[Math]::Min($surface.ActualWidth,$position.X))
        $y = [Math]::Max(0,[Math]::Min($surface.ActualHeight,$position.Y))
        [Windows.Controls.Canvas]::SetLeft($outline, [Math]::Min($x,$state.Start.X))
        [Windows.Controls.Canvas]::SetTop($outline, [Math]::Min($y,$state.Start.Y))
        $outline.Width = [Math]::Abs($x - $state.Start.X)
        $outline.Height = [Math]::Abs($y - $state.Start.Y)
    }.GetNewClosure())
    $surface.Add_MouseLeftButtonUp({
        $surface.ReleaseMouseCapture()
        $state.Start = $null
        if ($outline.Width -lt 60 -or $outline.Height -lt 60) { $outline.Visibility = 'Collapsed'; return }
        $x = [Windows.Controls.Canvas]::GetLeft($outline)
        $y = [Windows.Controls.Canvas]::GetTop($outline)
        $topLeft = $surface.PointToScreen([Windows.Point]::new($x,$y))
        $bottomRight = $surface.PointToScreen([Windows.Point]::new($x + $outline.Width,$y + $outline.Height))
        $state.Region = [Drawing.Rectangle]::FromLTRB(
            [int][Math]::Ceiling($topLeft.X), [int][Math]::Ceiling($topLeft.Y),
            [int][Math]::Floor($bottomRight.X), [int][Math]::Floor($bottomRight.Y))
        $overlay.DialogResult = $true
    }.GetNewClosure())
    if ($overlay.ShowDialog()) { return $state.Region }
}

function Initialize-RegionRecorder {
    if (!('PromptSprite.RegionRecorder' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'RegionRecorder.cs') -ReferencedAssemblies 'System.Drawing'
    }
}

function Record-VideoRegion([Windows.Window]$Widget,[Drawing.Rectangle]$Region,[string]$Path) {
    Initialize-RegionRecorder
    $helper = [Windows.Interop.WindowInteropHelper]::new($Widget)
    $source = [Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
    $loop = [Windows.Threading.DispatcherFrame]::new()
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(83)
    $state = @{ Error = $null }
    $clock = [Diagnostics.Stopwatch]::new()
    $dock = [Windows.Window]::new()
    $dock.Title = '小精灵正在录屏'
    $dock.Width = 184; $dock.Height = 44
    $dock.WindowStyle = 'None'; $dock.ResizeMode = 'NoResize'
    $dock.Topmost = $true; $dock.ShowInTaskbar = $false; $dock.ShowActivated = $false
    $dock.WindowStartupLocation = 'Manual'
    $dock.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#302342')
    $stop = [Windows.Controls.Button]::new()
    $stop.Content = '停止录制'
    $stop.Foreground = [Windows.Media.Brushes]::White
    $stop.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#4F367D')
    $stop.FontSize = 13
    $stop.ToolTip = 'Ctrl + Shift + F10'
    $dock.Content = $stop
    $stop.Add_Click({ $loop.Continue = $false }.GetNewClosure())
    $dock.Add_Closed({ $loop.Continue = $false }.GetNewClosure())

    $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($Widget)
    $area = [Windows.Forms.Screen]::FromRectangle($Region).WorkingArea
    $width = [int][Math]::Ceiling($dock.Width*$dpi.DpiScaleX)
    $height = [int][Math]::Ceiling($dock.Height*$dpi.DpiScaleY)
    $left = [Math]::Max($area.Left,[Math]::Min($Region.Left,$area.Right-$width))
    $top = [Math]::Max($area.Top,[Math]::Min($Region.Top,$area.Bottom-$height))
    $candidates = @(
        [Drawing.Rectangle]::new($left,$Region.Top-$height-6,$width,$height)
        [Drawing.Rectangle]::new($left,$Region.Bottom+6,$width,$height)
        [Drawing.Rectangle]::new(($Region.Left-$width-6),$top,$width,$height)
        [Drawing.Rectangle]::new(($Region.Right+6),$top,$width,$height)
    )
    $position = $candidates | Where-Object { $area.Contains($_) } | Select-Object -First 1
    if ($position) {
        $origin = $Widget.PointToScreen([Windows.Point]::new(0,0))
        $dock.Left = $Widget.Left + ($position.X-$origin.X)/$dpi.DpiScaleX
        $dock.Top = $Widget.Top + ($position.Y-$origin.Y)/$dpi.DpiScaleY
    }

    $hotkeyId = 0x4A63
    $hook = [Windows.Interop.HwndSourceHook]({
        param($handle,$message,$wParam,$lParam,[ref]$handled)
        if ($message -eq 0x0312 -and $wParam.ToInt32() -eq $hotkeyId) {
            $loop.Continue = $false
            $handled.Value = $true
        }
        [IntPtr]::Zero
    }.GetNewClosure())
    $source.AddHook($hook)
    $registered = [PromptSprite.RegionRecorder]::RegisterHotKey($helper.Handle,$hotkeyId,0x4006,0x79)
    $recorder = $null
    try {
        if (!$position -and !$registered) { throw '停止快捷键被占用。请缩小选区，给停止按钮留出空间。' }
        if ($position) { $dock.Show() }
        $recorder = [PromptSprite.RegionRecorder]::new($Path,$Region,12)
        $timer.Add_Tick({
            try {
                $ms = $clock.ElapsedMilliseconds
                if ($ms -ge 30500) { $loop.Continue = $false; return }
                if ($ms -lt 500) { return }
                $recorder.Capture()
                $stop.Content = '停止录制 · {0:00}s' -f [Math]::Floor(($ms-500)/1000)
            } catch {
                $state.Error = $_.Exception
                $loop.Continue = $false
            }
        }.GetNewClosure())
        $clock.Start()
        $timer.Start()
        [Windows.Threading.Dispatcher]::PushFrame($loop)
        if ($state.Error) { throw $state.Error }
        if ($recorder.FrameCount -lt 4) { throw '录制时间太短，请播放视频后再录一段。' }
        if (!$recorder.HasVisibleContent) { throw '录屏没有可见画面，请确认视频正在播放。' }
        @{ Frames = $recorder.FrameCount; Seconds = [Math]::Round($recorder.FrameCount / 12, 1) }
    } finally {
        $timer.Stop()
        if ($registered) { $null = [PromptSprite.RegionRecorder]::UnregisterHotKey($helper.Handle,$hotkeyId) }
        $source.RemoveHook($hook)
        if ($dock.IsVisible) { $dock.Close() }
        if ($recorder) { $recorder.Dispose() }
    }
}