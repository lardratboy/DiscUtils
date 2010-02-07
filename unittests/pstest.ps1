#
#  Copyright (c) 2008-2009, Kenneth Bell
#
#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#  DEALINGS IN THE SOFTWARE.
#

#
# Test script for .NET DiscUtils
# ------------------------------
#
# This script is a test harness for the PowerShell interface in DiscUtils, and
# also for the NTFS implementation in DiscUtils.  The script performs operations
# on the virtual file system, and periodically runs chkdsk to verify the filesystem
# has not been corrupted.
#




#
#-- Variables
#
$DiscUtilsModule = "c:\work\codeplex\discutils\trunk\utils\DiscUtils.PowerShell\bin\release\discutils.psd1"
$diskfile = "C:\temp\newdisk.vhd"
$testdrive = "Q"
$sig = 0x12345657
$verbose = $false;

#
#-- Configure PowerShell
#
$ErrorActionPreference = "Stop"
Import-Module $DiscUtilsModule

#
#-- Define Functions
#
function Trace
{
    param($prefix, $lines)

    if($verbose)
    {
        foreach($line in $lines)
        {
            Write-Host ("$prefix" + ":" + "$line")
        }
    }
}

function InvokeDiskpart
{
    param($script)

    Trace "DISKPART" $script

    $script | out-file -encoding ASCII -filepath c:\temp\diskpartscript.txt
    $output = $(diskpart /s c:\temp\diskpartscript.txt)
    if(-not $?)
    {
        Write-Error "DISKPART script failed: $script"
        Exit
    }
}

function AttachDisk
{
    param($disk, $drive)
    InvokeDiskpart @("select vdisk file=$disk", "attach vdisk readonly")
    sleep -seconds 1
    InvokeDiskpart @("select vdisk file=$disk", "select partition=1", "assign letter=$drive")
}

function DetachDisk
{
    param($disk)
    InvokeDiskpart @("select vdisk file=$disk", "detach vdisk")
}

function RunChkdsk
{
    Trace "CHKDSK" "Checking $diskfile as $testdrive"

    AttachDisk $diskfile $testdrive
    $chkdskOutput = chkdsk ("$testdrive" + ":")
    if(-not $?)
    {
        $chkdskOutput | Write-Warning
        Write-Error "CHKDSK failed!"
        Exit
    }
    
    DetachDisk $diskfile
}

function CheckAdmin
{
    $account = new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $account.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        Write-Error "This script must be run as an administrator"
        Exit
    }
}

function CreateDisk
{
    param($size)
    New-VirtualDisk $diskfile -Type VHD-dynamic -Size $size | out-null
    New-PSDrive vd -PSProvider VirtualDisk -Root $diskfile -ReadWrite -Scope Global | out-null
    $disk = Get-Item vd:\
    Initialize-VirtualDisk -InputObject $disk -Signature $sig | out-null
    $vol = New-Volume -InputObject $disk -Type WindowsNtfs
    Format-Volume -InputObject $vol -Filesystem Ntfs -Label "foo"
}

function Checkpoint
{
    Remove-PSDrive vd -Scope Global
    RunChkdsk
    New-PSDrive vd -PSProvider VirtualDisk -Root $diskfile -ReadWrite -Scope Global | out-null
}


#
#-- Main logic
#

$TempMountRoot = ("$testdrive" + ":\")
$ClusterData = New-Object byte[] 4096
$FourMB = New-Object byte[] 4194304
$NumFiles = 500

# Check we're elevated
CheckAdmin


# Clean up from aborted prior runs
if([System.IO.Directory]::Exists($TempMountRoot))
{
    "Detaching disk ($TempMountRoot)..."
    DetachDisk $diskfile
}


CreateDisk 10MB


"Creating TestFile.txt"
New-Item -Type file vd:\Volume0\TestFile.txt
Set-Content vd:\Volume0\TestFile.txt "This is a test file"

Checkpoint

"Creating file.bin"
New-Item -type file vd:\Volume0\file.bin
Set-Content vd:\Volume0\file.bin $ClusterData

Checkpoint

"Removing file.bin"
Remove-Item vd:\Volume0\file.bin

Checkpoint

"Creating $($NumFiles * 2) files"
for($i = 0; $i -lt $NumFiles; $i++)
{
    # Create some files with common prefix, and some with varying prefixes to
    # exercise directory hash tree a little.
    New-Item -type file "vd:\Volume0\file${i}.bin"
    Set-Content vd:\Volume0\file${i}.bin $ClusterData
    New-Item -type file "vd:\Volume0\${i}file.bin"
    Set-Content vd:\Volume0\${i}file.bin $ClusterData
}

Checkpoint

#"Creating fragmented file"
#for($i = 0; $i -lt $NumFiles; $i++)
#{
#    Remove-Item "vd:\Volume0\file${i}.bin"
#}
#New-Item -type file "vd:\Volume0\fragfile.bin"
#Set-Content "vd:\Volume0\fragfile.bin" $FourMB


# Cleanup
Remove-PSDrive vd
RunChkdsk
