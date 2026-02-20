# .SYNOPSIS
# Continuous connectivity monitor to a file server & domain controller.
#
# .DESCRIPTION
# Performs every CheckFrequency ms:
#   1. ICMP ping (IP + FQDN) for both targets.
#   2. DNS look-ups via primary NIC DNS and DC DNS (cache bypass).
#   3. Lightweight SMB share probe (first entry only) (Windows-only).
#
# Creates quarter-hour CSV logs for each test category and an hourly error-only CSV.
# Keeps 48-h history and purges older files.
#
# .PARAMETER FileServerFQDN
# The FQDN of the file/print server to monitor (e.g., "FILESERVERNAME.domain.net").
#
# .PARAMETER FileServerIP
# The IP address of the file/print server to monitor (e.g., "10.68.2.35").
#
# .PARAMETER FileServerShare
# The UNC path to the share on the file/print server to test (e.g.,
# "\\FILESERVERNAME.domain.net\Plant").
#
# .PARAMETER DomainControllerFQDN
# The FQDN of the Central US domain controller to monitor (e.g.,
# "CENTRALDC.domain.net").
#
# .PARAMETER DomainControllerIP
# The IP address of the Central US domain controller to monitor (e.g., "10.4.4.4").
#
# .PARAMETER DomainControllerShare
# The UNC path to the test share on the Central US domain controller
# "\\CENTRALDC.domain.net\TESTSHARE").
#
# .PARAMETER LogDirectory
# The root directory for all log files. The script will create subdirectories for each
# log type (e.g., "C:\Logs\ConnMon").
#
# .PARAMETER PrimaryDNSServer
# Optional: The IP address of the primary DNS server. If not provided, the script will
# attempt to detect it from the system's NIC configuration.
#
# .PARAMETER CheckFrequency
# The frequency of checks in milliseconds (default: 2500, range: 500-60000).
#
# .PARAMETER PingPacketSize
# The ICMP ping packet payload size in bytes (default: 56, range: 32-65500).
#
# .PARAMETER PingTimeout
# The timeout for ping replies in milliseconds (default: 3000, range: 500-10000).
#
# .PARAMETER ShareAccessTimeout
# The timeout for share access tests in milliseconds (default: 15000, range:
# 5000-60000).
#
# .PARAMETER MaxRuntimeMinutes
# Optional: The maximum runtime in minutes before auto-stop (default: 0, meaning
# indefinite).
#
# .EXAMPLE
# .\Watch-Network.ps1 `
#   -FileServerFQDN FILE1.corp.local -FileServerIP 10.1.2.3 `
#   -FileServerShare \\FILE1.corp.local\Plant `
#   -DomainControllerFQDN DC1.corp.local -DomainControllerIP 10.1.0.10 `
#   -DomainControllerShare \\DC1.corp.local\TestShare `
#   -LogDirectory C:\Logs\ConnMon -CheckFrequency 2500
#
# Starts continuous monitoring of the specified file server and domain controller
# with default settings (2500ms check frequency, 56-byte ping packets, 3000ms
# ping timeout). Creates CSV log files in C:\Logs\ConnMon organized by test
# type. Press Ctrl+C to stop.
#
# .EXAMPLE
# .\Watch-Network.ps1 `
#   -FileServerFQDN FILE1.corp.local -FileServerIP 10.1.2.3 `
#   -FileServerShare \\FILE1.corp.local\Plant `
#   -DomainControllerFQDN DC1.corp.local -DomainControllerIP 10.1.0.10 `
#   -DomainControllerShare \\DC1.corp.local\TestShare `
#   -LogDirectory C:\Logs\ConnMon -PrimaryDNSServer 10.1.0.10
#
# Runs the monitor with an explicitly specified primary DNS server instead of
# auto-detecting it from the system NIC configuration.
#
# .EXAMPLE
# .\Watch-Network.ps1 `
#   -FileServerFQDN FILE1.corp.local -FileServerIP 10.1.2.3 `
#   -FileServerShare \\FILE1.corp.local\Plant `
#   -DomainControllerFQDN DC1.corp.local -DomainControllerIP 10.1.0.10 `
#   -DomainControllerShare \\DC1.corp.local\TestShare `
#   -LogDirectory C:\Logs\ConnMon -MaxRuntimeMinutes 60
#
# Runs the monitor for a maximum of 60 minutes, then exits cleanly. Useful for
# scheduled diagnostics or time-limited troubleshooting sessions.
#
# .INPUTS
# None. You can't pipe objects to Watch-Network.ps1.
#
# .OUTPUTS
# None. Watch-Network.ps1 does not generate pipeline output. The script
# writes CSV log files to the directory specified by the -LogDirectory
# parameter and uses Write-Verbose, Write-Warning, and Write-Error for
# console feedback.
#
# Exit codes:
# 0 - Clean exit (Ctrl+C or MaxRuntimeMinutes reached)
# 1 - Fatal error (missing module, permission failure, or startup error)
#
# .NOTES
# Supported PowerShell Versions:
# - Windows PowerShell 5.1 with .NET Framework 4.6.2 or newer
# - PowerShell 7.4.x
# - PowerShell 7.5.x
#
# Supported Operating Systems:
# - Windows (all versions supporting the required PowerShell version)
# - macOS (PowerShell 7.x only)
# - Linux (PowerShell 7.x only)
#
# Module Dependencies:
# - ThreadJob
#
# Run under an account that can read the two shares.
# SYSTEM normally lacks those rights unless shares grant computer-account
# access. Tested on Windows Server 2022.
#
# PLATFORM COMPATIBILITY:
# The Authentication and Share Access test uses Get-ChildItem with UNC paths,
# which is a feature specific to the Windows operating system. This test will be
# automatically skipped when the script is run on Linux or macOS. All other
# tests (Ping, DNS) are cross-platform.
#
# # To schedule this script, use a command like the following, replacing arguments and
# # the user account:
# $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -File "C:\Scripts\Watch-Network.ps1" -FileServerFQDN "..." -FileServerIP "..." -LogDirectory "..." ...'
# $trigger = New-ScheduledTaskTrigger -AtStartup
# $principal = New-ScheduledTaskPrincipal -UserId 'DOMAIN\svc-Watch' -LogonType Password
# Register-ScheduledTask -TaskName 'ConnectivityMonitor' -Description 'Monitors connectivity to file server and DC.' -Action $action -Trigger $trigger -Principal $principal -Settings (New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable)
#
# On non-Windows platforms (Linux/macOS), Ctrl+C terminates the script with exit code 1
# (due to SIGINT), but cleanup and logging still occur. Share access tests are skipped.
# Ensure 'dig' is installed for DNS resolution (e.g., 'dnsutils' on Debian/Ubuntu or
# 'bind-utils' on RHEL/CentOS).
#
# Version: 1.1.20260220.0

#region License ####################################################################
# Copyright (c) 2025-2026 Frank Lesniak
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be included in all copies
# or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
# CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
# OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#endregion License ####################################################################

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FileServerFQDN,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')][string]$FileServerIP,
    [Parameter(Mandatory = $true)][string]$FileServerShare,
    [Parameter(Mandatory = $true)][string]$DomainControllerFQDN,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')][string]$DomainControllerIP,
    [Parameter(Mandatory = $true)][string]$DomainControllerShare,
    [Parameter(Mandatory = $true)][string]$LogDirectory,
    [Parameter(Mandatory = $false)][string]$PrimaryDNSServer = '',
    [Parameter(Mandatory = $false)][ValidateRange(500, 60000)][int]$CheckFrequency = 2500,
    [Parameter(Mandatory = $false)][ValidateRange(32, 65500)][int]$PingPacketSize = 56,
    [Parameter(Mandatory = $false)][ValidateRange(500, 10000)][int]$PingTimeout = 3000,
    [Parameter(Mandatory = $false)][ValidateRange(5000, 60000)][int]$ShareAccessTimeout = 15000,
    [Parameter(Mandatory = $false)][int]$MaxRuntimeMinutes = 0
)

function Get-PSVersion {
    # .SYNOPSIS
    # Returns the version of PowerShell that is running.
    #
    # .DESCRIPTION
    # The function outputs a [version] object representing the version of
    # PowerShell that is running. This function detects the PowerShell
    # runtime version but does not detect the underlying .NET Framework or
    # .NET Core version.
    #
    # On versions of PowerShell greater than or equal to version 2.0, this
    # function returns the equivalent of $PSVersionTable.PSVersion
    #
    # PowerShell 1.0 does not have a $PSVersionTable variable, so this
    # function returns [version]('1.0') on PowerShell 1.0.
    #
    # .EXAMPLE
    # $versionPS = Get-PSVersion
    # # $versionPS now contains the version of PowerShell that is running.
    # # On versions of PowerShell greater than or equal to version 2.0,
    # # this function returns the equivalent of $PSVersionTable.PSVersion.
    #
    # .EXAMPLE
    # $versionPS = Get-PSVersion
    # if ($versionPS.Major -ge 2) {
    #     Write-Host "PowerShell 2.0 or later detected"
    # } else {
    #     Write-Host "PowerShell 1.0 detected"
    # }
    # # This example demonstrates storing the returned version object in a
    # # variable and using it to make conditional decisions based on
    # # PowerShell version. The returned [version] object has properties
    # # like Major, Minor, Build, and Revision that can be used for
    # # version-based logic.
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSVersion.
    #
    # .OUTPUTS
    # System.Version. Get-PSVersion returns a [version] value indicating
    # the version of PowerShell that is running.
    #
    # .NOTES
    # Version: 1.0.20251231.0
    #
    # This function is compatible with all versions of PowerShell: Windows
    # PowerShell (v1.0 - 5.1), PowerShell Core 6.x, and PowerShell 7.x and
    # newer. It is compatible with Windows, macOS, and Linux.
    #
    # This function has no parameters.

    param()

    #region License ####################################################
    # Copyright (c) 2025 Frank Lesniak
    #
    # Permission is hereby granted, free of charge, to any person obtaining
    # a copy of this software and associated documentation files (the
    # "Software"), to deal in the Software without restriction, including
    # without limitation the rights to use, copy, modify, merge, publish,
    # distribute, sublicense, and/or sell copies of the Software, and to
    # permit persons to whom the Software is furnished to do so, subject to
    # the following conditions:
    #
    # The above copyright notice and this permission notice shall be
    # included in all copies or substantial portions of the Software.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
    # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    # SOFTWARE.
    #endregion License ####################################################

    if (Test-Path variable:\PSVersionTable) {
        return ($PSVersionTable.PSVersion)
    } else {
        return ([version]('1.0'))
    }
}

function Test-Windows {
    # .SYNOPSIS
    # Returns $true if PowerShell is running on Windows; otherwise, returns
    # $false.
    #
    # .DESCRIPTION
    # Returns a boolean ($true or $false) indicating whether the current
    # PowerShell session is running on Windows. This function is useful for
    # writing scripts that need to behave differently on Windows and non-
    # Windows platforms (Linux, macOS, etc.). Additionally, this function is
    # useful because it works on Windows PowerShell 1.0 through 5.1, which do
    # not have the $IsWindows global variable.
    #
    # .PARAMETER PSVersion
    # This parameter is optional; if supplied, it must be the version number of
    # the running version of PowerShell. If the version of PowerShell is
    # already known, it can be passed in to this function to avoid the overhead
    # of unnecessarily determining the version of PowerShell. If this parameter
    # is not supplied, the function will determine the version of PowerShell
    # that is running as part of its processing.
    #
    # .EXAMPLE
    # $boolIsWindows = Test-Windows
    #
    # .EXAMPLE
    # # The version of PowerShell is known to be 2.0 or above:
    # $boolIsWindows = Test-Windows -PSVersion $PSVersionTable.PSVersion
    #
    # .INPUTS
    # None. You can't pipe objects to Test-Windows.
    #
    # .OUTPUTS
    # System.Boolean. Test-Windows returns a boolean value indicating whether
    # PowerShell is running on Windows. $true means that PowerShell is running
    # on Windows; $false means that PowerShell is not running on Windows.
    #
    # .NOTES
    # This function also supports the use of a positional parameter instead of
    # a named parameter. If a positional parameter is used instead of a named
    # parameter, then one positional parameter is required: it must be the
    # version number of the running version of PowerShell. If the version of
    # PowerShell is already known, it can be passed in to this function to
    # avoid the overhead of unnecessarily determining the version of
    # PowerShell. If this parameter is not supplied, the function will
    # determine the version of PowerShell that is running as part of its
    # processing.
    #
    # This function supports Windows PowerShell 1.0 with .NET Framework 2.0 or
    # newer, newer versions of Windows PowerShell (at least up to and including
    # Windows PowerShell 5.1 with .NET Framework 4.8 or newer), PowerShell Core
    # 6.x, and PowerShell 7.x. This function supports Windows, and when run on
    # PowerShell Core 6.x or PowerShell 7.x, also supports macOS and Linux.
    #
    # Version: 1.1.20260109.0

    param (
        [version]$PSVersion = ([version]'0.0')
    )

    #region License ########################################################
    # Copyright (c) 2026 Frank Lesniak
    #
    # Permission is hereby granted, free of charge, to any person obtaining a
    # copy of this software and associated documentation files (the
    # "Software"), to deal in the Software without restriction, including
    # without limitation the rights to use, copy, modify, merge, publish,
    # distribute, sublicense, and/or sell copies of the Software, and to permit
    # persons to whom the Software is furnished to do so, subject to the
    # following conditions:
    #
    # The above copyright notice and this permission notice shall be included
    # in all copies or substantial portions of the Software.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    # OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
    # NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
    # DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
    # OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
    # USE OR OTHER DEALINGS IN THE SOFTWARE.
    #endregion License ########################################################

    function Get-PSVersion {
        # .SYNOPSIS
        # Returns the version of PowerShell that is running.
        #
        # .DESCRIPTION
        # The function outputs a [version] object representing the version of
        # PowerShell that is running. This function detects the PowerShell
        # runtime version but does not detect the underlying .NET Framework or
        # .NET Core version.
        #
        # On versions of PowerShell greater than or equal to version 2.0, this
        # function returns the equivalent of $PSVersionTable.PSVersion
        #
        # PowerShell 1.0 does not have a $PSVersionTable variable, so this
        # function returns [version]('1.0') on PowerShell 1.0.
        #
        # .EXAMPLE
        # $versionPS = Get-PSVersion
        # # $versionPS now contains the version of PowerShell that is running.
        # # On versions of PowerShell greater than or equal to version 2.0,
        # # this function returns the equivalent of $PSVersionTable.PSVersion.
        #
        # .EXAMPLE
        # $versionPS = Get-PSVersion
        # if ($versionPS.Major -ge 2) {
        #     Write-Host "PowerShell 2.0 or later detected"
        # } else {
        #     Write-Host "PowerShell 1.0 detected"
        # }
        # # This example demonstrates storing the returned version object in a
        # # variable and using it to make conditional decisions based on
        # # PowerShell version. The returned [version] object has properties
        # # like Major, Minor, Build, and Revision that can be used for
        # # version-based logic.
        #
        # .INPUTS
        # None. You can't pipe objects to Get-PSVersion.
        #
        # .OUTPUTS
        # System.Version. Get-PSVersion returns a [version] value indicating
        # the version of PowerShell that is running.
        #
        # .NOTES
        # Version: 1.0.20251231.0
        #
        # This function is compatible with all versions of PowerShell: Windows
        # PowerShell (v1.0 - 5.1), PowerShell Core 6.x, and PowerShell 7.x and
        # newer. It is compatible with Windows, macOS, and Linux.
        #
        # This function has no parameters.

        param()

        #region License ####################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining
        # a copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to
        # permit persons to whom the Software is furnished to do so, subject to
        # the following conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
        # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
        # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        # SOFTWARE.
        #endregion License ####################################################

        if (Test-Path variable:\PSVersionTable) {
            return ($PSVersionTable.PSVersion)
        } else {
            return ([version]('1.0'))
        }
    }

    $versionPS = $PSVersion
    if ($null -eq $versionPS -or $versionPS -eq ([version]'0.0')) {
        $versionPS = Get-PSVersion
    }

    if ($versionPS.Major -ge 6) {
        return $IsWindows
    } else {
        return $true
    }
}

function Get-PrimaryDnsServer {
    # .SYNOPSIS
    # Retrieves the IP address of the primary DNS server configured on the system.
    #
    # .DESCRIPTION
    # This function detects the primary DNS server IP address based on the
    # system configuration. On Windows, it prefers using Get-DnsClientServerAddress
    # falling back to WMI/CIM if necessary. On non-Windows (Linux/macOS), it
    # parses /etc/resolv.conf.
    #
    # .PARAMETER OSIsWindows
    # Optional: A precomputed boolean indicating if the OS is Windows. If not
    # provided, the function will detect it.
    #
    # .EXAMPLE
    # $strPrimaryDnsServer = Get-PrimaryDnsServer -OSIsWindows $true
    #
    # .INPUTS
    # None.
    #
    # .OUTPUTS
    # System.String. Returns the IP address as a string, or null if not found.
    #
    # .NOTES
    # This function requires administrative privileges on Windows for WMI/CIM
    # access in legacy fallback mode.
    #
    # Version: 1.0.20260220.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        $OSIsWindows
    )

    function Test-Windows {
        # .SYNOPSIS
        # Returns $true if PowerShell is running on Windows; otherwise, returns
        # $false.
        #
        # .DESCRIPTION
        # Returns a boolean ($true or $false) indicating whether the current
        # PowerShell session is running on Windows. This function is useful for
        # writing scripts that need to behave differently on Windows and non-
        # Windows platforms (Linux, macOS, etc.). Additionally, this function is
        # useful because it works on Windows PowerShell 1.0 through 5.1, which do
        # not have the $IsWindows global variable.
        #
        # .PARAMETER PSVersion
        # This parameter is optional; if supplied, it must be the version number of
        # the running version of PowerShell. If the version of PowerShell is
        # already known, it can be passed in to this function to avoid the overhead
        # of unnecessarily determining the version of PowerShell. If this parameter
        # is not supplied, the function will determine the version of PowerShell
        # that is running as part of its processing.
        #
        # .EXAMPLE
        # $boolIsWindows = Test-Windows
        #
        # .EXAMPLE
        # # The version of PowerShell is known to be 2.0 or above:
        # $boolIsWindows = Test-Windows -PSVersion $PSVersionTable.PSVersion
        #
        # .INPUTS
        # None. You can't pipe objects to Test-Windows.
        #
        # .OUTPUTS
        # System.Boolean. Test-Windows returns a boolean value indiciating whether
        # PowerShell is running on Windows. $true means that PowerShell is running
        # on Windows; $false means that PowerShell is not running on Windows.
        #
        # .NOTES
        # This function also supports the use of a positional parameter instead of
        # a named parameter. If a positional parameter is used instead of a named
        # parameter, then one positional parameter is required: it must be the
        # version number of the running version of PowerShell. If the version of
        # PowerShell is already known, it can be passed in to this function to
        # avoid the overhead of unnecessarily determining the version of
        # PowerShell. If this parameter is not supplied, the function will
        # determine the version of PowerShell that is running as part of its
        # processing.
        #
        # Version: 1.1.20250106.1

        #region License ########################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining a
        # copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to permit
        # persons to whom the Software is furnished to do so, subject to the
        # following conditions:
        #
        # The above copyright notice and this permission notice shall be included
        # in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
        # OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
        # NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
        # DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
        # OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
        # USE OR OTHER DEALINGS IN THE SOFTWARE.
        #endregion License ########################################################

        param (
            [version]$PSVersion = ([version]'0.0')
        )

        function Get-PSVersion {
            # .SYNOPSIS
            # Returns the version of PowerShell that is running.
            #
            # .DESCRIPTION
            # The function outputs a [version] object representing the version of
            # PowerShell that is running.
            #
            # On versions of PowerShell greater than or equal to version 2.0, this
            # function returns the equivalent of $PSVersionTable.PSVersion
            #
            # PowerShell 1.0 does not have a $PSVersionTable variable, so this
            # function returns [version]('1.0') on PowerShell 1.0.
            #
            # .EXAMPLE
            # $versionPS = Get-PSVersion
            # # $versionPS now contains the version of PowerShell that is running.
            # # On versions of PowerShell greater than or equal to version 2.0,
            # # this function returns the equivalent of $PSVersionTable.PSVersion.
            #
            # .INPUTS
            # None. You can't pipe objects to Get-PSVersion.
            #
            # .OUTPUTS
            # System.Version. Get-PSVersion returns a [version] value indiciating
            # the version of PowerShell that is running.
            #
            # .NOTES
            # Version: 1.0.20250106.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            if (Test-Path variable:\PSVersionTable) {
                return ($PSVersionTable.PSVersion)
            } else {
                return ([version]('1.0'))
            }
        }

        if ($PSVersion -ne ([version]'0.0')) {
            if ($PSVersion.Major -ge 6) {
                return $IsWindows
            } else {
                return $true
            }
        } else {
            $versionPS = Get-PSVersion
            if ($versionPS.Major -ge 6) {
                return $IsWindows
            } else {
                return $true
            }
        }
    }

    if ($null -eq $OSIsWindows) {
        $boolIsWindows = Test-Windows
    } else {
        $boolIsWindows = $OSIsWindows
    }

    # This function uses the best available method based on the sensed environment.
    if ($boolIsWindows) {
        # Modern Windows PowerShell (5.1) has the DnsClient module.
        try {
            # Attempt the modern, preferred cmdlet first.
            return (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                    Where-Object { $_.ServerAddresses } |
                    Select-Object -ExpandProperty ServerAddresses -First 1)
        } catch {
            Write-Warning "Get-DnsClientServerAddress failed. Falling back to WMI/CIM for legacy compatibility."
            # Legacy Windows (PS < 5) or fallback for modern Windows
            try {
                $wmiParams = @{
                    Class = 'Win32_NetworkAdapterConfiguration'
                    Filter = 'IPEnabled=TRUE'
                    ErrorAction = 'Stop'
                }
                $adapters = if ($PSVersionTable.PSVersion.Major -gt 2) { Get-CimInstance @wmiParams } else { Get-WmiObject @wmiParams }
                return ($adapters |
                        Where-Object { $_.DNSServerSearchOrder } |
                        Select-Object -ExpandProperty DNSServerSearchOrder -First 1)
            } catch {
                Write-Warning "Failed to get DNS server from WMI/CIM. Error: $($_.Exception.Message)"
                return $null
            }
        }
    } else {
        # Linux/macOS logic
        $resolvConfPath = '/etc/resolv.conf'
        if (Test-Path -LiteralPath $resolvConfPath) {
            try {
                return (Get-Content -LiteralPath $resolvConfPath -ErrorAction Stop |
                        Where-Object { $_ -match '^\s*nameserver\s+' } |
                        Select-Object -First 1).Split(' ')[1]
            } catch {
                Write-Warning "Failed to read or parse '$resolvConfPath'. Error: $($_.Exception.Message)"
                return $null
            }
        }
    }
}

