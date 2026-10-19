<#
.SYNOPSIS
Installs the Virtual Display Driver (MttVDD) in the Windows guest and binds it to the passthrough GPU.

.DESCRIPTION
Looking Glass needs an active display output on the passed-through GPU. With no QXL adapter in the VM
there is none, so this installs a virtual monitor driver. Steps:
  1. download the driver release and extract it
  2. verify the Authenticode signature of the driver's .cat and .dll/.sys (valid, signed by
     "SignPath Foundation", optionally pinned to a certificate thumbprint) BEFORE trusting anything
  3. import the signer certificate into LocalMachine\TrustedPublisher
  4. write C:\VirtualDisplayDriver\vdd_settings.xml (GPU name, extra resolutions, logging)
  5. install the driver package and create the root-enumerated device (pnputil cannot do this step)
  6. report the device and its status
Safe to run again: an existing device is not duplicated, settings are rewritten, and the device is
restarted so the driver rereads them.

Run it elevated. From the host, the guest agent runs as SYSTEM, which is elevated:
  guest/vm-guest-exec --timeout 600 --file guest/install-vdd.ps1 -- -GpuName "NVIDIA GeForce RTX 4070 Laptop GPU"

.PARAMETER GpuName
The name Windows shows for the GPU in Device Manager (GPU_NAME in /etc/win11-vm.conf). The virtual
monitor attaches to the adapter with this name; a wrong name leaves Looking Glass without an output.

.PARAMETER Resolutions
Extra resolutions as WIDTHxHEIGHT (60 Hz). A single comma-separated string is accepted too.

.PARAMETER VddVersion
Release tag of VirtualDrivers/Virtual-Display-Driver.

.PARAMETER VddUrl
Direct URL of the "Driver Only" zip. Default: derived from -VddVersion.

.PARAMETER ExpectedThumbprint
SHA-1 thumbprint the signer certificate must have. Default: the SignPath certificate that signed
release 25.7.23 (only applied when -VddVersion is 25.7.23). Pass '' to check only the signer name,
for example for a newer release signed with a renewed certificate.

.PARAMETER WorkDir
Scratch directory for the download and extraction.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GpuName,
    [string[]]$Resolutions = @('1920x1200', '3440x1440'),
    [string]$VddVersion = '25.7.23',
    [string]$VddUrl,
    [string]$ExpectedThumbprint,
    [string]$WorkDir = 'C:\vdd'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$KnownVersion = '25.7.23'
$KnownThumbprint = '3CF8CF26D8BA266C3A483AB7D26D4A818E317D76'
$SettingsDir = 'C:\VirtualDisplayDriver'
$HardwareId = 'Root\MttVDD'

function Write-Step([string]$Message) { Write-Host "== $Message" }

function Find-VddDevice {
    # Root\MttVDD devices, whether or not a driver is bound to them yet.
    Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.HardwareID -contains $HardwareId }
}

function Invoke-Pnputil {
    param([string[]]$PnpArgs)
    $ErrorActionPreference = 'Continue'   # native stderr must not become a terminating error
    $out = & pnputil.exe @PnpArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $out.TrimEnd() -split "`r?`n" | Select-Object -First 8 | ForEach-Object { Write-Host "   $_" }
    if ($code -ne 0 -and $code -ne 3010) { throw "pnputil $($PnpArgs -join ' ') failed with exit code $code" }
}

