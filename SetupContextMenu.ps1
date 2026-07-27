Param(
    [bool]$uninstall=$false
)

# Global definitions
$wtProfilesPath = "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$customConfigPath = "$PSScriptRoot\config.json"
$resourcePath = "$env:LOCALAPPDATA\WindowsTerminalContextIcons\"
$contextMenuIcoName = "terminal.ico"
$cmdIcoFileName = "cmd.ico"
$wslIcoFileName = "linux.ico"
$psIcoFileName = "powershell.ico"
$psCoreIcoFileName = "powershell-core.ico"
$azureCoreIcoFileName = "azure.ico"
$unknownIcoFileName = "unknown.ico"
$gitBashIcoFileName = "git-bash.ico"

# Emoji rendering: convert emoji character to .ico file
function Convert-EmojiToIcon {
    param([string]$Emoji, [string]$OutputPath)
    # Render emoji to ICO using System.Drawing (built into Windows, no deps)
    Add-Type -AssemblyName System.Drawing 2>$null
    $size = 32
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $bmp.SetResolution(96, 96)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    try { $font = New-Object System.Drawing.Font("Segoe UI Emoji", 20) } catch { $font = New-Object System.Drawing.Font("Segoe UI Symbol", 20) }
    $fmt = [System.Drawing.StringFormat]::new()
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($Emoji, $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new(-1, -1, $size+2, $size+2), $fmt)
    $g.Dispose()
    # Save as PNG in memory, then wrap in ICO
    $ms = [System.IO.MemoryStream]::new()
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $ms.ToArray()
    $ms.Dispose()
    $bmp.Dispose()
    # Write ICO (ICO header + embedded PNG)
    $fs = [System.IO.File]::OpenWrite($OutputPath)
    $writer = [System.IO.BinaryWriter]::new($fs)
    $writer.Write([byte[]]@(0,0,1,0,1,0))
    $writer.Write([byte]32); $writer.Write([byte]32)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$pngBytes.Length); $writer.Write([uint32]22)
    $writer.Write($pngBytes)
    $writer.Dispose()
    $fs.Dispose()
}

$menuRegID = "WindowsTerminal"
$contextMenuLabel = "Open Windows Terminal here"
$contextMenuRegPath = "Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\Directory\shell\$menuRegID"
$contextBGMenuRegPath = "Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\Directory\Background\shell\$menuRegID"
$subMenuRegRelativePath = "Directory\ContextMenus\$menuRegID"
$subMenuRegRoot = "Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\Directory\ContextMenus\$menuRegID"
$subMenuRegPath = "$subMenuRegRoot\shell\"

function Add-SubmenuReg ($regPath, $label, $iconPath, $command) {
    $cmdRegPath = "$regPath\command"
    [void](New-Item -Force -Path $regPath)
    [void](New-Item -Force -Path $cmdRegPath)
    [void](New-ItemProperty -Path $regPath -Name "MUIVerb" -PropertyType String -Value $label)
    [void](New-ItemProperty -Path $cmdRegPath -Name "(default)" -PropertyType String -Value $command)
    [void](New-ItemProperty -Path $regPath -Name "Icon" -PropertyType String -Value $iconPath)
}

# Clear register
if((Test-Path -Path $contextMenuRegPath)) {
    # If reg has existed
    Remove-Item -Recurse -Force -Path $contextMenuRegPath
    Write-Host "Clear reg $contextMenuRegPath"
}

if((Test-Path -Path $contextBGMenuRegPath)) {
    Remove-Item -Recurse -Force -Path $contextBGMenuRegPath
    Write-Host "Clear reg $contextBGMenuRegPath"
}

if((Test-Path -Path $subMenuRegRoot)) {
    Remove-Item -Recurse -Force -Path $subMenuRegRoot
    Write-Host "Clear reg $subMenuRegRoot"
}

if((Test-Path -Path $resourcePath)) {
    Remove-Item -Recurse -Force -Path $resourcePath
    Write-Host "Clear icon content folder $resourcePath"
}

if($uninstall) {
    Exit
}

# Setup icons
[void](New-Item -Path $resourcePath -ItemType Directory)
[void](Copy-Item -Path "$PSScriptRoot\icons\*.ico" -Destination $resourcePath)
Write-Output "Copy icons => $resourcePath"

# Load the custom config
if((Test-Path -Path $customConfigPath)) {
    $rawConfig = (Get-Content $customConfigPath -Encoding UTF8) -replace '^\s*\/\/.*' | Out-String
    $config = (ConvertFrom-Json -InputObject $rawConfig)
}

# Setup First layer context menu
[void](New-Item -Force -Path $contextMenuRegPath)
[void](New-ItemProperty -Path $contextMenuRegPath -Name ExtendedSubCommandsKey -PropertyType String -Value $subMenuRegRelativePath)
[void](New-ItemProperty -Path $contextMenuRegPath -Name Icon -PropertyType String -Value $resourcePath$contextMenuIcoName)
[void](New-ItemProperty -Path $contextMenuRegPath -Name MUIVerb -PropertyType String -Value $contextMenuLabel)
if($config.global.extended) {
    [void](New-ItemProperty -Path $contextMenuRegPath -Name Extended -PropertyType String)
}
Write-Host "Add top layer menu (shell) => $contextMenuRegPath"