function Invoke-DnsQuery {
    # .SYNOPSIS
    # Performs a DNS query for a hostname against a specified DNS server.
    #
    # .DESCRIPTION
    # Attempts to resolve a hostname to an A record IP address using platform-
    # specific methods: Resolve-DnsName on Windows (if available), nslookup on
    # Windows legacy fallback, or dig on non-Windows. Bypasses local cache.
    #
    # .PARAMETER HostName
    # The FQDN to resolve.
    #
    # .PARAMETER DnsServer
    # The IP address of the server to query.
    #
    # .PARAMETER ResolveDnsNameCommandAvailable
    # A boolean indicating if Resolve-DnsName cmdlet is available.
    #
    # .PARAMETER OSIsWindows
    # Optional: A precomputed boolean if the OS is Windows.
    #
    # .EXAMPLE
    # $result = Invoke-DnsQuery -HostName "example.com" -DnsServer "8.8.8.8"
    # -ResolveDnsNameCommandAvailable $true -OSIsWindows $true
    #
    # .INPUTS
    # None. You can't pipe objects to Invoke-DnsQuery.
    #
    # .OUTPUTS
    # A hashtable with Success (bool), IPAddress (string), and Error (string).
    #
    # .NOTES
    # On non-Windows, requires 'dig' to be installed.
    #
    # Version: 1.0.20260220.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$HostName,
        [string]$DnsServer,
        $ResolveDnsNameCommandAvailable,
        $OSIsWindows
    )

    function Test-Windows {
        # .SYNOPSIS
        # Returns $true if PowerShell is running on Windows; otherwise, returns
        # $false.
        #
        # .DESCRIPTION
        # Returns a boolean ($true or $false) indicating whether the current
        # PowerShell session is running on Windows. This function is useful for
        # writing scripts that need to behave differently on Windows and non-
        # Windows platforms (Linux, macOS, etc.). Additionally, this function is
        # useful because it works on Windows PowerShell 1.0 through 5.1, which do
        # not have the $IsWindows global variable.
        #
        # .PARAMETER PSVersion
        # This parameter is optional; if supplied, it must be the version number of
        # the running version of PowerShell. If the version of PowerShell is
        # already known, it can be passed in to this function to avoid the overhead
        # of unnecessarily determining the version of PowerShell. If this parameter
        # is not supplied, the function will determine the version of PowerShell
        # that is running as part of its processing.
        #
        # .EXAMPLE
        # $boolIsWindows = Test-Windows
        #
        # .EXAMPLE
        # # The version of PowerShell is known to be 2.0 or above:
        # $boolIsWindows = Test-Windows -PSVersion $PSVersionTable.PSVersion
        #
        # .INPUTS
        # None. You can't pipe objects to Test-Windows.
        #
        # .OUTPUTS
        # System.Boolean. Test-Windows returns a boolean value indiciating whether
        # PowerShell is running on Windows. $true means that PowerShell is running
        # on Windows; $false means that PowerShell is not running on Windows.
        #
        # .NOTES
        # This function also supports the use of a positional parameter instead of
        # a named parameter. If a positional parameter is used instead of a named
        # parameter, then one positional parameter is required: it must be the
        # version number of the running version of PowerShell. If the version of
        # PowerShell is already known, it can be passed in to this function to
        # avoid the overhead of unnecessarily determining the version of
        # PowerShell. If this parameter is not supplied, the function will
        # determine the version of PowerShell that is running as part of its
        # processing.
        #
        # Version: 1.1.20250106.1

        #region License ########################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining a
        # copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to permit
        # persons to whom the Software is furnished to do so, subject to the
        # following conditions:
        #
        # The above copyright notice and this permission notice shall be included
        # in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
        # OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
        # NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
        # DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
        # OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
        # USE OR OTHER DEALINGS IN THE SOFTWARE.
        #endregion License ########################################################

        param (
            [version]$PSVersion = ([version]'0.0')
        )

        function Get-PSVersion {
            # .SYNOPSIS
            # Returns the version of PowerShell that is running.
            #
            # .DESCRIPTION
            # The function outputs a [version] object representing the version of
            # PowerShell that is running.
            #
            # On versions of PowerShell greater than or equal to version 2.0, this
            # function returns the equivalent of $PSVersionTable.PSVersion
            #
            # PowerShell 1.0 does not have a $PSVersionTable variable, so this
            # function returns [version]('1.0') on PowerShell 1.0.
            #
            # .EXAMPLE
            # $versionPS = Get-PSVersion
            # # $versionPS now contains the version of PowerShell that is running.
            # # On versions of PowerShell greater than or equal to version 2.0,
            # # this function returns the equivalent of $PSVersionTable.PSVersion.
            #
            # .INPUTS
            # None. You can't pipe objects to Get-PSVersion.
            #
            # .OUTPUTS
            # System.Version. Get-PSVersion returns a [version] value indiciating
            # the version of PowerShell that is running.
            #
            # .NOTES
            # Version: 1.0.20250106.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            if (Test-Path variable:\PSVersionTable) {
                return ($PSVersionTable.PSVersion)
            } else {
                return ([version]('1.0'))
            }
        }

        if ($PSVersion -ne ([version]'0.0')) {
            if ($PSVersion.Major -ge 6) {
                return $IsWindows
            } else {
                return $true
            }
        } else {
            $versionPS = Get-PSVersion
            if ($versionPS.Major -ge 6) {
                return $IsWindows
            } else {
                return $true
            }
        }
    }

    if ($null -eq $OSIsWindows) {
        $boolIsWindows = Test-Windows
    } else {
        $boolIsWindows = $OSIsWindows
    }

    if ($null -eq $ResolveDnsNameCommandAvailable) {
        $boolResolveDnsNameCommandAvailable = ($boolIsWindows -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue))
    } else {
        $boolResolveDnsNameCommandAvailable = $ResolveDnsNameCommandAvailable
    }

    # Define the platform-specific command for nslookup
    $strNslookupCommand = if ($boolIsWindows) {
        "nslookup.exe"
    } else {
        "nslookup"
    }

    $result = @{ Success = $false; IPAddress = ''; Error = '' }

    # First, try the modern Windows-native cmdlet.
    if ($boolResolveDnsNameCommandAvailable) {
        try {
            $dnsRecord = Resolve-DnsName -Name $HostName -Server $DnsServer -Type A -DnsOnly -NoHostsFile -ErrorAction Stop
            $result.IPAddress = ($dnsRecord.IPAddress -join ';')
            $result.Success = $true
            return $result
        } catch {
            # This will fail on older OS or if the command fails, so we fall through to nslookup.
            $result.Error = "Resolve-DnsName failed: $($_.Exception.Message)"
        }
    }

    if ($OSIsWindows) {
        # WINDOWS FALLBACK: Use nslookup for legacy Windows or if Resolve-DnsName failed.
        try {
            # The original nslookup parsing logic for Windows remains here.
            $output = & $strNslookupCommand $HostName $DnsServer 2>&1
            $ipAddressLine = $output | Select-String -Pattern 'Addresses:\s+([\d.]+)' -AllMatches

            if ($null -ne $ipAddressLine) {
                if ($ipAddressLine.Matches.Count -eq 1) {
                    # nslookup returned a single "Addresses:" line, which is the expected format.
                    $result.IPAddress = $ipAddressLine.Matches.Groups[1].Value
                    $result.Success = [bool]($result.IPAddress)
                } else {
                    # nslookup returned multiple "Addresses:" lines, which is unexpected.
                    $result.Success = $false
                }
            } else {
                $ipAddressLine = $output | Select-String -Pattern 'Address:\s+([\d.]+)' -AllMatches

                if ($null -ne $ipAddressLine) {
                    # nslookup can return multiple "Address:" lines (e.g., for the server and the result)
                    # The actual result is the last one that is not the server's own IP.
                    if ($ipAddressLine.Matches.Count -ge 2) {
                        $result.IPAddress = $ipAddressLine.Matches | Select-Object -Last 1 | ForEach-Object { $_.Groups[1].Value }
                        $result.Success = [bool]($result.IPAddress)
                        if (-not $result.Success) { $result.Error = "nslookup parsed, but no valid IP was found in the result." }
                    } else {
                        $result.Success = $false
                        $errorLine = ($output | Where-Object { $_ -match '\*\*\*|Non-existent domain|timed out' }) -join '; '
                        $result.Error = if ($errorLine) { $errorLine } else { "nslookup failed to resolve '$HostName'." }
                    }
                } else {
                    $errorLine = ($output | Where-Object { $_ -match '\*\*\*|Non-existent domain|timed out' }) -join '; '
                    $result.Error = if ($errorLine) { $errorLine } else { "nslookup failed to resolve '$HostName'." }
                }
            }
        } catch {
            $result.Error = "Executing nslookup failed: $($_.Exception.Message)"
        }
    } else {
        # NON-WINDOWS: Use dig as the primary method.
        if (-not (Get-Command dig -ErrorAction SilentlyContinue)) {
            $result.Error = "'dig' command not found. On Linux, please install dnsutils (Debian/Ubuntu) or bind-utils (RHEL/CentOS)."
        } else {
            try {
                # Execute dig. The '+short' argument provides clean output (just the IP).
                # We redirect stderr to stdout (2>&1) to capture any error messages from the command.
                $digOutput = & dig +short "@$DnsServer" "$HostName" A 2>&1

                # $LASTEXITCODE is 0 on success.
                if (($LASTEXITCODE -eq 0) -and ($digOutput)) {
                    # Filter for valid IPv4 addresses to ensure clean data.
                    $ipAddresses = $digOutput | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }
                    if ($ipAddresses) {
                        $result.IPAddress = $ipAddresses -join ';'
                        $result.Success = $true
                    } else {
                        # This can happen if dig succeeds but returns a non-A record (e.g., CNAME)
                        $result.Error = "dig ran successfully but returned no valid IPv4 address. Output: $($digOutput -join '; ')"
                    }
                } else {
                    # This block handles command failures (e.g., domain not found).
                    $errorMsg = if ($digOutput) { ($digOutput | Out-String).Trim() } else { "dig command failed with exit code $LASTEXITCODE." }
                    $result.Error = "dig failed to resolve '$HostName'. Details: $errorMsg"
                }
            } catch {
                $result.Error = "A script exception occurred while executing dig: $($_.Exception.Message)"
            }
        }
    }

    Write-Debug ("DNS query result for {0} against {1}: Success={2}, IP={3}" -f $HostName, $DnsServer, $result.Success, $result.IPAddress)
    return $result
}

function Write-LogEntry {
    # .SYNOPSIS
    # Appends a formatted entry to a CSV log file.
    #
    # .DESCRIPTION
    # Writes a timestamped log entry to the appropriate CSV file based on type,
    # creating directories and headers if needed. Details are CSV-escaped.
    #
    # .PARAMETER TimeStamp
    # Optional: The UTC timestamp for the entry (defaults to current UTC time).
    #
    # .PARAMETER BaseLogDirectory
    # Required: The base directory for logs.
    #
    # .PARAMETER LogType
    # Required: The log category (e.g., 'ping', 'dns_primary', 'error').
    #
    # .PARAMETER TestName
    # Required: The name of the test (e.g., 'Ping_FileServer_FQDN').
    #
    # .PARAMETER Result
    # Required: The result status (e.g., 'SUCCESS', 'FAILURE').
    #
    # .PARAMETER Details
    # Required: Additional details; double-quotes are escaped for CSV.
    #
    # .EXAMPLE
    # Write-LogEntry -BaseLogDirectory "C:\Logs" -LogType "ping"
    #     -TestName "Ping_FileServer_IP" -Result "SUCCESS" -Details "RTT: 5ms"
    #
    # .INPUTS
    # None. You can't pipe objects to Write-LogEntry.
    #
    # .OUTPUTS
    # None. Write-LogEntry writes directly to CSV log files on disk.
    #
    # .NOTES
    # Log files are created hourly for 'error' and quarter-hourly for others.
    # Uses UTF-8 encoding.
    #
    # Version: 1.0.20260220.0

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [datetime]$TimeStamp = (Get-Date).ToUniversalTime(),
        [Parameter(Mandatory)][string]$BaseLogDirectory,
        [Parameter(Mandatory)][string]$LogType,
        [Parameter(Mandatory)][string]$TestName,
        [Parameter(Mandatory)][string]$Result,
        [Parameter(Mandatory)][string]$Details
    )

    $strLogSubdirectoryPath = Join-Path -Path $BaseLogDirectory -ChildPath $LogType

    # Use different timestamp formats based on log type
    $strTimeStampFragment = if ($LogType -eq 'error') {
        '{0:yyyyMMdd_HH}' -f $TimeStamp # Hourly for errors
        # e.g., 20250707_14
    } else {
        # Quarter-hourly for others
        $intCurrentQuarterHourStartMinute = [int]([math]::Floor($TimeStamp.Minute / 15)) * 15
        '{0:yyyyMMdd_HH}{1:00}' -f $TimeStamp, $intCurrentQuarterHourStartMinute
        # e.g., 20250707_1445
    }

    $strLogFilePath = Join-Path -Path $strLogSubdirectoryPath -ChildPath "${LogType}_${strTimeStampFragment}.csv"

    # Create directory and header if they don't exist
    if (-not (Test-Path -Path $strLogSubdirectoryPath)) {
        [void](New-Item -Path $strLogSubdirectoryPath -ItemType Directory -Force)
    }
    if (-not (Test-Path -Path $strLogFilePath)) {
        Set-Content -Path $strLogFilePath -Value 'UtcTimestamp,TestName,Result,Details' -Encoding UTF8
    }

    $strTimestampUTCISO8601Format = $TimeStamp.ToUniversalTime().ToString('o')
    # Sanitize details for CSV: double up any double-quotes
    $strReformattedDetails = $Details -replace '"', '""'
    $strLogLine = '"{0}","{1}","{2}","{3}"' -f $strTimestampUTCISO8601Format, $TestName, $Result, $strReformattedDetails

    # Append the content
    Write-Debug ("Writing log entry to: {0}" -f $strLogFilePath)
    Add-Content -Path $strLogFilePath -Value $strLogLine -Encoding UTF8
}

