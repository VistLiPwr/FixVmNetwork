# fix-vm-network.ps1
# Fix VirtualBox OVAs imported to VMware Workstation
# Usage: .\fix-vm-network.ps1 -VMPath "F:\targetmachine"
#        .\fix-vm-network.ps1 -VMPath "F:\targetmachine" -NetworkType bridged
param(
    [Parameter(Mandatory=$true)][string]$VMPath,
    [string]$NetworkType = "nat"
)

$ErrorActionPreference = "Continue"

function Fix-VMXFile($VMXPath) {
    Write-Host "  [VMX] $VMXPath" -ForegroundColor Cyan
    $vmx = Get-Content $VMXPath -Raw -Encoding UTF8
    if ($vmx -notmatch 'ethernet0\.connectionType') {
        $vmx = $vmx -replace '(ethernet0\.addressType\s*=\s*"[^"]*")', "ethernet0.connectionType = `"$NetworkType`"`r`n`$1"
    } else {
        $vmx = $vmx -replace 'ethernet0\.connectionType\s*=\s*"[^"]*"', "ethernet0.connectionType = `"$NetworkType`""
    }
    if ($vmx -match 'guestos\s*=\s*"other"') {
        $vmx = $vmx -replace 'guestos\s*=\s*"other"', 'guestos = "debian10-64"'
    }
    [System.IO.File]::WriteAllText($VMXPath, $vmx, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  [VMX] network=$NetworkType" -ForegroundColor Green
}

function Fix-LinuxDisk($VMDKPath) {
    Write-Host "  [DISK] $VMDKPath" -ForegroundColor Cyan
    $wslPath = "/mnt/" + $VMDKPath[0].ToString().ToLower() + $VMDKPath.Substring(2).Replace('\', '/')

    # Build commands as array, then join with LF
    $lines = @(
        'qemu-nbd --disconnect /dev/nbd0 2>/dev/null',
        'modprobe nbd 2>/dev/null',
        "qemu-nbd --connect=/dev/nbd0 $wslPath || { echo ERR_NBD; exit 1; }",
        'sleep 1',
        'PART=$(fdisk -l /dev/nbd0 2>/dev/null | grep -E "^/dev/nbd0p[0-9]+.*Linux" | grep -v swap | head -1 | sed "s/ .*//")',
        'if [ -z "$PART" ]; then echo ERR_PART; qemu-nbd --disconnect /dev/nbd0; exit 1; fi',
        'mkdir -p /mnt/vmfix',
        'mount "$PART" /mnt/vmfix || { echo ERR_MOUNT; qemu-nbd --disconnect /dev/nbd0; exit 1; }',
        'if [ -f /mnt/vmfix/etc/network/interfaces ]; then',
        "  sed -i 's/enp0s3/eth0/g; s/allow-hotplug/auto/g' /mnt/vmfix/etc/network/interfaces",
        '  echo FIX_interfaces',
        'else echo SKIP_interfaces; fi',
        'if [ -f /mnt/vmfix/etc/default/grub ] && ! grep -q net.ifnames=0 /mnt/vmfix/etc/default/grub; then',
        '  sed -i ''s|GRUB_CMDLINE_LINUX_DEFAULT="quiet"|GRUB_CMDLINE_LINUX_DEFAULT="quiet net.ifnames=0 biosdevname=0"|'' /mnt/vmfix/etc/default/grub',
        '  sed -i ''s|GRUB_CMDLINE_LINUX_DEFAULT=""|GRUB_CMDLINE_LINUX_DEFAULT="quiet net.ifnames=0 biosdevname=0"|'' /mnt/vmfix/etc/default/grub',
        '  echo FIX_grub_default',
        'else echo SKIP_grub_default; fi',
        "if [ -f /mnt/vmfix/boot/grub/grub.cfg ] && ! grep -q 'net.ifnames=0' /mnt/vmfix/boot/grub/grub.cfg; then",
        "  sed -i 's|ro  quiet|ro net.ifnames=0 biosdevname=0 quiet|g' /mnt/vmfix/boot/grub/grub.cfg",
        "  sed -i 's|ro single |ro net.ifnames=0 biosdevname=0 single |g' /mnt/vmfix/boot/grub/grub.cfg",
        '  echo FIX_grub_cfg',
        'else echo SKIP_grub_cfg; fi',
        'umount /mnt/vmfix',
        'qemu-nbd --disconnect /dev/nbd0',
        'echo DONE'
    )

    # Join lines and strip any CR (file may have been saved with CRLF)
    $script = ($lines -join "`n") -replace "`r", ""
    $result = $script | wsl -d kali-linux -u root -- bash 2>$null
    Write-Host "  [DISK] $result" -ForegroundColor Green
}

# --- Main ---
Write-Host "`n=== VM Network Fix Tool ===`nPath: $VMPath`nNetwork: $NetworkType`n" -ForegroundColor Magenta

wsl -d kali-linux -u root -- bash -c "apt-get install -y qemu-utils 2>/dev/null; echo ready" 2>$null | Out-Null
Write-Host "WSL ready" -ForegroundColor Green

if (-not (Test-Path $VMPath -PathType Container)) {
    Write-Host "ERROR: Path not found: $VMPath" -ForegroundColor Red; exit 1
}

$vmxFiles = Get-ChildItem -Path $VMPath -Filter "*.vmx" -Recurse -ErrorAction SilentlyContinue
if ($vmxFiles.Count -eq 0) { Write-Host "No VMX files found." -ForegroundColor Yellow; exit 0 }

foreach ($vmx in $vmxFiles) {
    Write-Host "`n--- $($vmx.BaseName) ---" -ForegroundColor Magenta
    Fix-VMXFile $vmx.FullName

    $vmdkFiles = Get-ChildItem -Path $vmx.DirectoryName -Filter "*.vmdk" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(-s\d+|-delta|0000\d+)\.vmdk' -and $_.Length -gt 100KB }

    foreach ($vmdk in $vmdkFiles) {
        Fix-LinuxDisk $vmdk.FullName.Replace('\', '/')
        break
    }
}

Write-Host "`n=== Done ===`nBoot VM: interface 'eth0' with DHCP on any hypervisor.`n" -ForegroundColor Magenta
