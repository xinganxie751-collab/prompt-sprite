$script:providerPath = Join-Path $env:LOCALAPPDATA 'PromptSprite/providers.json'

$script:spriteProviders = [ordered]@{
    codex = @{ Name='Codex'; Option='Codex · ChatGPT 登录'; Label='由 Codex 生成'; Help='使用本机 Codex CLI 的 ChatGPT 登录。' }
    doubao = @{ Name='豆包'; Option='豆包 · 火山方舟 API'; Label='由豆包生成'; Help='使用火山方舟的视觉模型。密钥留空会保留已有密钥，密钥加密保存于当前 Windows 账户。'; Endpoint='https://ark.cn-beijing.volces.com/api/v3/chat/completions'; ModelField='DoubaoModel'; KeyField='DoubaoKey'; TokenField='max_tokens' }
    deepseek = @{ Name='DeepSeek'; Option='DeepSeek · API'; Label='由 DeepSeek 生成'; Help='使用 deepseek-flash 读取图片和关键帧。密钥留空会保留已有密钥，密钥加密保存于当前 Windows 账户。'; Endpoint='https://api.deepseek.com/chat/completions'; Model='deepseek-flash'; KeyField='DeepSeekKey'; TokenField='max_tokens' }
    openai = @{ Name='OpenAI'; Option='OpenAI · API'; Label='OpenAI'; Endpoint='https://api.openai.com/v1/chat/completions'; Model='gpt-4.1-mini'; ModelField='OpenAIModel'; KeyField='OpenAIKey'; TokenField='max_completion_tokens' }
    gemini = @{ Name='Google Gemini'; Option='Google Gemini · API'; Label='Google Gemini'; Endpoint='https://generativelanguage.googleapis.com/v1beta/openai/chat/completions'; Model='gemini-3.1-flash-lite'; ModelField='GeminiModel'; KeyField='GeminiKey'; TokenField='max_tokens' }
    qwen = @{ Name='Qwen'; Option='Qwen · Alibaba Cloud API'; Label='Qwen'; Endpoint='https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'; Model='qwen3-vl-plus'; ModelField='QwenModel'; KeyField='QwenKey'; TokenField='max_tokens' }
    openrouter = @{ Name='OpenRouter'; Option='OpenRouter · API'; Label='OpenRouter'; Endpoint='https://openrouter.ai/api/v1/chat/completions'; ModelField='OpenRouterModel'; KeyField='OpenRouterKey'; TokenField='max_tokens' }
    custom = @{ Name='自定义 API'; Option='自定义 API'; Label='自定义 API'; ModelField='CustomModel'; KeyField='CustomKey'; EndpointField='CustomEndpoint' }
    manual = @{ Name='手动模式'; Option='手动 · 导出素材和指令'; Label='手动导出模式'; Help='本地准备指令与关键帧，供你手动发给常用聊天服务。' }
}

function Get-SpriteProvider([string]$Name) {
    $script:spriteProviders[$Name]
}

function Get-SpriteChatEndpoint([string]$Value) {
    $uri = $null
    if (![Uri]::TryCreate($Value.Trim(), [UriKind]::Absolute, [ref]$uri) -or
        ($uri.Scheme -ne 'https' -and !($uri.Scheme -eq 'http' -and $uri.IsLoopback)) -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) { return }
    $endpoint = $uri.AbsoluteUri.TrimEnd('/')
    if ($uri.AbsolutePath.TrimEnd('/') -notmatch '/chat/completions$') { $endpoint += '/chat/completions' }
    [Uri]$endpoint
}