function Remove-OldLogFile {
    # .SYNOPSIS
    # Removes log files older than 48 hours from a directory.
    #
    # .DESCRIPTION
    # Scans the specified directory and deletes files whose LastWriteTimeUtc
    # is older than 48 hours.
    #
    # .PARAMETER Path
    # The directory path to clean.
    #
    # .EXAMPLE
    # Remove-OldLogFile -Path "C:\Logs\ping"
    #
    # .INPUTS
    # None. You can't pipe objects to Remove-OldLogFile.
    #
    # .OUTPUTS
    # None. Remove-OldLogFile deletes files from disk silently.
    #
    # .NOTES
    # Uses -Force and ignores errors during deletion.
    #
    # Version: 1.0.20260220.0

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string]$Path
    )

    Get-ChildItem $Path -File |
        Where-Object { $_.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddHours(-48) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Get-PowerShellModuleUsingHashtable {
    # .SYNOPSIS
    # Gets a list of installed PowerShell modules for each entry in a hashtable.
    #
    # .DESCRIPTION
    # The Get-PowerShellModuleUsingHashtable function steps through each entry in
    # the supplied hashtable and gets a list of installed PowerShell modules for
    # each entry. The list of installed PowerShell modules for each entry is stored
    # in the value of the hashtable entry for that module (as an array).
    #
    # By default, the function operates silently and returns an integer status code
    # without emitting any errors or warnings. Optional switch parameters can be
    # used to output error or warning messages when the operation fails.
    #
    # .PARAMETER ReferenceToHashtable
    # This parameter is required; it is a reference (memory pointer) to a
    # hashtable. The referenced hashtable must have keys that are the names of
    # PowerShell modules and values that are initialized to be empty arrays (@()).
    # After running this function, the list of installed PowerShell modules for
    # each entry is stored in the value of the hashtable entry as a populated
    # array.
    #
    # .PARAMETER DoNotCheckPowerShellVersion
    # This parameter is optional. If this switch is present, the function will not
    # check the version of PowerShell that is running. This is useful if you are
    # running this function in a script and the script has already validated that
    # the version of PowerShell supports Get-Module -ListAvailable.
    #
    # .PARAMETER WriteErrorOnFailure
    # This parameter is optional; it is a switch parameter. If this parameter is
    # specified, a non-terminating error is written via Write-Error when the
    # function fails. If this parameter is not specified, no error is written.
    #
    # .PARAMETER WriteWarningOnFailure
    # This parameter is optional; it is a switch parameter. If this parameter is
    # specified, a warning is written via Write-Warning when the function fails. If
    # this parameter is not specified, or if the WriteErrorOnFailure parameter was
    # specified, no warning is written.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Authentication', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Groups', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Users', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable $refHashtableModuleNameToInstalledModules
    # if ($intReturnCode -ne 0) {
    #     Write-Host 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # This example gets the list of installed PowerShell modules for each of the
    # four modules listed in the hashtable using named parameters. The list of each
    # respective module is stored in the value of the hashtable entry for that
    # module. The function returns 0 on success or -1 on failure, which is captured
    # and checked to ensure the operation completed successfully. No errors or
    # warnings are emitted by the function itself.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable $refHashtableModuleNameToInstalledModules
    # if ($intReturnCode -eq 0) {
    #     Write-Host 'Successfully retrieved module information.'
    # }
    #
    # This example demonstrates using positional parameters instead of named
    # parameters. The first positional parameter is the reference to the hashtable.
    # The function returns 0 on success, which is captured and checked.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('NonExistentModule', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable $refHashtableModuleNameToInstalledModules -WriteWarningOnFailure
    # if ($intReturnCode -ne 0) {
    #     Write-Host 'Function returned an error status'
    # }
    #
    # This example demonstrates using the WriteWarningOnFailure switch parameter. If
    # the function fails (e.g., invalid hashtable or PowerShell version check
    # failure), a warning message is displayed. The function returns -1 on failure.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable $refHashtableModuleNameToInstalledModules -WriteErrorOnFailure
    # if ($intReturnCode -ne 0) {
    #     exit 1
    # }
    #
    # This example demonstrates using the WriteErrorOnFailure switch parameter. If
    # the function fails, a non-terminating error is written via Write-Error. The
    # function returns -1 on failure and the script exits with code 1.
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PowerShellModuleUsingHashtable.
    #
    # .OUTPUTS
    # System.Int32. Returns an integer status code:
    #   0 = Success. All module queries completed successfully
    #  -1 = Failure. Invalid input or PowerShell version check failed
    #
    # The list of installed PowerShell modules for each key in the referenced
    # hashtable is stored in the respective entry's value as an array.
    #
    # .NOTES
    # This function also supports the use of a positional parameter instead of a
    # named parameter. If a positional parameter is used instead of a named
    # parameter, then exactly one positional parameter is required: a reference
    # (memory pointer) to a hashtable. The referenced hashtable must have keys that
    # are the names of PowerShell modules and values that are initialized to be
    # empty arrays (@()). After running this function, the list of installed
    # PowerShell modules for each entry is stored in the value of the hashtable
    # entry as a populated array.
    #
    # Note: Switch parameters (WriteErrorOnFailure and WriteWarningOnFailure) are
    # not included in positional parameters by default.
    #
    # This function requires Windows PowerShell 2.0 with .NET Framework 2.0 or
    # newer (minimum runtime requirement), and supports newer versions of Windows
    # PowerShell (at least up to and including Windows PowerShell 5.1 with .NET
    # Framework 4.8 or newer), PowerShell Core 6.x, and PowerShell 7.x. This
    # function supports Windows and, when run on PowerShell Core 6.x or PowerShell
    # 7.x, also supports macOS and Linux. While the function requires PowerShell
    # 2.0+ at runtime, the syntax is compatible with Windows PowerShell 1.0
    # parsing to avoid parser errors when loaded as a library function in older
    # environments.
    #
    # Version: 2.0.20260103.2

    param (
        [ref]$ReferenceToHashtable = ([ref]$null),
        [switch]$DoNotCheckPowerShellVersion,
        [switch]$WriteErrorOnFailure,
        [switch]$WriteWarningOnFailure
    )

    #region License ############################################################
    # Copyright (c) 2026 Frank Lesniak
    #
    # Permission is hereby granted, free of charge, to any person obtaining a copy
    # of this software and associated documentation files (the "Software"), to deal
    # in the Software without restriction, including without limitation the rights
    # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    # copies of the Software, and to permit persons to whom the Software is
    # furnished to do so, subject to the following conditions:
    #
    # The above copyright notice and this permission notice shall be included in
    # all copies or substantial portions of the Software.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    # SOFTWARE.
    #endregion License ############################################################

    #region FunctionsToSupportErrorHandling ####################################
    function Get-ReferenceToLastError {
        # .SYNOPSIS
        # Gets a reference (memory pointer) to the last error that
        # occurred.
        #
        # .DESCRIPTION
        # Returns a reference (memory pointer) to $null ([ref]$null) if no
        # errors on the $error stack; otherwise, returns a reference to
        # the last error that occurred.
        #
        # .EXAMPLE
        # # Intentionally empty trap statement to prevent terminating
        # # errors from halting processing
        # trap { }
        #
        # # Retrieve the newest error on the stack prior to doing work:
        # $refLastKnownError = Get-ReferenceToLastError
        #
        # # Store current error preference; we will restore it after we do
        # # some work:
        # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
        #
        # # Set ErrorActionPreference to SilentlyContinue; this will
        # # suppress error output. Terminating errors will not output
        # # anything, kick to the empty trap statement and then continue
        # # on. Likewise, non- terminating errors will also not output
        # # anything, but they do not kick to the trap statement; they
        # # simply continue on.
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        #
        # # Do something that might trigger an error
        # Get-Item -Path 'C:\MayNotExist.txt'
        #
        # # Restore the former error preference
        # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
        #
        # # Retrieve the newest error on the error stack
        # $refNewestCurrentError = Get-ReferenceToLastError
        #
        # $boolErrorOccurred = $false
        # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
        #     # Both not $null
        #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
        #         $boolErrorOccurred = $true
        #     }
        # } else {
        #     # One is $null, or both are $null
        #     # NOTE: $refLastKnownError could be non-null, while
        #     # $refNewestCurrentError could be null if $error was cleared;
        #     # this does not indicate an error.
        #     #
        #     # So:
        #     # If both are null, no error.
        #     # If $refLastKnownError is null and $refNewestCurrentError is
        #     # non-null, error.
        #     # If $refLastKnownError is non-null and
        #     # $refNewestCurrentError is null, no error.
        #     #
        #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
        #         $boolErrorOccurred = $true
        #     }
        # }
        #
        # .INPUTS
        # None. You can't pipe objects to Get-ReferenceToLastError.
        #
        # .OUTPUTS
        # System.Management.Automation.PSReference ([ref]).
        # Get-ReferenceToLastError returns a reference (memory pointer) to
        # the last error that occurred. It returns a reference to $null
        # ([ref]$null) if there are no errors on the $error stack.
        #
        # .NOTES
        # This function accepts no parameters.
        #
        # This function is compatible with Windows PowerShell 1.0+ (with
        # .NET Framework 2.0 or newer), PowerShell Core 6.x, and PowerShell
        # 7.x on Windows, macOS, and Linux.
        #
        # Design Note: This function returns a [ref] object directly rather
        # than following the author's standard v1.0 pattern of returning an
        # integer status code. This design is intentional, as the
        # function's sole purpose is to provide a reference for error
        # tracking. Requiring a [ref] parameter would add unnecessary
        # complexity to the calling pattern.
        #
        # Version: 2.0.20251226.0

        #region License ################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person
        # obtaining a copy of this software and associated documentation
        # files (the "Software"), to deal in the Software without
        # restriction, including without limitation the rights to use,
        # copy, modify, merge, publish, distribute, sublicense, and/or sell
        # copies of the Software, and to permit persons to whom the
        # Software is furnished to do so, subject to the following
        # conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
        # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
        # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
        # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
        # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
        # OTHER DEALINGS IN THE SOFTWARE.
        #endregion License ################################################

        param()

        if ($Error.Count -gt 0) {
            return ([ref]($Error[0]))
        } else {
            return ([ref]$null)
        }
    }

    function Test-ErrorOccurred {
        # .SYNOPSIS
        # Checks to see if an error occurred during a time period, i.e.,
        # during the execution of a command.
        #
        # .DESCRIPTION
        # Using two references (memory pointers) to errors, this function
        # checks to see if an error occurred based on differences between
        # the two errors.
        #
        # To use this function, you must first retrieve a reference to the
        # last error that occurred prior to the command you are about to
        # run. Then, run the command. After the command completes, retrieve
        # a reference to the last error that occurred. Pass these two
        # references to this function to determine if an error occurred.
        #
        # .PARAMETER ReferenceToEarlierError
        # This parameter is required; it is a reference (memory pointer) to
        # a System.Management.Automation.ErrorRecord that represents the
        # newest error on the stack earlier in time, i.e., prior to running
        # the command for which you wish to determine whether an error
        # occurred.
        #
        # If no error was on the stack at this time,
        # ReferenceToEarlierError must be a reference to $null
        # ([ref]$null).
        #
        # .PARAMETER ReferenceToLaterError
        # This parameter is required; it is a reference (memory pointer) to
        # a System.Management.Automation.ErrorRecord that represents the
        # newest error on the stack later in time, i.e., after to running
        # the command for which you wish to determine whether an error
        # occurred.
        #
        # If no error was on the stack at this time, ReferenceToLaterError
        # must be a reference to $null ([ref]$null).
        #
        # .EXAMPLE
        # # Intentionally empty trap statement to prevent terminating
        # # errors from halting processing
        # trap { }
        #
        # # Retrieve the newest error on the stack prior to doing work
        # if ($Error.Count -gt 0) {
        #     $refLastKnownError = ([ref]($Error[0]))
        # } else {
        #     $refLastKnownError = ([ref]$null)
        # }
        #
        # # Store current error preference; we will restore it after we do
        # # some work:
        # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
        #
        # # Set ErrorActionPreference to SilentlyContinue; this will
        # # suppress error output. Terminating errors will not output
        # # anything, kick to the empty trap statement and then continue
        # # on. Likewise, non- terminating errors will also not output
        # # anything, but they do not kick to the trap statement; they
        # # simply continue on.
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        #
        # # Do something that might trigger an error
        # Get-Item -Path 'C:\MayNotExist.txt'
        #
        # # Restore the former error preference
        # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
        #
        # # Retrieve the newest error on the error stack
        # if ($Error.Count -gt 0) {
        #     $refNewestCurrentError = ([ref]($Error[0]))
        # } else {
        #     $refNewestCurrentError = ([ref]$null)
        # }
        #
        # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
        #     # Error occurred
        # } else {
        #     # No error occurred
        # }
        #
        # .EXAMPLE
        # # This example demonstrates the function returning $false when no
        # # error occurs during the operation. A command that executes
        # # successfully is run, and the function correctly identifies that
        # # no error occurred.
        #
        # # Intentionally empty trap statement to prevent terminating
        # # errors from halting processing
        # trap { }
        #
        # # Retrieve the newest error on the stack prior to doing work
        # if ($Error.Count -gt 0) {
        #     $refLastKnownError = ([ref]($Error[0]))
        # } else {
        #     $refLastKnownError = ([ref]$null)
        # }
        #
        # # Store current error preference; we will restore it after we do
        # # some work:
        # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
        #
        # # Set ErrorActionPreference to SilentlyContinue
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        #
        # # Do something that will succeed
        # Get-Item -Path $env:TEMP
        #
        # # Restore the former error preference
        # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
        #
        # # Retrieve the newest error on the error stack
        # if ($Error.Count -gt 0) {
        #     $refNewestCurrentError = ([ref]($Error[0]))
        # } else {
        #     $refNewestCurrentError = ([ref]$null)
        # }
        #
        # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
        #     # Error occurred
        # } else {
        #     # No error occurred - this branch executes because Get-Item
        #     # succeeded
        # }
        #
        # .EXAMPLE
        # # This example demonstrates a scenario where
        # # ReferenceToEarlierError is non-null but ReferenceToLaterError
        # # is null, simulating that $Error was cleared. The function
        # # returns $false because this does not indicate a new error
        # # occurred.
        #
        # # Intentionally empty trap statement to prevent terminating errors
        # # from halting processing
        # trap { }
        #
        # # Generate an error so that $Error has an entry
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        # Get-Item -Path 'C:\DoesNotExist-ErrorClearing-Example.txt'
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
        #
        # # Capture reference to the error
        # if ($Error.Count -gt 0) {
        #     $refLastKnownError = ([ref]($Error[0]))
        # } else {
        #     $refLastKnownError = ([ref]$null)
        # }
        #
        # # Clear the $Error array
        # $Error.Clear()
        #
        # # Capture reference after clearing (will be null)
        # if ($Error.Count -gt 0) {
        #     $refNewestCurrentError = ([ref]($Error[0]))
        # } else {
        #     $refNewestCurrentError = ([ref]$null)
        # }
        #
        # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
        #     # Error occurred
        # } else {
        #     # No error occurred - this branch executes because clearing
        #     # $Error does not indicate a new error
        # }
        #
        # .EXAMPLE
        # # This example demonstrates using the function with positional
        # # parameters instead of named parameters. Both approaches work
        # # correctly.
        #
        # # Intentionally empty trap statement to prevent terminating
        # # errors from halting processing
        # trap { }
        #
        # # Retrieve the newest error on the stack prior to doing work
        # if ($Error.Count -gt 0) {
        #     $refLastKnownError = ([ref]($Error[0]))
        # } else {
        #     $refLastKnownError = ([ref]$null)
        # }
        #
        # # Store current error preference
        # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
        #
        # # Set ErrorActionPreference to SilentlyContinue
        # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        #
        # # Do something that might trigger an error
        # Get-Item -Path 'C:\MayNotExist-Positional-Example.txt'
        #
        # # Restore the former error preference
        # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
        #
        # # Retrieve the newest error on the error stack
        # if ($Error.Count -gt 0) {
        #     $refNewestCurrentError = ([ref]($Error[0]))
        # } else {
        #     $refNewestCurrentError = ([ref]$null)
        # }
        #
        # # Note: Using positional parameters - first parameter is
        # # ReferenceToEarlierError, second is ReferenceToLaterError
        # if (Test-ErrorOccurred $refLastKnownError $refNewestCurrentError) {
        #     # Error occurred
        # } else {
        #     # No error occurred
        # }
        #
        # .INPUTS
        # None. You can't pipe objects to Test-ErrorOccurred.
        #
        # .OUTPUTS
        # System.Boolean. Test-ErrorOccurred returns a boolean value
        # indicating whether an error occurred during the time period in
        # question. $true indicates an error occurred; $false indicates no
        # error occurred.
        #
        # .NOTES
        # This function supports Windows PowerShell 1.0 with .NET Framework
        # 2.0 or newer, newer versions of Windows PowerShell (at least up
        # to and including Windows PowerShell 5.1 with .NET Framework 4.8
        # or newer), PowerShell Core 6.x, and PowerShell 7.x. This function
        # supports Windows and, when run on PowerShell Core 6.x or
        # PowerShell 7.x, also supports macOS and Linux.
        #
        # This function also supports the use of positional parameters
        # instead of named parameters. If positional parameters are used
        # instead of named parameters, then two positional parameters are
        # required:
        #
        # The first positional parameter is a reference (memory pointer) to
        # a System.Management.Automation.ErrorRecord that represents the
        # newest error on the stack earlier in time, i.e., prior to running
        # the command for which you wish to determine whether an error
        # occurred. If no error was on the stack at this time, the first
        # positional parameter must be a reference to $null ([ref]$null).
        #
        # The second positional parameter is a reference (memory pointer)
        # to a System.Management.Automation.ErrorRecord that represents the
        # newest error on the stack later in time, i.e., after to running
        # the command for which you wish to determine whether an error
        # occurred. If no error was on the stack at this time,
        # ReferenceToLaterError must be a reference to $null ([ref]$null).
        #
        # Version: 2.0.20251226.0

        param (
            [ref]$ReferenceToEarlierError = ([ref]$null),
            [ref]$ReferenceToLaterError = ([ref]$null)
        )

        #region License ################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person
        # obtaining a copy of this software and associated documentation
        # files (the "Software"), to deal in the Software without
        # restriction, including without limitation the rights to use,
        # copy, modify, merge, publish, distribute, sublicense, and/or sell
        # copies of the Software, and to permit persons to whom the
        # Software is furnished to do so, subject to the following
        # conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
        # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
        # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
        # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
        # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
        # OTHER DEALINGS IN THE SOFTWARE.
        #endregion License ################################################

        $boolErrorOccurred = $false
        if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
            # Both not $null
            if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                $boolErrorOccurred = $true
            }
        } else {
            # One is $null, or both are $null
            # NOTE: $ReferenceToEarlierError could be non-null, while
            # $ReferenceToLaterError could be null if $error was cleared;
            # this does not indicate an error.
            # So:
            # - If both are null, no error.
            # - If $ReferenceToEarlierError is null and
            #   $ReferenceToLaterError is non-null, error.
            # - If $ReferenceToEarlierError is non-null and
            #   $ReferenceToLaterError is null, no error.
            if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                $boolErrorOccurred = $true
            }
        }

        return $boolErrorOccurred
    }
    #endregion FunctionsToSupportErrorHandling ####################################

    #region HelperFunctions ####################################################
    function Get-PSVersion {
        # .SYNOPSIS
        # Returns the version of PowerShell that is running.
        #
        # .DESCRIPTION
        # The function outputs a [version] object representing the version of
        # PowerShell that is running. This function detects the PowerShell
        # runtime version but does not detect the underlying .NET Framework or
        # .NET Core version.
        #
        # On versions of PowerShell greater than or equal to version 2.0, this
        # function returns the equivalent of $PSVersionTable.PSVersion
        #
        # PowerShell 1.0 does not have a $PSVersionTable variable, so this
        # function returns [version]('1.0') on PowerShell 1.0.
        #
        # .EXAMPLE
        # $versionPS = Get-PSVersion
        # # $versionPS now contains the version of PowerShell that is running.
        # # On versions of PowerShell greater than or equal to version 2.0,
        # # this function returns the equivalent of $PSVersionTable.PSVersion.
        #
        # .EXAMPLE
        # $versionPS = Get-PSVersion
        # if ($versionPS.Major -ge 2) {
        #     Write-Host "PowerShell 2.0 or later detected"
        # } else {
        #     Write-Host "PowerShell 1.0 detected"
        # }
        # # This example demonstrates storing the returned version object in a
        # # variable and using it to make conditional decisions based on
        # # PowerShell version. The returned [version] object has properties
        # # like Major, Minor, Build, and Revision that can be used for
        # # version-based logic.
        #
        # .INPUTS
        # None. You can't pipe objects to Get-PSVersion.
        #
        # .OUTPUTS
        # System.Version. Get-PSVersion returns a [version] value indicating
        # the version of PowerShell that is running.
        #
        # .NOTES
        # Version: 1.0.20251231.0
        #
        # This function is compatible with all versions of PowerShell: Windows
        # PowerShell (v1.0 - 5.1), PowerShell Core 6.x, and PowerShell 7.x and
        # newer. It is compatible with Windows, macOS, and Linux.
        #
        # This function has no parameters.

        param()

        #region License ####################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining
        # a copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to
        # permit persons to whom the Software is furnished to do so, subject to
        # the following conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
        # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
        # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        # SOFTWARE.
        #endregion License ####################################################

        if (Test-Path variable:\PSVersionTable) {
            return ($PSVersionTable.PSVersion)
        } else {
            return ([version]('1.0'))
        }
    }
    #endregion HelperFunctions ####################################################

    trap {
        # Intentionally left empty to prevent terminating errors from halting
        # processing
    }

    #region Process input ######################################################
    # Validate that the required parameter was supplied:
    if ($null -eq $ReferenceToHashtable) {
        $strMessage = 'The Get-PowerShellModuleUsingHashtable function requires a parameter (-ReferenceToHashtable), which must reference a hashtable.'
        if ($boolWriteErrorOnFailure) {
            Write-Error -Message $strMessage
        } elseif ($boolWriteWarningOnFailure) {
            Write-Warning -Message $strMessage
        }
        return -1
    }
    if ($null -eq $ReferenceToHashtable.Value) {
        $strMessage = 'The Get-PowerShellModuleUsingHashtable function requires a parameter (-ReferenceToHashtable), which must reference a hashtable.'
        if ($boolWriteErrorOnFailure) {
            Write-Error -Message $strMessage
        } elseif ($boolWriteWarningOnFailure) {
            Write-Warning -Message $strMessage
        }
        return -1
    }
    if ($ReferenceToHashtable.Value.GetType().FullName -ne 'System.Collections.Hashtable') {
        $strMessage = 'The Get-PowerShellModuleUsingHashtable function requires a parameter (-ReferenceToHashtable), which must reference a hashtable.'
        if ($boolWriteErrorOnFailure) {
            Write-Error -Message $strMessage
        } elseif ($boolWriteWarningOnFailure) {
            Write-Warning -Message $strMessage
        }
        return -1
    }

    $boolCheckForPowerShellVersion = $true
    if ($null -ne $DoNotCheckPowerShellVersion) {
        if ($DoNotCheckPowerShellVersion.IsPresent) {
            $boolCheckForPowerShellVersion = $false
        }
    }

    $boolWriteErrorOnFailure = $false
    $boolWriteWarningOnFailure = $false
    if ($null -ne $WriteErrorOnFailure) {
        if ($WriteErrorOnFailure.IsPresent -eq $true) {
            $boolWriteErrorOnFailure = $true
        }
    }
    if (-not $boolWriteErrorOnFailure) {
        if ($null -ne $WriteWarningOnFailure) {
            if ($WriteWarningOnFailure.IsPresent -eq $true) {
                $boolWriteWarningOnFailure = $true
            }
        }
    }
    #endregion Process input ######################################################

    #region Verify environment #################################################
    if ($boolCheckForPowerShellVersion) {
        $versionPS = Get-PSVersion
        if ($versionPS.Major -lt 2) {
            $strMessage = 'The Get-PowerShellModuleUsingHashtable function requires PowerShell version 2.0 or greater.'
            if ($boolWriteErrorOnFailure) {
                Write-Error -Message $strMessage
            } elseif ($boolWriteWarningOnFailure) {
                Write-Warning -Message $strMessage
            }
            return -1
        }
    }
    #endregion Verify environment #################################################

    #region Main Processing ################################################
    $actionPreferenceVerboseAtStartOfFunction = $VerbosePreference

    $arrModulesToGet = @(($ReferenceToHashtable.Value).Keys)
    $intCountOfModules = $arrModulesToGet.Count

    # Retrieve the newest error on the stack prior to doing work
    $refLastKnownError = Get-ReferenceToLastError

    # Store current error preference; we will restore it after we do the work of
    # this function
    $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

    # Set ErrorActionPreference to SilentlyContinue; this will suppress error
    # output. Terminating errors will not output anything, kick to the empty trap
    # statement and then continue on. Likewise, non-terminating errors will also
    # not output anything, but they do not kick to the trap statement; they simply
    # continue on.
    $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

    # Get the list of installed modules for each module name in the hashtable
    ###############################################################################
    # # The following code is commented out and converted to a one-liner
    # # intentionally so that error handling works correctly.
    # for ($intCounter = 0; $intCounter -lt $intCountOfModules; $intCounter++) {
    #     Write-Verbose ('Checking for {0} module...' -f $arrModulesToGet[$intCounter])
    #     # Suppress verbose output from Get-Module (v1.0 compatible approach)
    #     $VerbosePreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
    #     ($ReferenceToHashtable.Value).Item($arrModulesToGet[$intCounter]) = @(Get-Module -Name ($arrModulesToGet[$intCounter]) -ListAvailable)
    #     $VerbosePreference = $actionPreferenceVerboseAtStartOfFunction
    # }
    ###############################################################################
    # Here is the one-liner version of the above code:
    for ($intCounter = 0; $intCounter -lt $intCountOfModules; $intCounter++) { Write-Verbose ('Checking for {0} module...' -f $arrModulesToGet[$intCounter]); $VerbosePreference = [System.Management.Automation.ActionPreference]::SilentlyContinue; ($ReferenceToHashtable.Value).Item($arrModulesToGet[$intCounter]) = @(Get-Module -Name ($arrModulesToGet[$intCounter]) -ListAvailable); $VerbosePreference = $actionPreferenceVerboseAtStartOfFunction; }

    # Restore the former error preference
    $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

    # Retrieve the newest error on the error stack
    $refNewestCurrentError = Get-ReferenceToLastError

    if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
        # Error occurred

        # Return failure indicator:
        return -1
    } else {
        # No error occurred

        # Return success indicator:
        return 0
    }

    #endregion Main Processing ################################################
}

function Test-PowerShellModuleInstalledUsingHashtable {
    # .SYNOPSIS
    # Tests to see if a PowerShell module is installed based on entries in a
    # hashtable. If the PowerShell module is not installed, an error or warning
    # message may optionally be displayed.
    #
    # .DESCRIPTION
    # The Test-PowerShellModuleInstalledUsingHashtable function steps through each
    # entry in the supplied hashtable and, if there are any modules not installed,
    # it optionally throws an error or warning for each module that is not
    # installed. If all modules are installed, the function returns $true;
    # otherwise, if any module is not installed, the function returns $false.
    #
    # .PARAMETER HashtableOfInstalledModules
    # This parameter is required; it is a hashtable. The hashtable must have keys
    # that are the names of PowerShell modules with each hashtable entry's value
    # (in the key-value pair) populated with arrays of ModuleInfoGrouping objects
    # (i.e., the object returned from Get-Module).
    #
    # .PARAMETER HashtableOfCustomNotInstalledMessages
    # This parameter is optional; if supplied, it is a hashtable. The hashtable
    # must have keys that are custom error or warning messages (string) to be
    # displayed if one or more modules are not installed. The value for each key
    # must be an array of PowerShell module names (strings) relevant to that error
    # or warning message.
    #
    # If this parameter is not supplied, or if a custom error or warning message is
    # not supplied in the hashtable for a given module, the script will default to
    # using the following message:
    #
    # <MODULENAME> module not found. Please install it and then try again.
    # You can install the <MODULENAME> PowerShell module from the PowerShell
    # Gallery by running the following command:
    # Install-Module <MODULENAME>;
    #
    # If the installation command fails, you may need to upgrade the version of
    # PowerShellGet. To do so, run the following commands, then restart PowerShell:
    # Set-ExecutionPolicy Bypass -Scope Process -Force;
    # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    # Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;
    # Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;
    #
    # .PARAMETER ThrowErrorIfModuleNotInstalled
    # This parameter is optional; it is a switch parameter. If this parameter is
    # specified, an error is thrown for each module that is not installed. If this
    # parameter is not specified, no error is thrown.
    #
    # .PARAMETER ThrowWarningIfModuleNotInstalled
    # This parameter is optional; it is a switch parameter. If this parameter is
    # specified, a warning is thrown for each module that is not installed. If this
    # parameter is not specified, or if the ThrowErrorIfModuleNotInstalled
    # parameter was specified, no warning is thrown.
    #
    # .PARAMETER ReferenceToArrayOfMissingModules
    # This parameter is optional; if supplied, it is a reference to an array. The
    # array must be initialized to be empty. If any modules are not installed, the
    # names of those modules are added to the array.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Authentication', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Groups', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Users', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable $refHashtableModuleNameToInstalledModules
    # if ($intReturnCode -ne 0) {
    #     Write-Error 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # $hashtableCustomNotInstalledMessageToModuleNames = @{}
    # $strGraphNotInstalledMessage = 'Microsoft.Graph.Authentication, Microsoft.Graph.Groups, and/or Microsoft.Graph.Users modules were not found. Please install the full Microsoft.Graph module and then try again.' + [System.Environment]::NewLine + 'You can install the Microsoft.Graph PowerShell module from the PowerShell Gallery by running the following command:' + [System.Environment]::NewLine + 'Install-Module Microsoft.Graph;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
    # $hashtableCustomNotInstalledMessageToModuleNames.Add($strGraphNotInstalledMessage, @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users'))
    #
    # $boolResult = Test-PowerShellModuleInstalledUsingHashtable -HashtableOfInstalledModules $hashtableModuleNameToInstalledModules -HashtableOfCustomNotInstalledMessages $hashtableCustomNotInstalledMessageToModuleNames -ThrowErrorIfModuleNotInstalled
    # if ($boolResult -eq $false) {
    #     Write-Warning 'One or more required modules are not installed.'
    #     return
    # }
    #
    # This example checks to see if the PnP.PowerShell,
    # Microsoft.Graph.Authentication, Microsoft.Graph.Groups, and
    # Microsoft.Graph.Users modules are installed using named parameters. If any of
    # these modules are not installed, an error is thrown for the PnP.PowerShell
    # module or the group of Microsoft.Graph modules, respectively, and $boolResult
    # is set to $false. If all modules are installed, $boolResult is set to $true.
    # The function returns a boolean value indicating whether all modules are
    # installed.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
    # $intReturnCode = Get-PowerShellModuleUsingHashtable $refHashtableModuleNameToInstalledModules
    # if ($intReturnCode -ne 0) {
    #     Write-Error 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # $boolResult = Test-PowerShellModuleInstalledUsingHashtable $hashtableModuleNameToInstalledModules $null $true
    # if ($boolResult -eq $false) {
    #     Write-Warning 'PnP.PowerShell module is not installed.'
    #     return
    # }
    #
    # This example demonstrates using positional parameters instead of named
    # parameters. The first positional parameter is the hashtable of installed
    # modules, the second is the hashtable of custom messages (null in this case),
    # and the third is the switch to throw an error if a module is not installed.
    # The function returns $true if the module is installed, $false otherwise.
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PowerShellModuleInstalledUsingHashtable.
    #
    # .OUTPUTS
    # System.Boolean. Test-PowerShellModuleInstalledUsingHashtable returns a
    # boolean value indicating whether all modules were installed. $true means
    # that every module specified in the hashtable (i.e., the one passed in the
    # HashtableOfInstalledModules parameter) was installed; $false means that at
    # least one module was not installed.
    #
    # .NOTES
    # Version: 3.0.20251231.1
    #
    # This function supports Windows PowerShell 1.0 with .NET Framework 2.0 or
    # newer, newer versions of Windows PowerShell (at least up to and including
    # Windows PowerShell 5.1 with .NET Framework 4.8 or newer), PowerShell Core
    # 6.x, and PowerShell 7.x. This function supports Windows and, when run on
    # PowerShell Core 6.x or PowerShell 7.x, also supports macOS and Linux.
    #
    # This function also supports the use of positional parameters instead of named
    # parameters. If positional parameters are used instead of named parameters,
    # then five positional parameters are supported in the following order:
    # 1. HashtableOfInstalledModules (required)
    # 2. HashtableOfCustomNotInstalledMessages (optional)
    # 3. ThrowErrorIfModuleNotInstalled (optional switch)
    # 4. ThrowWarningIfModuleNotInstalled (optional switch)
    # 5. ReferenceToArrayOfMissingModules (optional)

    #region License ############################################################
    # Copyright (c) 2025 Frank Lesniak
    #
    # Permission is hereby granted, free of charge, to any person obtaining a copy
    # of this software and associated documentation files (the "Software"), to deal
    # in the Software without restriction, including without limitation the rights
    # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    # copies of the Software, and to permit persons to whom the Software is
    # furnished to do so, subject to the following conditions:
    #
    # The above copyright notice and this permission notice shall be included in
    # all copies or substantial portions of the Software.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    # SOFTWARE.
    #endregion License ############################################################

    param (
        [hashtable]$HashtableOfInstalledModules = $null,
        [hashtable]$HashtableOfCustomNotInstalledMessages = $null,
        [switch]$ThrowErrorIfModuleNotInstalled,
        [switch]$ThrowWarningIfModuleNotInstalled,
        [ref]$ReferenceToArrayOfMissingModules = ([ref]$null)
    )

    trap {
        # Intentionally left empty to prevent terminating errors from halting
        # processing
    }

    #region Process input ######################################################
    # Validate that the required parameter was supplied:
    if ($null -eq $HashtableOfInstalledModules) {
        $strMessage = 'The Test-PowerShellModuleInstalledUsingHashtable function requires a parameter (-HashtableOfInstalledModules), which must be a hashtable.'
        Write-Error -Message $strMessage
        return $false
    }
    if ($HashtableOfInstalledModules.GetType().FullName -ne 'System.Collections.Hashtable') {
        $strMessage = 'The Test-PowerShellModuleInstalledUsingHashtable function requires a parameter (-HashtableOfInstalledModules), which must be a hashtable.'
        Write-Error -Message $strMessage
        return $false
    }

    $boolThrowErrorForMissingModule = $false
    if ($null -ne $ThrowErrorIfModuleNotInstalled) {
        if ($ThrowErrorIfModuleNotInstalled.IsPresent) {
            $boolThrowErrorForMissingModule = $true
        }
    }
    $boolThrowWarningForMissingModule = $false
    if (-not $boolThrowErrorForMissingModule) {
        if ($null -ne $ThrowWarningIfModuleNotInstalled) {
            if ($ThrowWarningIfModuleNotInstalled.IsPresent) {
                $boolThrowWarningForMissingModule = $true
            }
        }
    }
    #endregion Process input ######################################################

    $boolResult = $true

    $hashtableMessagesToThrowForMissingModule = @{}
    $hashtableModuleNameToCustomMessageToThrowForMissingModule = @{}
    if ($null -ne $HashtableOfCustomNotInstalledMessages) {
        if ($HashtableOfCustomNotInstalledMessages.GetType().FullName -eq 'System.Collections.Hashtable') {
            $arrMessages = @($HashtableOfCustomNotInstalledMessages.Keys)
            foreach ($strMessage in $arrMessages) {
                $hashtableMessagesToThrowForMissingModule.Add($strMessage, $false)

                $HashtableOfCustomNotInstalledMessages.Item($strMessage) | ForEach-Object {
                    $hashtableModuleNameToCustomMessageToThrowForMissingModule.Add($_, $strMessage)
                }
            }
        }
    }

    $arrModuleNames = @($HashtableOfInstalledModules.Keys)
    foreach ($strModuleName in $arrModuleNames) {
        $arrInstalledModules = @($HashtableOfInstalledModules.Item($strModuleName))
        if ($arrInstalledModules.Count -eq 0) {
            $boolResult = $false

            if ($hashtableModuleNameToCustomMessageToThrowForMissingModule.ContainsKey($strModuleName) -eq $true) {
                $strMessage = $hashtableModuleNameToCustomMessageToThrowForMissingModule.Item($strModuleName)
                $hashtableMessagesToThrowForMissingModule.Item($strMessage) = $true
            } else {
                $strMessage = $strModuleName + ' module not found. Please install it and then try again.' + [System.Environment]::NewLine + 'You can install the ' + $strModuleName + ' PowerShell module from the PowerShell Gallery by running the following command:' + [System.Environment]::NewLine + 'Install-Module ' + $strModuleName + ';' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
                $hashtableMessagesToThrowForMissingModule.Add($strMessage, $true)
            }

            if ($null -ne $ReferenceToArrayOfMissingModules) {
                if ($null -ne $ReferenceToArrayOfMissingModules.Value) {
                    ($ReferenceToArrayOfMissingModules.Value) += $strModuleName
                }
            }
        }
    }

    if ($boolThrowErrorForMissingModule) {
        $arrMessages = @($hashtableMessagesToThrowForMissingModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForMissingModule.Item($strMessage)) {
                Write-Error $strMessage
            }
        }
    } elseif ($boolThrowWarningForMissingModule) {
        $arrMessages = @($hashtableMessagesToThrowForMissingModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForMissingModule.Item($strMessage)) {
                Write-Warning $strMessage
            }
        }
    }

    return $boolResult
}