[void](New-Item -Force -Path $contextBGMenuRegPath)
[void](New-ItemProperty -Path $contextBGMenuRegPath -Name ExtendedSubCommandsKey -PropertyType String -Value $subMenuRegRelativePath)
[void](New-ItemProperty -Path $contextBGMenuRegPath -Name Icon -PropertyType String -Value $resourcePath$contextMenuIcoName)
[void](New-ItemProperty -Path $contextBGMenuRegPath -Name MUIVerb -PropertyType String -Value $contextMenuLabel)
if($config.global.extended) {
    [void](New-ItemProperty -Path $contextBGMenuRegPath -Name Extended -PropertyType String)
}
Write-Host "Add top layer menu (background) => $contextMenuRegPath"

# Get Windows terminal profile
$rawContent = (Get-Content $wtProfilesPath -Encoding UTF8) -replace '^\s*\/\/.*' | Out-String
$json = (ConvertFrom-Json -InputObject $rawContent);

$profiles = $null;

if($json.profiles.list){
    Write-Host "Working with the new profiles style"
    $profiles = $json.profiles.list;
} else{
    Write-Host "Working with the old profiles style"
    $profiles = $json.profiles;
}

$profileSortOrder = 0

# Setup each profile item
$profiles | ForEach-Object {    
    $profileSortOrder += 1
    $profileSortOrderString = "{0:00}" -f $profileSortOrder 
    $profileName = $_.name
    $guid = $_.guid
    $configEntry = $config.profiles.$guid
        
    $leagaleName = $profileName -replace '[ \r\n\t]', '-'
    $subItemRegPath = "$subMenuRegPath$profileSortOrderString$leagaleName"
    $subItemAdminRegPath = "$subItemRegPath-Admin"

    if ($configEntry.hidden -eq $null) {
        $isHidden = $_.hidden
    } else {
        $isHidden = $configEntry.hidden
    }
    $commandLine = $_.commandline
    $source = $_.source
    $icoPath = ""

    # Final values
    $iconPath_f = ""
    $label_f = ""
    $labelAdmin_f = ""
    $command_f = ""
    $commandAdmin_f = ""

    if ($isHidden -eq $false) {

        # Decide label
        if ($configEntry.label) {
            $label_f = $configEntry.label
        }
        else {
            $label_f = $profileName
        }
        $labelAdmin_f = "$label_f (Admin)"
        
        $command_f = "`"$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe`" -p `"$profileName`" -d `"%V\.`""
        $commandAdmin_f = "powershell -WindowStyle hidden -Command `"Start-Process powershell -WindowStyle hidden -Verb RunAs -ArgumentList `"`"`"`"-Command $env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe -p '$profileName' -d '%V\.'`"`"`"`""
        
        if($configEntry.icon){
            $useFullPath = [System.IO.Path]::IsPathRooted($configEntry.icon);
            $tmpIconPath = $configEntry.icon;            
            $icoPath = If (!$useFullPath) {"$resourcePath$tmpIconPath"} Else { "$tmpIconPath" }
        }
        elseif ($_.icon) {
            $icoPath = $_.icon
        }
        elseif(($commandLine -match "cmd\.exe(?:\s|$)")) {
            $icoPath = "$cmdIcoFileName"
        }
        elseif (($commandLine -match "powershell\.exe(?:\s|$)")) {
            $icoPath = "$psIcoFileName"
        }
        elseif ($source -eq "Windows.Terminal.Wsl") {
            $icoPath = "$wslIcoFileName"
        }
        elseif ($source -eq "Windows.Terminal.PowershellCore") {
            $icoPath = "$psCoreIcoFileName"
        }
        elseif ($source -eq "Windows.Terminal.Azure") {
            $icoPath = "$azureCoreIcoFileName"
        }
        elseif ($source -eq "Git") {
            $icoPath = "$gitBashIcoFileName"
        }else{
            # Unhandled Icon
            $icoPath = "$unknownIcoFileName"
            Write-Host "No icon found, using unknown.ico instead"
        }

        # If icon is non-file (emoji, etc.), render it to an .ico file
        if ($icoPath -and $icoPath -notmatch '^[a-zA-Z]:\\|\.(?:ico|exe|dll|png|bmp)$') {
            $emojiHash = [System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($icoPath)).Replace("-", "")
            $emojiIcoPath = "$resourcePath" + "emoji-$emojiHash.ico"
            if (-not (Test-Path $emojiIcoPath)) {
                Write-Host "Rendering emoji icon $icoPath to $emojiIcoPath"
                Convert-EmojiToIcon -Emoji $icoPath -OutputPath $emojiIcoPath
            }
            $icoPath = $emojiIcoPath
        }

        if($icoPath -ne "") {
            $iconPath_f = If ($configEntry.icon -or $_.icon) { "$icoPath" } Else { "$resourcePath$icoPath" }
        }

        Write-Host "Add new entry $profileName => $subItemRegPath"

        Add-SubmenuReg -regPath:$subItemRegPath -label:$label_f -iconPath:$iconPath_f -command:$command_f

        if ($configEntry.showRunAs) {
            Add-SubmenuReg -regPath:$subItemAdminRegPath -label:$labelAdmin_f -iconPath:$iconPath_f -command:$commandAdmin_f
        }
    }else{
        Write-Host "Skip entry $profileName => $subItemRegPath"
    }
}