try {
    # ---- preconditions -------------------------------------------------------------------
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $id.IsSystem -or (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'This script must run elevated (as Administrator or SYSTEM). Use an elevated PowerShell, or run it from the host with vm-guest-exec.' }

    if ([string]::IsNullOrWhiteSpace($GpuName)) { throw '-GpuName must not be empty.' }
    $GpuName = $GpuName.Trim()

    # Accept both -Resolutions a,b (array) and "a,b" (one string, as -File or the guest agent passes it).
    $resList = @($Resolutions | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
    foreach ($r in $resList) {
        if ($r -notmatch '^(\d{3,5})x(\d{3,5})$') { throw "Bad resolution '$r': use WIDTHxHEIGHT, for example 1920x1200." }
    }

    if (-not $VddUrl) {
        $VddUrl = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/$VddVersion/VirtualDisplayDriver-x86.Driver.Only.zip"
    }
    # Pin the certificate only for the release it is known for, unless the caller chose explicitly.
    $pin = $null
    if ($PSBoundParameters.ContainsKey('ExpectedThumbprint')) {
        if ($ExpectedThumbprint) { $pin = ($ExpectedThumbprint -replace '[^0-9A-Fa-f]', '').ToUpper() }
    }
    elseif ($VddVersion -eq $KnownVersion) {
        $pin = $KnownThumbprint
    }
    else {
        Write-Warning "No thumbprint pinned for release $VddVersion (only the signer name is checked). Pass -ExpectedThumbprint to pin one."
    }

    # ---- 1. download + extract -----------------------------------------------------------
    Write-Step "Download $VddUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $zip = Join-Path $WorkDir 'vdd.zip'
    $drv = Join-Path $WorkDir 'drv'
    Invoke-WebRequest -UseBasicParsing -Uri $VddUrl -OutFile $zip
    if (Test-Path -LiteralPath $drv) { Remove-Item -LiteralPath $drv -Recurse -Force }
    Expand-Archive -Force -LiteralPath $zip -DestinationPath $drv
    $inf = Get-ChildItem -LiteralPath $drv -Recurse -Filter 'MttVDD.inf' | Select-Object -First 1
    if (-not $inf) { throw "MttVDD.inf not found in the extracted archive ($drv)." }
    $src = $inf.DirectoryName
    Write-Host "   driver package: $src"

    # ---- 2. verify the signature BEFORE trusting it --------------------------------------
    Write-Step 'Verify Authenticode signatures'
    $cat = Get-ChildItem -LiteralPath $src -Filter '*.cat' | Select-Object -First 1
    if (-not $cat) { throw "No .cat file next to MttVDD.inf in $src." }
    $bins = @(Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Extension -in '.dll', '.sys' })
    $signer = $null
    foreach ($f in @($cat) + $bins) {
        $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
        $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(none)' }
        Write-Host "   $($f.Name): $($sig.Status) | $subject"
        if ($f.Extension -ne '.cat' -and $sig.Status -eq 'NotSigned') {
            # A driver binary may be covered only by the signed catalog. The .cat is mandatory and checked below.
            Write-Warning "$($f.Name) has no embedded signature; it is only covered by the catalog."
            continue
        }
        if ($sig.Status -ne 'Valid') { throw "Signature of $($f.Name) is '$($sig.Status)', not Valid. Refusing to trust this driver." }
        if ($sig.SignerCertificate.Subject -notlike '*SignPath Foundation*') { throw "$($f.Name) is not signed by SignPath Foundation (signer: $subject). Refusing to trust this driver." }
        if ($pin -and $sig.SignerCertificate.Thumbprint -ne $pin) { throw "$($f.Name) signer thumbprint $($sig.SignerCertificate.Thumbprint) is not the expected $pin." }
        if ($f.Extension -eq '.cat') { $signer = $sig.SignerCertificate }
    }
    if (-not $signer) { throw 'Catalog signer certificate not found.' }

    # ---- 3. trust the signer ---------------------------------------------------------------
    Write-Step 'Add the signer to LocalMachine\TrustedPublisher'
    if (Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$($signer.Thumbprint)") {
        Write-Host '   already trusted'
    }
    else {
        $cer = Join-Path $WorkDir 'signer.cer'
        Export-Certificate -Cert $signer -FilePath $cer | Out-Null
        Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
        Write-Host '   trusted publisher added'
    }

    # ---- 4. settings -----------------------------------------------------------------------
    Write-Step "Write $SettingsDir\vdd_settings.xml"
    New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
    $settingsPath = Join-Path $SettingsDir 'vdd_settings.xml'
    if (Test-Path -LiteralPath $settingsPath) {
        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak" -Force
        $x = Get-Content -LiteralPath $settingsPath -Raw
    }
    else {
        $x = Get-Content -LiteralPath (Join-Path $src 'vdd_settings.xml') -Raw
    }
    # friendlyname decides which GPU the virtual monitor attaches to.
    $gpuXml = [Security.SecurityElement]::Escape($GpuName).Replace('$', '$$')
    $x = [regex]::Replace($x, '<friendlyname>[^<]*</friendlyname>', "<friendlyname>$gpuXml</friendlyname>")
    $new = ''
    foreach ($r in $resList) {
        $w, $h = $r -split 'x'
        if ($x -notmatch "<width>\s*$w\s*</width>\s*<height>\s*$h\s*</height>") {
            $new += "        <resolution><width>$w</width><height>$h</height><refresh_rate>60</refresh_rate></resolution>`r`n"
        }
    }
    if ($new) {
        $closeTag = [regex]'(?s)\s*</resolutions>'
        if (-not $closeTag.IsMatch($x)) { throw 'vdd_settings.xml has no </resolutions> element; the file layout changed.' }
        $x = $closeTag.Replace($x, "`r`n$($new.TrimEnd())`r`n    </resolutions>", 1)
    }
    $x = $x -replace '<logging>false</logging>', '<logging>true</logging>'
    Set-Content -LiteralPath $settingsPath -Value $x -Encoding UTF8
    $doc = [xml](Get-Content -LiteralPath $settingsPath -Raw)
    if ($doc.SelectSingleNode('//friendlyname').InnerText -ne $GpuName) { throw 'friendlyname was not written to vdd_settings.xml.' }
    if ($doc.SelectSingleNode('//logging[not(*)]').InnerText -ne 'true') { Write-Warning 'logging is not enabled in vdd_settings.xml (unexpected file layout).' }
    Write-Host "   settings xml OK (GPU '$GpuName', extra resolutions: $($resList -join ', '))"

    # ---- 5. driver + device ----------------------------------------------------------------
    Write-Step 'Install the driver package'
    Invoke-Pnputil @('/add-driver', (Join-Path $src 'MttVDD.inf'), '/install')

    $existing = @(Find-VddDevice)
    if ($existing.Count -gt 0 -and ($existing | Where-Object { $_.ConfigManagerErrorCode -eq 0 })) {
        Write-Step 'Device already present, restarting it so it rereads the settings'
        foreach ($d in $existing) {
            try { Invoke-Pnputil @('/restart-device', $d.DeviceID) }
            catch { Write-Warning "Could not restart $($d.DeviceID): $($_.Exception.Message). Reboot the guest if the new settings do not apply." }
        }
    }
    else {
        if (-not ('Dev' -as [type])) {
            Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class Dev {
  [StructLayout(LayoutKind.Sequential)] public struct SP_DEVINFO_DATA { public int cbSize; public Guid ClassGuid; public int DevInst; public IntPtr Reserved; }
  [DllImport("setupapi.dll", SetLastError=true)] public static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid g, IntPtr h);
  [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool SetupDiCreateDeviceInfoW(IntPtr s, string name, ref Guid g, string desc, IntPtr h, int flags, ref SP_DEVINFO_DATA d);
  [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool SetupDiSetDeviceRegistryPropertyW(IntPtr s, ref SP_DEVINFO_DATA d, int prop, byte[] buf, int size);
  [DllImport("setupapi.dll", SetLastError=true)] public static extern bool SetupDiCallClassInstaller(int f, IntPtr s, ref SP_DEVINFO_DATA d);
  [DllImport("setupapi.dll")] public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("newdev.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr h, string hwid, string inf, int flags, out bool reboot);
}
'@
        }
        if ($existing.Count -eq 0) {
            Write-Step 'Create the root-enumerated display device (SetupAPI)'
            $guid = [Guid]'4D36E968-E325-11CE-BFC1-08002BE10318'   # Display adapters class
            $set = [Dev]::SetupDiCreateDeviceInfoList([ref]$guid, [IntPtr]::Zero)
            if ($set -eq [IntPtr](-1)) { throw "CreateDeviceInfoList failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
            try {
                $d = New-Object Dev+SP_DEVINFO_DATA
                $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d)
                if (-not [Dev]::SetupDiCreateDeviceInfoW($set, 'Display', [ref]$guid, $null, [IntPtr]::Zero, 1, [ref]$d)) { throw "CreateDeviceInfo failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
                $hw = [Text.Encoding]::Unicode.GetBytes("${HardwareId}`0`0")
                if (-not [Dev]::SetupDiSetDeviceRegistryPropertyW($set, [ref]$d, 1, $hw, $hw.Length)) { throw "SetHwId failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
                if (-not [Dev]::SetupDiCallClassInstaller(0x19, $set, [ref]$d)) { throw "RegisterDevice failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
            }
            finally {
                [Dev]::SetupDiDestroyDeviceInfoList($set) | Out-Null
            }
        }
        else {
            Write-Step 'Device exists but has no working driver; binding the driver'
        }
        $reboot = $false
        if (-not [Dev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $HardwareId, (Join-Path $src 'MttVDD.inf'), 1, [ref]$reboot)) { throw "UpdateDriver failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
        Write-Host "   driver installed, reboot needed: $reboot"
    }

    # ---- 6. report -------------------------------------------------------------------------
    Start-Sleep -Seconds 6
    Write-Step 'Result'
    (Get-PnpDevice -Class Display | Format-Table Status, FriendlyName -AutoSize | Out-String).TrimEnd() | Write-Host
    $dev = @(Find-VddDevice)
    if ($dev.Count -eq 0) { throw 'The Virtual Display Driver device is not present after installation.' }
    $bad = @($dev | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    foreach ($d in $dev) { Write-Host "Virtual Display device: $($d.Name) | $($d.DeviceID) | status $($d.Status) | problem code $($d.ConfigManagerErrorCode)" }
    if ($bad.Count -gt 0) {
        Write-Host 'RESULT: device present but not working (see the problem code). Check C:\VirtualDisplayDriver logs and reboot the guest.'
        exit 3
    }
    Write-Host 'RESULT: Virtual Display Driver installed and running. Set the Windows display to use it (see GUEST-STEPS.md).'
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