function Test-PowerShellModuleUpdatesAvailableUsingHashtable {
    # .SYNOPSIS
    # Tests to see if updates are available for a PowerShell module based on
    # entries in a hashtable. If updates are available for a PowerShell module, an
    # error or warning message may optionally be displayed.
    #
    # .DESCRIPTION
    # The Test-PowerShellModuleUpdatesAvailableUsingHashtable function steps
    # through each entry in the supplied hashtable and, if there are updates
    # available, it optionally throws an error or warning for each module that has
    # updates available. If all modules are installed and up to date, the function
    # returns $true; otherwise, if any module is not installed or not up to date,
    # the function returns $false.
    #
    # .PARAMETER HashtableOfInstalledModules
    # This parameter is required; it is a hashtable. The hashtable must have keys
    # that are the names of PowerShell modules with each key's value populated with
    # arrays of ModuleInfoGrouping objects (the result of Get-Module).
    #
    # .PARAMETER ThrowErrorIfModuleNotInstalled
    # This parameter is optional; if supplied, an error is thrown for each module
    # that is not installed. If this parameter is not specified, no error is
    # thrown.
    #
    # .PARAMETER ThrowWarningIfModuleNotInstalled
    # This parameter is optional; if supplied, a warning is thrown for each module
    # that is not installed. If this parameter is not specified, or if the
    # ThrowErrorIfModuleNotInstalled parameter was specified, no warning is thrown.
    #
    # .PARAMETER ThrowErrorIfModuleNotUpToDate
    # This parameter is optional; if supplied, an error is thrown for each module
    # that is not up to date. If this parameter is not specified, no error is
    # thrown.
    #
    # .PARAMETER ThrowWarningIfModuleNotUpToDate
    # This parameter is optional; if supplied, a warning is thrown for each module
    # that is not up to date. If this parameter is not specified, or if the
    # ThrowErrorIfModuleNotUpToDate parameter was specified, no warning is thrown.
    #
    # .PARAMETER HashtableOfCustomNotInstalledMessages
    # This parameter is optional; if supplied, it is a hashtable. The hashtable
    # must have keys that are custom error or warning messages (each key is a
    # string object) to be displayed if one or more modules are not installed. The
    # value for each key must be an array of PowerShell module names (strings)
    # relevant to that error or warning message.
    #
    # If this parameter is not supplied, or if a custom error or warning message is
    # not supplied in the hashtable for a given module, the script will default to
    # using the following message:
    #
    # <MODULENAME> module not found. Please install it and then try again.
    # You can install the <MODULENAME> PowerShell module from the PowerShell
    # Gallery by running the following command:
    # Install-Module <MODULENAME>;
    #
    # If the installation command fails, you may need to upgrade the version of
    # PowerShellGet. To do so, run the following commands, then restart PowerShell:
    # Set-ExecutionPolicy Bypass -Scope Process -Force;
    # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    # Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;
    # Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;
    #
    # .PARAMETER HashtableOfCustomNotUpToDateMessages
    # This parameter is optional; if supplied, it is a hashtable. The hashtable
    # must have keys that are custom error or warning messages (string) to be
    # displayed if one or more modules are not up to date. The value for each key
    # must be an array of PowerShell module names (strings) relevant to that error
    # or warning message.
    #
    # If this parameter is not supplied, or if a custom error or warning message is
    # not supplied in the hashtable for a given module, the script will default to
    # using the following message:
    #
    # A newer version of the <MODULENAME> PowerShell module is available. Please
    # consider updating it by running the following command:
    # Install-Module <MODULENAME> -Force;
    #
    # If the installation command fails, you may need to upgrade the version of
    # PowerShellGet. To do so, run the following commands, then restart PowerShell:
    # Set-ExecutionPolicy Bypass -Scope Process -Force;
    # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    # Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;
    # Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;
    #
    # .PARAMETER ReferenceToArrayOfMissingModules
    # This parameter is optional; if supplied, it is a reference to an array. The
    # array must be initialized to be empty. If any modules are not installed, the
    # names of those modules are added to the array.
    #
    # .PARAMETER ReferenceToArrayOfOutOfDateModules
    # This parameter is optional; if supplied, it is a reference to an array. The
    # array must be initialized to be empty. If any modules are not up to date, the
    # names of those modules are added to the array.
    #
    # .PARAMETER DoNotCheckPowerShellVersion
    # This parameter is optional. If this switch is present, the function will not
    # check the version of PowerShell that is running. This is useful if you are
    # running this function in a script and the script has already validated that
    # the version of PowerShell supports Find-Module.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable ([ref]$hashtableModuleNameToInstalledModules)
    # if ($intReturnCode -ne 0) {
    #     Write-Error 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # $hashtableCustomNotInstalledMessageToModuleNames = @{}
    #
    # $hashtableCustomNotUpToDateMessageToModuleNames = @{}
    #
    # $boolResult = Test-PowerShellModuleUpdatesAvailableUsingHashtable -HashtableOfInstalledModules $hashtableModuleNameToInstalledModules -ThrowErrorIfModuleNotInstalled -ThrowWarningIfModuleNotUpToDate -HashtableOfCustomNotInstalledMessages $hashtableCustomNotInstalledMessageToModuleNames -HashtableOfCustomNotUpToDateMessages $hashtableCustomNotUpToDateMessageToModuleNames
    # if ($boolResult -eq $false) {
    #     Write-Warning 'PnP.PowerShell module is not installed or not up to date.'
    #     return
    # }
    #
    # This example checks to see if the PnP.PowerShell module is installed using
    # named parameters. If it is not installed, an error is thrown and $boolResult
    # is set to $false. If it is installed but not up to date, a warning message is
    # thrown and $boolResult is set to false. If PnP.PowerShell is installed and up
    # to date, $boolResult is set to $true. The function returns a boolean value
    # indicating whether the module is both installed and up to date.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Authentication', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Groups', @())
    # $hashtableModuleNameToInstalledModules.Add('Microsoft.Graph.Users', @())
    # $intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable ([ref]$hashtableModuleNameToInstalledModules)
    # if ($intReturnCode -ne 0) {
    #     Write-Error 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # $hashtableCustomNotInstalledMessageToModuleNames = @{}
    # $strGraphNotInstalledMessage = 'Microsoft.Graph.Authentication, Microsoft.Graph.Groups, and/or Microsoft.Graph.Users modules were not found. Please install the full Microsoft.Graph module and then try again.' + [System.Environment]::NewLine + 'You can install the Microsoft.Graph PowerShell module from the PowerShell Gallery by running the following command:' + [System.Environment]::NewLine + 'Install-Module Microsoft.Graph;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
    # $hashtableCustomNotInstalledMessageToModuleNames.Add($strGraphNotInstalledMessage, @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users'))
    #
    # $hashtableCustomNotUpToDateMessageToModuleNames = @{}
    # $strGraphNotUpToDateMessage = 'A newer version of the Microsoft.Graph.Authentication, Microsoft.Graph.Groups, and/or Microsoft.Graph.Users modules was found. Please consider updating it by running the following command:' + [System.Environment]::NewLine + 'Install-Module Microsoft.Graph -Force;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
    # $hashtableCustomNotUpToDateMessageToModuleNames.Add($strGraphNotUpToDateMessage, @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users'))
    #
    # $boolResult = Test-PowerShellModuleUpdatesAvailableUsingHashtable -HashtableOfInstalledModules $hashtableModuleNameToInstalledModules -ThrowErrorIfModuleNotInstalled -ThrowWarningIfModuleNotUpToDate -HashtableOfCustomNotInstalledMessages $hashtableCustomNotInstalledMessageToModuleNames -HashtableOfCustomNotUpToDateMessages $hashtableCustomNotUpToDateMessageToModuleNames
    # if ($boolResult -eq $false) {
    #     Write-Warning 'One or more modules are not installed or not up to date.'
    #     return
    # }
    #
    # This example checks to see if the PnP.PowerShell,
    # Microsoft.Graph.Authentication, Microsoft.Graph.Groups, and
    # Microsoft.Graph.Users modules are installed using named parameters. If any of
    # these modules are not installed, an error is thrown for the PnP.PowerShell
    # module or the group of Microsoft.Graph modules, respectively, and $boolResult
    # is set to $false. If any of these modules are installed but not up to date, a
    # warning message is thrown for the PnP.PowerShell module or the group of
    # Microsoft.Graph modules, respectively, and $boolResult is set to false. If all
    # modules are installed and up to date, $boolResult is set to $true. The
    # function returns a boolean value indicating whether all modules are both
    # installed and up to date.
    #
    # .EXAMPLE
    # $hashtableModuleNameToInstalledModules = @{}
    # $hashtableModuleNameToInstalledModules.Add('PnP.PowerShell', @())
    # $intReturnCode = Get-PowerShellModuleUsingHashtable ([ref]$hashtableModuleNameToInstalledModules)
    # if ($intReturnCode -ne 0) {
    #     Write-Error 'Failed to get the list of installed PowerShell modules.'
    #     return
    # }
    #
    # $boolResult = Test-PowerShellModuleUpdatesAvailableUsingHashtable $hashtableModuleNameToInstalledModules $true $false $true $false
    # if ($boolResult -eq $false) {
    #     Write-Warning 'PnP.PowerShell module is not installed or not up to date.'
    #     return
    # }
    #
    # This example demonstrates using positional parameters instead of named
    # parameters. The first positional parameter is the hashtable of installed
    # modules, the second is the switch to throw an error if a module is not
    # installed, the third is the switch to throw a warning if a module is not
    # installed (false since we're throwing errors), the fourth is the switch to
    # throw an error if a module is not up to date, and the fifth is the switch to
    # throw a warning if a module is not up to date (false since we're throwing
    # errors for not up to date). The function returns $true if the module is
    # installed and up to date, $false otherwise.
    #
    # .INPUTS
    # None. You can't pipe objects to
    # Test-PowerShellModuleUpdatesAvailableUsingHashtable.
    #
    # .OUTPUTS
    # System.Boolean. Test-PowerShellModuleUpdatesAvailableUsingHashtable returns a
    # boolean value indiciating whether all modules are installed and up to date.
    # If all modules are installed and up to date, the function returns $true;
    # otherwise, if any module is not installed or not up to date, the function
    # returns $false.
    #
    # .NOTES
    # This function also supports the use of positional parameters instead of named
    # parameters. If positional parameters are used instead of named parameters,
    # then up to ten positional parameters may be specified. The first positional
    # parameter is a hashtable of installed modules (the
    # $HashtableOfInstalledModules parameter). The second positional parameter is
    # a switch indicating whether to throw an error if a module is not installed
    # (the $ThrowErrorIfModuleNotInstalled parameter). The third positional
    # parameter is a switch indicating whether to throw a warning if a module is
    # not installed (the $ThrowWarningIfModuleNotInstalled parameter). The fourth
    # positional parameter is a switch indicating whether to throw an error if a
    # module is not up to date (the $ThrowErrorIfModuleNotUpToDate parameter). The
    # fifth positional parameter is a switch indicating whether to throw a warning
    # if a module is not up to date (the $ThrowWarningIfModuleNotUpToDate
    # parameter). The sixth positional parameter is a hashtable of custom messages
    # to display if a module is not installed (the
    # $HashtableOfCustomNotInstalledMessages parameter). The seventh positional
    # parameter is a hashtable of custom messages to display if a module is not up
    # to date (the $HashtableOfCustomNotUpToDateMessages parameter). The eighth
    # positional parameter is a reference to an array to store the names of missing
    # modules (the $ReferenceToArrayOfMissingModules parameter). The ninth
    # positional parameter is a reference to an array to store the names of
    # out-of-date modules (the $ReferenceToArrayOfOutOfDateModules parameter). The
    # tenth positional parameter is a switch indicating whether to skip the
    # PowerShell version check (the $DoNotCheckPowerShellVersion parameter).
    #
    # This function requires Windows PowerShell 5.0 with .NET Framework 4.5 or
    # newer (minimum runtime requirement), and supports newer versions of Windows
    # PowerShell (at least up to and including Windows PowerShell 5.1 with .NET
    # Framework 4.8 or newer), PowerShell Core 6.x, and PowerShell 7.x. This
    # function supports Windows and, when run on PowerShell Core 6.x or PowerShell
    # 7.x, also supports macOS and Linux. While the function requires PowerShell
    # 5.0+ at runtime, the syntax is compatible with Windows PowerShell 1.0
    # parsing to avoid parser errors when loaded as a library function in older
    # environments.
    #
    # Version: 2.2.20251231.1

    #region License ############################################################
    # Copyright (c) 2025 Frank Lesniak
    #
    # Permission is hereby granted, free of charge, to any person obtaining a copy
    # of this software and associated documentation files (the "Software"), to deal
    # in the Software without restriction, including without limitation the rights
    # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    # copies of the Software, and to permit persons to whom the Software is
    # furnished to do so, subject to the following conditions:
    #
    # The above copyright notice and this permission notice shall be included in
    # all copies or substantial portions of the Software.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    # SOFTWARE.
    #endregion License ############################################################

    param (
        [hashtable]$HashtableOfInstalledModules = $null,
        [switch]$ThrowErrorIfModuleNotInstalled,
        [switch]$ThrowWarningIfModuleNotInstalled,
        [switch]$ThrowErrorIfModuleNotUpToDate,
        [switch]$ThrowWarningIfModuleNotUpToDate,
        [hashtable]$HashtableOfCustomNotInstalledMessages = $null,
        [hashtable]$HashtableOfCustomNotUpToDateMessages = $null,
        [ref]$ReferenceToArrayOfMissingModules = ([ref]$null),
        [ref]$ReferenceToArrayOfOutOfDateModules = ([ref]$null),
        [switch]$DoNotCheckPowerShellVersion
    )

    function Get-PSVersion {
        # .SYNOPSIS
        # Returns the version of PowerShell that is running.
        #
        # .DESCRIPTION
        # The function outputs a [version] object representing the version of
        # PowerShell that is running.
        #
        # On versions of PowerShell greater than or equal to version 2.0, this
        # function returns the equivalent of $PSVersionTable.PSVersion
        #
        # PowerShell 1.0 does not have a $PSVersionTable variable, so this
        # function returns [version]('1.0') on PowerShell 1.0.
        #
        # .EXAMPLE
        # $versionPS = Get-PSVersion
        # # $versionPS now contains the version of PowerShell that is running.
        # # On versions of PowerShell greater than or equal to version 2.0,
        # # this function returns the equivalent of $PSVersionTable.PSVersion.
        #
        # .INPUTS
        # None. You can't pipe objects to Get-PSVersion.
        #
        # .OUTPUTS
        # System.Version. Get-PSVersion returns a [version] value indiciating
        # the version of PowerShell that is running.
        #
        # .NOTES
        # Version: 1.0.20250106.0

        #region License ####################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining
        # a copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to
        # permit persons to whom the Software is furnished to do so, subject to
        # the following conditions:
        #
        # The above copyright notice and this permission notice shall be
        # included in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
        # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
        # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        # SOFTWARE.
        #endregion License ####################################################

        if (Test-Path variable:\PSVersionTable) {
            return ($PSVersionTable.PSVersion)
        } else {
            return ([version]('1.0'))
        }
    }

    function Convert-StringToFlexibleVersion {
        # .SYNOPSIS
        # Converts a string to a version object. However, when the string contains
        # characters not allowed in a version object, this function will attempt to
        # convert the string to a version object by removing the characters that are
        # not allowed, identifying the portions of the version object that are
        # not allowed, which can be evaluated further if needed.
        #
        # .DESCRIPTION
        # First attempts to convert a string to a version object. If the string
        # contains characters not allowed in a version object, this function will
        # iteratively attempt to convert the string to a version object by removing
        # period-separated substrings, working right to left, until the version is
        # successfully converted. Then, for the portions that could not be
        # converted, the function will select the numerical-only portions of the
        # problematic substrings and use those to generate a "best effort" version
        # object. The leftover portions of the substrings that could not be
        # converted will be returned by reference.
        #
        # .PARAMETER ReferenceToVersionObject
        # This parameter is required; it is a reference to a System.Version object
        # that will be used to store the version object that is generated from the
        # string. If the string is successfully converted to a version object, the
        # version object will be stored in this reference. If one or more portions
        # of the string could not be converted to a version object, the version
        # object will be generated from the portions that could be converted, and
        # the portions that could not be converted will be stored in the
        # other reference parameters.
        #
        # .PARAMETER ReferenceArrayOfLeftoverStrings
        # This parameter is required; it is a reference to an array of five
        # elements. Each element is a string; One or more of the elements may be
        # modified if the string could not be converted to a version object. If the
        # string could not be converted to a version object, any portions of the
        # string that exceed the major, minor, build, and revision version portions
        # will be stored in the elements of the array.
        #
        # The first element of the array will be modified if the major version
        # portion of the string could not be converted to a version object. If the
        # major version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the major version will be
        # used to generate the version object. The remaining portion of the major
        # version will be stored in the first element of the array.
        #
        # The second element of the array will be modified if the minor version
        # portion of the string could not be converted to a version object. If the
        # minor version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the minor version will be
        # used to generate the version object. The remaining portion of the minor
        # version will be stored in second element of the array.
        #
        # If the major version portion of the string could not be converted to a
        # version object, the entire minor version portion of the string will be
        # stored in the second element, and no portion of the supplied minor
        # version reference will be used to generate the version object.
        #
        # The third element of the array will be modified if the build version
        # portion of the string could not be converted to a version object. If the
        # build version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the build version will be
        # used to generate the version object. The remaining portion of the build
        # version will be stored in the third element of the array.
        #
        # If the major or minor version portions of the string could not be
        # converted to a version object, the entire build version portion of the
        # string will be stored in the third element, and no portion of the
        # supplied build version reference will be used to generate the version
        # object.
        #
        # The fourth element of the array will be modified if the revision version
        # portion of the string could not be converted to a version object. If the
        # revision version portion of the string could not be converted to a
        # version object, the left-most numerical-only portion of the revision
        # version will be used to generate the version object. The remaining
        # portion of the revision version will be stored in the fourth element of
        # the array.
        #
        # If the major, minor, or build version portions of the string could not be
        # converted to a version object, the entire revision version portion of the
        # string will be stored in the fourth element, and no portion of the
        # supplied revision version reference will be used to generate the version
        # object.
        #
        # The fifth element of the array will be modified if the string could not
        # be converted to a version object. If the string could not be converted to
        # a version object, any portions of the string that exceed the major,
        # minor, build, and revision version portions will be stored in the string
        # reference.
        #
        # For example, if the string is '1.2.3.4.5', the fifth element in the array
        # will be '5'. If the string is '1.2.3.4.5.6', the fifth element of the
        # array will be '5.6'.
        #
        # .PARAMETER StringToConvert
        # This parameter is required; it is string that will be converted to a
        # version object. If the string contains characters not allowed in a
        # version object, this function will attempt to convert the string to a
        # version object by removing the characters that are not allowed,
        # identifying the portions of the version object that are not allowed,
        # which can be evaluated further if needed.
        #
        # .PARAMETER PSVersion
        # This parameter is optional; it is a version object that represents the
        # version of PowerShell that is running the script. If this parameter is
        # supplied, it will improve the performance of the function by allowing it
        # to skip the determination of the PowerShell engine version.
        #
        # .EXAMPLE
        # $version = $null
        # $arrLeftoverStrings = @('', '', '', '', '')
        # $strVersion = '1.2.3.4'
        # $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$version) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $strVersion
        # # $intReturnCode will be 0 because the string is in a valid format for a
        # # version object.
        # # $version will be a System.Version object with Major=1, Minor=2,
        # # Build=3, Revision=4.
        # # All strings in $arrLeftoverStrings will be empty.
        #
        # .EXAMPLE
        # $version = $null
        # $arrLeftoverStrings = @('', '', '', '', '')
        # $strVersion = '1.2.3.4-beta3'
        # $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$version) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $strVersion
        # # $intReturnCode will be 4 because the string is not in a valid format
        # # for a version object. The 4 indicates that the revision version portion
        # # of the string could not be converted to a version object.
        # # $version will be a System.Version object with Major=1, Minor=2,
        # # Build=3, Revision=4.
        # # $arrLeftoverStrings[3] will be '-beta3'. All other elements of
        # # $arrLeftoverStrings will be empty.
        #
        # .EXAMPLE
        # $version = $null
        # $arrLeftoverStrings = @('', '', '', '', '')
        # $strVersion = '1.2.2147483700.4'
        # $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$version) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $strVersion
        # # $intReturnCode will be 3 because the string is not in a valid format
        # # for a version object. The 3 indicates that the build version portion of
        # # the string could not be converted to a version object (the value
        # # exceeds the maximum value for a version element - 2147483647).
        # # $version will be a System.Version object with Major=1, Minor=2,
        # # Build=2147483647, Revision=-1.
        # # $arrLeftoverStrings[2] will be '53' (2147483700 - 2147483647) and
        # # $arrLeftoverStrings[3] will be '4'. All other elements of
        # # $arrLeftoverStrings will be empty.
        #
        # .EXAMPLE
        # $version = $null
        # $arrLeftoverStrings = @('', '', '', '', '')
        # $strVersion = '1.2.2147483700-beta5.4'
        # $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$version) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $strVersion
        # # $intReturnCode will be 3 because the string is not in a valid format
        # # for a version object. The 3 indicates that the build version portion of
        # # the string could not be converted to a version object (the value
        # # exceeds the maximum value for a version element - 2147483647).
        # # $version will be a System.Version object with Major=1, Minor=2,
        # # Build=2147483647, Revision=-1.
        # # $arrLeftoverStrings[2] will be '53-beta5' (2147483700 - 2147483647)
        # # plus the non-numeric portion of the string ('-beta5') and
        # # $arrLeftoverStrings[3] will be '4'. All other elements of
        # # $arrLeftoverStrings will be empty.
        #
        # .EXAMPLE
        # $version = $null
        # $arrLeftoverStrings = @('', '', '', '', '')
        # $strVersion = '1.2.3.4.5'
        # $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$version) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $strVersion
        # # $intReturnCode will be 5 because the string is in a valid format for a
        # # version object. The 5 indicates that there were excess portions of the
        # # string that could not be converted to a version object.
        # # $version will be a System.Version object with Major=1, Minor=2,
        # # Build=3, Revision=4.
        # # $arrLeftoverStrings[4] will be '5'. All other elements of
        # # $arrLeftoverStrings will be empty.
        #
        # .INPUTS
        # None. You can't pipe objects to Convert-StringToFlexibleVersion.
        #
        # .OUTPUTS
        # System.Int32. Convert-StringToFlexibleVersion returns an integer value
        # indicating whether the string was successfully converted to a version
        # object. The return value is as follows:
        # 0: The string was successfully converted to a version object.
        # 1: The string could not be converted to a version object because the
        #    major version portion of the string contained characters that made it
        #    impossible to convert to a version object. With these characters
        #    removed, the major version portion of the string was converted to a
        #    version object.
        # 2: The string could not be converted to a version object because the
        #    minor version portion of the string contained characters that made it
        #    impossible to convert to a version object. With these characters
        #    removed, the minor version portion of the string was converted to a
        #    version object.
        # 3: The string could not be converted to a version object because the
        #    build version portion of the string contained characters that made it
        #    impossible to convert to a version object. With these characters
        #    removed, the build version portion of the string was converted to a
        #    version object.
        # 4: The string could not be converted to a version object because the
        #    revision version portion of the string contained characters that made
        #    it impossible to convert to a version object. With these characters
        #    removed, the revision version portion of the string was converted to a
        #    version object.
        # 5: The string was successfully converted to a version object, but there
        #    were excess portions of the string that could not be converted to a
        #    version object.
        # -1: The string could not be converted to a version object because the
        #     string did not begin with numerical characters.
        #
        # .NOTES
        # This function also supports the use of positional parameters instead of
        # named parameters. If positional parameters are used instead of named
        # parameters, then three or four positional parameters are required:
        #
        # The first positional parameter is a reference to a System.Version object
        # that will be used to store the version object that is generated from the
        # string. If the string is successfully converted to a version object, the
        # version object will be stored in this reference. If one or more portions
        # of the string could not be converted to a version object, the version
        # object will be generated from the portions that could be converted, and
        # the portions that could not be converted will be stored in the
        # other reference parameters.
        #
        # The second positional parameter is a reference to an array of five
        # elements. Each element is a string; One or more of the elements may be
        # modified if the string could not be converted to a version object. If the
        # string could not be converted to a version object, any portions of the
        # string that exceed the major, minor, build, and revision version portions
        # will be stored in the elements of the array.
        #
        # The first element of the array will be modified if the major version
        # portion of the string could not be converted to a version object. If the
        # major version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the major version will be
        # used to generate the version object. The remaining portion of the major
        # version will be stored in the first element of the array.
        #
        # The second element of the array will be modified if the minor version
        # portion of the string could not be converted to a version object. If the
        # minor version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the minor version will be
        # used to generate the version object. The remaining portion of the minor
        # version will be stored in second element of the array.
        #
        # If the major version portion of the string could not be converted to a
        # version object, the entire minor version portion of the string will be
        # stored in the second element, and no portion of the supplied minor
        # version reference will be used to generate the version object.
        #
        # The third element of the array will be modified if the build version
        # portion of the string could not be converted to a version object. If the
        # build version portion of the string could not be converted to a version
        # object, the left-most numerical-only portion of the build version will be
        # used to generate the version object. The remaining portion of the build
        # version will be stored in the third element of the array.
        #
        # If the major or minor version portions of the string could not be
        # converted to a version object, the entire build version portion of the
        # string will be stored in the third element, and no portion of the
        # supplied build version reference will be used to generate the version
        # object.
        #
        # The fourth element of the array will be modified if the revision version
        # portion of the string could not be converted to a version object. If the
        # revision version portion of the string could not be converted to a
        # version object, the left-most numerical-only portion of the revision
        # version will be used to generate the version object. The remaining
        # portion of the revision version will be stored in the fourth element of
        # the array.
        #
        # If the major, minor, or build version portions of the string could not be
        # converted to a version object, the entire revision version portion of the
        # string will be stored in the fourth element, and no portion of the
        # supplied revision version reference will be used to generate the version
        # object.
        #
        # The fifth element of the array will be modified if the string could not
        # be converted to a version object. If the string could not be converted to
        # a version object, any portions of the string that exceed the major,
        # minor, build, and revision version portions will be stored in the string
        # reference.
        #
        # For example, if the string is '1.2.3.4.5', the fifth element in the array
        # will be '5'. If the string is '1.2.3.4.5.6', the fifth element of the
        # array will be '5.6'.
        #
        # The third positional parameter is string that will be converted to a
        # version object. If the string contains characters not allowed in a
        # version object, this function will attempt to convert the string to a
        # version object by removing the characters that are not allowed,
        # identifying the portions of the version object that are not allowed,
        # which can be evaluated further if needed.
        #
        # If supplied, the fourth positional parameter is a version object that
        # represents the version of PowerShell that is running the script. If this
        # parameter is supplied, it will improve the performance of the function by
        # allowing it to skip the determination of the PowerShell engine version.
        #
        # Version: 1.0.20250218.0

        #region License ########################################################
        # Copyright (c) 2025 Frank Lesniak
        #
        # Permission is hereby granted, free of charge, to any person obtaining a
        # copy of this software and associated documentation files (the
        # "Software"), to deal in the Software without restriction, including
        # without limitation the rights to use, copy, modify, merge, publish,
        # distribute, sublicense, and/or sell copies of the Software, and to permit
        # persons to whom the Software is furnished to do so, subject to the
        # following conditions:
        #
        # The above copyright notice and this permission notice shall be included
        # in all copies or substantial portions of the Software.
        #
        # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
        # OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
        # NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
        # DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
        # OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
        # USE OR OTHER DEALINGS IN THE SOFTWARE.
        #endregion License ########################################################

        param (
            [ref]$ReferenceToVersionObject = ([ref]$null),
            [ref]$ReferenceArrayOfLeftoverStrings = ([ref]$null),
            [string]$StringToConvert = '',
            [version]$PSVersion = ([version]'0.0')
        )

        function Convert-StringToVersionSafely {
            # .SYNOPSIS
            # Attempts to convert a string to a System.Version object.
            #
            # .DESCRIPTION
            # Attempts to convert a string to a System.Version object. If the
            # string cannot be converted to a System.Version object, the function
            # suppresses the error and returns $false. If the string can be
            # converted to a version object, the function returns $true and passes
            # the version object by reference to the caller.
            #
            # .PARAMETER ReferenceToVersionObject
            # This parameter is required; it is a reference to a System.Version
            # object that will be used to store the converted version object if the
            # conversion is successful.
            #
            # .PARAMETER StringToConvert
            # This parameter is required; it is a string that is to be converted to
            # a System.Version object.
            #
            # .EXAMPLE
            # $version = $null
            # $strVersion = '1.2.3.4'
            # $boolSuccess = Convert-StringToVersionSafely -ReferenceToVersionObject ([ref]$version) -StringToConvert $strVersion
            # # $boolSuccess will be $true, indicating that the conversion was
            # # successful.
            # # $version will contain a System.Version object with major version 1,
            # # minor version 2, build version 3, and revision version 4.
            #
            # .EXAMPLE
            # $version = $null
            # $strVersion = '1'
            # $boolSuccess = Convert-StringToVersionSafely -ReferenceToVersionObject ([ref]$version) -StringToConvert $strVersion
            # # $boolSuccess will be $false, indicating that the conversion was
            # # unsuccessful.
            # # $version is undefined in this instance.
            #
            # .INPUTS
            # None. You can't pipe objects to Convert-StringToVersionSafely.
            #
            # .OUTPUTS
            # System.Boolean. Convert-StringToVersionSafely returns a boolean value
            # indiciating whether the process completed successfully. $true means
            # the conversion completed successfully; $false means there was an
            # error.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is a reference to a System.Version
            # object that will be used to store the converted version object if the
            # conversion is successful.
            #
            # The second positional parameter is a string that is to be converted
            # to a System.Version object.
            #
            # Version: 1.0.20250215.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [ref]$ReferenceToVersionObject = ([ref]$null),
                [string]$StringToConvert = ''
            )

            #region FunctionsToSupportErrorHandling ############################
            function Get-ReferenceToLastError {
                # .SYNOPSIS
                # Gets a reference (memory pointer) to the last error that
                # occurred.
                #
                # .DESCRIPTION
                # Returns a reference (memory pointer) to $null ([ref]$null) if no
                # errors on on the $error stack; otherwise, returns a reference to
                # the last error that occurred.
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work:
                # $refLastKnownError = Get-ReferenceToLastError
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will suppress
                # # error output. Terminating errors will not output anything, kick
                # # to the empty trap statement and then continue on. Likewise, non-
                # # terminating errors will also not output anything, but they do not
                # # kick to the trap statement; they simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # $refNewestCurrentError = Get-ReferenceToLastError
                #
                # $boolErrorOccurred = $false
                # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #     # Both not $null
                #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # } else {
                #     # One is $null, or both are $null
                #     # NOTE: $refLastKnownError could be non-null, while
                #     # $refNewestCurrentError could be null if $error was cleared;
                #     # this does not indicate an error.
                #     #
                #     # So:
                #     # If both are null, no error.
                #     # If $refLastKnownError is null and $refNewestCurrentError is
                #     # non-null, error.
                #     # If $refLastKnownError is non-null and $refNewestCurrentError
                #     # is null, no error.
                #     #
                #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Get-ReferenceToLastError.
                #
                # .OUTPUTS
                # System.Management.Automation.PSReference ([ref]).
                # Get-ReferenceToLastError returns a reference (memory pointer) to
                # the last error that occurred. It returns a reference to $null
                # ([ref]$null) if there are no errors on on the $error stack.
                #
                # .NOTES
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################

                if ($Error.Count -gt 0) {
                    return ([ref]($Error[0]))
                } else {
                    return ([ref]$null)
                }
            }

            function Test-ErrorOccurred {
                # .SYNOPSIS
                # Checks to see if an error occurred during a time period, i.e.,
                # during the execution of a command.
                #
                # .DESCRIPTION
                # Using two references (memory pointers) to errors, this function
                # checks to see if an error occurred based on differences between
                # the two errors.
                #
                # To use this function, you must first retrieve a reference to the
                # last error that occurred prior to the command you are about to
                # run. Then, run the command. After the command completes, retrieve
                # a reference to the last error that occurred. Pass these two
                # references to this function to determine if an error occurred.
                #
                # .PARAMETER ReferenceToEarlierError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time,
                # ReferenceToEarlierError must be a reference to $null
                # ([ref]$null).
                #
                # .PARAMETER ReferenceToLaterError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time, ReferenceToLaterError
                # must be a reference to $null ([ref]$null).
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work
                # if ($Error.Count -gt 0) {
                #     $refLastKnownError = ([ref]($Error[0]))
                # } else {
                #     $refLastKnownError = ([ref]$null)
                # }
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will
                # # suppress error output. Terminating errors will not output
                # # anything, kick to the empty trap statement and then continue
                # # on. Likewise, non- terminating errors will also not output
                # # anything, but they do not kick to the trap statement; they
                # # simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # if ($Error.Count -gt 0) {
                #     $refNewestCurrentError = ([ref]($Error[0]))
                # } else {
                #     $refNewestCurrentError = ([ref]$null)
                # }
                #
                # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                #     # Error occurred
                # } else {
                #     # No error occurred
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Test-ErrorOccurred.
                #
                # .OUTPUTS
                # System.Boolean. Test-ErrorOccurred returns a boolean value
                # indicating whether an error occurred during the time period in
                # question. $true indicates an error occurred; $false indicates no
                # error occurred.
                #
                # .NOTES
                # This function also supports the use of positional parameters
                # instead of named parameters. If positional parameters are used
                # instead of named parameters, then two positional parameters are
                # required:
                #
                # The first positional parameter is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time, the first
                # positional parameter must be a reference to $null ([ref]$null).
                #
                # The second positional parameter is a reference (memory pointer)
                # to a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time,
                # ReferenceToLaterError must be a reference to $null ([ref]$null).
                #
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################
                param (
                    [ref]$ReferenceToEarlierError = ([ref]$null),
                    [ref]$ReferenceToLaterError = ([ref]$null)
                )

                # TODO: Validate input

                $boolErrorOccurred = $false
                if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                    # Both not $null
                    if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                } else {
                    # One is $null, or both are $null
                    # NOTE: $ReferenceToEarlierError could be non-null, while
                    # $ReferenceToLaterError could be null if $error was cleared;
                    # this does not indicate an error.
                    # So:
                    # - If both are null, no error.
                    # - If $ReferenceToEarlierError is null and
                    #   $ReferenceToLaterError is non-null, error.
                    # - If $ReferenceToEarlierError is non-null and
                    #   $ReferenceToLaterError is null, no error.
                    if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                }

                return $boolErrorOccurred
            }
            #endregion FunctionsToSupportErrorHandling ############################

            trap {
                # Intentionally left empty to prevent terminating errors from
                # halting processing
            }

            # Retrieve the newest error on the stack prior to doing work
            $refLastKnownError = Get-ReferenceToLastError

            # Store current error preference; we will restore it after we do the
            # work of this function
            $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

            # Set ErrorActionPreference to SilentlyContinue; this will suppress
            # error output. Terminating errors will not output anything, kick to
            # the empty trap statement and then continue on. Likewise, non-
            # terminating errors will also not output anything, but they do not
            # kick to the trap statement; they simply continue on.
            $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

            $ReferenceToVersionObject.Value = [version]$StringToConvert

            # Restore the former error preference
            $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

            # Retrieve the newest error on the error stack
            $refNewestCurrentError = Get-ReferenceToLastError

            if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                # Error occurred; return failure indicator:
                return $false
            } else {
                # No error occurred; return success indicator:
                return $true
            }
        }

        function Split-StringOnLiteralString {
            # .SYNOPSIS
            # Splits a string into an array using a literal string as the splitter.
            #
            # .DESCRIPTION
            # Splits a string using a literal string (as opposed to regex). The
            # function is designed to be backward-compatible with all versions of
            # PowerShell and has been tested successfully on PowerShell v1. This
            # function behaves more like VBScript's Split() function than other
            # string splitting-approaches in PowerShell while avoiding the use of
            # RegEx.
            #
            # .PARAMETER StringToSplit
            # This parameter is required; it is the string to be split into an
            # array.
            #
            # .PARAMETER Splitter
            # This parameter is required; it is the string that will be used to
            # split the string specified in the StringToSplit parameter.
            #
            # .EXAMPLE
            # $result = Split-StringOnLiteralString -StringToSplit 'What do you think of this function?' -Splitter ' '
            # # $result.Count is 7
            # # $result[2] is 'you'
            #
            # .EXAMPLE
            # $result = Split-StringOnLiteralString 'What do you think of this function?' ' '
            # # $result.Count is 7
            #
            # .EXAMPLE
            # $result = Split-StringOnLiteralString -StringToSplit 'foo' -Splitter ' '
            # # $result.GetType().FullName is System.Object[]
            # # $result.Count is 1
            #
            # .EXAMPLE
            # $result = Split-StringOnLiteralString -StringToSplit 'foo' -Splitter ''
            # # $result.GetType().FullName is System.Object[]
            # # $result.Count is 5 because of how .NET handles a split using an
            # # empty string:
            # # $result[0] is ''
            # # $result[1] is 'f'
            # # $result[2] is 'o'
            # # $result[3] is 'o'
            # # $result[4] is ''
            #
            # .INPUTS
            # None. You can't pipe objects to Split-StringOnLiteralString.
            #
            # .OUTPUTS
            # System.String[]. Split-StringOnLiteralString returns an array of
            # strings, with each string being an element of the resulting array
            # from the split operation. This function always returns an array, even
            # when there is zero elements or one element in it.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is the string to be split into an
            # array.
            #
            # The second positional parameter is the string that will be used to
            # split the string specified in the first positional parameter.
            #
            # Also, please note that if -StringToSplit (or the first positional
            # parameter) is $null, then the function will return an array with one
            # element, which is an empty string. This is because the function
            # converts $null to an empty string before splitting the string.
            #
            # Version: 3.0.20250211.1

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [string]$StringToSplit = '',
                [string]$Splitter = ''
            )

            $strSplitterInRegEx = [regex]::Escape($Splitter)
            $result = @([regex]::Split($StringToSplit, $strSplitterInRegEx))

            # The following code forces the function to return an array, always,
            # even when there are zero or one elements in the array
            $intElementCount = 1
            if ($null -ne $result) {
                if ($result.GetType().FullName.Contains('[]')) {
                    if (($result.Count -ge 2) -or ($result.Count -eq 0)) {
                        $intElementCount = $result.Count
                    }
                }
            }
            $strLowercaseFunctionName = $MyInvocation.InvocationName.ToLower()
            $boolArrayEncapsulation = $MyInvocation.Line.ToLower().Contains('@(' + $strLowercaseFunctionName + ')') -or $MyInvocation.Line.ToLower().Contains('@(' + $strLowercaseFunctionName + ' ')
            if ($boolArrayEncapsulation) {
                return ($result)
            } elseif ($intElementCount -eq 0) {
                return (, @())
            } elseif ($intElementCount -eq 1) {
                return (, (, $StringToSplit))
            } else {
                return ($result)
            }
        }

        function Convert-StringToInt32Safely {
            # .SYNOPSIS
            # Attempts to convert a string to a System.Int32.
            #
            # .DESCRIPTION
            # Attempts to convert a string to a System.Int32. If the string
            # cannot be converted to a System.Int32, the function suppresses the
            # error and returns $false. If the string can be converted to an
            # int32, the function returns $true and passes the int32 by
            # reference to the caller.
            #
            # .PARAMETER ReferenceToInt32
            # This parameter is required; it is a reference to a System.Int32
            # object that will be used to store the converted int32 object if the
            # conversion is successful.
            #
            # .PARAMETER StringToConvert
            # This parameter is required; it is a string that is to be converted to
            # a System.Int32 object.
            #
            # .EXAMPLE
            # $int = $null
            # $strInt = '1234'
            # $boolSuccess = Convert-StringToInt32Safely -ReferenceToInt32 ([ref]$int) -StringToConvert $strInt
            # # $boolSuccess will be $true, indicating that the conversion was
            # # successful.
            # # $int will contain a System.Int32 object equal to 1234.
            #
            # .EXAMPLE
            # $int = $null
            # $strInt = 'abc'
            # $boolSuccess = Convert-StringToInt32Safely -ReferenceToInt32 ([ref]$int) -StringToConvert $strInt
            # # $boolSuccess will be $false, indicating that the conversion was
            # # unsuccessful.
            # # $int will be undefined in this case.
            #
            # .INPUTS
            # None. You can't pipe objects to Convert-StringToInt32Safely.
            #
            # .OUTPUTS
            # System.Boolean. Convert-StringToInt32Safely returns a boolean value
            # indiciating whether the process completed successfully. $true means
            # the conversion completed successfully; $false means there was an
            # error.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is a reference to a System.Int32
            # object that will be used to store the converted int32 object if the
            # conversion is successful.
            #
            # The second positional parameter is a string that is to be converted
            # to a System.Int32 object.
            #
            # Version: 1.0.20250215.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [ref]$ReferenceToInt32 = ([ref]$null),
                [string]$StringToConvert = ''
            )

            #region FunctionsToSupportErrorHandling ############################
            function Get-ReferenceToLastError {
                # .SYNOPSIS
                # Gets a reference (memory pointer) to the last error that
                # occurred.
                #
                # .DESCRIPTION
                # Returns a reference (memory pointer) to $null ([ref]$null) if no
                # errors on on the $error stack; otherwise, returns a reference to
                # the last error that occurred.
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work:
                # $refLastKnownError = Get-ReferenceToLastError
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will suppress
                # # error output. Terminating errors will not output anything, kick
                # # to the empty trap statement and then continue on. Likewise, non-
                # # terminating errors will also not output anything, but they do not
                # # kick to the trap statement; they simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # $refNewestCurrentError = Get-ReferenceToLastError
                #
                # $boolErrorOccurred = $false
                # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #     # Both not $null
                #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # } else {
                #     # One is $null, or both are $null
                #     # NOTE: $refLastKnownError could be non-null, while
                #     # $refNewestCurrentError could be null if $error was cleared;
                #     # this does not indicate an error.
                #     #
                #     # So:
                #     # If both are null, no error.
                #     # If $refLastKnownError is null and $refNewestCurrentError is
                #     # non-null, error.
                #     # If $refLastKnownError is non-null and $refNewestCurrentError
                #     # is null, no error.
                #     #
                #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Get-ReferenceToLastError.
                #
                # .OUTPUTS
                # System.Management.Automation.PSReference ([ref]).
                # Get-ReferenceToLastError returns a reference (memory pointer) to
                # the last error that occurred. It returns a reference to $null
                # ([ref]$null) if there are no errors on on the $error stack.
                #
                # .NOTES
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################

                if ($Error.Count -gt 0) {
                    return ([ref]($Error[0]))
                } else {
                    return ([ref]$null)
                }
            }

            function Test-ErrorOccurred {
                # .SYNOPSIS
                # Checks to see if an error occurred during a time period, i.e.,
                # during the execution of a command.
                #
                # .DESCRIPTION
                # Using two references (memory pointers) to errors, this function
                # checks to see if an error occurred based on differences between
                # the two errors.
                #
                # To use this function, you must first retrieve a reference to the
                # last error that occurred prior to the command you are about to
                # run. Then, run the command. After the command completes, retrieve
                # a reference to the last error that occurred. Pass these two
                # references to this function to determine if an error occurred.
                #
                # .PARAMETER ReferenceToEarlierError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time,
                # ReferenceToEarlierError must be a reference to $null
                # ([ref]$null).
                #
                # .PARAMETER ReferenceToLaterError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time, ReferenceToLaterError
                # must be a reference to $null ([ref]$null).
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work
                # if ($Error.Count -gt 0) {
                #     $refLastKnownError = ([ref]($Error[0]))
                # } else {
                #     $refLastKnownError = ([ref]$null)
                # }
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will
                # # suppress error output. Terminating errors will not output
                # # anything, kick to the empty trap statement and then continue
                # # on. Likewise, non- terminating errors will also not output
                # # anything, but they do not kick to the trap statement; they
                # # simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # if ($Error.Count -gt 0) {
                #     $refNewestCurrentError = ([ref]($Error[0]))
                # } else {
                #     $refNewestCurrentError = ([ref]$null)
                # }
                #
                # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                #     # Error occurred
                # } else {
                #     # No error occurred
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Test-ErrorOccurred.
                #
                # .OUTPUTS
                # System.Boolean. Test-ErrorOccurred returns a boolean value
                # indicating whether an error occurred during the time period in
                # question. $true indicates an error occurred; $false indicates no
                # error occurred.
                #
                # .NOTES
                # This function also supports the use of positional parameters
                # instead of named parameters. If positional parameters are used
                # instead of named parameters, then two positional parameters are
                # required:
                #
                # The first positional parameter is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time, the first
                # positional parameter must be a reference to $null ([ref]$null).
                #
                # The second positional parameter is a reference (memory pointer)
                # to a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time,
                # ReferenceToLaterError must be a reference to $null ([ref]$null).
                #
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################
                param (
                    [ref]$ReferenceToEarlierError = ([ref]$null),
                    [ref]$ReferenceToLaterError = ([ref]$null)
                )

                # TODO: Validate input

                $boolErrorOccurred = $false
                if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                    # Both not $null
                    if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                } else {
                    # One is $null, or both are $null
                    # NOTE: $ReferenceToEarlierError could be non-null, while
                    # $ReferenceToLaterError could be null if $error was cleared;
                    # this does not indicate an error.
                    # So:
                    # - If both are null, no error.
                    # - If $ReferenceToEarlierError is null and
                    #   $ReferenceToLaterError is non-null, error.
                    # - If $ReferenceToEarlierError is non-null and
                    #   $ReferenceToLaterError is null, no error.
                    if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                }

                return $boolErrorOccurred
            }
            #endregion FunctionsToSupportErrorHandling ############################

            trap {
                # Intentionally left empty to prevent terminating errors from
                # halting processing
            }

            # Retrieve the newest error on the stack prior to doing work
            $refLastKnownError = Get-ReferenceToLastError

            # Store current error preference; we will restore it after we do the
            # work of this function
            $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

            # Set ErrorActionPreference to SilentlyContinue; this will suppress
            # error output. Terminating errors will not output anything, kick to
            # the empty trap statement and then continue on. Likewise, non-
            # terminating errors will also not output anything, but they do not
            # kick to the trap statement; they simply continue on.
            $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

            $ReferenceToInt32.Value = [int32]$StringToConvert

            # Restore the former error preference
            $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

            # Retrieve the newest error on the error stack
            $refNewestCurrentError = Get-ReferenceToLastError

            if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                # Error occurred; return failure indicator:
                return $false
            } else {
                # No error occurred; return success indicator:
                return $true
            }
        }

        function Convert-StringToInt64Safely {
            # .SYNOPSIS
            # Attempts to convert a string to a System.Int64.
            #
            # .DESCRIPTION
            # Attempts to convert a string to a System.Int64. If the string
            # cannot be converted to a System.Int64, the function suppresses the
            # error and returns $false. If the string can be converted to an
            # int64, the function returns $true and passes the int64 by
            # reference to the caller.
            #
            # .PARAMETER ReferenceToInt64
            # This parameter is required; it is a reference to a System.Int64
            # object that will be used to store the converted int64 object if the
            # conversion is successful.
            #
            # .PARAMETER StringToConvert
            # This parameter is required; it is a string that is to be converted to
            # a System.Int64 object.
            #
            # .EXAMPLE
            # $int = $null
            # $strInt = '1234'
            # $boolSuccess = Convert-StringToInt64Safely -ReferenceToInt64 ([ref]$int) -StringToConvert $strInt
            # # $boolSuccess will be $true, indicating that the conversion was
            # # successful.
            # # $int will contain a System.Int64 object equal to 1234.
            #
            # .EXAMPLE
            # $int = $null
            # $strInt = 'abc'
            # $boolSuccess = Convert-StringToInt64Safely -ReferenceToInt64 ([ref]$int) -StringToConvert $strInt
            # # $boolSuccess will be $false, indicating that the conversion was
            # # unsuccessful.
            # # $int will be undefined in this case.
            #
            # .INPUTS
            # None. You can't pipe objects to Convert-StringToInt64Safely.
            #
            # .OUTPUTS
            # System.Boolean. Convert-StringToInt64Safely returns a boolean value
            # indiciating whether the process completed successfully. $true means
            # the conversion completed successfully; $false means there was an
            # error.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is a reference to a System.Int64
            # object that will be used to store the converted int64 object if the
            # conversion is successful.
            #
            # The second positional parameter is a string that is to be converted
            # to a System.Int64 object.
            #
            # Version: 1.0.20250215.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [ref]$ReferenceToInt64 = ([ref]$null),
                [string]$StringToConvert = ''
            )

            #region FunctionsToSupportErrorHandling ############################
            function Get-ReferenceToLastError {
                # .SYNOPSIS
                # Gets a reference (memory pointer) to the last error that
                # occurred.
                #
                # .DESCRIPTION
                # Returns a reference (memory pointer) to $null ([ref]$null) if no
                # errors on on the $error stack; otherwise, returns a reference to
                # the last error that occurred.
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work:
                # $refLastKnownError = Get-ReferenceToLastError
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will suppress
                # # error output. Terminating errors will not output anything, kick
                # # to the empty trap statement and then continue on. Likewise, non-
                # # terminating errors will also not output anything, but they do not
                # # kick to the trap statement; they simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # $refNewestCurrentError = Get-ReferenceToLastError
                #
                # $boolErrorOccurred = $false
                # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #     # Both not $null
                #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # } else {
                #     # One is $null, or both are $null
                #     # NOTE: $refLastKnownError could be non-null, while
                #     # $refNewestCurrentError could be null if $error was cleared;
                #     # this does not indicate an error.
                #     #
                #     # So:
                #     # If both are null, no error.
                #     # If $refLastKnownError is null and $refNewestCurrentError is
                #     # non-null, error.
                #     # If $refLastKnownError is non-null and $refNewestCurrentError
                #     # is null, no error.
                #     #
                #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Get-ReferenceToLastError.
                #
                # .OUTPUTS
                # System.Management.Automation.PSReference ([ref]).
                # Get-ReferenceToLastError returns a reference (memory pointer) to
                # the last error that occurred. It returns a reference to $null
                # ([ref]$null) if there are no errors on on the $error stack.
                #
                # .NOTES
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################

                if ($Error.Count -gt 0) {
                    return ([ref]($Error[0]))
                } else {
                    return ([ref]$null)
                }
            }

            function Test-ErrorOccurred {
                # .SYNOPSIS
                # Checks to see if an error occurred during a time period, i.e.,
                # during the execution of a command.
                #
                # .DESCRIPTION
                # Using two references (memory pointers) to errors, this function
                # checks to see if an error occurred based on differences between
                # the two errors.
                #
                # To use this function, you must first retrieve a reference to the
                # last error that occurred prior to the command you are about to
                # run. Then, run the command. After the command completes, retrieve
                # a reference to the last error that occurred. Pass these two
                # references to this function to determine if an error occurred.
                #
                # .PARAMETER ReferenceToEarlierError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time,
                # ReferenceToEarlierError must be a reference to $null
                # ([ref]$null).
                #
                # .PARAMETER ReferenceToLaterError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time, ReferenceToLaterError
                # must be a reference to $null ([ref]$null).
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work
                # if ($Error.Count -gt 0) {
                #     $refLastKnownError = ([ref]($Error[0]))
                # } else {
                #     $refLastKnownError = ([ref]$null)
                # }
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will
                # # suppress error output. Terminating errors will not output
                # # anything, kick to the empty trap statement and then continue
                # # on. Likewise, non- terminating errors will also not output
                # # anything, but they do not kick to the trap statement; they
                # # simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # if ($Error.Count -gt 0) {
                #     $refNewestCurrentError = ([ref]($Error[0]))
                # } else {
                #     $refNewestCurrentError = ([ref]$null)
                # }
                #
                # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                #     # Error occurred
                # } else {
                #     # No error occurred
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Test-ErrorOccurred.
                #
                # .OUTPUTS
                # System.Boolean. Test-ErrorOccurred returns a boolean value
                # indicating whether an error occurred during the time period in
                # question. $true indicates an error occurred; $false indicates no
                # error occurred.
                #
                # .NOTES
                # This function also supports the use of positional parameters
                # instead of named parameters. If positional parameters are used
                # instead of named parameters, then two positional parameters are
                # required:
                #
                # The first positional parameter is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time, the first
                # positional parameter must be a reference to $null ([ref]$null).
                #
                # The second positional parameter is a reference (memory pointer)
                # to a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time,
                # ReferenceToLaterError must be a reference to $null ([ref]$null).
                #
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################
                param (
                    [ref]$ReferenceToEarlierError = ([ref]$null),
                    [ref]$ReferenceToLaterError = ([ref]$null)
                )

                # TODO: Validate input

                $boolErrorOccurred = $false
                if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                    # Both not $null
                    if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                } else {
                    # One is $null, or both are $null
                    # NOTE: $ReferenceToEarlierError could be non-null, while
                    # $ReferenceToLaterError could be null if $error was cleared;
                    # this does not indicate an error.
                    # So:
                    # - If both are null, no error.
                    # - If $ReferenceToEarlierError is null and
                    #   $ReferenceToLaterError is non-null, error.
                    # - If $ReferenceToEarlierError is non-null and
                    #   $ReferenceToLaterError is null, no error.
                    if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                }

                return $boolErrorOccurred
            }
            #endregion FunctionsToSupportErrorHandling ############################

            trap {
                # Intentionally left empty to prevent terminating errors from
                # halting processing
            }

            # Retrieve the newest error on the stack prior to doing work
            $refLastKnownError = Get-ReferenceToLastError

            # Store current error preference; we will restore it after we do the
            # work of this function
            $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

            # Set ErrorActionPreference to SilentlyContinue; this will suppress
            # error output. Terminating errors will not output anything, kick to
            # the empty trap statement and then continue on. Likewise, non-
            # terminating errors will also not output anything, but they do not
            # kick to the trap statement; they simply continue on.
            $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

            $ReferenceToInt64.Value = [int64]$StringToConvert

            # Restore the former error preference
            $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

            # Retrieve the newest error on the error stack
            $refNewestCurrentError = Get-ReferenceToLastError

            if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                # Error occurred; return failure indicator:
                return $false
            } else {
                # No error occurred; return success indicator:
                return $true
            }
        }

        function Get-PSVersion {
            # .SYNOPSIS
            # Returns the version of PowerShell that is running.
            #
            # .DESCRIPTION
            # The function outputs a [version] object representing the version of
            # PowerShell that is running.
            #
            # On versions of PowerShell greater than or equal to version 2.0, this
            # function returns the equivalent of $PSVersionTable.PSVersion
            #
            # PowerShell 1.0 does not have a $PSVersionTable variable, so this
            # function returns [version]('1.0') on PowerShell 1.0.
            #
            # .EXAMPLE
            # $versionPS = Get-PSVersion
            # # $versionPS now contains the version of PowerShell that is running.
            # # On versions of PowerShell greater than or equal to version 2.0,
            # # this function returns the equivalent of $PSVersionTable.PSVersion.
            #
            # .INPUTS
            # None. You can't pipe objects to Get-PSVersion.
            #
            # .OUTPUTS
            # System.Version. Get-PSVersion returns a [version] value indiciating
            # the version of PowerShell that is running.
            #
            # .NOTES
            # Version: 1.0.20250106.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            if (Test-Path variable:\PSVersionTable) {
                return ($PSVersionTable.PSVersion)
            } else {
                return ([version]('1.0'))
            }
        }

        function Convert-StringToBigIntegerSafely {
            # .SYNOPSIS
            # Attempts to convert a string to a System.Numerics.BigInteger object.
            #
            # .DESCRIPTION
            # Attempts to convert a string to a System.Numerics.BigInteger object.
            # If the string cannot be converted to a System.Numerics.BigInteger
            # object, the function suppresses the error and returns $false. If the
            # string can be converted to a bigint object, the function returns
            # $true and passes the bigint object by reference to the caller.
            #
            # .PARAMETER ReferenceToBigIntegerObject
            # This parameter is required; it is a reference to a
            # System.Numerics.BigInteger object that will be used to store the
            # converted bigint object if the conversion is successful.
            #
            # .PARAMETER StringToConvert
            # This parameter is required; it is a string that is to be converted to
            # a System.Numerics.BigInteger object.
            #
            # .EXAMPLE
            # $bigint = $null
            # $strBigInt = '100000000000000000000000000000'
            # $boolSuccess = Convert-StringToBigIntegerSafely -ReferenceToBigIntegerObject ([ref]$bigint) -StringToConvert $strBigInt
            # # $boolSuccess will be $true, indicating that the conversion was
            # # successful.
            # # $bigint will contain a System.Numerics.BigInteger object equal to
            # # 100000000000000000000000000000.
            #
            # .EXAMPLE
            # $bigint = $null
            # $strBigInt = 'abc'
            # $boolSuccess = Convert-StringToBigIntegerSafely -ReferenceToBigIntegerObject ([ref]$bigint) -StringToConvert $strBigInt
            # # $boolSuccess will be $false, indicating that the conversion was
            # # unsuccessful.
            # # $bigint will be undefined in this case.
            #
            # .INPUTS
            # None. You can't pipe objects to Convert-StringToBigIntegerSafely.
            #
            # .OUTPUTS
            # System.Boolean. Convert-StringToBigIntegerSafely returns a boolean
            # value indiciating whether the process completed successfully. $true
            # means the conversion completed successfully; $false means there was
            # an error.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is a reference to a
            # System.Numerics.BigInteger object that will be used to store the
            # converted bigint object if the conversion is successful.
            #
            # The second positional parameter is a string that is to be converted
            # to a System.Numerics.BigInteger object.
            #
            # Version: 1.0.20250216.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [ref]$ReferenceToBigIntegerObject = ([ref]$null),
                [string]$StringToConvert = ''
            )

            #region FunctionsToSupportErrorHandling ############################
            function Get-ReferenceToLastError {
                # .SYNOPSIS
                # Gets a reference (memory pointer) to the last error that
                # occurred.
                #
                # .DESCRIPTION
                # Returns a reference (memory pointer) to $null ([ref]$null) if no
                # errors on on the $error stack; otherwise, returns a reference to
                # the last error that occurred.
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work:
                # $refLastKnownError = Get-ReferenceToLastError
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will suppress
                # # error output. Terminating errors will not output anything, kick
                # # to the empty trap statement and then continue on. Likewise, non-
                # # terminating errors will also not output anything, but they do not
                # # kick to the trap statement; they simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # $refNewestCurrentError = Get-ReferenceToLastError
                #
                # $boolErrorOccurred = $false
                # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #     # Both not $null
                #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # } else {
                #     # One is $null, or both are $null
                #     # NOTE: $refLastKnownError could be non-null, while
                #     # $refNewestCurrentError could be null if $error was cleared;
                #     # this does not indicate an error.
                #     #
                #     # So:
                #     # If both are null, no error.
                #     # If $refLastKnownError is null and $refNewestCurrentError is
                #     # non-null, error.
                #     # If $refLastKnownError is non-null and $refNewestCurrentError
                #     # is null, no error.
                #     #
                #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Get-ReferenceToLastError.
                #
                # .OUTPUTS
                # System.Management.Automation.PSReference ([ref]).
                # Get-ReferenceToLastError returns a reference (memory pointer) to
                # the last error that occurred. It returns a reference to $null
                # ([ref]$null) if there are no errors on on the $error stack.
                #
                # .NOTES
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################

                if ($Error.Count -gt 0) {
                    return ([ref]($Error[0]))
                } else {
                    return ([ref]$null)
                }
            }

            function Test-ErrorOccurred {
                # .SYNOPSIS
                # Checks to see if an error occurred during a time period, i.e.,
                # during the execution of a command.
                #
                # .DESCRIPTION
                # Using two references (memory pointers) to errors, this function
                # checks to see if an error occurred based on differences between
                # the two errors.
                #
                # To use this function, you must first retrieve a reference to the
                # last error that occurred prior to the command you are about to
                # run. Then, run the command. After the command completes, retrieve
                # a reference to the last error that occurred. Pass these two
                # references to this function to determine if an error occurred.
                #
                # .PARAMETER ReferenceToEarlierError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time,
                # ReferenceToEarlierError must be a reference to $null
                # ([ref]$null).
                #
                # .PARAMETER ReferenceToLaterError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time, ReferenceToLaterError
                # must be a reference to $null ([ref]$null).
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work
                # if ($Error.Count -gt 0) {
                #     $refLastKnownError = ([ref]($Error[0]))
                # } else {
                #     $refLastKnownError = ([ref]$null)
                # }
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will
                # # suppress error output. Terminating errors will not output
                # # anything, kick to the empty trap statement and then continue
                # # on. Likewise, non- terminating errors will also not output
                # # anything, but they do not kick to the trap statement; they
                # # simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # if ($Error.Count -gt 0) {
                #     $refNewestCurrentError = ([ref]($Error[0]))
                # } else {
                #     $refNewestCurrentError = ([ref]$null)
                # }
                #
                # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                #     # Error occurred
                # } else {
                #     # No error occurred
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Test-ErrorOccurred.
                #
                # .OUTPUTS
                # System.Boolean. Test-ErrorOccurred returns a boolean value
                # indicating whether an error occurred during the time period in
                # question. $true indicates an error occurred; $false indicates no
                # error occurred.
                #
                # .NOTES
                # This function also supports the use of positional parameters
                # instead of named parameters. If positional parameters are used
                # instead of named parameters, then two positional parameters are
                # required:
                #
                # The first positional parameter is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time, the first
                # positional parameter must be a reference to $null ([ref]$null).
                #
                # The second positional parameter is a reference (memory pointer)
                # to a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time,
                # ReferenceToLaterError must be a reference to $null ([ref]$null).
                #
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################
                param (
                    [ref]$ReferenceToEarlierError = ([ref]$null),
                    [ref]$ReferenceToLaterError = ([ref]$null)
                )

                # TODO: Validate input

                $boolErrorOccurred = $false
                if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                    # Both not $null
                    if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                } else {
                    # One is $null, or both are $null
                    # NOTE: $ReferenceToEarlierError could be non-null, while
                    # $ReferenceToLaterError could be null if $error was cleared;
                    # this does not indicate an error.
                    # So:
                    # - If both are null, no error.
                    # - If $ReferenceToEarlierError is null and
                    #   $ReferenceToLaterError is non-null, error.
                    # - If $ReferenceToEarlierError is non-null and
                    #   $ReferenceToLaterError is null, no error.
                    if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                }

                return $boolErrorOccurred
            }
            #endregion FunctionsToSupportErrorHandling ############################

            trap {
                # Intentionally left empty to prevent terminating errors from
                # halting processing
            }

            # Retrieve the newest error on the stack prior to doing work
            $refLastKnownError = Get-ReferenceToLastError

            # Store current error preference; we will restore it after we do the
            # work of this function
            $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

            # Set ErrorActionPreference to SilentlyContinue; this will suppress
            # error output. Terminating errors will not output anything, kick to
            # the empty trap statement and then continue on. Likewise, non-
            # terminating errors will also not output anything, but they do not
            # kick to the trap statement; they simply continue on.
            $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

            $ReferenceToBigIntegerObject.Value = [System.Numerics.BigInteger]$StringToConvert

            # Restore the former error preference
            $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

            # Retrieve the newest error on the error stack
            $refNewestCurrentError = Get-ReferenceToLastError

            if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                # Error occurred; return failure indicator:
                return $false
            } else {
                # No error occurred; return success indicator:
                return $true
            }
        }

        function Convert-StringToDoubleSafely {
            # .SYNOPSIS
            # Attempts to convert a string to a System.Double.
            #
            # .DESCRIPTION
            # Attempts to convert a string to a System.Double. If the string
            # cannot be converted to a System.Double, the function suppresses the
            # error and returns $false. If the string can be converted to an
            # double, the function returns $true and passes the double by
            # reference to the caller.
            #
            # .PARAMETER ReferenceToDouble
            # This parameter is required; it is a reference to a System.Double
            # object that will be used to store the converted double object if the
            # conversion is successful.
            #
            # .PARAMETER StringToConvert
            # This parameter is required; it is a string that is to be converted to
            # a System.Double object.
            #
            # .EXAMPLE
            # $double = $null
            # $str = '100000000000000000000000'
            # $boolSuccess = Convert-StringToDoubleSafely -ReferenceToDouble ([ref]$double) -StringToConvert $str
            # # $boolSuccess will be $true, indicating that the conversion was
            # # successful.
            # # $double will contain a System.Double object equal to 1E+23
            #
            # .EXAMPLE
            # $double = $null
            # $str = 'abc'
            # $boolSuccess = Convert-StringToDoubleSafely -ReferenceToDouble ([ref]$double) -StringToConvert $str
            # # $boolSuccess will be $false, indicating that the conversion was
            # # unsuccessful.
            # # $double will undefined in this case.
            #
            # .INPUTS
            # None. You can't pipe objects to Convert-StringToDoubleSafely.
            #
            # .OUTPUTS
            # System.Boolean. Convert-StringToDoubleSafely returns a boolean value
            # indiciating whether the process completed successfully. $true means
            # the conversion completed successfully; $false means there was an
            # error.
            #
            # .NOTES
            # This function also supports the use of positional parameters instead
            # of named parameters. If positional parameters are used instead of
            # named parameters, then two positional parameters are required:
            #
            # The first positional parameter is a reference to a System.Double
            # object that will be used to store the converted double object if the
            # conversion is successful.
            #
            # The second positional parameter is a string that is to be converted
            # to a System.Double object.
            #
            # Version: 1.0.20250216.0

            #region License ####################################################
            # Copyright (c) 2025 Frank Lesniak
            #
            # Permission is hereby granted, free of charge, to any person obtaining
            # a copy of this software and associated documentation files (the
            # "Software"), to deal in the Software without restriction, including
            # without limitation the rights to use, copy, modify, merge, publish,
            # distribute, sublicense, and/or sell copies of the Software, and to
            # permit persons to whom the Software is furnished to do so, subject to
            # the following conditions:
            #
            # The above copyright notice and this permission notice shall be
            # included in all copies or substantial portions of the Software.
            #
            # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
            # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
            # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
            # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
            # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
            # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
            # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            # SOFTWARE.
            #endregion License ####################################################

            param (
                [ref]$ReferenceToDouble = ([ref]$null),
                [string]$StringToConvert = ''
            )

            #region FunctionsToSupportErrorHandling ############################
            function Get-ReferenceToLastError {
                # .SYNOPSIS
                # Gets a reference (memory pointer) to the last error that
                # occurred.
                #
                # .DESCRIPTION
                # Returns a reference (memory pointer) to $null ([ref]$null) if no
                # errors on on the $error stack; otherwise, returns a reference to
                # the last error that occurred.
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work:
                # $refLastKnownError = Get-ReferenceToLastError
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will suppress
                # # error output. Terminating errors will not output anything, kick
                # # to the empty trap statement and then continue on. Likewise, non-
                # # terminating errors will also not output anything, but they do not
                # # kick to the trap statement; they simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # $refNewestCurrentError = Get-ReferenceToLastError
                #
                # $boolErrorOccurred = $false
                # if (($null -ne $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #     # Both not $null
                #     if (($refLastKnownError.Value) -ne ($refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # } else {
                #     # One is $null, or both are $null
                #     # NOTE: $refLastKnownError could be non-null, while
                #     # $refNewestCurrentError could be null if $error was cleared;
                #     # this does not indicate an error.
                #     #
                #     # So:
                #     # If both are null, no error.
                #     # If $refLastKnownError is null and $refNewestCurrentError is
                #     # non-null, error.
                #     # If $refLastKnownError is non-null and $refNewestCurrentError
                #     # is null, no error.
                #     #
                #     if (($null -eq $refLastKnownError.Value) -and ($null -ne $refNewestCurrentError.Value)) {
                #         $boolErrorOccurred = $true
                #     }
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Get-ReferenceToLastError.
                #
                # .OUTPUTS
                # System.Management.Automation.PSReference ([ref]).
                # Get-ReferenceToLastError returns a reference (memory pointer) to
                # the last error that occurred. It returns a reference to $null
                # ([ref]$null) if there are no errors on on the $error stack.
                #
                # .NOTES
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################

                if ($Error.Count -gt 0) {
                    return ([ref]($Error[0]))
                } else {
                    return ([ref]$null)
                }
            }

            function Test-ErrorOccurred {
                # .SYNOPSIS
                # Checks to see if an error occurred during a time period, i.e.,
                # during the execution of a command.
                #
                # .DESCRIPTION
                # Using two references (memory pointers) to errors, this function
                # checks to see if an error occurred based on differences between
                # the two errors.
                #
                # To use this function, you must first retrieve a reference to the
                # last error that occurred prior to the command you are about to
                # run. Then, run the command. After the command completes, retrieve
                # a reference to the last error that occurred. Pass these two
                # references to this function to determine if an error occurred.
                #
                # .PARAMETER ReferenceToEarlierError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time,
                # ReferenceToEarlierError must be a reference to $null
                # ([ref]$null).
                #
                # .PARAMETER ReferenceToLaterError
                # This parameter is required; it is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred.
                #
                # If no error was on the stack at this time, ReferenceToLaterError
                # must be a reference to $null ([ref]$null).
                #
                # .EXAMPLE
                # # Intentionally empty trap statement to prevent terminating
                # # errors from halting processing
                # trap { }
                #
                # # Retrieve the newest error on the stack prior to doing work
                # if ($Error.Count -gt 0) {
                #     $refLastKnownError = ([ref]($Error[0]))
                # } else {
                #     $refLastKnownError = ([ref]$null)
                # }
                #
                # # Store current error preference; we will restore it after we do
                # # some work:
                # $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference
                #
                # # Set ErrorActionPreference to SilentlyContinue; this will
                # # suppress error output. Terminating errors will not output
                # # anything, kick to the empty trap statement and then continue
                # # on. Likewise, non- terminating errors will also not output
                # # anything, but they do not kick to the trap statement; they
                # # simply continue on.
                # $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
                #
                # # Do something that might trigger an error
                # Get-Item -Path 'C:\MayNotExist.txt'
                #
                # # Restore the former error preference
                # $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference
                #
                # # Retrieve the newest error on the error stack
                # if ($Error.Count -gt 0) {
                #     $refNewestCurrentError = ([ref]($Error[0]))
                # } else {
                #     $refNewestCurrentError = ([ref]$null)
                # }
                #
                # if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                #     # Error occurred
                # } else {
                #     # No error occurred
                # }
                #
                # .INPUTS
                # None. You can't pipe objects to Test-ErrorOccurred.
                #
                # .OUTPUTS
                # System.Boolean. Test-ErrorOccurred returns a boolean value
                # indicating whether an error occurred during the time period in
                # question. $true indicates an error occurred; $false indicates no
                # error occurred.
                #
                # .NOTES
                # This function also supports the use of positional parameters
                # instead of named parameters. If positional parameters are used
                # instead of named parameters, then two positional parameters are
                # required:
                #
                # The first positional parameter is a reference (memory pointer) to
                # a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack earlier in time, i.e., prior to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time, the first
                # positional parameter must be a reference to $null ([ref]$null).
                #
                # The second positional parameter is a reference (memory pointer)
                # to a System.Management.Automation.ErrorRecord that represents the
                # newest error on the stack later in time, i.e., after to running
                # the command for which you wish to determine whether an error
                # occurred. If no error was on the stack at this time,
                # ReferenceToLaterError must be a reference to $null ([ref]$null).
                #
                # Version: 2.0.20250215.0

                #region License ################################################
                # Copyright (c) 2025 Frank Lesniak
                #
                # Permission is hereby granted, free of charge, to any person
                # obtaining a copy of this software and associated documentation
                # files (the "Software"), to deal in the Software without
                # restriction, including without limitation the rights to use,
                # copy, modify, merge, publish, distribute, sublicense, and/or sell
                # copies of the Software, and to permit persons to whom the
                # Software is furnished to do so, subject to the following
                # conditions:
                #
                # The above copyright notice and this permission notice shall be
                # included in all copies or substantial portions of the Software.
                #
                # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
                # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
                # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
                # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
                # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
                # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
                # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
                # OTHER DEALINGS IN THE SOFTWARE.
                #endregion License ################################################
                param (
                    [ref]$ReferenceToEarlierError = ([ref]$null),
                    [ref]$ReferenceToLaterError = ([ref]$null)
                )

                # TODO: Validate input

                $boolErrorOccurred = $false
                if (($null -ne $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                    # Both not $null
                    if (($ReferenceToEarlierError.Value) -ne ($ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                } else {
                    # One is $null, or both are $null
                    # NOTE: $ReferenceToEarlierError could be non-null, while
                    # $ReferenceToLaterError could be null if $error was cleared;
                    # this does not indicate an error.
                    # So:
                    # - If both are null, no error.
                    # - If $ReferenceToEarlierError is null and
                    #   $ReferenceToLaterError is non-null, error.
                    # - If $ReferenceToEarlierError is non-null and
                    #   $ReferenceToLaterError is null, no error.
                    if (($null -eq $ReferenceToEarlierError.Value) -and ($null -ne $ReferenceToLaterError.Value)) {
                        $boolErrorOccurred = $true
                    }
                }

                return $boolErrorOccurred
            }
            #endregion FunctionsToSupportErrorHandling ############################

            trap {
                # Intentionally left empty to prevent terminating errors from
                # halting processing
            }

            # Retrieve the newest error on the stack prior to doing work
            $refLastKnownError = Get-ReferenceToLastError

            # Store current error preference; we will restore it after we do the
            # work of this function
            $actionPreferenceFormerErrorPreference = $global:ErrorActionPreference

            # Set ErrorActionPreference to SilentlyContinue; this will suppress
            # error output. Terminating errors will not output anything, kick to
            # the empty trap statement and then continue on. Likewise, non-
            # terminating errors will also not output anything, but they do not
            # kick to the trap statement; they simply continue on.
            $global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

            $ReferenceToDouble.Value = [double]$StringToConvert

            # Restore the former error preference
            $global:ErrorActionPreference = $actionPreferenceFormerErrorPreference

            # Retrieve the newest error on the error stack
            $refNewestCurrentError = Get-ReferenceToLastError

            if (Test-ErrorOccurred -ReferenceToEarlierError $refLastKnownError -ReferenceToLaterError $refNewestCurrentError) {
                # Error occurred; return failure indicator:
                return $false
            } else {
                # No error occurred; return success indicator:
                return $true
            }
        }

        $ReferenceArrayOfLeftoverStrings.Value = @('', '', '', '', '')

        $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $StringToConvert

        if ($boolResult) {
            return 0
        }

        # If we are still here, the conversion was not successful.

        $arrVersionElements = Split-StringOnLiteralString -StringToSplit $StringToConvert -Splitter '.'
        $intCountOfVersionElements = $arrVersionElements.Count

        if ($intCountOfVersionElements -lt 2) {
            # You can't have a version with less than two elements
            return -1
        }

        if ($intCountOfVersionElements -ge 5) {
            $strExcessVersionElements = [string]::join('.', $arrVersionElements[4..($intCountOfVersionElements - 1)])
        } else {
            $strExcessVersionElements = ''
        }

        if ($intCountOfVersionElements -ge 3) {
            $intElementInQuestion = 3
        } else {
            $intElementInQuestion = $intCountOfVersionElements
        }

        $boolConversionSuccessful = $false

        # See if excess elements are our only problem
        if (-not [string]::IsNullOrEmpty($strExcessVersionElements)) {
            $strAttemptedVersion = [string]::join('.', $arrVersionElements[0..$intElementInQuestion])
            $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersion
            if ($boolResult) {
                # Conversion successful; the only problem was the excess elements
                $boolConversionSuccessful = $true
                $intReturnValue = 5
                ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
            }
        }

        while ($intElementInQuestion -gt 0 -and -not $boolConversionSuccessful) {
            $strAttemptedVersion = [string]::join('.', $arrVersionElements[0..($intElementInQuestion - 1)])
            $boolResult = $false
            if ($intElementInQuestion -gt 1) {
                $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersion
            }
            if ($boolResult -or $intElementInQuestion -eq 1) {
                # Conversion successful or we're on the second element
                # See if we can trim out non-numerical characters
                $strRegexFirstNumericalCharacters = '^\d+'
                $strFirstNumericalCharacters = [regex]::Match($arrVersionElements[$intElementInQuestion], $strRegexFirstNumericalCharacters).Value
                if ([string]::IsNullOrEmpty($strFirstNumericalCharacters)) {
                    # No numerical characters found
                    ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = $arrVersionElements[$intElementInQuestion]
                    for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                        ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                    }
                    $boolConversionSuccessful = $true
                    $intReturnValue = $intElementInQuestion + 1
                    ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                } else {
                    # Numerical characters found
                    $boolResult = Convert-StringToInt32Safely -ReferenceToInt32 ([ref]$null) -StringToConvert $strFirstNumericalCharacters
                    if ($boolResult) {
                        # Append the first numerical characters to the version
                        $strAttemptedVersionNew = $strAttemptedVersion + '.' + $strFirstNumericalCharacters
                        $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersionNew
                        if ($boolResult) {
                            # Conversion successful
                            $strExcessCharactersInThisElement = ($arrVersionElements[$intElementInQuestion]).Substring($strFirstNumericalCharacters.Length)
                            ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = $strExcessCharactersInThisElement
                            for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                                ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                            }
                            $boolConversionSuccessful = $true
                            $intReturnValue = $intElementInQuestion + 1
                            ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                        } else {
                            # Conversion was not successful even though we just
                            # tried converting using numbers we know are
                            # convertable to an int32. This makes no sense.
                            # Throw warning:
                            $strMessage = 'Conversion of string "' + $strAttemptedVersionNew + '" to a version object failed even though "' + $strAttemptedVersion + '" converted to a version object just fine, and we proved that "' + $strFirstNumericalCharacters + '" was converted to an int32 object successfully. This should not be possible!'
                            Write-Warning -Message $strMessage
                        }
                    } else {
                        # The string of numbers could not be converted to an int32;
                        # this is probably because the represented number is too
                        # large.
                        # Try converting to int64:
                        $int64 = $null
                        $boolResult = Convert-StringToInt64Safely -ReferenceToInt64 ([ref]$int64) -StringToConvert $strFirstNumericalCharacters
                        if ($boolResult) {
                            # Converted to int64 but not int32
                            $intRemainder = $int64 - [int32]::MaxValue
                            $strAttemptedVersionNew = $strAttemptedVersion + '.' + [int32]::MaxValue
                            $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersionNew
                            if ($boolResult) {
                                # Conversion successful
                                $strExcessCharactersInThisElement = ($arrVersionElements[$intElementInQuestion]).Substring($strFirstNumericalCharacters.Length)
                                ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = ([string]$intRemainder) + $strExcessCharactersInThisElement
                                for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                                    ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                                }
                                $boolConversionSuccessful = $true
                                $intReturnValue = $intElementInQuestion + 1
                                ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                            } else {
                                # Conversion was not successful even though we just
                                # tried converting using numbers we know are
                                # convertable to an int32. This makes no sense.
                                # Throw warning:
                                $strMessage = 'Conversion of string "' + $strAttemptedVersionNew + '" to a version object failed even though "' + $strAttemptedVersion + '" converted to a version object just fine, and we know that "' + ([string]([int32]::MaxValue)) + '" is a valid int32 number. This should not be possible!'
                                Write-Warning -Message $strMessage
                            }
                        } else {
                            # Conversion to int64 failed; this is probably because
                            # the represented number is too large.
                            if ($PSVersion -eq ([version]'0.0')) {
                                $versionPS = Get-PSVersion
                            } else {
                                $versionPS = $PSVersion
                            }

                            if ($versionPS.Major -ge 3) {
                                # Use bigint
                                $bigint = $null
                                $boolResult = Convert-StringToBigIntegerSafely -ReferenceToBigIntegerObject ([ref]$bigint) -StringToConvert $strFirstNumericalCharacters
                                if ($boolResult) {
                                    # Converted to bigint but not int32 or
                                    # int64
                                    $bigintRemainder = $bigint - [int32]::MaxValue
                                    $strAttemptedVersionNew = $strAttemptedVersion + '.' + [int32]::MaxValue
                                    $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersionNew
                                    if ($boolResult) {
                                        # Conversion successful
                                        $strExcessCharactersInThisElement = ($arrVersionElements[$intElementInQuestion]).Substring($strFirstNumericalCharacters.Length)
                                        ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = ([string]$bigintRemainder) + $strExcessCharactersInThisElement
                                        for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                                            ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                                        }
                                        $boolConversionSuccessful = $true
                                        $intReturnValue = $intElementInQuestion + 1
                                        ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                                    } else {
                                        # Conversion was not successful even though
                                        # we just tried converting using numbers we
                                        # know are convertable to an int32. This
                                        # makes no sense. Throw warning:
                                        $strMessage = 'Conversion of string "' + $strAttemptedVersionNew + '" to a version object failed even though "' + $strAttemptedVersion + '" converted to a version object just fine, and we know that "' + ([string]([int32]::MaxValue)) + '" is a valid int32 number. This should not be possible!'
                                        Write-Warning -Message $strMessage
                                    }
                                } else {
                                    # Conversion to bigint failed; given that we
                                    # know that the string is all numbers, this
                                    # should not be possible. Throw warning
                                    $strMessage = 'The string "' + $strFirstNumericalCharacters + '" could not be converted to an int32, int64, or bigint number. This should not be possible!'
                                    Write-Warning -Message $strMessage
                                }
                            } else {
                                # Use double
                                $double = $null
                                $boolResult = Convert-StringToDoubleSafely -ReferenceToDouble ([ref]$double) -StringToConvert $strFirstNumericalCharacters
                                if ($boolResult) {
                                    # Converted to double but not int32 or
                                    # int64
                                    $doubleRemainder = $double - [int32]::MaxValue
                                    $strAttemptedVersionNew = $strAttemptedVersion + '.' + [int32]::MaxValue
                                    $boolResult = Convert-StringToVersionSafely -ReferenceToVersionObject $ReferenceToVersionObject -StringToConvert $strAttemptedVersionNew
                                    if ($boolResult) {
                                        # Conversion successful
                                        $strExcessCharactersInThisElement = ($arrVersionElements[$intElementInQuestion]).Substring($strFirstNumericalCharacters.Length)
                                        ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = ([string]$doubleRemainder) + $strExcessCharactersInThisElement
                                        for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                                            ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                                        }
                                        $boolConversionSuccessful = $true
                                        $intReturnValue = $intElementInQuestion + 1
                                        ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                                    } else {
                                        # Conversion was not successful even though
                                        # we just tried converting using numbers we
                                        # know are convertable to an int32. This
                                        # makes no sense. Throw warning:
                                        $strMessage = 'Conversion of string "' + $strAttemptedVersionNew + '" to a version object failed even though "' + $strAttemptedVersion + '" converted to a version object just fine, and we know that "' + ([string]([int32]::MaxValue)) + '" is a valid int32 number. This should not be possible!'
                                        Write-Warning -Message $strMessage
                                    }
                                } else {
                                    # Conversion to double failed; given that we
                                    # know that the string is all numbers, this
                                    # should not be possible unless the string of
                                    # numbers exceeded the maximum size allowed
                                    # for a double. This is possible, so don't
                                    # throw a warning.
                                    # Treat like no numerical characters found
                                    ($ReferenceArrayOfLeftoverStrings.Value)[$intElementInQuestion] = $arrVersionElements[$intElementInQuestion]
                                    for ($intCounterA = $intElementInQuestion + 1; $intCounterA -le 3; $intCounterA++) {
                                        ($ReferenceArrayOfLeftoverStrings.Value)[$intCounterA] = $arrVersionElements[$intCounterA]
                                    }
                                    $boolConversionSuccessful = $true
                                    $intReturnValue = $intElementInQuestion + 1
                                    ($ReferenceArrayOfLeftoverStrings.Value)[4] = $strExcessVersionElements
                                }
                            }
                        }
                    }
                }
            }
            $intElementInQuestion--
        }

        if (-not $boolConversionSuccessful) {
            # Conversion was not successful
            return -1
        } else {
            return $intReturnValue
        }
    }

    #region Process input ######################################################
    # Validate that the required parameter was supplied:
    if ($null -eq $HashtableOfInstalledModules) {
        $strMessage = 'The parameter $HashtableOfInstalledModules must be a hashtable. The hashtable must have keys that are the names of PowerShell modules with each key''s value populated with arrays of ModuleInfoGrouping objects (the result of Get-Module).'
        Write-Error -Message $strMessage
        return $false
    }
    if ($HashtableOfInstalledModules.GetType().FullName -ne 'System.Collections.Hashtable') {
        $strMessage = 'The parameter $HashtableOfInstalledModules must be a hashtable. The hashtable must have keys that are the names of PowerShell modules with each key''s value populated with arrays of ModuleInfoGrouping objects (the result of Get-Module).'
        Write-Error -Message $strMessage
        return $false
    }

    $boolThrowErrorForMissingModule = $false
    if ($null -ne $ThrowErrorIfModuleNotInstalled) {
        if ($ThrowErrorIfModuleNotInstalled.IsPresent -eq $true) {
            $boolThrowErrorForMissingModule = $true
        }
    }

    $boolThrowWarningForMissingModule = $false
    if (-not $boolThrowErrorForMissingModule) {
        if ($null -ne $ThrowWarningIfModuleNotInstalled) {
            if ($ThrowWarningIfModuleNotInstalled.IsPresent -eq $true) {
                $boolThrowWarningForMissingModule = $true
            }
        }
    }

    $boolThrowErrorForOutdatedModule = $false
    if ($null -ne $ThrowErrorIfModuleNotUpToDate) {
        if ($ThrowErrorIfModuleNotUpToDate.IsPresent -eq $true) {
            $boolThrowErrorForOutdatedModule = $true
        }
    }

    $boolThrowWarningForOutdatedModule = $false
    if (-not $boolThrowErrorForOutdatedModule) {
        if ($null -ne $ThrowWarningIfModuleNotUpToDate) {
            if ($ThrowWarningIfModuleNotUpToDate.IsPresent -eq $true) {
                $boolThrowWarningForOutdatedModule = $true
            }
        }
    }

    $boolCheckPowerShellVersion = $true
    if ($null -ne $DoNotCheckPowerShellVersion) {
        if ($DoNotCheckPowerShellVersion.IsPresent -eq $true) {
            $boolCheckPowerShellVersion = $false
        }
    }
    #endregion Process input ######################################################

    #region Verify environment #################################################
    if ($boolCheckPowerShellVersion) {
        $versionPS = Get-PSVersion
        if ($versionPS.Major -lt 5) {
            $strMessage = 'Test-PowerShellModuleUpdatesAvailableUsingHashtable requires PowerShell version 5.0 or newer.'
            Write-Warning -Message $strMessage
            return $false
        }
    } else {
        $versionPS = [version]'5.0'
    }
    #endregion Verify environment #################################################

    $VerbosePreferenceAtStartOfFunction = $VerbosePreference

    $boolResult = $true

    $hashtableMessagesToThrowForMissingModule = @{}
    $hashtableModuleNameToCustomMessageToThrowForMissingModule = @{}
    if ($null -ne $HashtableOfCustomNotInstalledMessages) {
        if ($HashtableOfCustomNotInstalledMessages.GetType().FullName -eq 'System.Collections.Hashtable') {
            foreach ($strMessage in @($HashtableOfCustomNotInstalledMessages.Keys)) {
                $hashtableMessagesToThrowForMissingModule.Add($strMessage, $false)

                $HashtableOfCustomNotInstalledMessages.Item($strMessage) | ForEach-Object {
                    $hashtableModuleNameToCustomMessageToThrowForMissingModule.Add($_, $strMessage)
                }
            }
        }
    }

    $hashtableMessagesToThrowForOutdatedModule = @{}
    $hashtableModuleNameToCustomMessageToThrowForOutdatedModule = @{}
    if ($null -ne $HashtableOfCustomNotUpToDateMessages) {
        if ($HashtableOfCustomNotUpToDateMessages.GetType().FullName -eq 'System.Collections.Hashtable') {
            foreach ($strMessage in @($HashtableOfCustomNotUpToDateMessages.Keys)) {
                $hashtableMessagesToThrowForOutdatedModule.Add($strMessage, $false)

                $HashtableOfCustomNotUpToDateMessages.Item($strMessage) | ForEach-Object {
                    $hashtableModuleNameToCustomMessageToThrowForOutdatedModule.Add($_, $strMessage)
                }
            }
        }
    }

    foreach ($strModuleName in @($HashtableOfInstalledModules.Keys)) {
        if (@($HashtableOfInstalledModules.Item($strModuleName)).Count -eq 0) {
            # Module is not installed
            $boolResult = $false

            if ($hashtableModuleNameToCustomMessageToThrowForMissingModule.ContainsKey($strModuleName) -eq $true) {
                $strMessage = $hashtableModuleNameToCustomMessageToThrowForMissingModule.Item($strModuleName)
                $hashtableMessagesToThrowForMissingModule.Item($strMessage) = $true
            } else {
                $strMessage = $strModuleName + ' module not found. Please install it and then try again.' + [System.Environment]::NewLine + 'You can install the ' + $strModuleName + ' PowerShell module from the PowerShell Gallery by running the following command:' + [System.Environment]::NewLine + 'Install-Module ' + $strModuleName + ';' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
                $hashtableMessagesToThrowForMissingModule.Add($strMessage, $true)
            }

            if ($null -ne $ReferenceToArrayOfMissingModules) {
                if ($null -ne $ReferenceToArrayOfMissingModules.Value) {
                    ($ReferenceToArrayOfMissingModules.Value) += $strModuleName
                }
            }
        } else {
            # Module is installed
            $versionNewestInstalledModule = (@($HashtableOfInstalledModules.Item($strModuleName)) | ForEach-Object { [version]($_.Version) } | Sort-Object)[-1]

            $arrModuleNewestInstalledModule = @(@($HashtableOfInstalledModules.Item($strModuleName)) | Where-Object { ([version]($_.Version)) -eq $versionNewestInstalledModule })

            # In the event there are multiple installations of the same version, reduce to a
            # single instance of the module
            if ($arrModuleNewestInstalledModule.Count -gt 1) {
                $moduleNewestInstalled = @($arrModuleNewestInstalledModule | Select-Object -Unique)[0]
            } else {
                $moduleNewestInstalled = $arrModuleNewestInstalledModule[0]
            }

            $VerbosePreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
            $moduleNewestAvailable = Find-Module -Name $strModuleName -ErrorAction SilentlyContinue
            $VerbosePreference = $VerbosePreferenceAtStartOfFunction

            if ($null -ne $moduleNewestAvailable) {
                $versionNewestModuleInPSGallery = $null
                $arrLeftoverStrings = @('', '', '', '', '')
                $intReturnCode = Convert-StringToFlexibleVersion -ReferenceToVersionObject ([ref]$versionNewestModuleInPSGallery) -ReferenceArrayOfLeftoverStrings ([ref]$arrLeftoverStrings) -StringToConvert $moduleNewestAvailable.Version -PSVersion $versionPS
                if ($intReturnCode -ge 0) {
                    # Conversion of the string version object from Find-Module was
                    # successful
                    if ($versionNewestModuleInPSGallery -gt $moduleNewestInstalled.Version) {
                        # A newer version is available
                        $boolResult = $false

                        if ($hashtableModuleNameToCustomMessageToThrowForOutdatedModule.ContainsKey($strModuleName) -eq $true) {
                            $strMessage = $hashtableModuleNameToCustomMessageToThrowForOutdatedModule.Item($strModuleName)
                            $hashtableMessagesToThrowForOutdatedModule.Item($strMessage) = $true
                        } else {
                            $strMessage = 'A newer version of the ' + $strModuleName + ' PowerShell module is available. Please consider updating it by running the following command:' + [System.Environment]::NewLine + 'Install-Module ' + $strModuleName + ' -Force;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
                            $hashtableMessagesToThrowForOutdatedModule.Add($strMessage, $true)
                        }

                        if ($null -ne $ReferenceToArrayOfOutOfDateModules) {
                            if ($null -ne $ReferenceToArrayOfOutOfDateModules.Value) {
                                ($ReferenceToArrayOfOutOfDateModules.Value) += $strModuleName
                            }
                        }
                    }
                } else {
                    # Conversion of the string version object from Find-Module
                    # failed; this should not happen - throw a warning
                    $strMessage = 'When searching the PowerShell Gallery for the newest version of the module "' + $strModuleName + '", the conversion of its version string "' + $moduleNewestAvailable.Version + '" to a version object failed. This should not be possible!'
                    Write-Warning -Message $strMessage
                }
            } else {
                # Couldn't find the module in the PowerShell Gallery
            }
        }
    }

    if ($boolThrowErrorForMissingModule -eq $true) {
        $arrMessages = @($hashtableMessagesToThrowForMissingModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForMissingModule.Item($strMessage) -eq $true) {
                Write-Error $strMessage
            }
        }
    } elseif ($boolThrowWarningForMissingModule -eq $true) {
        $arrMessages = @($hashtableMessagesToThrowForMissingModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForMissingModule.Item($strMessage) -eq $true) {
                Write-Warning $strMessage
            }
        }
    }

    if ($boolThrowErrorForOutdatedModule -eq $true) {
        $arrMessages = @($hashtableMessagesToThrowForOutdatedModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForOutdatedModule.Item($strMessage) -eq $true) {
                Write-Error $strMessage
            }
        }
    } elseif ($boolThrowWarningForOutdatedModule -eq $true) {
        $arrMessages = @($hashtableMessagesToThrowForOutdatedModule.Keys)
        foreach ($strMessage in $arrMessages) {
            if ($hashtableMessagesToThrowForOutdatedModule.Item($strMessage) -eq $true) {
                Write-Warning $strMessage
            }
        }
    }
    return $boolResult
}

