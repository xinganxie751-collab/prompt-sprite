if (!(Get-Command Get-SpriteText -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Locale.ps1') }
function Initialize-WebView2 {
    if ('Microsoft.Web.WebView2.Wpf.WebView2' -as [type]) { return }
    $directory = Join-Path $PSScriptRoot 'webview2'
    $core = Join-Path $directory 'Microsoft.Web.WebView2.Core.dll'
    $wpf = Join-Path $directory 'Microsoft.Web.WebView2.Wpf.dll'
    if (!(Test-Path -LiteralPath $core) -or !(Test-Path -LiteralPath $wpf)) {
        throw (Get-SpriteText '没有找到内置浏览器组件。请从完整的小精灵文件夹启动。')
    }
    $env:Path = "$directory;$env:Path"
    $null = [Reflection.Assembly]::LoadFrom($core)
    $null = [Reflection.Assembly]::LoadFrom($wpf)
}

function Show-SpriteBrowser([Windows.Window]$Browser) {
    if ($Browser.WindowState -eq 'Minimized') { $Browser.WindowState = 'Normal' }
    if (!$Browser.IsVisible) { $Browser.Show() }
    $wasTopmost = $Browser.Topmost
    $Browser.Topmost = $true
    $null = $Browser.Activate()
    $Browser.Topmost = $wasTopmost
}

function ConvertTo-VideoScreenRegion($View,$Bounds) {
    if (!$Bounds -or $Bounds.vw -le 0 -or $Bounds.vh -le 0 -or $View.ActualWidth -le 0 -or $View.ActualHeight -le 0) { return }
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    $sx = $View.ActualWidth / $Bounds.vw
    $sy = $View.ActualHeight / $Bounds.vh
    $a = $View.PointToScreen([Windows.Point]::new($Bounds.x*$sx,$Bounds.y*$sy))
    $b = $View.PointToScreen([Windows.Point]::new(($Bounds.x+$Bounds.w)*$sx,($Bounds.y+$Bounds.h)*$sy))
    $rect = [Drawing.Rectangle]::FromLTRB([int][Math]::Ceiling($a.X),[int][Math]::Ceiling($a.Y),[int][Math]::Floor($b.X),[int][Math]::Floor($b.Y))
    if ($rect.Width -ge 120 -and $rect.Height -ge 90 -and [Windows.Forms.Screen]::FromRectangle($rect).Bounds.Contains($rect)) { $rect }
}

function New-SpriteBrowser([Windows.Window]$Owner, [scriptblock]$Record, [Uri]$InitialUri) {
    Initialize-WebView2
    [xml]$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="小精灵浏览器" Width="935" Height="735" MinWidth="560" MinHeight="380"
        WindowStartupLocation="CenterOwner" FontFamily="Microsoft YaHei UI, Segoe UI"
        Background="#FCFAFF" Foreground="#251E35" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#EFE7FA"/>
      <Setter Property="BorderBrush" Value="#E5D8F0"/>
      <Setter Property="Foreground" Value="#251E35"/>
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MinHeight" Value="34"/>
    </Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#F4EEFC" BorderBrush="#E9DFF1" BorderThickness="0,0,0,1" Padding="12,9">
      <DockPanel LastChildFill="True">
        <Button x:Name="Back" DockPanel.Dock="Left" Content="返回" IsEnabled="False" Margin="0,0,6,0"/>
        <Button x:Name="Reload" DockPanel.Dock="Left" Content="刷新" IsEnabled="False" Margin="0,0,8,0"/>
        <Button x:Name="Record" DockPanel.Dock="Right" Content="录屏" Background="#4F367D" Foreground="White" Margin="8,0,0,0"/>
        <Button x:Name="Go" DockPanel.Dock="Right" Content="打开" IsEnabled="False" Margin="6,0,0,0"/>
        <TextBox x:Name="Address" MinHeight="34" VerticalContentAlignment="Center" Padding="9,3"
                 Background="#FFFFFF" BorderBrush="#DDCFEA" AutomationProperties.Name="网页地址或抖音分享文案"/>
      </DockPanel>
    </Border>
    <TextBlock x:Name="Status" DockPanel.Dock="Bottom" Text="正在启动浏览器…" Foreground="#655D74"
               Margin="13,7" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
    <Grid x:Name="Surface" Background="#FFFFFF"/>
  </DockPanel>
</Window>
'@
    $reader = [Xml.XmlNodeReader]::new($layout)
    $browser = [Windows.Markup.XamlReader]::Load($reader)
    $browser.Owner = $Owner
    Set-SpriteLocalizedTree $browser
    $tr=New-SpriteTranslator
    $address = $browser.FindName('Address')
    $status = $browser.FindName('Status')
    $back = $browser.FindName('Back')
    $reload = $browser.FindName('Reload')
    $go = $browser.FindName('Go')
    $view = [Microsoft.Web.WebView2.Wpf.WebView2]::new()
    $view.CreationProperties = [Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties]::new()
    $view.CreationProperties.UserDataFolder = Join-Path $env:LOCALAPPDATA 'PromptSprite/WebView2'
    $null = $browser.FindName('Surface').Children.Add($view)
    $state = @{ Window = $browser; Address = $address; View = $view; Closed = $false }

    $parseUrl = {
        param([string]$Text)
        $match = [regex]::Match($Text,'https?://[^\s<>"“”‘’，。！；、｜]+','IgnoreCase')
        $uri = $null
        if ($match.Success -and [Uri]::TryCreate($match.Value.TrimEnd(')',']','}',',','.'), [UriKind]::Absolute, [ref]$uri) -and
            $uri.Scheme -in @('http','https') -and !$uri.UserInfo) { $uri }
    }
    $navigate = {
        $target = & $parseUrl $address.Text
        if (!$target) { $status.Text = & $tr '请粘贴网页地址，或包含链接的抖音分享文案。'; return }
        if ($view.CoreWebView2) { $view.CoreWebView2.Navigate($target.AbsoluteUri) }
    }.GetNewClosure()
    $go.Add_Click({ & $navigate }.GetNewClosure())
    $address.Add_KeyDown({
        param($sender,$event)
        if ($event.Key -eq 'Enter') { & $navigate; $event.Handled = $true }
    }.GetNewClosure())
    $back.Add_Click({ if ($view.CanGoBack) { $view.GoBack() } }.GetNewClosure())
    $reload.Add_Click({ if ($view.CoreWebView2) { $view.Reload() } }.GetNewClosure())
    $recordButton = $browser.FindName('Record')
    $regionConverter = ${function:ConvertTo-VideoScreenRegion}
    $probe = @'
(() => {
  const players = [];
  for (const video of document.querySelectorAll('video')) {
    const box = video.getBoundingClientRect();
    const style = getComputedStyle(video);
    if (!video.videoWidth || video.readyState < 2 || style.visibility !== 'visible' ||
        Number(style.opacity) === 0 || video.mediaKeys) continue;
    const x = Math.max(0, box.left), y = Math.max(0, box.top);
    const w = Math.min(innerWidth, box.right) - x, h = Math.min(innerHeight, box.bottom) - y;
    if (w < 160 || h < 90 || w * h < box.width * box.height * .85) continue;
    const top = document.elementFromPoint(x + w / 2, y + h / 2);
    const container = video.parentElement;
    if (!top || (top !== video && !(container && container.contains(top)))) continue;
    players.push({x, y, w, h, vw: innerWidth, vh: innerHeight, area: w * h});
  }
  players.sort((a,b) => b.area - a.area);
  return players.length && (players.length === 1 || players[0].area >= 1.4 * players[1].area) ? players[0] : null;
})()
'@
    $detection = @{ Task=$null; Deadline=$null; Source=$null }
    $probeTimer = [Windows.Threading.DispatcherTimer]::new()
    $probeTimer.Interval = [TimeSpan]::FromMilliseconds(85)
    $probeTimer.Add_Tick({
        if (!$detection.Task.IsCompleted -and [DateTime]::UtcNow -lt $detection.Deadline) { return }
        $probeTimer.Stop()
        try {
            $region = $null
            try {
                if ($detection.Task.Status -eq 'RanToCompletion' -and $detection.Source -eq $view.CoreWebView2.Source) {
                    $bounds = $detection.Task.Result | ConvertFrom-Json
                    $region = & $regionConverter $view $bounds
                }
            } catch { $region = $null }
            if ($region) {
                $status.Text = & $tr '已找到视频区域。'
                $choice = [Windows.MessageBox]::Show($browser,
                    (& $tr '录制检测到的视频区域？请让视频窗口保持可见。选择「否」可手动框选。'),
                    (& $tr '开始录制视频'),[Windows.MessageBoxButton]::YesNoCancel,[Windows.MessageBoxImage]::Question)
                if ($choice -eq 'Yes') { & $Record $region $browser }
                elseif ($choice -eq 'No') { & $Record $null $browser }
            } else {
                $status.Text = & $tr '没有找到清晰的视频区域，请手动框选。'
                & $Record $null $browser
            }
        } finally { $recordButton.IsEnabled = $true }
    }.GetNewClosure())
    $recordButton.Add_Click({
        if (!$view.CoreWebView2) { & $Record $null $browser; return }
        $recordButton.IsEnabled = $false
        $status.Text = & $tr '正在识别视频区域…'
        try {
            $detection.Source = $view.CoreWebView2.Source
            $detection.Task = $view.CoreWebView2.ExecuteScriptAsync($probe)
            $detection.Deadline = [DateTime]::UtcNow.AddSeconds(2)
            $probeTimer.Start()
        } catch {
            $recordButton.IsEnabled = $true
            & $Record $null $browser
        }
    }.GetNewClosure())
    $onStarting = {
        param($sender,$event)
        $uri = $null
        if (![Uri]::TryCreate($event.Uri,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo) {
            $event.Cancel = $true
            $status.Text = & $tr '该链接要求打开其他应用。可以直接在抖音里播放，再用小精灵录屏。'
            return
        }
        $status.Text = & $tr '正在打开网页…'
    }.GetNewClosure()
    $onNewWindow = {
        param($sender,$event)
        $event.Handled = $true
        $target = & $parseUrl $event.Uri
        if ($target) { $sender.Navigate($target.AbsoluteUri) }
    }.GetNewClosure()
    $onCompleted = {
        param($sender,$event)
        $back.IsEnabled = $view.CanGoBack
        if ($event.IsSuccess) {
            if ($sender.Source) { $address.Text = $sender.Source }
            $status.Text = ''
        } elseif ($event.WebErrorStatus -ne 'OperationCanceled') {
            $status.Text = & $tr '网页加载失败。请检查网络或尝试用抖音 App 播放。'
        }
    }.GetNewClosure()
    $view.Add_CoreWebView2InitializationCompleted({
        param($sender,$event)
        if (!$event.IsSuccess) {
            $status.Text = & $tr '内置浏览器启动失败。请确认已安装 Microsoft Edge WebView2 Runtime。'
            return
        }
        $go.IsEnabled = $true
        $reload.IsEnabled = $true
        $core = $view.CoreWebView2
        $core.Settings.IsWebMessageEnabled = $false
        $core.Settings.AreHostObjectsAllowed = $false
        $core.Add_NavigationStarting($onStarting)
        $core.Add_NewWindowRequested($onNewWindow)
        $core.Add_NavigationCompleted($onCompleted)
        & $navigate
    }.GetNewClosure())
    $browser.Add_Closed({ $probeTimer.Stop(); $state.Closed = $true; $view.Dispose() }.GetNewClosure())
    $address.Text = $InitialUri.AbsoluteUri
    Show-SpriteBrowser $browser
    $null = $view.EnsureCoreWebView2Async($null)
    $state
}
