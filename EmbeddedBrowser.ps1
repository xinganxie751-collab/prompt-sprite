function Initialize-WebView2 {
    if ('Microsoft.Web.WebView2.Wpf.WebView2' -as [type]) { return }
    $directory = Join-Path $PSScriptRoot 'webview2'
    $core = Join-Path $directory 'Microsoft.Web.WebView2.Core.dll'
    $wpf = Join-Path $directory 'Microsoft.Web.WebView2.Wpf.dll'
    if (!(Test-Path -LiteralPath $core) -or !(Test-Path -LiteralPath $wpf)) {
        throw '没有找到内置浏览器组件。请从完整的小精灵文件夹启动。'
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
        if (!$target) { $status.Text = '请粘贴网页地址，或包含链接的抖音分享文案。'; return }
        if ($view.CoreWebView2) { $view.CoreWebView2.Navigate($target.AbsoluteUri) }
    }.GetNewClosure()
    $go.Add_Click({ & $navigate }.GetNewClosure())
    $address.Add_KeyDown({
        param($sender,$event)
        if ($event.Key -eq 'Enter') { & $navigate; $event.Handled = $true }
    }.GetNewClosure())
    $back.Add_Click({ if ($view.CanGoBack) { $view.GoBack() } }.GetNewClosure())
    $reload.Add_Click({ if ($view.CoreWebView2) { $view.Reload() } }.GetNewClosure())
    $browser.FindName('Record').Add_Click({ & $Record }.GetNewClosure())
    $onStarting = {
        param($sender,$event)
        $uri = $null
        if (![Uri]::TryCreate($event.Uri,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo) {
            $event.Cancel = $true
            $status.Text = '该链接要求打开其他应用。可以直接在抖音里播放，再用小精灵录屏。'
            return
        }
        $status.Text = '正在打开网页…'
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
            $status.Text = '网页加载失败。请检查网络或尝试用抖音 App 播放。'
        }
    }.GetNewClosure()
    $view.Add_CoreWebView2InitializationCompleted({
        param($sender,$event)
        if (!$event.IsSuccess) {
            $status.Text = '内置浏览器启动失败。请确认已安装 Microsoft Edge WebView2 Runtime。'
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
    $browser.Add_Closed({ $state.Closed = $true; $view.Dispose() }.GetNewClosure())
    $address.Text = $InitialUri.AbsoluteUri
    Show-SpriteBrowser $browser
    $null = $view.EnsureCoreWebView2Async($null)
    $state
}
