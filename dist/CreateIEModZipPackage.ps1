# Copyright (c) 2019 AL|EN (alienquake@hotmail.com)

function Get-IEModVersion {
    param($Path)
    $regexVersion = [Regex]'.*?VERSION(\s*)(|~"|~|"|)(@.+|.+)("~|"|~|)(|\s*)'
    $regexCommentsMultiLine = '\/\*[\s\S]*?\*\/|([^\\:]|^)\/\/.*$'
    $regexCommentsSingleLine = '//(.*?)\r?\n'

    $dataRaw = Get-Content -Path $Path -ReadCount 0 -Raw

    $dataClean = ($dataRAW -replace $regexCommentsMultiLine) -replace $regexCommentsSingleLine 

    [string]$dataVersion = ($regexVersion.Matches($dataClean).Groups[3].Value.Trim() -replace '~') -replace '"'
    $dataVersion
}

$Token = $ENV:GITHUB_TOKEN
$Base64Token = [System.Convert]::ToBase64String([char[]]$Token)
$Headers = @{ Authorization = 'Basic {0}' -f $Base64Token }

$ModTopDirectory = $PWD

Write-Host $ModTopDirectory

$ModMainFile = (Get-ChildItem -Path $PWD -Recurse -Depth 1 -Include "*.tp2")[0]
$ModMainFolder = $ModMainFile.Directory.BaseName

Write-Host $ModMainFile.FullName
$ModID = $ModMainFile.BaseName -replace 'setup-'

$cleanModID = $ModID -replace "\W+", ''

if ($cleanModID[0] -ceq $cleanModID[0].ToString().ToUpperInvariant()){
    $weiduExeBaseName = "Setup-$ModID"
} else {
    $weiduExeBaseName = "setup-$ModID"
}

$ModVersion = Get-IEModVersion -Path $ModMainFile.FullName

if ($null -eq $ModVersion -or $ModVersion -eq '') {
    Write-Host "Cannot detect VERSION keyword"
    Exit 1
} else {
    Write-Host "Version: $ModVersion"
    Write-Host "Version cut: $($ModVersion -replace "\s+", '_')"
}

$iniDataFile = try { Get-ChildItem -Path $ModTopDirectory/$ModMainFolder -Filter "$ModID.ini"  } catch { $null }

if ($iniDataFile) {
    $iniData = try { Get-Content $iniDataFile -EA 0 } catch { $null }
}

# workaround for GitHub release asset name limitation
$simplePackageBaseName = (($ModID -replace "\s+", '_') -replace "\W") -replace '_+', '-'
$simpleVersion = $ModVersion -replace "\s+", '-'
$PackageBaseName = ($simplePackageBaseName + '-' + $simpleVersion).ToLower()

if ($iniData) {
    $nameKey = $iniData | ? { $_ -notlike "^\s+#*" -and $_ -like "Name*=*" }
    if ($nameKey){
        $ModDisplayName = ((($iniData | ? { $_ -notlike "^\s+#*" -and $_ -like "Name*=*" }) -split '=') -split '#')[1].Trim()
        if ($ModDisplayName){
            $simplePackageBaseName = (($ModDisplayName -replace "\s+", '_') -replace "\W") -replace '_+', '-'
            $PackageBaseName = ($simplePackageBaseName + '-' + $simpleVersion).ToLower()
        }
    }
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

New-Item -Path $tempDir/$outIEMod/$ModMainFolder -ItemType Directory -Force | Out-Null
New-Item -Path $tempDir/$outZip/$ModMainFolder -ItemType Directory -Force | Out-Null

Write-Host "$tempDir/$outIEMod/$ModMainFolder"
Write-Host "$tempDir/$outZip/$ModMainFolder"

$regexAny = ".*", "*.bak", "*.iemod", "*.tmp", "*.temp", 'backup', 'Thumbs.db', 'ehthumbs.db', '__macosx', '$RECYCLE.BIN'
$excludedAny = Get-ChildItem -Path $ModTopDirectory/$ModMainFolder -Recurse -Include $regexAny

# create iemod package
Copy-Item -Path $ModTopDirectory/$ModMainFolder/* -Destination $tempDir/$outIEMod/$ModMainFolder -Recurse -Exclude $regexAny | Out-Null

Write-Host "Creating $PackageBaseName.iemod" -ForegroundColor Green

# compress iemod package
7z a -tzip "$ModTopDirectory/$PackageBaseName.iemod" "$tempDir/$outIEMod/*"

# zip package
Copy-Item -Path $ModTopDirectory/$ModMainFolder/* -Destination $tempDir/$outZip/$ModMainFolder -Recurse -Exclude $regexAny | Out-Null

# get latest weidu version
$datalastRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/weiduorg/weidu/releases/latest" -Headers $Headers -Method Get
$weiduWinUrl = $datalastRelease.assets | ? name -Like "WeiDU*Windows*amd64*" | Select-Object -ExpandProperty browser_download_url
$weiduMacUrl = $datalastRelease.assets | ? name -Like "WeiDU*Mac*" | Select-Object -ExpandProperty browser_download_url

Invoke-WebRequest -Uri $weiduWinUrl -Headers $Headers -OutFile "$tempDir/WeiDU-Windows.zip" -PassThru | Out-Null
Expand-Archive -Path "$tempDir/WeiDU-Windows.zip" -DestinationPath "$tempDir/" | Out-Null

Invoke-WebRequest -Uri $weiduMacUrl -Headers $Headers -OutFile "$tempDir/WeiDU-Mac.zip" -PassThru | Out-Null
Expand-Archive -Path "$tempDir/WeiDU-Mac.zip" -DestinationPath "$tempDir/" | Out-Null

# copy latest WeiDU version
Copy-Item "$tempDir/WeiDU-Windows/weidu.exe" "$tempDir/$outZip/$weiduExeBaseName.exe" | Out-Null
Copy-Item "$tempDir/WeiDU-Mac/weidu" "$tempDir/$outZip/$($weiduExeBaseName.tolower())" | Out-Null
chmod +x "$tempDir/$outZip/$($weiduExeBaseName.tolower())"

# create .command file
'cd "${0%/*}"' + "`n" + 'ScriptName="${0##*/}"' + "`n" + './${ScriptName%.*}' + "`n" | Set-Content -Path "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command" | Out-Null
chmod +x "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command"
Get-Content "$tempDir/$outZip/$($weiduExeBaseName.tolower()).command"
Get-ChildItem "$tempDir/$outZip" -Recurse

Write-Host "Creating $PackageBaseName.zip" -ForegroundColor Green

# compress zip package
7z a "$ModTopDirectory/$PackageBaseName.zip" "$tempDir/$outZip/*"

if ($excludedAny) {
    Write-Warning "Excluded items fom the package:"
    $excludedAny.FullName.Substring($ModTopDirectory.length) | Write-Warning
}

Write-Output "PackageBaseName=$PackageBaseName" >> $env:GITHUB_OUTPUT

Write-Host "Finished." -ForegroundColor Green
