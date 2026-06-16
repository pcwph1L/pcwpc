param(
    [string]$Targets = "",                 # "10.100.1.0/24" or "10.100.1.10,10.100.1.20"
    [string]$InputFile = "",               # file with one host/IP/CIDR per line (supports # comments)

    [string]$Domain = "",
    [string]$Username = "",
    [string]$Password = "",

    [int]$ListDepth = 1,                   # 0 = just the share root
    [int]$MaxDirSamples = 20,              # max dir names to sample per share
    [int]$MaxFileSamples = 30,             # max file names to sample per share
    [switch]$TestWrite,                    # try write (create+delete a temp file)
    [string]$OutCsv = ".\smbscan_results.csv"
)

# ---------- Helpers ----------
function Read-TargetsFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Input file not found: $Path" }
    Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and (-not $_.StartsWith("#")) }
}

function Expand-CIDR {
    param([string]$CIDR)
    if ($CIDR -notmatch "/") { return @($CIDR) }

    $parts  = $CIDR.Split("/")
    $baseIp = [System.Net.IPAddress]::Parse($parts[0])
    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) { throw "Invalid CIDR prefix: $prefix" }

    $ip      = $baseIp.GetAddressBytes()                # big-endian
    $octMask = 0,128,192,224,240,248,252,254,255
    $mask = New-Object 'System.Byte[]' 4
    $p = $prefix
    for ($i=0; $i -lt 4; $i++) { $take = [Math]::Max([Math]::Min($p,8),0); $mask[$i] = [byte]$octMask[$take]; $p -= $take }

    $net   = New-Object 'System.Byte[]' 4
    $inv   = New-Object 'System.Byte[]' 4
    $bcast = New-Object 'System.Byte[]' 4
    for ($i=0; $i -lt 4; $i++) {
        $net[$i]   = [byte] ($ip[$i] -band $mask[$i])
        $inv[$i]   = [byte] (255 - $mask[$i])
        $bcast[$i] = [byte] ($net[$i] -bor $inv[$i])
    }

    function BytesClone([byte[]]$b){ $c = New-Object 'System.Byte[]' $b.Length; [Array]::Copy($b,$c,$b.Length); return $c }
    function BytesInc([byte[]]$b){ for($i=3;$i-ge 0;$i--){ if($b[$i] -lt 255){ $b[$i]++; break } else { $b[$i]=0 } }; return $b }
    function BytesDec([byte[]]$b){ for($i=3;$i-ge 0;$i--){ if($b[$i] -gt 0){ $b[$i]--; break } else { $b[$i]=255 } }; return $b }
    function BytesEq([byte[]]$a,[byte[]]$b){ for($i=0;$i -lt 4;$i++){ if($a[$i] -ne $b[$i]){ return $false } } return $true }
    function BytesToIp([byte[]]$b){ return [System.Net.IPAddress]::new($b).ToString() }

    $start = BytesClone $net
    $end   = BytesClone $bcast
    if ($prefix -le 30) { $start = BytesInc (BytesClone $start); $end = BytesDec (BytesClone $end) }

    $results = New-Object System.Collections.Generic.List[string]
    if ($prefix -le 30) {
        $cur = BytesClone $start
        while ($true) {
            $results.Add((BytesToIp $cur))
            if (BytesEq $cur $end) { break }
            $cur = BytesInc $cur
        }
    } else {
        # /31 or /32
        $results.Add((BytesToIp $start))
        if (-not (BytesEq $start $end)) { $results.Add((BytesToIp $end)) }
    }
    return $results
}

function Resolve-Targets {
    $all = @()
    if ($InputFile) {
        $fileItems = Read-TargetsFromFile -Path $InputFile
        foreach ($item in $fileItems) { if ($item -match "/") { $all += Expand-CIDR -CIDR $item } else { $all += $item } }
    }
    if ($Targets) {
        foreach ($part in $Targets.Split(",")) {
            $t = $part.Trim(); if (-not $t) { continue }
            if ($t -match "/") { $all += Expand-CIDR -CIDR $t } else { $all += $t }
        }
    }
    $all = $all | Select-Object -Unique
    if (-not $all -or $all.Count -eq 0) { throw "No targets provided. Use -Targets and/or -InputFile." }
    return $all
}

function Test-Tcp445 {
    param([string]$IP, [int]$TimeoutMs = 1000)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($IP, 445, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $client.Close(); return $false }
        $client.EndConnect($iar); $client.Close(); return $true
    } catch { return $false }
}

function Connect-SMB {
    param([string]$Target)
    if ($Username -and $Password) {
        if ($Domain -ne "") { $credPrefix = "$Domain\$Username" } else { $credPrefix = $Username }
        cmd /c "net use \\$Target\IPC$ /user:`"$credPrefix`" `"$Password`" >NUL 2>&1" | Out-Null
    } else {
        cmd /c "net use \\$Target\IPC$ /delete /y >NUL 2>&1" | Out-Null
    }
}

function Disconnect-SMB {
    param([string]$Target)
    cmd /c "net use \\$Target\* /delete /y >NUL 2>&1" | Out-Null
}

