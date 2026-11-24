$script:providerPath = Join-Path $env:LOCALAPPDATA 'PromptSprite/providers.json'

function Read-SpriteProviders([string]$Path=$script:providerPath) {
    $settings = @{ Provider='codex'; Language='en-US'; DoubaoModel=''; DoubaoKey=''; DeepSeekKey='' }
    if (![IO.File]::Exists($Path)) { return $settings }
    try {
        $stored = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($stored.Provider -in 'codex','doubao','deepseek','manual') { $settings.Provider = [string]$stored.Provider }
        if ($stored.Language -and $script:spriteLanguageNames.Contains([string]$stored.Language)) { $settings.Language = [string]$stored.Language }
        foreach ($field in 'DoubaoModel','DoubaoKey','DeepSeekKey') { $settings[$field] = [string]$stored.$field }
    } catch { return @{ Provider='codex'; Language='en-US'; DoubaoModel=''; DoubaoKey=''; DeepSeekKey='' } }
    $settings
}

function Save-SpriteProviders([hashtable]$Settings,[string]$Path=$script:providerPath) {
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $tmp = $Path + '.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($tmp,($Settings | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp,$Path,$tmp+'.bak') }
        else { [IO.File]::Move($tmp,$Path) }
    } finally {
        foreach ($file in $tmp,($tmp+'.bak')) { if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) } }
    }
}