function Test-SharePermissions {
    # .SYNOPSIS
    # Tests read access to a list of shares.
    #
    # .DESCRIPTION
    # Attempts to list the first item in each share to verify read permissions.
    # Logs fatal errors if access fails and returns $false if any fail.
    #
    # .PARAMETER Shares
    # Required: An array of PSCustomObjects with 'Path' property for each share.
    #
    # .PARAMETER LogDirectory
    # Required: The base log directory for error logging.
    #
    # .EXAMPLE
    # $shares = @([pscustomobject]@{Path='\\server\share1'}, [pscustomobject]@{Path='\\server\share2'})
    # $valid = Test-SharePermissions -Shares $shares -LogDirectory "C:\Logs"
    #
    # .INPUTS
    # None. You can't pipe objects to Test-SharePermissions.
    #
    # .OUTPUTS
    # System.Boolean. $true if all shares are accessible; $false otherwise.
    #
    # .NOTES
    # This is an initial check; ongoing tests use timed jobs for robustness.
    #
    # Version: 1.0.20260220.0

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][array]$Shares,
        [Parameter(Mandatory)][string]$LogDirectory
    )

    $allPermissionsValid = $true

    foreach ($share in $Shares) {
        try {
            # Attempt to list the first item to confirm read access.
            # We use -ErrorAction Stop to force the try/catch block to trigger on any error.
            [void](Get-ChildItem -Path $share.Path -ErrorAction Stop | Select-Object -First 1)
            Write-Verbose "Initial permission check for '$($share.Path)' successful."
        }
        catch {
            # If any error occurs (Access Denied, Path Not Found, etc.), log it and fail.
            $strDetails = "FATAL: Initial permission check failed for share '$($share.Path)'. Error: $($_.Exception.Message.Trim())"

            # Construct a log entry for the fatal error.
            $hashtableLogParams = @{
                'BaseLogDirectory' = $LogDirectory
                'LogType' = 'error'
                'TestName' = 'Startup.Permissions.Check'
                'Result' = 'FATAL'
                'Details' = $strDetails
            }
            # Write the fatal error to the central error log.
            Write-LogEntry @hashtableLogParams

            # Output the error message to the console as well.
            Write-Error $strDetails

            $allPermissionsValid = $false
        }
    }

    return $allPermissionsValid
}

