function Get-IEModVersion { param($Path)
    $regexVersion = [Regex]::new('.*?VERSION(\s*)(|~"|~|"|)(@.+|.+)("~|"|~|)(|\s*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $line = $line -replace "\/\/(.*)(\n|)"
        if ($line -match "\S" -and $line -notmatch "\/\*[\s\S]*?\*\/") {
            if ($regexVersion.IsMatch($line)) {
                [string]$dataVersionLine = $regexVersion.Matches($line).Groups[3].Value.ToString().trimStart(' ').trimStart('~').trimStart('"').TrimEnd(' ').TrimEnd('~').TrimEnd('"')
                $dataVersionLine
                break
            }
        }
    }
}

$Token = $ENV:GITHUB_TOKEN
$Base64Token = [System.Convert]::ToBase64String([char[]]$Token)
$Headers = @{ Authorization = 'Basic {0}' -f $Base64Token }

$ModTopDirectory = $PWD

Write-Host $ModTopDirectory # D:/a/ActionTest/ActionTest

$ModMainFile = (Get-ChildItem -Path $PWD -Recurse -Depth 1 -Include "*.tp2")[0]

Write-Host $ModMainFile.FullName # D:/a/ActionTest/ActionTest/ActionTest/ActionTest.tp2
$ModID = $ModMainFile.BaseName -replace 'setup-'

$weiduExeBaseName = "Setup-$ModID"

$ModVersion = Get-IEModVersion -Path $ModMainFile.FullName

if ($null -eq $ModVersion -or $ModVersion -eq '') {
    Write-Host "Cannot detect VERSION keyword"
    Exit 1
} else {
    Write-Host "Version: $ModVersion"
    Write-Host "Version cut: $($ModVersion -replace "\s+", '_')"
}

$iniData = try { Get-Content $ModTopDirectory/$ModID/$ModID.ini -EA 0 } catch { }
# Github release asset name limitation
if ($iniData) {
    $ModDisplayName = ((($iniData | ? { $_ -notlike "^\s+#*" -and $_ -like "Name*=*" }) -split '=') -split '#')[1].TrimStart(' ').TrimEnd(' ')
    $simplePackageBaseName = (($ModDisplayName -replace "\s+", '_') -replace "\W") -replace '_+','-'
    $simpleVersion = $ModVersion -replace "\s+",'-'
    $PackageBaseName = ($simplePackageBaseName + '-' + $simpleVersion).ToLower()
} else {
    $simplePackageBaseName = (($ModID -replace "\s+", '_') -replace "\W") -replace '_+','-'
    $simpleVersion = $ModVersion -replace "\s+",'-'
    $PackageBaseName = ($simplePackageBaseName + '-' + $simpleVersion).ToLower()
}

Write-Host "PackageBaseName: $PackageBaseName"

$outIEMod = "$ModID-iemod"
$outZip = "$ModID-zip"

Write-Host "$outIEMod $outZip"

# temp dir
if ($PSVersionTable.PSEdition -eq 'Desktop' -or $isWindows) {
    $tempDir = Join-path -Path $env:TEMP -ChildPath (Get-Random)
} else {
    $tempDir = Join-path -Path '/tmp' -ChildPath (Get-Random)
}

New-Item -Path $tempDir/$outIEMod/$ModID -ItemType Directory -Force | Out-Null
New-Item -Path $tempDir/$outZip/$ModID -ItemType Directory -Force | Out-Null

Write-Host "$tempDir/$outIEMod/$ModID"
Write-Host "$tempDir/$outZip/$ModID"

$regexAny = ".*", "*.bak", "*.iemod", "*.tmp", "*.temp", 'backup', 'bgforge.ini', 'Thumbs.db', 'ehthumbs.db', '__macosx', '$RECYCLE.BIN'
$excludedAny = Get-ChildItem -Path $ModTopDirectory/$ModID -Recurse -Include $regexAny

#iemod package
Copy-Item -Path $ModTopDirectory/$ModID/* -Destination $tempDir/$outIEMod/$ModID -Recurse -Exclude $regexAny | Out-Null

Write-Host "Creating $PackageBaseName.iemod" -ForegroundColor Green

Compress-Archive -Path $tempDir/$outIEMod/* -DestinationPath "$ModTopDirectory/$PackageBaseName.zip" -Force -CompressionLevel Optimal | Out-Null
Rename-Item -Path "$ModTopDirectory/$PackageBaseName.zip" -NewName "$ModTopDirectory/$PackageBaseName.iemod" -Force | Out-Null

# zip package
Copy-Item -Path $ModTopDirectory/$ModID/* -Destination $tempDir/$outZip/$ModID -Recurse -Exclude $regexAny | Out-Null

# get latest weidu version
$datalastRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/weiduorg/weidu/releases/latest" -Headers $Headers -Method Get
$weiduWinUrl = $datalastRelease.assets | ? name -Match 'Windows' | Select-Object -ExpandProperty browser_download_url
$weiduMacUrl = $datalastRelease.assets | ? name -Match 'Mac' | Select-Object -ExpandProperty browser_download_url

Invoke-WebRequest -Uri $weiduWinUrl -Headers $Headers -OutFile "$tempDir/WeiDU-Windows.zip" -PassThru | Out-Null
Expand-Archive -Path "$tempDir/WeiDU-Windows.zip" -DestinationPath "$tempDir/" | Out-Null

Invoke-WebRequest -Uri $weiduMacUrl -Headers $Headers -OutFile "$tempDir/WeiDU-Mac.zip" -PassThru | Out-Null
Expand-Archive -Path "$tempDir/WeiDU-Mac.zip" -DestinationPath "$tempDir/" | Out-Null

# Copy latest WeiDU version
Copy-Item "$tempDir/WeiDU-Windows/bin/amd64/weidu.exe" "$tempDir/$outZip/$weiduExeBaseName.exe" | Out-Null
Copy-Item "$tempDir/WeiDU-Mac/bin/amd64/weidu" "$tempDir/$outZip/$($weiduExeBaseName.tolower())" | Out-Null
chmod +x "$tempDir/$outZip/$($weiduExeBaseName.tolower())"
# Create .command script
'cd "${0%/*}"' + "`n" + 'ScriptName="${0##*/}"' + "`n" + './${ScriptName%.*}' + "`n" | Set-Content -Path "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command" | Out-Null
chmod +x "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command"
Get-Content "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command"

Get-ChildItem "$tempDir/$outZip" -Recurse

Write-Host "Creating $PackageBaseName.zip" -ForegroundColor Green

#Compress-Archive -Path $tempDir/$outZip/* -DestinationPath "$ModTopDirectory/$PackageBaseName.zip" -Force -CompressionLevel Optimal | Out-Null
#use 7zip
7z a "$ModTopDirectory/$PackageBaseName.zip" "$tempDir/$outZip/*"
if ($excludedAny) {
    Write-Warning "Excluded items fom the package:"
    $excludedAny.FullName.Substring($ModTopDirectory.length) | Write-Warning
}
Write-Host "Finished." -ForegroundColor Green
Write-Host "##[set-output name=PackageBaseName;]$($PackageBaseName)"
