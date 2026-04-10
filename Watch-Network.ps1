# .SYNOPSIS
# Continuous connectivity monitor for arbitrary PSConnMon targets.
#
# .DESCRIPTION
# Supports two invocation models:
#   1. A YAML or JSON configuration file for the modern PSConnMon workflow.
#   2. A PowerShell object workflow that accepts target objects plus optional
#      top-level section objects.
#
# .PARAMETER ConfigPath
# The YAML or JSON configuration file to run.
#
# .PARAMETER Targets
# An array of target objects that map directly to the PSConnMon `targets`
# section.
#
# .PARAMETER Agent
# Optional object for `agent` section values when using `-Targets`.
#
# .PARAMETER Publish
# Optional object for `publish` section values when using `-Targets`.
#
# .PARAMETER Tests
# Optional object for `tests` section values when using `-Targets`.
#
# .PARAMETER Auth
# Optional object for `auth` section values when using `-Targets`.
#
# .PARAMETER Extensions
# Optional array of trusted local extension definitions when using `-Targets`.
#
# .PARAMETER RunOnce
# Executes one monitoring cycle and exits.
#
# .PARAMETER MaxRuntimeMinutes
# Optional: The maximum runtime in minutes before auto-stop. A value of `0`
# means indefinite unless `-RunOnce` is used.
#
# .EXAMPLE
# .\Watch-Network.ps1 -ConfigPath .\config\psconnmon.yaml
#
# Runs PSConnMon using a configuration file.
#
# .EXAMPLE
# .\Watch-Network.ps1 `
#   -Targets @(
#       @{
#           id = 'loopback'
#           fqdn = 'localhost'
#           address = '127.0.0.1'
#           tests = @('ping')
#       }
#   ) `
#   -Agent @{ agentId = 'ops-01'; siteId = 'lab'; spoolDirectory = 'data/spool' } `
#   -Tests @{ enabled = @('ping') } `
#   -RunOnce
#
# Runs PSConnMon using direct PowerShell objects that mirror the config model.
#
# .INPUTS
# None. You can't pipe objects to Watch-Network.ps1.
#
# .OUTPUTS
# System.Int32. Returns the exit code from Invoke-PSConnMon.
#
# Exit codes:
# 0 - Clean exit
# 1 - Fatal startup or execution error
#
# .NOTES
# Version: 0.3.20260409.0

[CmdletBinding(DefaultParameterSetName = 'ConfigPath')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ConfigPath')]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'ObjectInput')]
    [object[]]$Targets,

    [Parameter(Mandatory = $false, ParameterSetName = 'ObjectInput')]
    [AllowNull()][object]$Agent = $null,

    [Parameter(Mandatory = $false, ParameterSetName = 'ObjectInput')]
    [AllowNull()][object]$Publish = $null,

    [Parameter(Mandatory = $false, ParameterSetName = 'ObjectInput')]
    [AllowNull()][object]$Tests = $null,

    [Parameter(Mandatory = $false, ParameterSetName = 'ObjectInput')]
    [AllowNull()][object]$Auth = $null,

    [Parameter(Mandatory = $false, ParameterSetName = 'ObjectInput')]
    [AllowEmptyCollection()][object[]]$Extensions = @(),

    [Parameter(Mandatory = $false)]
    [switch]$RunOnce,

    [Parameter(Mandatory = $false)]
    [int]$MaxRuntimeMinutes = 0
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSConnMon/PSConnMon.psd1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

if ($PSCmdlet.ParameterSetName -eq 'ObjectInput') {
    $config = ConvertTo-PSConnMonConfig -Targets $Targets -Agent $Agent -Publish $Publish -Tests $Tests -Auth $Auth -Extensions $Extensions
    $exitCode = Invoke-PSConnMon -Config $config -RunOnce:$RunOnce -MaxRuntimeMinutes $MaxRuntimeMinutes
    exit $exitCode
}

$exitCode = Invoke-PSConnMon -ConfigPath $ConfigPath -RunOnce:$RunOnce -MaxRuntimeMinutes $MaxRuntimeMinutes
exit $exitCode