#region Initial Setup ##############################################################
$versionPS = Get-PSVersion
if ($versionPS.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.1 or later. Current version: $versionPS"
    exit 1
} elseif ($versionPS.Major -eq 5 -and $versionPS.Minor -lt 1) {
    Write-Error "This script requires PowerShell 5.1 or later. Current version: $versionPS"
    exit 1
}

#region Check for Required PowerShell Modules ######################################
$hashtableModuleNameToInstalledModules = @{}
$hashtableModuleNameToInstalledModules.Add('ThreadJob', @())
$refHashtableModuleNameToInstalledModules = [ref]$hashtableModuleNameToInstalledModules
$intReturnCode = Get-PowerShellModuleUsingHashtable -ReferenceToHashtable $refHashtableModuleNameToInstalledModules
if ($intReturnCode -ne 0) {
    Write-Error 'Failed to get the list of installed PowerShell modules.'
    exit 1
}

$hashtableCustomNotInstalledMessageToModuleNames = @{}
$strThreadJobNotInstalledMessage = 'ThreadJob module was not found. Please install it and then try again.' + [System.Environment]::NewLine + 'You can install the ThreadJob PowerShell module from the PowerShell Gallery by running the following command:' + [System.Environment]::NewLine + 'Install-Module ThreadJob -Scope CurrentUser -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
$hashtableCustomNotInstalledMessageToModuleNames.Add($strThreadJobNotInstalledMessage, @('ThreadJob'))

