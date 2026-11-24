$script:spriteLanguageNames = [ordered]@{
    'en-US' = 'English'
    'zh-CN' = '简体中文'
    'ja-JP' = '日本語'
    'ko-KR' = '한국어'
    'ru-RU' = 'Русский'
    'de-DE' = 'Deutsch'
}
$script:spriteLanguage = @{ Current='en-US' }
$script:spriteTranslations = @{}
$script:spriteTextKeys = @{}
$catalog = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Translations.json')) | ConvertFrom-Json
foreach ($locale in $catalog.PSObject.Properties) {
    $translations = @{}
    foreach ($entry in $locale.Value.PSObject.Properties) {
        $translations[$entry.Name] = $entry.Value
        $script:spriteTextKeys[$entry.Name] = $entry.Name
        $script:spriteTextKeys[$entry.Value] = $entry.Name
    }
    $script:spriteTranslations[$locale.Name] = $translations
}

function Get-SpriteText([string]$Text,[object[]]$Values=@()) {
    $translations = $script:spriteTranslations[$script:spriteLanguage.Current]
    $label = if ($translations -and $translations.ContainsKey($Text)) { $translations[$Text] } else { $Text }
    if ($Values.Count) { $label -f $Values } else { $label }
}

function New-SpriteTranslator {
    $language = $script:spriteLanguage
    $catalog = $script:spriteTranslations
    {
        param([string]$Text,[object[]]$Values=@())
        $translations = $catalog[$language.Current]
        $label = if ($translations -and $translations.ContainsKey($Text)) { $translations[$Text] } else { $Text }
        if ($Values.Count) { $label -f $Values } else { $label }
    }.GetNewClosure()
}

function Set-SpriteLocalizedTree($Root) {
    if ($Root -isnot [Windows.DependencyObject]) { return }
    foreach ($property in 'Text','Content','Title','ToolTip') {
        if ($property -eq 'Text' -and ($Root -is [Windows.Controls.TextBox] -or $Root -is [Windows.Controls.ComboBox])) { continue }
        if (!$Root.PSObject.Properties[$property]) { continue }
        $old = $Root.$property
        if ($old -is [string] -and $script:spriteTextKeys.ContainsKey($old)) {
            $Root.$property = Get-SpriteText $script:spriteTextKeys[$old]
        }
    }
    $name = [Windows.Automation.AutomationProperties]::GetName($Root)
    if ($name -and $script:spriteTextKeys.ContainsKey($name)) {
        [Windows.Automation.AutomationProperties]::SetName($Root, (Get-SpriteText $script:spriteTextKeys[$name]))
    }
    foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($Root)) { Set-SpriteLocalizedTree $child }
}