function Get-Shares {
    param([string]$Target)
    $shares=@(); $script:lastNetViewErr=$null
    try {
        $out = cmd /c "net view \\$Target /all 2>&1"
        $txt = ($out | Out-String)
        if ($txt -match "System error 53") { $script:lastNetViewErr="system_error_53" }
        foreach ($line in $out) { if ($line -match "^\s*(\S+)\s+Disk") { $shares += $matches[1] } }
    } catch { $script:lastNetViewErr=$_.Exception.Message }
    $shares | Where-Object { $_ -notin @("ADMIN$","C$","D$","E$","PRINT$") }
}

function Get-Samples {
    param([string]$UNC, [int]$Depth, [int]$MaxDirs, [int]$MaxFiles)
    $dirNames = @(); $fileNames = @()
    try {
        if ($Depth -le 0) {
            $dirItems  = Get-ChildItem -LiteralPath $UNC -Directory -Force -ErrorAction Stop
            $fileItems = Get-ChildItem -LiteralPath $UNC -File      -Force -ErrorAction Stop
        } else {
            $dirItems  = Get-ChildItem -LiteralPath $UNC -Directory -Recurse -Depth $Depth -Force -ErrorAction Stop
            $fileItems = Get-ChildItem -LiteralPath $UNC -File      -Recurse -Depth $Depth -Force -ErrorAction Stop
        }
        $dirNames  = $dirItems  | Select-Object -ExpandProperty FullName -First $MaxDirs
        $fileNames = $fileItems | Select-Object -ExpandProperty FullName -First $MaxFiles
        return ,@($true, $dirNames, $fileNames, $null)
    } catch {
        return ,@($false, $dirNames, $fileNames, $_.Exception.Message)
    }
}

function Test-UNCWrite {
    param([string]$UNC)
    $tmpName = "_smbscan_test_" + ([Guid]::NewGuid().ToString("N")) + ".tmp"
    $tmpPath = Join-Path $UNC $tmpName
    try {
        "test" | Out-File -LiteralPath $tmpPath -Encoding ascii -ErrorAction Stop
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction Stop
        return ,$true,$null
    } catch {
        return ,$false,$_.Exception.Message
    }
}

# ---------- Main ----------
$rows = New-Object System.Collections.Generic.List[Object]
try { $targetsList = Resolve-Targets } catch { Write-Host "[!] $_"; exit 1 }

Write-Host "[*] Targets: $($targetsList.Count)"

foreach ($ip in $targetsList) {
    Write-Host "`n[+] Host: $ip"

    # Probe SMB first (tcp/445)
    if (-not (Test-Tcp445 -IP $ip)) {
        $rows.Add([pscustomobject]@{
            IP=$ip; Share=""; UNC=""; Readable=$false; Writable=$false;
            Status="no_smb_listener"; Error="tcp/445 closed or filtered"; 
            SampleDirs=""; SampleFiles=""
        })
        Write-Host "    - tcp/445 closed/filtered"
        continue
    }

    try {
        Connect-SMB -Target $ip
        $shares = Get-Shares -Target $ip

        if (-not $shares -or $shares.Count -eq 0) {
            $statusVal = "no_shares_or_denied"
            $errorVal  = ""
            if ($script:lastNetViewErr) {
                $statusVal = $script:lastNetViewErr
                $errorVal  = "net view: $script:lastNetViewErr"
            }

            $rows.Add([pscustomobject]@{
                IP=$ip; Share=""; UNC=""; Readable=$false; Writable=$false;
                Status=$statusVal; Error=$errorVal; SampleDirs=""; SampleFiles=""
            })
            Write-Host "    - No shares (or access denied)"
            continue
        }

        foreach ($s in $shares) {
            $unc = "\\$ip\$s"
            Write-Host "    -> $unc"

            $tmp = Get-Samples -UNC $unc -Depth $ListDepth -MaxDirs $MaxDirSamples -MaxFiles $MaxFileSamples
            $canRead  = $tmp[0]; $dirNames = $tmp[1]; $fileNames = $tmp[2]; $readErr = $tmp[3]

            $canWrite = $false; $writeErr = $null
            if ($TestWrite -and $canRead) {
                $tmpW = Test-UNCWrite -UNC $unc
                $canWrite = $tmpW[0]; $writeErr = $tmpW[1]
            }

            if ($canRead) { $status = "ok" } else { $status = "access_denied_or_error" }

            $errMsg = $readErr
            if ($writeErr) {
                if ($errMsg) { $errMsg = "$errMsg; write: $writeErr" } else { $errMsg = "write: $writeErr" }
            }

            $rows.Add([pscustomobject]@{
                IP          = $ip
                Share       = $s
                UNC         = $unc
                Readable    = $canRead
                Writable    = $canWrite
                Status      = $status
                Error       = $errMsg
                SampleDirs  = ($dirNames  -join "; ")
                SampleFiles = ($fileNames -join "; ")
            })
        }
    } catch {
        $rows.Add([pscustomobject]@{
            IP=$ip; Share=""; UNC=""; Readable=$false; Writable=$false;
            Status="error"; Error=$_.Exception.Message; SampleDirs=""; SampleFiles=""
        })
        Write-Host "    - Error: $($_.Exception.Message)"
    } finally {
        try { Disconnect-SMB -Target $ip } catch {}
    }
}

$rows | Export-Csv -NoTypeInformation -Path $OutCsv
Write-Host "`n[+] Done. Results saved to $OutCsv"