$boolResult = Test-PowerShellModuleInstalledUsingHashtable -HashtableOfInstalledModules $hashtableModuleNameToInstalledModules -HashtableOfCustomNotInstalledMessages $hashtableCustomNotInstalledMessageToModuleNames -ThrowErrorIfModuleNotInstalled

if (-not $boolResult) {
    exit 1
}

$hashtableCustomNotUpToDateMessageToModuleNames = @{}
$strThreadJobNotUpToDateMessage = 'A newer version of the ThreadJob module is available. Please consider updating it by running the following command:' + [System.Environment]::NewLine + 'Install-Module ThreadJob -Scope CurrentUser -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine + 'If the installation command fails, you may need to upgrade the version of PowerShellGet. To do so, run the following commands, then restart PowerShell:' + [System.Environment]::NewLine + 'Set-ExecutionPolicy Bypass -Scope Process -Force;' + [System.Environment]::NewLine + '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;' + [System.Environment]::NewLine + 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;' + [System.Environment]::NewLine + 'Install-Module PowerShellGet -MinimumVersion 2.2.4 -SkipPublisherCheck -Force -AllowClobber;' + [System.Environment]::NewLine + [System.Environment]::NewLine
$hashtableCustomNotUpToDateMessageToModuleNames.Add($strThreadJobNotUpToDateMessage, @('ThreadJob'))