function Read-SpriteProviders([string]$Path=$script:providerPath) {
    $settings = @{ Provider='codex'; Language='en-US' }
    foreach ($definition in $script:spriteProviders.Values) {
        if ($definition.ModelField) { $settings[$definition.ModelField] = [string]$definition.Model }
        if ($definition.KeyField) { $settings[$definition.KeyField] = '' }
        if ($definition.EndpointField) { $settings[$definition.EndpointField] = '' }
    }
    if (![IO.File]::Exists($Path)) { return $settings }
    try { $stored = [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { return $settings }
    if ($stored.Provider -and $script:spriteProviders.Contains([string]$stored.Provider)) { $settings.Provider = [string]$stored.Provider }
    if ($stored.Language -and $script:spriteLanguageNames.Contains([string]$stored.Language)) { $settings.Language = [string]$stored.Language }
    foreach ($field in @($settings.Keys)) {
        if ($field -notin 'Provider','Language' -and $stored.PSObject.Properties[$field]) {
            $settings[$field] = [string]$stored.$field
        }
    }
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
    <ComboBox x:Name="Provider" Height="34" AutomationProperties.Name="选择模型来源"/>
    <TextBlock Text="界面与输出语言 / Language" Margin="0,11,0,4"/>
    <ComboBox x:Name="Language" Height="34" AutomationProperties.Name="选择语言"/>
    <TextBlock x:Name="Help" TextWrapping="Wrap" Foreground="#665473" Margin="0,10,0,3"/>
    <StackPanel x:Name="ApiInputs" Visibility="Collapsed">
      <StackPanel x:Name="ModelRow" Margin="0,7,0,0">
        <TextBlock Text="视觉模型 ID 或推理接入点" Margin="0,0,0,4"/>
        <TextBox x:Name="Model" Height="34" Padding="7,5" AutomationProperties.Name="视觉模型 ID 或推理接入点"/>
      </StackPanel>
      <StackPanel x:Name="EndpointRow" Margin="0,7,0,0">
        <TextBlock Text="API 基础地址" Margin="0,0,0,4"/>
        <TextBox x:Name="Endpoint" Height="34" Padding="7,5" AutomationProperties.Name="API 基础地址"/>
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
    $tr = New-SpriteTranslator
    $providers = $script:spriteProviders
    $pick = $dialog.FindName('Provider')
    $help = $dialog.FindName('Help')
    $key = $dialog.FindName('Key')
    $row = $dialog.FindName('ModelRow')
    $model = $dialog.FindName('Model')
    $endpointRow = $dialog.FindName('EndpointRow')
    $endpoint = $dialog.FindName('Endpoint')
    $api = $dialog.FindName('ApiInputs')
    $forget = $dialog.FindName('Forget')
    $status = $dialog.FindName('Status')
    $login = $dialog.FindName('Login')
    $draft = $Settings.Clone()
    $state = @{ Previous=''; Login=$false }
    $normalizeEndpoint = ${function:Get-SpriteChatEndpoint}
    $cacheEdits = {
        if (!$state.Previous) { return }
        $definition = $providers[$state.Previous]
        if ($definition.ModelField) { $draft[$definition.ModelField] = $model.Text.Trim() }
        if ($definition.EndpointField) {
            $changed = (& $normalizeEndpoint $endpoint.Text) -cne (& $normalizeEndpoint $draft[$definition.EndpointField])
            if ($changed) { $draft[$definition.KeyField] = '' }
            $draft[$definition.EndpointField] = $endpoint.Text.Trim()
        }
        if ($definition.KeyField) {
            if ($forget.IsChecked) { $draft[$definition.KeyField] = '' }
            elseif ($key.SecurePassword.Length) { $draft[$definition.KeyField] = ConvertFrom-SecureString $key.SecurePassword }
        }
    }.GetNewClosure()
    $pick.Add_SelectionChanged({
        & $cacheEdits
        $kind = [string]$pick.SelectedItem.Tag
        if (!$kind) { return }
        $state.Previous = $kind
        $definition = $providers[$kind]
        $key.Clear()
        $forget.IsChecked = $false
        $status.Text = ''
        $api.Visibility = if ($definition.KeyField) {'Visible'} else {'Collapsed'}
        $row.Visibility = if ($definition.ModelField) {'Visible'} else {'Collapsed'}
        $endpointRow.Visibility = if ($definition.EndpointField) {'Visible'} else {'Collapsed'}
        $login.Visibility = if ($kind -eq 'codex') {'Visible'} else {'Collapsed'}
        $model.Text = if ($definition.ModelField) { [string]$draft[$definition.ModelField] } else { '' }
        $endpoint.Text = if ($definition.EndpointField) { [string]$draft[$definition.EndpointField] } else { '' }
        $help.Text = if ($definition.Help) { & $tr $definition.Help }
            elseif ($definition.EndpointField) { & $tr '输入兼容 Chat Completions 的地址与模型 ID。仅本机 HTTP 接口可不填密钥。' }
            else { & $tr '使用支持图片输入的模型 ID。密钥留空会保留已有密钥。' }
    }.GetNewClosure())
    $login.Add_Click({$state.Login=$true;$dialog.DialogResult=$true}.GetNewClosure())
    $dialog.FindName('Save').Add_Click({
        try {
            $definition = $providers[[string]$pick.SelectedItem.Tag]
            if ($definition.ModelField -and $model.Text.Trim() -notmatch '^[a-zA-Z0-9._:/@-]{1,160}$') {
                $status.Text = & $tr '请输入有效的模型 ID 或推理接入点。'
                return
            }
            if ($definition.EndpointField -and !(& $normalizeEndpoint $endpoint.Text)) {
                $status.Text = & $tr '请输入 HTTPS API 地址，或本机 HTTP 地址。'
                return
            }
            & $cacheEdits
            $dialog.DialogResult = $true
        } catch { $status.Text = & $tr '无法保存密钥，请检查 Windows 加密服务。' }
    }.GetNewClosure())
    foreach ($kind in $providers.Keys) {
        $item = [Windows.Controls.ComboBoxItem]::new()
        $item.Tag = $kind
        $item.Content = Get-SpriteText $providers[$kind].Option
        $null = $pick.Items.Add($item)
        if ($kind -eq $Settings.Provider) { $pick.SelectedItem = $item }
    }
    if ($pick.SelectedIndex -lt 0) { $pick.SelectedIndex = 0 }
    if ($dialog.ShowDialog()) { $draft.Provider=[string]$pick.SelectedItem.Tag; $draft.Language=[string]$lang.SelectedItem.Tag; @{Settings=$draft;Login=$state.Login} }
}