function Edit-SpriteProviders([Windows.Window]$Owner,[hashtable]$Settings) {
    [xml]$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="模型来源" Width="425" SizeToContent="Height" ResizeMode="NoResize" Topmost="True"
        ShowInTaskbar="False" WindowStartupLocation="CenterOwner" Background="#FCFAFF"
        Foreground="#261C34" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="13">
  <StackPanel Margin="18">
    <TextBlock Text="模型来源" FontSize="22" FontWeight="Bold" Margin="0,0,0,10"/>
    <ComboBox x:Name="Provider" Height="34" AutomationProperties.Name="选择模型来源">
      <ComboBoxItem Tag="codex" Content="Codex · ChatGPT 登录"/>
      <ComboBoxItem Tag="doubao" Content="豆包 · 火山方舟 API"/>
      <ComboBoxItem Tag="deepseek" Content="DeepSeek · API"/>
      <ComboBoxItem Tag="manual" Content="手动 · 导出素材和指令"/>
    </ComboBox>
    <TextBlock Text="界面与输出语言 / Language" Margin="0,11,0,4"/>
    <ComboBox x:Name="Language" Height="34" AutomationProperties.Name="选择语言"/>
    <TextBlock x:Name="Help" TextWrapping="Wrap" Foreground="#665473" Margin="0,10,0,3"/>
    <StackPanel x:Name="ApiInputs" Visibility="Collapsed">
      <StackPanel x:Name="ModelRow" Margin="0,7,0,0">
        <TextBlock Text="视觉模型 ID 或推理接入点" Margin="0,0,0,4"/>
        <TextBox x:Name="Model" Height="34" Padding="7,5" AutomationProperties.Name="豆包视觉模型 ID"/>
      </StackPanel>
      <TextBlock Text="API 密钥" Margin="0,9,0,4"/>
      <PasswordBox x:Name="Key" Height="34" Padding="7,5" AutomationProperties.Name="API 密钥"/>
      <CheckBox x:Name="Forget" Content="删除此服务已保存的密钥" Margin="0,7,0,0"/>
    </StackPanel>
    <Button x:Name="Login" Content="登录 Codex" HorizontalAlignment="Left" Padding="10,6" Margin="0,8,0,0"/>
    <TextBlock x:Name="Status" TextWrapping="Wrap" Foreground="#824363" Margin="0,7,0,0"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,11,0,0">
      <Button x:Name="Cancel" Content="取消" IsCancel="True" MinWidth="65" Padding="8,6" Margin="0,0,8,0"/>
      <Button x:Name="Save" Content="保存" IsDefault="True" MinWidth="72" Padding="8,6" Background="#5B3B85" Foreground="White"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dialog = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout))
    $dialog.Owner = $Owner
    Set-SpriteLocalizedTree $dialog
    $lang=$dialog.FindName('Language')
    foreach ($code in $script:spriteLanguageNames.Keys) {
        $item = [Windows.Controls.ComboBoxItem]::new()
        $item.Tag = $code
        $item.Content = $script:spriteLanguageNames[$code]
        $null = $lang.Items.Add($item)
        if ($code -eq $Settings.Language) { $lang.SelectedItem = $item }
    }
    if ($lang.SelectedIndex -lt 0) { $lang.SelectedIndex = 0 }
    $tr=New-SpriteTranslator
    $pick=$dialog.FindName('Provider'); $help=$dialog.FindName('Help'); $key=$dialog.FindName('Key')
    $row=$dialog.FindName('ModelRow'); $model=$dialog.FindName('Model'); $api=$dialog.FindName('ApiInputs')
    $forget=$dialog.FindName('Forget'); $status=$dialog.FindName('Status'); $login=$dialog.FindName('Login')
    $draft=$Settings.Clone()
    $state=@{ Previous=''; Login=$false }
    $cacheEdits = {
        $kind=$state.Previous
        if ($kind -eq 'doubao') { $draft.DoubaoModel=$model.Text.Trim() }
        if ($kind -in 'doubao','deepseek') {
            $field=if ($kind -eq 'doubao') {'DoubaoKey'} else {'DeepSeekKey'}
            if ($forget.IsChecked) { $draft[$field]='' }
            elseif ($key.SecurePassword.Length) { $draft[$field]=ConvertFrom-SecureString $key.SecurePassword }
        }
    }.GetNewClosure()
    $pick.Add_SelectionChanged({
        & $cacheEdits
        $kind=[string]$pick.SelectedItem.Tag
        $state.Previous=$kind
        $key.Clear(); $forget.IsChecked=$false; $status.Text=''
        $api.Visibility=if($kind -in 'doubao','deepseek'){'Visible'}else{'Collapsed'}
        $row.Visibility=if($kind -eq 'doubao'){'Visible'}else{'Collapsed'}
        $login.Visibility=if($kind -eq 'codex'){'Visible'}else{'Collapsed'}
        $model.Text=$draft.DoubaoModel
        $help.Text=switch($kind){
            'codex' {& $tr '使用本机 Codex CLI 的 ChatGPT 登录。'}
            'doubao' {& $tr '使用火山方舟的视觉模型。密钥留空会保留已有密钥，密钥加密保存于当前 Windows 账户。'}
            'deepseek' {& $tr '使用 deepseek-flash 读取图片和关键帧。密钥留空会保留已有密钥，密钥加密保存于当前 Windows 账户。'}
            'manual' {& $tr '本地准备指令与关键帧，供你手动发给常用聊天服务。'}
        }
    }.GetNewClosure())
    $login.Add_Click({$state.Login=$true;$dialog.DialogResult=$true}.GetNewClosure())
    $dialog.FindName('Save').Add_Click({
        try {
            & $cacheEdits
            $kind=[string]$pick.SelectedItem.Tag
            if ($kind -eq 'doubao' -and $draft.DoubaoModel -notmatch '^[a-zA-Z0-9._-]{1,128}$') {
                $status.Text=(& $tr '请填写火山方舟控制台里的视觉模型 ID 或接入点。'); return
            }
            $dialog.DialogResult=$true
        } catch { $status.Text=(& $tr '无法保存密钥，请检查 Windows 加密服务。') }
    }.GetNewClosure())
    $pick.SelectedIndex=[Math]::Max(0,[Array]::IndexOf(@('codex','doubao','deepseek','manual'),$Settings.Provider))
    if ($dialog.ShowDialog()) { $draft.Provider=[string]$pick.SelectedItem.Tag; $draft.Language=[string]$lang.SelectedItem.Tag; @{Settings=$draft;Login=$state.Login} }
}