$boolResult = Test-PowerShellModuleUpdatesAvailableUsingHashtable -HashtableOfInstalledModules $hashtableModuleNameToInstalledModules -ThrowErrorIfModuleNotInstalled -ThrowWarningIfModuleNotUpToDate -HashtableOfCustomNotInstalledMessages $hashtableCustomNotInstalledMessageToModuleNames -HashtableOfCustomNotUpToDateMessages $hashtableCustomNotUpToDateMessageToModuleNames
#endregion Check for Required PowerShell Modules ######################################

$boolIsWindows = Test-Windows -PSVersion $versionPS
if ($boolIsWindows) {
    [console]::TreatControlCAsInput = $true
}

$boolResolveDnsNameCommandAvailable = ($boolIsWindows -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue))

Set-StrictMode -Version Latest
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$strLogDirectory = $LogDirectory.TrimEnd('\')
$arrLogSubdirectories = 'ping', 'dns_primary', 'dns_dc', 'share_fileserver', 'share_dc', 'error' |
    ForEach-Object { Join-Path $strLogDirectory $_ }
$null = $arrLogSubdirectories | ForEach-Object {
    $strLoggingSubDirectory = $_
    if (-not (Test-Path $strLoggingSubDirectory)) {
        try {
            [void](New-Item -ItemType Directory -Path $strLoggingSubDirectory)
        } catch {
            Write-Error ('Could not create logging subdirectory "' + $strLoggingSubDirectory + '". Please sure that the path is writeable, then re-launch the script.')
            exit 1
        }
    }
}

# Get Primary DNS server IP
if ([string]::IsNullOrEmpty($PrimaryDNSServer)) {
    # Primary NIC DNS
    $strPrimaryDNSServer = Get-PrimaryDnsServer -OSIsWindows $boolIsWindows
    Write-Debug ("Primary DNS server detected: {0}" -f $strPrimaryDNSServer)
} else {
    $strPrimaryDNSServer = $PrimaryDNSServer.Trim()
}

# Define all the ping targets in a structured array
$arrPingTargets = @(
    [pscustomobject]@{
        Name = 'DC.IP'
        Target = $DomainControllerIP
    },
    [pscustomobject]@{
        Name = 'FileServer.IP'
        Target = $FileServerIP
    }
)

# Define which DNS servers to query against
$arrDNSServersToTest = @(
    [pscustomobject]@{
        Name = 'Primary' # A friendly name for the TestName
        Server = $strPrimaryDNSServer # The IP of the server to query
        LogType = 'dns_primary' # The subfolder and log file prefix
    },
    [pscustomobject]@{
        Name = 'DC'
        Server = $DomainControllerIP
        LogType = 'dns_dc'
    }
)

# Define which hostnames to resolve
$arrFQDNsToTest = @(
    [pscustomobject]@{
        Name = 'FileServer' # A friendly name for the TestName
        Fqdn = $FileServerFQDN # The actual FQDN to look up
    },
    [pscustomobject]@{
        Name = 'DomainController'
        Fqdn = $DomainControllerFQDN
    }
)

# Define which shares to test
$arrSharesToTest = @(
    [pscustomobject]@{
        Name = 'DomainController'
        Path = $DomainControllerShare # e.g., '\\CENTRALDC\TESTSHARE'
        LogType = 'share_dc'
    },
    [pscustomobject]@{
        Name = 'FileServer'
        Path = $FileServerShare       # e.g., '\\FILESERVER\Plant'
        LogType = 'share_fileserver'
    }
)

# --- Initial Permission Check ---
Write-Verbose "Performing initial share permission checks..."
if (-not (Test-SharePermissions -Shares $arrSharesToTest -LogDirectory $strLogDirectory)) {
    Write-Error "One or more share permission checks failed. See the error log for details. Script will now exit."
    # Exit with a non-zero exit code to indicate failure, useful for scheduled tasks.
    exit 1
}
Write-Verbose "All initial permission checks passed."

$strWriteLogEntryFunctionDefinition = ${function:Write-LogEntry}.ToString()
$strInvokeDNSQueryFunctionDefinition = ${function:Invoke-DnsQuery}.ToString()

$scriptblockPingTest = {
    param(
        $strWriteLogEntryFunctionDefinition,
        $arrPingTargets,
        $strLogDirectory,
        $intPingTimeoutInMS,
        $intPingPacketSizeInBytes
    )

    # Helper functions must be redefined in the thread job's scope.
    ${function:Write-LogEntry} = $strWriteLogEntryFunctionDefinition

    $datetimeUTC = (Get-Date).ToUniversalTime()
    $arrErrorsToReturn = @()

    $pingSender = New-Object System.Net.NetworkInformation.Ping
    $arrPingBuffer = [byte[]]::CreateInstance([byte], $intPingPacketSizeInBytes)
    $pingoptions = New-Object System.Net.NetworkInformation.PingOptions(64, $true)

    foreach ($objTarget in $arrPingTargets) {
        $strTestName = "Ping.$($objTarget.Name)"
        try {
            $pingreply = $null
            $pingreply = $pingSender.Send($objTarget.Target, $intPingTimeoutInMS, $arrPingBuffer, $pingoptions)

            $boolErrorOccurred = $false

            switch ($pingreply.Status) {
                ([System.Net.NetworkInformation.IPStatus]::Success) {
                    # Success case
                    $strIP = if ($objTarget.Target -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                        $pingreply.Address.IPAddressToString
                    } else {
                        $objTarget.Target
                    }
                    $strDetails = "Roundtrip: $($pingreply.RoundtripTime)ms; ResolvedIP: $strIP"

                    # Log success to the 'ping' log
                    $hashtableLogParams = @{
                        'BaseLogDirectory' = $strLogDirectory
                        'TimeStamp' = $datetimeUTC
                        'LogType' = 'ping'
                        'TestName' = $strTestName
                        'Result' = 'SUCCESS'
                        'Details' = $strDetails
                    }
                    Write-LogEntry @hashtableLogParams
                }

                ([System.Net.NetworkInformation.IPStatus]::TimedOut) {
                    $strDetails = 'Status: Request Timed Out'
                    $boolErrorOccurred = $true
                }

                ([System.Net.NetworkInformation.IPStatus]::DestinationHostUnreachable) {
                    $strDetails = 'Status: Destination Host Unreachable'
                    $boolErrorOccurred = $true
                }

                default {
                    $strDetails = "Status: $($pingreply.Status)"
                    $boolErrorOccurred = $true
                }
            }

            if ($boolErrorOccurred) {
                # Write to test-specific log:
                $hashtableLogParams = @{
                    'BaseLogDirectory' = $strLogDirectory
                    'TimeStamp' = $datetimeUTC
                    'LogType' = 'ping'
                    'TestName' = $strTestName
                    'Result' = 'FAILURE'
                    'Details' = $strDetails
                }
                Write-LogEntry @hashtableLogParams

                # Send back for writing to central log
                $arrErrorsToReturn += @{
                    'BaseLogDirectory' = $strLogDirectory
                    'TimeStamp' = $datetimeUTC
                    'LogType' = 'error'
                    'TestName' = $strTestName
                    'Result' = 'FAILURE'
                    'Details' = $strDetails
                }
            }
        } catch {
            # In a catch {}. $_ is the last error to occur, equivalent to $Error[0]
            $strDetails = $_.Exception.Message.Trim()

            # Write to test-specific log:
            $hashtableLogParams = @{
                'BaseLogDirectory' = $strLogDirectory
                'TimeStamp' = $datetimeUTC
                'LogType' = 'ping'
                'TestName' = $strTestName
                'Result' = 'ERROR'
                'Details' = $strDetails
            }
            Write-LogEntry @hashtableLogParams

            # Send back for writing to central log
            $arrErrorsToReturn += @{
                'BaseLogDirectory' = $strLogDirectory
                'TimeStamp' = $datetimeUTC
                'LogType' = 'error'
                'TestName' = $strTestName
                'Result' = 'ERROR'
                'Details' = $strDetails
            }
        }
    }
    $pingSender.Dispose()
    return $arrErrorsToReturn # Return errors for central processing
}

$scriptblockDNSTest = {
    param(
        $strWriteLogEntryFunctionDefinition,
        $strInvokeDNSQueryFunctionDefinition,
        $arrDNSServersToTest,
        $arrFQDNsToTest,
        $strLogDirectory,
        $boolResolveDnsNameCommandAvailable,
        $boolIsWindows
    )

    # Helper functions must be redefined in the thread job's scope.
    ${function:Write-LogEntry} = $strWriteLogEntryFunctionDefinition
    ${function:Invoke-DnsQuery} = $strInvokeDNSQueryFunctionDefinition

    $datetimeUTC = (Get-Date).ToUniversalTime()
    $arrErrorsToReturn = @()

    foreach ($pscustomobjectDNSServer in $arrDNSServersToTest) {
        if (-not $pscustomobjectDNSServer.Server) { continue }

        foreach ($pscustomobjectFQDN in $arrFQDNsToTest) {
            $strTestName = "DNS.$($pscustomobjectDNSServer.Name).$($pscustomobjectFQDN.Name)"

            $hashtableParams = @{
                'HostName' = $pscustomobjectFQDN.FQDN
                'DNSServer' = $pscustomobjectDNSServer.Server
                'ResolveDnsNameCommandAvailable' = $boolResolveDnsNameCommandAvailable
                'OSIsWindows' = $boolIsWindows
            }
            $objResult = Invoke-DnsQuery @hashtableParams

            if ($objResult.Success) {
                # SUCCESS CASE
                $strDetails = "Resolved: $($objResult.IPAddress)"

                # Log success directly to the appropriate DNS log
                $hashtableLogParams = @{
                    'BaseLogDirectory' = $strLogDirectory
                    'TimeStamp' = $datetimeUTC
                    'LogType' = $pscustomobjectDNSServer.LogType # e.g., 'dns_primary' or 'dns_dc'
                    'TestName' = $strTestName
                    'Result' = 'SUCCESS'
                    'Details' = $strDetails
                }
                Write-LogEntry @hashtableLogParams
            } else {
                # FAILURE CASE
                $strDetails = $objResult.Error

                # Write to test-specific log:
                $hashtableLogParams = @{
                    'BaseLogDirectory' = $strLogDirectory
                    'TimeStamp' = $datetimeUTC
                    'LogType' = $pscustomobjectDNSServer.LogType # e.g., 'dns_primary' or 'dns_dc'
                    'TestName' = $strTestName
                    'Result' = 'FAILURE'
                    'Details' = $strDetails
                }
                Write-LogEntry @hashtableLogParams

                # Send back for writing to central log
                $arrErrorsToReturn += @{
                    'BaseLogDirectory' = $strLogDirectory
                    'TimeStamp' = $datetimeUTC
                    'LogType' = 'error'
                    'TestName' = $strTestName
                    'Result' = 'FAILURE'
                    'Details' = $strDetails
                }
            }
        }
    }

    # Return any collected errors for the main script to process
    return $arrErrorsToReturn
}

$scriptblockShareAccessTest = {
    param(
        $strWriteLogEntryFunctionDefinition,
        $arrSharesToTest,
        $strLogDirectory,
        $boolIsWindows,
        $intShareAccessTimeout
    )

    # Helper functions must be redefined in the thread job's scope.
    ${function:Write-LogEntry} = $strWriteLogEntryFunctionDefinition

    # The share access test is Windows-only.
    if (-not $boolIsWindows) { return }

    $datetimeUTC = (Get-Date).ToUniversalTime()
    $arrErrorsToReturn = @()

    foreach ($pscustomobjectShare in $arrSharesToTest) {
        $strTestName = "Share.$($pscustomobjectShare.Name).Access"
        $job = $null

        try {
            # Start the Get-ChildItem command in a separate process to avoid hanging the main script.
            $job = Start-Job -ScriptBlock {
                param($Path)
                # The -Force parameter can help with hidden or system files if necessary.
                Get-ChildItem -Path $Path -Force -ErrorAction Stop | Select-Object -First 1
            } -ArgumentList $pscustomobjectShare.Path

            # Wait for the job to finish, but only for the specified timeout period.
            if (Wait-Job -Job $job -Timeout $intShareAccessTimeout) {
                # The job completed within the timeout window. Now, check if it succeeded or failed.
                try {
                    $item = Receive-Job -Job $job -Wait

                    if ($null -ne $item) {
                        # SUCCESS CASE
                        $strDetails = "Access confirmed, at least one item found."

                        # Log success directly
                        $hashtableLogParams = @{
                            BaseLogDirectory = $strLogDirectory
                            TimeStamp = $datetimeUTC
                            LogType = $pscustomobjectShare.LogType
                            TestName = $strTestName
                            Result = 'SUCCESS'
                            Details = $strDetails
                        }
                        Write-LogEntry @hashtableLogParams
                    } else {
                        # EMPTY SHARE CASE
                        $strDetails = "Share is accessible but contains no items."

                        # Write to test-specific log:
                        $hashtableLogParams = @{
                            BaseLogDirectory = $strLogDirectory
                            TimeStamp = $datetimeUTC
                            LogType = $pscustomobjectShare.LogType
                            TestName = $strTestName
                            Result = 'EMPTY'
                            Details = $strDetails
                        }
                        Write-LogEntry @hashtableLogParams

                        # Send back for writing to central log
                        $arrErrorsToReturn += @{
                            BaseLogDirectory = $strLogDirectory
                            TimeStamp = $datetimeUTC
                            LogType = 'error'
                            TestName = $strTestName
                            Result = 'EMPTY'
                            Details = $strDetails
                        }
                    }
                } catch {
                    # EXCEPTION CASE (e.g., Access Denied, Path Not Found inside the job)
                    $strDetails = $_.Exception.Message.Trim()

                    # Write to test-specific log:
                    $hashtableLogParams = @{
                        BaseLogDirectory = $strLogDirectory
                        TimeStamp = $datetimeUTC
                        LogType = $pscustomobjectShare.LogType
                        TestName = $strTestName
                        Result = 'ERROR'
                        Details = $strDetails
                    }
                    Write-LogEntry @hashtableLogParams

                    # Send back for writing to central log
                    $arrErrorsToReturn += @{
                        BaseLogDirectory = $strLogDirectory
                        TimeStamp = $datetimeUTC
                        LogType = 'error'
                        TestName = $strTestName
                        Result = 'ERROR'
                        Details = $strDetails
                    }
                }
            } else {
                # TIMEOUT CASE: The job did not complete in time.
                $strDetails = "The operation timed out after $intShareAccessTimeout seconds."
                $hashtableLogParams = @{
                    BaseLogDirectory = $strLogDirectory
                    TimeStamp = $datetimeUTC
                    LogType = $pscustomobjectShare.LogType
                    TestName = $strTestName
                    Result = 'TIMEOUT'
                    Details = $strDetails
                }
                Write-LogEntry @hashtableLogParams

                # Send back for writing to central log
                $arrErrorsToReturn += @{
                    BaseLogDirectory = $strLogDirectory
                    TimeStamp = $datetimeUTC
                    LogType = 'error'
                    TestName = $strTestName
                    Result = 'TIMEOUT'
                    Details = $strDetails
                }
            }
        } catch {
            # This outer catch handles unexpected errors with Start-Job or Wait-Job itself.
            # In a catch {}. $_ is the last error to occur, equivalent to $Error[0]
            $strDetails = "A script-level error occurred during the share test: $($_.Exception.Message.Trim())"

            # Write to test-specific log:
            $hashtableLogParams = @{
                BaseLogDirectory = $strLogDirectory
                TimeStamp = $datetimeUTC
                LogType = $pscustomobjectShare.LogType
                TestName = $strTestName
                Result = 'FATAL'
                Details = $strDetails
            }
            Write-LogEntry @hashtableLogParams

            # Send back for writing to central log
            $arrErrorsToReturn += @{
                'BaseLogDirectory' = $strLogDirectory
                'TimeStamp' = $datetimeUTC
                'LogType' = 'error'
                'TestName' = $strTestName
                'Result' = 'FATAL'
                'Details' = $strDetails
            }
        } finally {
            # Clean up the job to prevent resource leaks.
            if ($null -ne $job) {
                # Stop the job in case it's still running (e.g., on timeout) and remove it.
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Return any collected errors/warnings for the main script to process
    return $arrErrorsToReturn
}

$arrPingScriptblockArguments = @(
    $strWriteLogEntryFunctionDefinition,
    $arrPingTargets,
    $strLogDirectory,
    $PingTimeout,
    $PingPacketSize
)

$arrDNSTestScriptblockArguments = @(
    $strWriteLogEntryFunctionDefinition,
    $strInvokeDNSQueryFunctionDefinition,
    $arrDNSServersToTest,
    $arrFQDNsToTest,
    $strLogDirectory,
    $boolResolveDnsNameCommandAvailable,
    $boolIsWindows
)

$arrShareAccessTestScriptblockArguments = @(
    $strWriteLogEntryFunctionDefinition,
    $arrSharesToTest,
    $strLogDirectory,
    $boolIsWindows,
    ([int]($ShareAccessTimeout / 1000))
)

# Variable to track if the last completed cycle had an error. Script-scoped for the exit event.
$script:cycleHadError = $false
$script:StopRequested = $false
$script:ExitCode = 0
#endregion Initial Setup ##############################################################

Write-Verbose "Connectivity monitor started. Press Ctrl+C to stop."
$arrLogSubdirectories | ForEach-Object { Remove-OldLogFile $_ }
$datetimeLastCleanup = (Get-Date).ToUniversalTime()
$datetimeStart = [DateTime]::UtcNow

try {
    while ($true) {
        # Check for Ctrl+C at loop start
        if ($boolIsWindows -and [console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if (($key.Modifiers -band [consolemodifiers]::control) -and ($key.Key -eq [consolekey]::c)) {
                Write-Verbose 'Ctrl+C detected. Stopping connectivity monitor.'
                $script:StopRequested = $true
            }
        }

        if ($MaxRuntimeMinutes -gt 0 -and (([DateTime]::UtcNow - $datetimeStart).TotalMinutes -gt $MaxRuntimeMinutes)) {
            Write-Verbose "Runtime limit ($MaxRuntimeMinutes minutes) reached. Stopping."
            $script:StopRequested = $true
        }

        if ($script:StopRequested) {
            # Exit loop gracefully
            break
        }

        $datetimeLoopStart = [DateTime]::UtcNow
        $script:cycleHadError = $false # Reset error flag for the new cycle
        Write-Debug ("Starting monitoring cycle at {0:o}" -f $datetimeLoopStart)

        # Start all jobs in parallel
        $arrJobs = @(
            Start-ThreadJob -ScriptBlock $scriptblockPingTest -ArgumentList $arrPingScriptblockArguments
            Start-ThreadJob -ScriptBlock $scriptblockDNSTest -ArgumentList $arrDNSTestScriptblockArguments
            Start-ThreadJob -ScriptBlock $scriptblockShareAccessTest -ArgumentList $arrShareAccessTestScriptblockArguments
        )
        Write-Debug ("Started {0} thread jobs for ping, DNS, and share access tests" -f $arrJobs.Count)

        # Wait for all jobs to complete
        [void]($arrJobs | Wait-Job)

        # Collect all errors from the jobs
        $arrAllErrors = @($arrJobs | Receive-Job)

        # --- Central Error Logging ---
        if ($arrAllErrors.Count -gt 0) {
            $script:cycleHadError = $true
            foreach ($hashtableErrorLogEntry in $arrAllErrors) {
                Write-LogEntry @hashtableErrorLogEntry
            }
        }

        # --- Cleanup and Maintenance ---
        $arrJobs | Remove-Job # Clean up completed jobs to free resources

        # Check for Ctrl+C after threads have completed
        if ($boolIsWindows -and [console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if (($key.Modifiers -band [consolemodifiers]::control) -and ($key.Key -eq [consolekey]::c)) {
                Write-Verbose 'Ctrl+C detected. Stopping connectivity monitor.'
                $script:StopRequested = $true
            }
        }

        if ($script:StopRequested) {
            # Exit loop gracefully
            break
        }

        if (($datetimeLastCleanup.AddHours(1)) -le (Get-Date).ToUniversalTime()) {
            Write-Verbose "Performing hourly log file cleanup..."
            $arrLogSubdirectories | ForEach-Object { Remove-OldLogFile $_ }
            $datetimeLastCleanup = (Get-Date).ToUniversalTime()
        }

        # --- Dynamic Sleep Calculation ---
        $cycleDuration = ([DateTime]::UtcNow - $datetimeLoopStart).TotalMilliseconds
        $sleepDuration = $CheckFrequency - $cycleDuration

        if ($sleepDuration -gt 0) {
            $remainingSleep = $sleepDuration
            while ($remainingSleep -gt 0 -and (-not $script:StopRequested)) {
                $sleepChunk = [math]::Min($remainingSleep, 100) # Sleep in 100ms chunks
                Start-Sleep -Milliseconds $sleepChunk
                $remainingSleep -= $sleepChunk

                # Check for Ctrl+C during sleep cycles
                if ($boolIsWindows -and [console]::KeyAvailable) {
                    $key = [console]::ReadKey($true)
                    if (($key.Modifiers -band [consolemodifiers]::control) -and ($key.Key -eq [consolekey]::c)) {
                        Write-Verbose 'Ctrl+C detected. Stopping connectivity monitor.'
                        $script:StopRequested = $true
                    }
                }

                if ($script:StopRequested) {
                    # Exit loop gracefully
                    break
                }
            }
        }
        # If the cycle took longer than the frequency, it will start the next one immediately.
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    Write-Verbose 'Ctrl+C detected (likely on non-Windows platform). Stopping gracefully.'
    $script:StopRequested = $true
    try {
        $hashtableLogParams = @{
            'BaseLogDirectory' = $strLogDirectory
            'LogType' = 'error'
            'TestName' = 'MainLoop.CtrlC'
            'Result' = 'INFO'
            'Details' = 'Script terminated by Ctrl+C on non-Windows platform.'
        }
        Write-LogEntry @hashtableLogParams
    } catch {
        # If logging fails, we still want to exit gracefully.
        Write-Information "Could not write Ctrl+C termination to the log file. Details: $($_.ToString())"
    }
} catch {
    # This block catches any unexpected, script-terminating errors from the 'try' block.

    # 1. Format the error message for logging. Using $_.ToString() provides the full stack trace.
    $strErrorMessage = "FATAL: Unhandled exception in main loop. Error: $($_.ToString())"

    # 2. Write the error to the console for immediate visibility.
    Write-Warning $strErrorMessage

    # 3. Log this critical failure to the central error log.
    # We wrap this in its own try/catch in case logging itself fails.
    try {
        $hashtableLogParams = @{
            'BaseLogDirectory' = $strLogDirectory
            'LogType' = 'error'
            'TestName' = 'MainLoop.UnhandledException'
            'Result' = 'FATAL'
            'Details' = $strErrorMessage
        }
        Write-LogEntry @hashtableLogParams
    } catch {
        # If logging fails, this is a last resort to ensure the error is not lost.
        Write-Error "CRITICAL: Could not write the unhandled exception to the log file. Details: $strErrorMessage"
    }

    # 4. Set the cycle error flag. This ensures that if the script is stopped,
    # it will exit with an error code, which can be useful for scheduled task monitoring.
    $script:cycleHadError = $true
} finally {
    Write-Verbose 'Cleaning up resources before exiting...'

    if ($script:cycleHadError) {
        $script:ExitCode = 1
    } else {
        $script:ExitCode = 0
    }

    # Cleanup
    if ($boolIsWindows) {
        [console]::TreatControlCAsInput = $false  # Restore default
    }
    # Dispose of any remaining job-related resources if necessary
    Get-Job | Remove-Job -Force

    Write-Verbose ('About to return: ' + $script:ExitCode)
    exit $script:ExitCode
}
#endregion Main Execution Loop

Write-Verbose 'Exiting connectivity monitor script.'
Write-Verbose ('About to return: ' + $script:ExitCode)
exit $script:ExitCode
