Set-StrictMode -Version Latest

$script:ValidResultStates = @('SUCCESS', 'FAILURE', 'TIMEOUT', 'EMPTY', 'SKIPPED', 'FATAL', 'INFO')

function Get-PSConnMonPowerShellVersion {
    # .SYNOPSIS
    # Returns the version of PowerShell that is running.
    #
    # .DESCRIPTION
    # Outputs a [version] object representing the active PowerShell runtime. The
    # implementation is intentionally compatible with older editions that do not
    # always expose the same global variables.
    #
    # .EXAMPLE
    # $versionPS = Get-PSConnMonPowerShellVersion
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonPowerShellVersion.
    #
    # .OUTPUTS
    # System.Version. The detected PowerShell version.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([version])]
    param()

    if (Test-Path -Path variable:\PSVersionTable) {
        return $PSVersionTable.PSVersion
    }

    return [version]'1.0'
}

function Test-PSConnMonWindows {
    # .SYNOPSIS
    # Returns $true when PowerShell is running on Windows.
    #
    # .DESCRIPTION
    # Detects whether the current runtime is hosted on Windows in a way that is
    # compatible with Windows PowerShell 5.1 as well as newer cross-platform
    # releases.
    #
    # .PARAMETER PSVersion
    # Optional precomputed PowerShell version.
    #
    # .EXAMPLE
    # $boolIsWindows = Test-PSConnMonWindows
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonWindows.
    #
    # .OUTPUTS
    # System.Boolean. Returns $true on Windows and $false otherwise.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)][version]$PSVersion = (Get-PSConnMonPowerShellVersion)
    )

    if ($PSVersion.Major -lt 6) {
        return $true
    }

    if (Test-Path -Path variable:\IsWindows) {
        return [bool]$IsWindows
    }

    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function ConvertTo-PSConnMonHashtable {
    # .SYNOPSIS
    # Recursively converts PowerShell objects to hashtables and arrays.
    #
    # .DESCRIPTION
    # Normalizes objects returned by JSON or YAML parsers so PSConnMon can work
    # consistently across PowerShell editions that do not all support
    # `ConvertFrom-Json -AsHashtable`.
    #
    # .PARAMETER InputObject
    # The object graph to normalize.
    #
    # .EXAMPLE
    # $config = ConvertTo-PSConnMonHashtable -InputObject $parsedObject
    #
    # .INPUTS
    # System.Object. The object graph to convert.
    #
    # .OUTPUTS
    # System.Object. A hashtable, array, or scalar value.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $convertedValue = @{}
        foreach ($key in $InputObject.Keys) {
            $convertedValue[$key] = ConvertTo-PSConnMonHashtable -InputObject $InputObject[$key]
        }

        return $convertedValue
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $convertedItems = New-Object System.Collections.Generic.List[object]
        foreach ($itemValue in $InputObject) {
            $convertedItems.Add((ConvertTo-PSConnMonHashtable -InputObject $itemValue)) | Out-Null
        }

        return $convertedItems.ToArray()
    }

    if ($InputObject -is [pscustomobject]) {
        $convertedValue = @{}
        foreach ($propertyValue in $InputObject.PSObject.Properties) {
            $convertedValue[$propertyValue.Name] = ConvertTo-PSConnMonHashtable -InputObject $propertyValue.Value
        }

        return $convertedValue
    }

    return $InputObject
}

function ConvertTo-PSConnMonArray {
    # .SYNOPSIS
    # Normalizes scalars and collections to a PowerShell array.
    #
    # .DESCRIPTION
    # Ensures that list-like configuration values behave consistently regardless
    # of whether they came from YAML, JSON, or direct PowerShell object input.
    #
    # .PARAMETER InputObject
    # The input value to normalize.
    #
    # .EXAMPLE
    # $targets = ConvertTo-PSConnMonArray -InputObject $config.targets
    #
    # .INPUTS
    # System.Object. The value to normalize.
    #
    # .OUTPUTS
    # System.Object[]. The normalized array.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$InputObject
    )

    if ($null -eq $InputObject) {
        return , @()
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string]) -and -not ($InputObject -is [hashtable])) {
        [object[]]$result = @($InputObject)
        return , $result
    }

    [object[]]$result = @($InputObject)
    return , $result
}

function Get-PSConnMonPrimaryDnsServer {
    # .SYNOPSIS
    # Retrieves the primary DNS server configured on the current host.
    #
    # .DESCRIPTION
    # Uses platform-appropriate discovery to identify the preferred DNS server.
    # On Windows, it prefers the DnsClient cmdlets and falls back to CIM. On
    # Linux and macOS, it reads `/etc/resolv.conf`.
    #
    # .PARAMETER OSIsWindows
    # Optional precomputed operating system flag.
    #
    # .EXAMPLE
    # $dnsServer = Get-PSConnMonPrimaryDnsServer
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonPrimaryDnsServer.
    #
    # .OUTPUTS
    # System.String. The detected DNS server IP or an empty string.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)][bool]$OSIsWindows = (Test-PSConnMonWindows)
    )

    if ($OSIsWindows) {
        if (Get-Command -Name Get-DnsClientServerAddress -ErrorAction SilentlyContinue) {
            $serverValue = Get-DnsClientServerAddress -AddressFamily IPv4 |
                Where-Object { $_.ServerAddresses.Count -gt 0 } |
                Select-Object -First 1 -ExpandProperty ServerAddresses |
                Select-Object -First 1

            if (-not [string]::IsNullOrWhiteSpace($serverValue)) {
                return $serverValue.Trim()
            }
        }

        try {
            $serverValue = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
                Where-Object { $_.DNSServerSearchOrder } |
                Select-Object -First 1 -ExpandProperty DNSServerSearchOrder |
                Select-Object -First 1

            if (-not [string]::IsNullOrWhiteSpace($serverValue)) {
                return $serverValue.Trim()
            }
        } catch {
            Write-Verbose ('Unable to determine primary DNS server from CIM. Details: {0}' -f $_.Exception.Message)
        }

        return ''
    }

    $resolvConfPath = '/etc/resolv.conf'
    if (-not (Test-Path -Path $resolvConfPath -PathType Leaf)) {
        return ''
    }

    $lineValue = Get-Content -Path $resolvConfPath -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*nameserver\s+\S+' } |
        Select-Object -First 1

    if ($null -eq $lineValue) {
        return ''
    }

    return (($lineValue -split '\s+')[1]).Trim()
}

function ConvertTo-PSConnMonConfig {
    # .SYNOPSIS
    # Creates a normalized PSConnMon configuration from PowerShell objects.
    #
    # .DESCRIPTION
    # Accepts PowerShell hashtables or PSCustomObjects that mirror the top-level
    # PSConnMon configuration sections and returns a validated, normalized
    # configuration hashtable. This keeps direct PowerShell invocation close to
    # the YAML/JSON model without requiring every setting to become a separate
    # command-line parameter.
    #
    # .PARAMETER Targets
    # An array of target objects. Each target must provide `id`, `fqdn`, and
    # `address`. Optional properties include `dnsServers`, `shares`, `tests`,
    # `roles`, `tags`, and `externalTraceTarget`.
    #
    # .PARAMETER Agent
    # Optional object containing `agent` section values.
    #
    # .PARAMETER Publish
    # Optional object containing `publish` section values.
    #
    # .PARAMETER Tests
    # Optional object containing `tests` section values.
    #
    # .PARAMETER Auth
    # Optional object containing `auth` section values.
    #
    # .PARAMETER Extensions
    # Optional array of extension objects.
    #
    # .EXAMPLE
    # $config = ConvertTo-PSConnMonConfig -Targets @(
    #     @{
    #         id = 'loopback'
    #         fqdn = 'localhost'
    #         address = '127.0.0.1'
    #         tests = @('ping')
    #     }
    # ) -Agent @{
    #     agentId = 'ops-01'
    #     siteId = 'lab'
    #     spoolDirectory = 'data/spool'
    # } -Tests @{
    #     enabled = @('ping')
    # }
    #
    # .INPUTS
    # None. You can't pipe objects to ConvertTo-PSConnMonConfig.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The normalized PSConnMon configuration.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][object[]]$Targets,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Agent = $null,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Publish = $null,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Tests = $null,
        [Parameter(Mandatory = $false)][AllowNull()][object]$Auth = $null,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Extensions = @()
    )

    $targetValues = New-Object System.Collections.Generic.List[object]
    foreach ($targetValue in $Targets) {
        $targetValues.Add((ConvertTo-PSConnMonHashtable -InputObject $targetValue)) | Out-Null
    }

    $extensionValues = New-Object System.Collections.Generic.List[object]
    foreach ($extensionValue in (ConvertTo-PSConnMonArray -InputObject $Extensions)) {
        $extensionValues.Add((ConvertTo-PSConnMonHashtable -InputObject $extensionValue)) | Out-Null
    }

    $config = @{
        schemaVersion = '1.0'
        agent = if ($null -eq $Agent) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Agent }
        publish = if ($null -eq $Publish) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Publish }
        tests = if ($null -eq $Tests) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Tests }
        auth = if ($null -eq $Auth) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Auth }
        targets = $targetValues.ToArray()
        extensions = $extensionValues.ToArray()
        _runtime = @{
            configDirectory = (Get-Location).Path
        }
    }

    return (Test-PSConnMonConfig -Config $config -PassThru)
}

$script:PSConnMonIsWindows = Test-PSConnMonWindows

function Assert-PSConnMonDependency {
    # .SYNOPSIS
    # Validates that a required dependency is available.
    #
    # .DESCRIPTION
    # Ensures that the requested PowerShell module or native command is
    # available before PSConnMon attempts to execute probe logic that depends on
    # it. This keeps failure handling deterministic and gives operators a single,
    # actionable message.
    #
    # .PARAMETER DependencyName
    # The dependency name to validate.
    #
    # .PARAMETER DependencyType
    # Indicates whether the dependency is a PowerShell module or a native
    # command.
    #
    # .EXAMPLE
    # Assert-PSConnMonDependency -DependencyName 'ThreadJob' -DependencyType 'Module'
    #
    # .INPUTS
    # None. You can't pipe objects to Assert-PSConnMonDependency.
    #
    # .OUTPUTS
    # None. The function throws when the dependency is missing.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)][string]$DependencyName,
        [Parameter(Mandatory = $true)][ValidateSet('Module', 'Command')][string]$DependencyType
    )

    if ($DependencyType -eq 'Module') {
        if (-not (Get-Module -ListAvailable -Name $DependencyName)) {
            if ($DependencyName -eq 'ThreadJob') {
                throw 'ThreadJob is required. Install-Module ThreadJob -Scope CurrentUser -AllowClobber'
            }

            throw ('Missing PowerShell module dependency: {0}' -f $DependencyName)
        }

        Import-Module -Name $DependencyName -ErrorAction Stop
        return
    }

    if (-not (Get-Command -Name $DependencyName -ErrorAction SilentlyContinue)) {
        throw ('Missing native command dependency: {0}' -f $DependencyName)
    }
}

function Merge-PSConnMonHashtable {
    # .SYNOPSIS
    # Deep-merges configuration hashtables.
    #
    # .DESCRIPTION
    # Recursively merges a hashtable of defaults with a hashtable of overrides,
    # preserving nested dictionaries and replacing leaf values with the caller's
    # requested settings.
    #
    # .PARAMETER DefaultValue
    # The default configuration hashtable.
    #
    # .PARAMETER OverrideValue
    # The override configuration hashtable.
    #
    # .EXAMPLE
    # Merge-PSConnMonHashtable -DefaultValue $defaults -OverrideValue $overrides
    #
    # .INPUTS
    # None. You can't pipe objects to Merge-PSConnMonHashtable.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The merged hashtable.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$DefaultValue,
        [Parameter(Mandatory = $true)][hashtable]$OverrideValue
    )

    $mergedValue = @{}
    foreach ($key in $DefaultValue.Keys) {
        if ($OverrideValue.ContainsKey($key)) {
            $defaultChild = $DefaultValue[$key]
            $overrideChild = $OverrideValue[$key]

            if ($defaultChild -is [hashtable] -and $overrideChild -is [hashtable]) {
                $mergedValue[$key] = Merge-PSConnMonHashtable -DefaultValue $defaultChild -OverrideValue $overrideChild
            } else {
                $mergedValue[$key] = $overrideChild
            }
        } else {
            $mergedValue[$key] = $DefaultValue[$key]
        }
    }

    foreach ($key in $OverrideValue.Keys) {
        if (-not $mergedValue.ContainsKey($key)) {
            $mergedValue[$key] = $OverrideValue[$key]
        }
    }

    return $mergedValue
}

function Read-PSConnMonConfig {
    # .SYNOPSIS
    # Reads a PSConnMon configuration file.
    #
    # .DESCRIPTION
    # Loads a PSConnMon configuration file from disk and converts it to a
    # hashtable so that PSConnMon can validate and normalize it. YAML is the
    # preferred human-authored format when the runtime supports it; JSON remains
    # supported for compatibility and low-dependency automation.
    #
    # .PARAMETER Path
    # The YAML or JSON configuration path.
    #
    # .EXAMPLE
    # Read-PSConnMonConfig -Path '.\config\psconnmon.yaml'
    #
    # .INPUTS
    # None. You can't pipe objects to Read-PSConnMonConfig.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The parsed configuration.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw ('Configuration file was not found: {0}' -f $Path)
    }

    $rawContent = Get-Content -Path $Path -Raw -Encoding UTF8
    $extension = ([System.IO.Path]::GetExtension($Path)).ToLowerInvariant()

    if ($extension -in @('.yaml', '.yml')) {
        if (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
            return (ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Yaml -Yaml $rawContent))
        }

        if (Get-Module -ListAvailable -Name powershell-yaml) {
            Import-Module -Name powershell-yaml -ErrorAction Stop
            return (ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Yaml -Yaml $rawContent))
        }

        throw 'YAML configuration requires PowerShell 7 with ConvertFrom-Yaml or the powershell-yaml module. Use JSON instead if you need zero extra dependencies.'
    }

    return (ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Json -InputObject $rawContent))
}

function Get-PSConnMonEventRecord {
    # .SYNOPSIS
    # Creates a normalized PSConnMon event object.
    #
    # .DESCRIPTION
    # Produces a single event matching the canonical PSConnMon schema. The event
    # includes explicit target identity, result state, and room for hop-level or
    # probe-specific metadata.
    #
    # .PARAMETER AgentId
    # The monitoring agent identifier.
    #
    # .PARAMETER SiteId
    # The site identifier.
    #
    # .PARAMETER TargetId
    # The target identifier.
    #
    # .PARAMETER Fqdn
    # The target FQDN.
    #
    # .PARAMETER TargetAddress
    # The target address that was probed.
    #
    # .PARAMETER TestType
    # The normalized test type.
    #
    # .PARAMETER ProbeName
    # The friendly probe name.
    #
    # .PARAMETER Result
    # The normalized result state.
    #
    # .PARAMETER Details
    # Additional event details.
    #
    # .PARAMETER LatencyMs
    # Optional latency in milliseconds.
    #
    # .PARAMETER Loss
    # Optional packet loss percentage.
    #
    # .PARAMETER ErrorCode
    # Optional normalized error code.
    #
    # .PARAMETER DnsServer
    # Optional DNS server used for the probe.
    #
    # .PARAMETER HopIndex
    # Optional traceroute hop index.
    #
    # .PARAMETER HopAddress
    # Optional traceroute hop address.
    #
    # .PARAMETER HopName
    # Optional traceroute hop name.
    #
    # .PARAMETER HopLatencyMs
    # Optional traceroute hop latency.
    #
    # .PARAMETER PathHash
    # Optional path fingerprint.
    #
    # .PARAMETER Metadata
    # Optional metadata hashtable.
    #
    # .EXAMPLE
    # Get-PSConnMonEventRecord -AgentId 'branch-01' -SiteId 'plant-a' -TargetId 'fs01' `
    #   -Fqdn 'fs01.example.com' -TargetAddress '10.10.10.5' -TestType 'ping' `
    #   -ProbeName 'Ping.Primary' -Result 'SUCCESS' -LatencyMs 12.5
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonEventRecord.
    #
    # .OUTPUTS
    # System.Management.Automation.PSCustomObject. The normalized event object.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$AgentId,
        [Parameter(Mandatory = $true)][string]$SiteId,
        [Parameter(Mandatory = $true)][string]$TargetId,
        [Parameter(Mandatory = $true)][string]$Fqdn,
        [Parameter(Mandatory = $true)][string]$TargetAddress,
        [Parameter(Mandatory = $true)][string]$TestType,
        [Parameter(Mandatory = $true)][string]$ProbeName,
        [Parameter(Mandatory = $true)][ValidateSet('SUCCESS', 'FAILURE', 'TIMEOUT', 'EMPTY', 'SKIPPED', 'FATAL', 'INFO')][string]$Result,
        [Parameter(Mandatory = $false)][string]$Details = '',
        [Parameter(Mandatory = $false)][double]$LatencyMs = [double]::NaN,
        [Parameter(Mandatory = $false)][double]$Loss = [double]::NaN,
        [Parameter(Mandatory = $false)][string]$ErrorCode = '',
        [Parameter(Mandatory = $false)][string]$DnsServer = '',
        [Parameter(Mandatory = $false)][int]$HopIndex = -1,
        [Parameter(Mandatory = $false)][string]$HopAddress = '',
        [Parameter(Mandatory = $false)][string]$HopName = '',
        [Parameter(Mandatory = $false)][double]$HopLatencyMs = [double]::NaN,
        [Parameter(Mandatory = $false)][string]$PathHash = '',
        [Parameter(Mandatory = $false)][hashtable]$Metadata = @{}
    )

    $eventValue = [ordered]@{
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        agentId = $AgentId
        siteId = $SiteId
        targetId = $TargetId
        fqdn = $Fqdn
        targetAddress = $TargetAddress
        testType = $TestType
        probeName = $ProbeName
        result = $Result
        latencyMs = if ([double]::IsNaN($LatencyMs)) { $null } else { $LatencyMs }
        loss = if ([double]::IsNaN($Loss)) { $null } else { $Loss }
        errorCode = if ([string]::IsNullOrWhiteSpace($ErrorCode)) { $null } else { $ErrorCode }
        details = $Details
        dnsServer = if ([string]::IsNullOrWhiteSpace($DnsServer)) { $null } else { $DnsServer }
        hopIndex = if ($HopIndex -lt 0) { $null } else { $HopIndex }
        hopAddress = if ([string]::IsNullOrWhiteSpace($HopAddress)) { $null } else { $HopAddress }
        hopName = if ([string]::IsNullOrWhiteSpace($HopName)) { $null } else { $HopName }
        hopLatencyMs = if ([double]::IsNaN($HopLatencyMs)) { $null } else { $HopLatencyMs }
        pathHash = if ([string]::IsNullOrWhiteSpace($PathHash)) { $null } else { $PathHash }
        metadata = $Metadata
    }

    return [pscustomobject]$eventValue
}

function Get-PSConnMonConfigDirectory {
    # .SYNOPSIS
    # Returns the active PSConnMon config directory.
    #
    # .DESCRIPTION
    # Resolves the runtime config directory captured during config loading and
    # falls back to the current working directory when no runtime metadata is
    # present.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Get-PSConnMonConfigDirectory -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonConfigDirectory.
    #
    # .OUTPUTS
    # System.String. The resolved config directory.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    if (
        $Config.ContainsKey('_runtime') -and
        ($Config._runtime -is [hashtable]) -and
        (-not [string]::IsNullOrWhiteSpace($Config._runtime.configDirectory))
    ) {
        return [System.IO.Path]::GetFullPath([string]$Config._runtime.configDirectory)
    }

    return [System.IO.Path]::GetFullPath((Get-Location).Path)
}

function Test-PSConnMonPathIsUnderAllowedRoots {
    # .SYNOPSIS
    # Tests whether one path remains under an allowlisted root.
    #
    # .DESCRIPTION
    # Compares a normalized candidate path against one or more normalized root
    # paths and returns `$true` when the candidate stays within at least one
    # root boundary.
    #
    # .PARAMETER CandidatePath
    # The normalized path to validate.
    #
    # .PARAMETER AllowedRoots
    # One or more normalized root paths.
    #
    # .EXAMPLE
    # Test-PSConnMonPathIsUnderAllowedRoots -CandidatePath $path -AllowedRoots $roots
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonPathIsUnderAllowedRoots.
    #
    # .OUTPUTS
    # System.Boolean. Returns `$true` when the candidate is allowlisted.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string[]]$AllowedRoots
    )

    foreach ($allowedRoot in $AllowedRoots) {
        $normalizedRoot = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if (($CandidatePath -eq $normalizedRoot) -or $CandidatePath.StartsWith(($normalizedRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function New-PSConnMonProbeException {
    # .SYNOPSIS
    # Creates a PSConnMon exception with a normalized error code.
    #
    # .DESCRIPTION
    # Wraps a message in an InvalidOperationException and stores a PSConnMon
    # error code in the exception data bag so probe callers can emit
    # deterministic event error codes without parsing free-form text.
    #
    # .PARAMETER ErrorCode
    # The normalized PSConnMon error code.
    #
    # .PARAMETER Message
    # The human-readable exception message.
    #
    # .EXAMPLE
    # throw (New-PSConnMonProbeException -ErrorCode 'LinuxSecretFileMissing' -Message 'Linux secret file was not found.')
    #
    # .INPUTS
    # None. You can't pipe objects to New-PSConnMonProbeException.
    #
    # .OUTPUTS
    # System.InvalidOperationException. The tagged exception instance.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([System.InvalidOperationException])]
    param(
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $exception = New-Object System.InvalidOperationException($Message)
    $exception.Data['PSConnMonErrorCode'] = $ErrorCode
    return $exception
}

function Resolve-PSConnMonTrustedFilePath {
    # .SYNOPSIS
    # Resolves an allowlisted local file path for PSConnMon secrets.
    #
    # .DESCRIPTION
    # Resolves a local file path relative to the config directory or a caller
    # supplied base directory, enforces allowlisted root boundaries, rejects
    # symlink leaf nodes, and optionally constrains the file extension.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER InputPath
    # The caller-supplied file path.
    #
    # .PARAMETER BaseDirectory
    # Optional base directory used for relative path resolution.
    #
    # .PARAMETER ErrorCodePrefix
    # Prefix used to construct deterministic PSConnMon error codes.
    #
    # .PARAMETER PathLabel
    # Human-readable label used in error messages.
    #
    # .PARAMETER AllowedExtensions
    # Optional allowlist of lowercase file extensions.
    #
    # .EXAMPLE
    # Resolve-PSConnMonTrustedFilePath -Config $config -InputPath './secrets/linux-share.json' -ErrorCodePrefix 'LinuxSecret' -PathLabel 'Linux auth secret file' -AllowedExtensions @('.json')
    #
    # .INPUTS
    # None. You can't pipe objects to Resolve-PSConnMonTrustedFilePath.
    #
    # .OUTPUTS
    # System.String. The resolved trusted file path.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $false)][string]$BaseDirectory = '',
        [Parameter(Mandatory = $true)][string]$ErrorCodePrefix,
        [Parameter(Mandatory = $true)][string]$PathLabel,
        [Parameter(Mandatory = $false)][string[]]$AllowedExtensions = @()
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}PathRequired' -f $ErrorCodePrefix) -Message ('{0} path is required.' -f $PathLabel))
    }

    $resolvedBaseDirectory = if ([string]::IsNullOrWhiteSpace($BaseDirectory)) {
        Get-PSConnMonConfigDirectory -Config $Config
    } else {
        [System.IO.Path]::GetFullPath($BaseDirectory)
    }

    $candidatePath = if ([System.IO.Path]::IsPathRooted($InputPath)) {
        [System.IO.Path]::GetFullPath($InputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $resolvedBaseDirectory -ChildPath $InputPath))
    }

    $allowedRoots = @(
        (Get-PSConnMonConfigDirectory -Config $Config),
        [System.IO.Path]::GetFullPath((Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'secrets'))
    )

    if (-not (Test-PSConnMonPathIsUnderAllowedRoots -CandidatePath $candidatePath -AllowedRoots $allowedRoots)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}PathNotAllowed' -f $ErrorCodePrefix) -Message ('{0} must remain under the config directory or spool secrets directory. Path: {1}' -f $PathLabel, $candidatePath))
    }

    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}FileMissing' -f $ErrorCodePrefix) -Message ('{0} was not found: {1}' -f $PathLabel, $candidatePath))
    }

    $resolvedPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop).ProviderPath)
    if (-not (Test-PSConnMonPathIsUnderAllowedRoots -CandidatePath $resolvedPath -AllowedRoots $allowedRoots)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}PathNotAllowed' -f $ErrorCodePrefix) -Message ('{0} resolved outside the allowlisted roots. Path: {1}' -f $PathLabel, $resolvedPath))
    }

    $itemValue = Get-Item -LiteralPath $candidatePath -Force
    if (($itemValue.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}SymlinkNotAllowed' -f $ErrorCodePrefix) -Message ('{0} must not be a symlink or reparse point. Path: {1}' -f $PathLabel, $candidatePath))
    }

    if ($AllowedExtensions.Count -gt 0) {
        $extension = ([System.IO.Path]::GetExtension($resolvedPath)).ToLowerInvariant()
        if ($extension -notin $AllowedExtensions) {
            throw (New-PSConnMonProbeException -ErrorCode ('{0}FileExtensionInvalid' -f $ErrorCodePrefix) -Message ('{0} must use one of these extensions: {1}' -f $PathLabel, (($AllowedExtensions | Sort-Object) -join ', ')))
        }
    }

    return $resolvedPath
}

function Resolve-PSConnMonTrustedOutputPath {
    # .SYNOPSIS
    # Resolves an allowlisted writable local path for PSConnMon secrets.
    #
    # .DESCRIPTION
    # Resolves a local output path relative to the config directory or a caller
    # supplied base directory and enforces the same allowlisted root boundary
    # used for local secret files. Existing leaf and parent symlinks are
    # rejected.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER InputPath
    # The caller-supplied output path.
    #
    # .PARAMETER BaseDirectory
    # Optional base directory used for relative path resolution.
    #
    # .PARAMETER ErrorCodePrefix
    # Prefix used to construct deterministic PSConnMon error codes.
    #
    # .PARAMETER PathLabel
    # Human-readable label used in error messages.
    #
    # .EXAMPLE
    # Resolve-PSConnMonTrustedOutputPath -Config $config -InputPath './secrets/krb5cc-fs01' -ErrorCodePrefix 'LinuxCredentialCache' -PathLabel 'Linux credential cache path'
    #
    # .INPUTS
    # None. You can't pipe objects to Resolve-PSConnMonTrustedOutputPath.
    #
    # .OUTPUTS
    # System.String. The resolved output path.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $false)][string]$BaseDirectory = '',
        [Parameter(Mandatory = $true)][string]$ErrorCodePrefix,
        [Parameter(Mandatory = $true)][string]$PathLabel
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}PathRequired' -f $ErrorCodePrefix) -Message ('{0} path is required.' -f $PathLabel))
    }

    $resolvedBaseDirectory = if ([string]::IsNullOrWhiteSpace($BaseDirectory)) {
        Get-PSConnMonConfigDirectory -Config $Config
    } else {
        [System.IO.Path]::GetFullPath($BaseDirectory)
    }

    $candidatePath = if ([System.IO.Path]::IsPathRooted($InputPath)) {
        [System.IO.Path]::GetFullPath($InputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $resolvedBaseDirectory -ChildPath $InputPath))
    }

    $allowedRoots = @(
        (Get-PSConnMonConfigDirectory -Config $Config),
        [System.IO.Path]::GetFullPath((Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'secrets'))
    )

    if (-not (Test-PSConnMonPathIsUnderAllowedRoots -CandidatePath $candidatePath -AllowedRoots $allowedRoots)) {
        throw (New-PSConnMonProbeException -ErrorCode ('{0}PathNotAllowed' -f $ErrorCodePrefix) -Message ('{0} must remain under the config directory or spool secrets directory. Path: {1}' -f $PathLabel, $candidatePath))
    }

    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        $itemValue = Get-Item -LiteralPath $candidatePath -Force
        if (($itemValue.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw (New-PSConnMonProbeException -ErrorCode ('{0}SymlinkNotAllowed' -f $ErrorCodePrefix) -Message ('{0} must not be a symlink or reparse point. Path: {1}' -f $PathLabel, $candidatePath))
        }
    }

    $parentPath = Split-Path -Path $candidatePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and (Test-Path -LiteralPath $parentPath -PathType Container)) {
        $resolvedParentPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $parentPath -ErrorAction Stop).ProviderPath)
        if (-not (Test-PSConnMonPathIsUnderAllowedRoots -CandidatePath $resolvedParentPath -AllowedRoots $allowedRoots)) {
            throw (New-PSConnMonProbeException -ErrorCode ('{0}PathNotAllowed' -f $ErrorCodePrefix) -Message ('{0} resolved outside the allowlisted roots. Path: {1}' -f $PathLabel, $resolvedParentPath))
        }

        $parentItemValue = Get-Item -LiteralPath $parentPath -Force
        if (($parentItemValue.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw (New-PSConnMonProbeException -ErrorCode ('{0}ParentSymlinkNotAllowed' -f $ErrorCodePrefix) -Message ('{0} parent directory must not be a symlink or reparse point. Path: {1}' -f $PathLabel, $parentPath))
        }
    }

    return $candidatePath
}

function Resolve-PSConnMonLinuxAuthProfileDefinition {
    # .SYNOPSIS
    # Resolves one Linux auth profile definition.
    #
    # .DESCRIPTION
    # Validates one configured Linux auth profile, resolves any referenced local
    # secret files and keytabs, and returns a runtime-ready profile context that
    # can be used by Linux share and Kerberos probes.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER Profile
    # The Linux auth profile definition.
    #
    # .EXAMPLE
    # Resolve-PSConnMonLinuxAuthProfileDefinition -Config $config -Profile $config.auth.linuxProfiles[0]
    #
    # .INPUTS
    # None. You can't pipe objects to Resolve-PSConnMonLinuxAuthProfileDefinition.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The resolved profile context.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Profile
    )

    if ([string]::IsNullOrWhiteSpace($Profile.id)) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxProfileIdRequired' -Message 'Each Linux auth profile requires an id.')
    }

    $profileMode = if ($Profile.ContainsKey('mode')) { [string]$Profile.mode } else { '' }
    if ($profileMode -notin @('currentContext', 'kerberosKeytab', 'usernamePassword')) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxProfileModeInvalid' -Message ('Linux auth profile {0} uses an unsupported mode.' -f $Profile.id))
    }

    $profileContext = @{
        id = [string]$Profile.id
        mode = $profileMode
        secretReference = if ($Profile.ContainsKey('secretReference')) { [string]$Profile.secretReference } else { '' }
    }

    if ($profileMode -eq 'currentContext') {
        if (-not [string]::IsNullOrWhiteSpace($profileContext.secretReference)) {
            throw (New-PSConnMonProbeException -ErrorCode 'LinuxCurrentContextSecretUnsupported' -Message ('Linux auth profile {0} uses currentContext and must not define a secretReference.' -f $Profile.id))
        }

        return $profileContext
    }

    if ([string]::IsNullOrWhiteSpace($profileContext.secretReference)) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxSecretReferenceRequired' -Message ('Linux auth profile {0} requires a secretReference.' -f $Profile.id))
    }

    $secretPath = Resolve-PSConnMonTrustedFilePath -Config $Config -InputPath $profileContext.secretReference -ErrorCodePrefix 'LinuxSecret' -PathLabel 'Linux auth secret file' -AllowedExtensions @('.json')
    $secretDirectory = Split-Path -Path $secretPath -Parent

    try {
        $secretValue = ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $secretPath -Raw -Encoding UTF8))
    } catch {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxSecretFileInvalid' -Message ('Linux auth secret file is not valid JSON. Path: {0}' -f $secretPath))
    }

    if (-not ($secretValue -is [hashtable])) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxSecretFileInvalid' -Message ('Linux auth secret file must deserialize to an object. Path: {0}' -f $secretPath))
    }

    $profileContext.secretPath = $secretPath

    if ($profileMode -eq 'kerberosKeytab') {
        if ([string]::IsNullOrWhiteSpace([string]$secretValue.principal)) {
            throw (New-PSConnMonProbeException -ErrorCode 'LinuxKerberosPrincipalRequired' -Message ('Linux auth profile {0} requires principal in its secret file.' -f $Profile.id))
        }

        if ([string]::IsNullOrWhiteSpace([string]$secretValue.keytabPath)) {
            throw (New-PSConnMonProbeException -ErrorCode 'LinuxKeytabPathRequired' -Message ('Linux auth profile {0} requires keytabPath in its secret file.' -f $Profile.id))
        }

        $profileContext.principal = [string]$secretValue.principal
        $profileContext.keytabPath = Resolve-PSConnMonTrustedFilePath -Config $Config -InputPath ([string]$secretValue.keytabPath) -BaseDirectory $secretDirectory -ErrorCodePrefix 'LinuxKeytab' -PathLabel 'Linux keytab file'

        $credentialCachePath = if ($secretValue.ContainsKey('ccachePath') -and (-not [string]::IsNullOrWhiteSpace([string]$secretValue.ccachePath))) {
            Resolve-PSConnMonTrustedOutputPath -Config $Config -InputPath ([string]$secretValue.ccachePath) -BaseDirectory $secretDirectory -ErrorCodePrefix 'LinuxCredentialCache' -PathLabel 'Linux credential cache path'
        } else {
            Resolve-PSConnMonTrustedOutputPath -Config $Config -InputPath ([System.IO.Path]::GetFullPath((Join-Path -Path (Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'secrets') -ChildPath ('krb5cc-{0}' -f $Profile.id)))) -ErrorCodePrefix 'LinuxCredentialCache' -PathLabel 'Linux credential cache path'
        }

        $profileContext.ccachePath = $credentialCachePath
        return $profileContext
    }

    if ([string]::IsNullOrWhiteSpace([string]$secretValue.username)) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxUsernameRequired' -Message ('Linux auth profile {0} requires username in its secret file.' -f $Profile.id))
    }

    if ([string]::IsNullOrWhiteSpace([string]$secretValue.password)) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxPasswordRequired' -Message ('Linux auth profile {0} requires password in its secret file.' -f $Profile.id))
    }

    $profileContext.username = [string]$secretValue.username
    $profileContext.password = [string]$secretValue.password
    $profileContext.domain = if ($secretValue.ContainsKey('domain')) { [string]$secretValue.domain } else { '' }
    return $profileContext
}

function Resolve-PSConnMonLinuxAuthProfileContext {
    # .SYNOPSIS
    # Selects the effective Linux auth profile for a probe.
    #
    # .DESCRIPTION
    # Applies PSConnMon Linux auth profile precedence for one target or share
    # probe. Share-scoped profile references override target-scoped references.
    # When no explicit profile is configured, the legacy current-context Linux
    # behavior remains active.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Share
    # Optional share definition for share-scoped overrides.
    #
    # .EXAMPLE
    # Resolve-PSConnMonLinuxAuthProfileContext -Config $config -Target $config.targets[0] -Share $config.targets[0].shares[0]
    #
    # .INPUTS
    # None. You can't pipe objects to Resolve-PSConnMonLinuxAuthProfileContext.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The effective profile context.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $false)][AllowNull()][hashtable]$Share = $null
    )

    $selectedProfileId = ''
    if (($null -ne $Share) -and $Share.ContainsKey('linuxProfileId') -and (-not [string]::IsNullOrWhiteSpace([string]$Share.linuxProfileId))) {
        $selectedProfileId = [string]$Share.linuxProfileId
    } elseif ($Target.ContainsKey('linuxProfileId') -and (-not [string]::IsNullOrWhiteSpace([string]$Target.linuxProfileId))) {
        $selectedProfileId = [string]$Target.linuxProfileId
    }

    if ([string]::IsNullOrWhiteSpace($selectedProfileId)) {
        return @{
            id = ''
            mode = 'currentContext'
            secretReference = ''
        }
    }

    $profiles = if ($Config.auth.ContainsKey('linuxProfiles')) {
        ConvertTo-PSConnMonArray -InputObject $Config.auth.linuxProfiles
    } else {
        @()
    }

    $profileValue = $profiles | Where-Object { $_.id -eq $selectedProfileId } | Select-Object -First 1
    if ($null -eq $profileValue) {
        throw (New-PSConnMonProbeException -ErrorCode 'LinuxProfileNotFound' -Message ('Linux auth profile was not found: {0}' -f $selectedProfileId))
    }

    return (Resolve-PSConnMonLinuxAuthProfileDefinition -Config $Config -Profile $profileValue)
}

function Resolve-PSConnMonExtensionPath {
    # .SYNOPSIS
    # Resolves and validates a configured extension script path.
    #
    # .DESCRIPTION
    # Ensures that extension scripts are loaded only from trusted local paths.
    # Relative paths are resolved against the config directory when available,
    # otherwise against the current working directory. The resolved file must
    # remain under either the config directory or the spool extension directory.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER Extension
    # The extension definition.
    #
    # .EXAMPLE
    # Resolve-PSConnMonExtensionPath -Config $config -Extension $config.extensions[0]
    #
    # .INPUTS
    # None. You can't pipe objects to Resolve-PSConnMonExtensionPath.
    #
    # .OUTPUTS
    # System.String. The resolved extension script path.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Extension
    )

    $baseDirectory = if (
        $Config.ContainsKey('_runtime') -and
        ($Config._runtime -is [hashtable]) -and
        (-not [string]::IsNullOrWhiteSpace($Config._runtime.configDirectory))
    ) {
        $Config._runtime.configDirectory
    } else {
        (Get-Location).Path
    }

    $candidatePath = if ([System.IO.Path]::IsPathRooted($Extension.path)) {
        [System.IO.Path]::GetFullPath($Extension.path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $baseDirectory -ChildPath $Extension.path))
    }

    $allowedRoots = @(
        [System.IO.Path]::GetFullPath($baseDirectory),
        [System.IO.Path]::GetFullPath((Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'extensions'))
    )

    $pathIsAllowed = $false
    foreach ($allowedRoot in $allowedRoots) {
        $normalizedRoot = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if (($candidatePath -eq $normalizedRoot) -or $candidatePath.StartsWith(($normalizedRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
            $pathIsAllowed = $true
            break
        }
    }

    if (-not $pathIsAllowed) {
        throw ('Extension path must remain under the config directory or spool extension directory. Path: {0}' -f $candidatePath)
    }

    if (-not (Test-Path -Path $candidatePath -PathType Leaf)) {
        throw ('Extension script was not found: {0}' -f $candidatePath)
    }

    if (([System.IO.Path]::GetExtension($candidatePath)).ToLowerInvariant() -ne '.ps1') {
        throw ('Extension scripts must use the .ps1 extension. Path: {0}' -f $candidatePath)
    }

    return $candidatePath
}

function ConvertTo-PSConnMonExtensionEvent {
    # .SYNOPSIS
    # Normalizes one extension return object into a PSConnMon event.
    #
    # .DESCRIPTION
    # Accepts an extension-returned object or event-like hashtable and converts
    # it into a canonical PSConnMon event while applying safe defaults for agent,
    # site, target, and metadata fields.
    #
    # .PARAMETER Event
    # The extension-returned event object.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER Target
    # The current target definition.
    #
    # .PARAMETER Extension
    # The extension definition.
    #
    # .EXAMPLE
    # ConvertTo-PSConnMonExtensionEvent -Event $event -Config $config -Target $target -Extension $extension
    #
    # .INPUTS
    # None. You can't pipe objects to ConvertTo-PSConnMonExtensionEvent.
    #
    # .OUTPUTS
    # System.Management.Automation.PSCustomObject. The normalized event.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object]$Event,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Extension
    )

    $eventValue = ConvertTo-PSConnMonHashtable -InputObject $Event
    if ($null -eq $eventValue) {
        throw ('Extension {0} returned a null event.' -f $Extension.id)
    }

    $metadataValue = if ($eventValue.ContainsKey('metadata') -and ($eventValue.metadata -is [hashtable])) {
        Merge-PSConnMonHashtable -DefaultValue @{ extensionId = $Extension.id } -OverrideValue $eventValue.metadata
    } else {
        @{ extensionId = $Extension.id }
    }

    return Get-PSConnMonEventRecord `
        -AgentId $(if ($eventValue.ContainsKey('agentId')) { [string]$eventValue.agentId } else { [string]$Config.agent.agentId }) `
        -SiteId $(if ($eventValue.ContainsKey('siteId')) { [string]$eventValue.siteId } else { [string]$Config.agent.siteId }) `
        -TargetId $(if ($eventValue.ContainsKey('targetId')) { [string]$eventValue.targetId } else { [string]$Target.id }) `
        -Fqdn $(if ($eventValue.ContainsKey('fqdn')) { [string]$eventValue.fqdn } else { [string]$Target.fqdn }) `
        -TargetAddress $(if ($eventValue.ContainsKey('targetAddress')) { [string]$eventValue.targetAddress } else { [string]$Target.address }) `
        -TestType $(if ($eventValue.ContainsKey('testType')) { [string]$eventValue.testType } else { [string]$Extension.id }) `
        -ProbeName $(if ($eventValue.ContainsKey('probeName')) { [string]$eventValue.probeName } else { [string]$Extension.entryPoint }) `
        -Result $(if ($eventValue.ContainsKey('result')) { [string]$eventValue.result } else { 'INFO' }) `
        -Details $(if ($eventValue.ContainsKey('details')) { [string]$eventValue.details } else { 'Extension completed without additional details.' }) `
        -LatencyMs $(if ($eventValue.ContainsKey('latencyMs') -and $null -ne $eventValue.latencyMs) { [double]$eventValue.latencyMs } else { [double]::NaN }) `
        -Loss $(if ($eventValue.ContainsKey('loss') -and $null -ne $eventValue.loss) { [double]$eventValue.loss } else { [double]::NaN }) `
        -ErrorCode $(if ($eventValue.ContainsKey('errorCode')) { [string]$eventValue.errorCode } else { '' }) `
        -DnsServer $(if ($eventValue.ContainsKey('dnsServer')) { [string]$eventValue.dnsServer } else { '' }) `
        -HopIndex $(if ($eventValue.ContainsKey('hopIndex') -and $null -ne $eventValue.hopIndex) { [int]$eventValue.hopIndex } else { -1 }) `
        -HopAddress $(if ($eventValue.ContainsKey('hopAddress')) { [string]$eventValue.hopAddress } else { '' }) `
        -HopName $(if ($eventValue.ContainsKey('hopName')) { [string]$eventValue.hopName } else { '' }) `
        -HopLatencyMs $(if ($eventValue.ContainsKey('hopLatencyMs') -and $null -ne $eventValue.hopLatencyMs) { [double]$eventValue.hopLatencyMs } else { [double]::NaN }) `
        -PathHash $(if ($eventValue.ContainsKey('pathHash')) { [string]$eventValue.pathHash } else { '' }) `
        -Metadata $metadataValue
}

function Invoke-PSConnMonExtensionProbe {
    # .SYNOPSIS
    # Executes one configured extension probe for a target.
    #
    # .DESCRIPTION
    # Loads a trusted local PowerShell script, invokes the configured entrypoint
    # with the current target and configuration, and normalizes the returned
    # objects into canonical PSConnMon events.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER Extension
    # The configured extension definition.
    #
    # .EXAMPLE
    # Invoke-PSConnMonExtensionProbe -Target $target -Config $config -Extension $extension
    #
    # .INPUTS
    # None. You can't pipe objects to Invoke-PSConnMonExtensionProbe.
    #
    # .OUTPUTS
    # System.Object[]. One or more normalized PSConnMon events.
    #
    # .NOTES
    # Version: 0.3.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Extension
    )

    try {
        $extensionPath = Resolve-PSConnMonExtensionPath -Config $Config -Extension $Extension
        . $extensionPath

        $entryPointCommand = Get-Command -Name $Extension.entryPoint -CommandType Function -ErrorAction Stop
        $extensionResults = & $entryPointCommand -Target $Target -Config $Config -Extension $Extension
        $normalizedEvents = New-Object System.Collections.Generic.List[object]

        foreach ($resultValue in (ConvertTo-PSConnMonArray -InputObject $extensionResults)) {
            $normalizedEvents.Add((ConvertTo-PSConnMonExtensionEvent -Event $resultValue -Config $Config -Target $Target -Extension $Extension)) | Out-Null
        }

        if ($normalizedEvents.Count -eq 0) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType $Extension.id `
                    -ProbeName $Extension.entryPoint -Result 'EMPTY' `
                    -Details ('Extension {0} returned no events.' -f $Extension.id) `
                    -Metadata @{ extensionId = $Extension.id }
            )
        }

        return $normalizedEvents.ToArray()
    } catch {
        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType $Extension.id `
                -ProbeName $(if ($Extension.ContainsKey('entryPoint')) { $Extension.entryPoint } else { 'Invoke-PSConnMonExtension' }) `
                -Result 'FATAL' -ErrorCode 'ExtensionProbeFailure' -Details $_.Exception.Message `
                -Metadata @{ extensionId = $Extension.id }
        )
    }
}

function Convert-PSConnMonSharePathToLinux {
    # .SYNOPSIS
    # Converts a UNC share path to an smbclient-compatible path.
    #
    # .DESCRIPTION
    # Rewrites a Windows UNC path into the forward-slash format expected by
    # smbclient on Linux and macOS hosts.
    #
    # .PARAMETER SharePath
    # The input UNC path.
    #
    # .EXAMPLE
    # Convert-PSConnMonSharePathToLinux -SharePath '\\fs01\plant'
    #
    # .INPUTS
    # None. You can't pipe objects to Convert-PSConnMonSharePathToLinux.
    #
    # .OUTPUTS
    # System.String. The smbclient-compatible path.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$SharePath
    )

    return ($SharePath -replace '^\\\\', '//' -replace '\\', '/')
}

function Get-PSConnMonTracerouteHopEvent {
    # .SYNOPSIS
    # Parses traceroute output into PSConnMon events.
    #
    # .DESCRIPTION
    # Reads platform-specific traceroute output and emits canonical hop events
    # plus one summary event with a deterministic path fingerprint.
    #
    # .PARAMETER OutputLines
    # The raw traceroute output lines.
    #
    # .PARAMETER AgentId
    # The monitoring agent identifier.
    #
    # .PARAMETER SiteId
    # The site identifier.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER TargetAddress
    # The address used for the trace.
    #
    # .EXAMPLE
    # Get-PSConnMonTracerouteHopEvent -OutputLines $lines -AgentId 'agent-01' `
    #   -SiteId 'site-a' -Target $target -TargetAddress '8.8.8.8'
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonTracerouteHopEvent.
    #
    # .OUTPUTS
    # System.Object[]. Hop events.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][string[]]$OutputLines,
        [Parameter(Mandatory = $true)][string]$AgentId,
        [Parameter(Mandatory = $true)][string]$SiteId,
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][string]$TargetAddress
    )

    $hopValues = New-Object System.Collections.Generic.List[string]
    $eventValues = New-Object System.Collections.Generic.List[object]

    foreach ($lineValue in $OutputLines) {
        $trimmedLine = $lineValue.Trim()
        if ($trimmedLine -match '^(?<hop>\d+)\s+(?<rest>.+)$') {
            $hopIndex = [int]$Matches.hop
            $hopAddress = ''
            $hopName = ''
            $hopLatencyMs = [double]::NaN

            if ($trimmedLine -match '(\d{1,3}(\.\d{1,3}){3})') {
                $hopAddress = $Matches[1]
            }

            if ($trimmedLine -match '(<\d+|\d+(\.\d+)?)\s*ms') {
                $latencyText = $Matches[1].TrimStart('<')
                $hopLatencyMs = [double]$latencyText
            }

            if ($trimmedLine -match '^\d+\s+([A-Za-z0-9\.\-]+)\s+\(?(\d{1,3}(\.\d{1,3}){3})?\)?') {
                $candidateHopName = $Matches[1]
                if (
                    (-not [string]::IsNullOrWhiteSpace($candidateHopName)) -and
                    ($candidateHopName -ne $hopAddress) -and
                    ($candidateHopName -notmatch '^\d+(\.\d+)?$')
                ) {
                    $hopName = $candidateHopName
                }
            }

            $hopValues.Add(('{0}:{1}' -f $hopIndex, $hopAddress))
            $eventValues.Add(
                (Get-PSConnMonEventRecord -AgentId $AgentId -SiteId $SiteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $TargetAddress -TestType 'traceroute' `
                    -ProbeName 'Traceroute.Path' -Result 'INFO' -Details $trimmedLine `
                    -HopIndex $hopIndex -HopAddress $hopAddress -HopName $hopName `
                    -HopLatencyMs $hopLatencyMs -Metadata @{ role = 'hop' })
            ) | Out-Null
        }
    }

    $pathHash = ''
    if ($hopValues.Count -gt 0) {
        $joinedPath = [string]::Join('|', $hopValues)
        $sha256Provider = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256Provider.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($joinedPath))
        } finally {
            $sha256Provider.Dispose()
        }
        $pathHash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16)
    }

    foreach ($eventValue in $eventValues) {
        $eventValue.pathHash = if ([string]::IsNullOrWhiteSpace($pathHash)) { $null } else { $pathHash }
    }

    if ($hopValues.Count -gt 0) {
        $eventValues.Add(
            (Get-PSConnMonEventRecord -AgentId $AgentId -SiteId $SiteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $TargetAddress -TestType 'traceroute' `
                -ProbeName 'Traceroute.Summary' -Result 'SUCCESS' `
                -Details ('Traceroute completed with {0} hops.' -f $hopValues.Count) `
                -PathHash $pathHash -Metadata @{
                    role = 'summary'
                    hopCount = $hopValues.Count
                })
        ) | Out-Null
    }

    return $eventValues.ToArray()
}

function Test-PSConnMonConfig {
    # .SYNOPSIS
    # Validates and normalizes a PSConnMon configuration.
    #
    # .DESCRIPTION
    # Loads a PSConnMon configuration from disk or uses an in-memory hashtable,
    # validates required sections, fills defaults, and optionally returns the
    # normalized configuration.
    #
    # .PARAMETER Path
    # Optional path to a JSON configuration file.
    #
    # .PARAMETER Config
    # Optional in-memory hashtable configuration.
    #
    # .PARAMETER PassThru
    # Returns the normalized configuration when specified.
    #
    # .EXAMPLE
    # Test-PSConnMonConfig -Path '.\config\psconnmon.json'
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonConfig.
    #
    # .OUTPUTS
    # System.Boolean or System.Collections.Hashtable. Returns $true by default or
    # the normalized configuration with -PassThru.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([bool])]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)][string]$Path,
        [Parameter(Mandatory = $false)][hashtable]$Config,
        [Parameter(Mandatory = $false)][switch]$PassThru
    )

    if ($PSBoundParameters.ContainsKey('Path')) {
        $Config = Read-PSConnMonConfig -Path $Path
        $Config._runtime = @{
            configDirectory = (Split-Path -Path ([System.IO.Path]::GetFullPath($Path)) -Parent)
        }
    }

    if ($null -eq $Config) {
        throw 'Either -Path or -Config must be provided.'
    }

    if (-not $Config.ContainsKey('_runtime')) {
        $Config._runtime = @{
            configDirectory = (Get-Location).Path
        }
    }

    $defaultConfig = @{
        schemaVersion = '1.0'
        agent = @{
            agentId = 'branch-01'
            siteId = 'default-site'
            spoolDirectory = 'data/spool'
            batchSize = 250
            publishIntervalSeconds = 30
            configPollIntervalSeconds = 60
            cycleIntervalSeconds = 30
            maxRuntimeMinutes = 0
            cleanupAfterDays = 7
        }
        publish = @{
            mode = 'local'
            format = 'jsonl'
            csvMirror = $false
            azure = @{
                enabled = $false
                accountName = ''
                containerName = ''
                blobPrefix = 'events'
                configBlobPath = ''
                authMode = 'managedIdentity'
                sasToken = ''
            }
        }
        tests = @{
            enabled = @('ping', 'dns', 'share', 'internetQuality', 'traceroute')
            pingTimeoutMs = 3000
            pingPacketSize = 56
            shareAccessTimeoutSeconds = 15
            tracerouteTimeoutSeconds = 20
            tracerouteProbeTimeoutSeconds = 3
            internetQualitySampleCount = 4
        }
        auth = @{
            linuxSmbMode = 'currentContext'
            secretReference = ''
            linuxProfiles = @()
        }
        targets = @()
        extensions = @()
    }

    $normalizedConfig = Merge-PSConnMonHashtable -DefaultValue $defaultConfig -OverrideValue $Config
    $normalizedConfig.targets = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.targets
    $normalizedConfig.extensions = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.extensions
    $normalizedConfig.tests.enabled = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.tests.enabled
    $normalizedConfig.auth.linuxProfiles = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.auth.linuxProfiles

    if ($normalizedConfig.schemaVersion -ne '1.0') {
        throw 'Only schemaVersion 1.0 is supported.'
    }

    if ([string]::IsNullOrWhiteSpace($normalizedConfig.agent.agentId)) {
        throw 'agent.agentId is required.'
    }

    if ([string]::IsNullOrWhiteSpace($normalizedConfig.agent.siteId)) {
        throw 'agent.siteId is required.'
    }

    if ($normalizedConfig.targets.Count -lt 1) {
        throw 'At least one target is required.'
    }

    $linuxProfileIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($linuxProfileValue in $normalizedConfig.auth.linuxProfiles) {
        if ([string]::IsNullOrWhiteSpace($linuxProfileValue.id)) {
            throw 'Each auth.linuxProfiles entry requires an id.'
        }

        if (-not $linuxProfileIds.Add([string]$linuxProfileValue.id)) {
            throw ('Duplicate Linux auth profile id: {0}' -f $linuxProfileValue.id)
        }

        if (-not $linuxProfileValue.ContainsKey('mode') -or [string]::IsNullOrWhiteSpace([string]$linuxProfileValue.mode)) {
            throw ('Linux auth profile {0} requires mode.' -f $linuxProfileValue.id)
        }

        if ([string]$linuxProfileValue.mode -notin @('currentContext', 'kerberosKeytab', 'usernamePassword')) {
            throw ('Linux auth profile {0} uses an unsupported mode.' -f $linuxProfileValue.id)
        }

        if (-not $linuxProfileValue.ContainsKey('secretReference')) {
            $linuxProfileValue.secretReference = ''
        }

        [void](Resolve-PSConnMonLinuxAuthProfileDefinition -Config $normalizedConfig -Profile $linuxProfileValue)
    }

    $targetIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($targetValue in $normalizedConfig.targets) {
        if ([string]::IsNullOrWhiteSpace($targetValue.id)) {
            throw 'Each target requires an id.'
        }

        if (-not $targetIds.Add($targetValue.id)) {
            throw ('Duplicate target id: {0}' -f $targetValue.id)
        }

        if ([string]::IsNullOrWhiteSpace($targetValue.fqdn)) {
            throw ('Target {0} requires fqdn.' -f $targetValue.id)
        }

        if ([string]::IsNullOrWhiteSpace($targetValue.address)) {
            throw ('Target {0} requires address.' -f $targetValue.id)
        }

        if ($targetValue.ContainsKey('tests')) {
            $targetValue.tests = ConvertTo-PSConnMonArray -InputObject $targetValue.tests
        }

        if ($targetValue.ContainsKey('shares')) {
            $targetValue.shares = ConvertTo-PSConnMonArray -InputObject $targetValue.shares
        }

        if ($targetValue.ContainsKey('dnsServers')) {
            $targetValue.dnsServers = ConvertTo-PSConnMonArray -InputObject $targetValue.dnsServers
        }

        if ($targetValue.ContainsKey('roles')) {
            $targetValue.roles = ConvertTo-PSConnMonArray -InputObject $targetValue.roles
        }

        if ($targetValue.ContainsKey('tags')) {
            $targetValue.tags = ConvertTo-PSConnMonArray -InputObject $targetValue.tags
        }

        if (-not $targetValue.ContainsKey('linuxProfileId')) {
            $targetValue.linuxProfileId = ''
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$targetValue.linuxProfileId) -and (-not $linuxProfileIds.Contains([string]$targetValue.linuxProfileId))) {
            throw ('Target {0} references an unknown linuxProfileId: {1}' -f $targetValue.id, $targetValue.linuxProfileId)
        }

        if (-not $targetValue.ContainsKey('tests') -or $targetValue.tests.Count -eq 0) {
            $targetValue.tests = @($normalizedConfig.tests.enabled)
        }

        if (-not $targetValue.ContainsKey('shares')) {
            $targetValue.shares = @()
        }

        if (-not $targetValue.ContainsKey('dnsServers')) {
            $targetValue.dnsServers = @()
        }

        if (-not $targetValue.ContainsKey('roles')) {
            $targetValue.roles = @()
        }

        if (-not $targetValue.ContainsKey('tags')) {
            $targetValue.tags = @()
        }

        if (-not $targetValue.ContainsKey('externalTraceTarget')) {
            $targetValue.externalTraceTarget = $targetValue.address
        }

        foreach ($shareValue in $targetValue.shares) {
            if ([string]::IsNullOrWhiteSpace($shareValue.id)) {
                throw ('Each share for target {0} requires an id.' -f $targetValue.id)
            }

            if ([string]::IsNullOrWhiteSpace($shareValue.path)) {
                throw ('Share {0} for target {1} requires path.' -f $shareValue.id, $targetValue.id)
            }

            if (-not $shareValue.ContainsKey('linuxProfileId')) {
                $shareValue.linuxProfileId = ''
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$shareValue.linuxProfileId) -and (-not $linuxProfileIds.Contains([string]$shareValue.linuxProfileId))) {
                throw ('Share {0} for target {1} references an unknown linuxProfileId: {2}' -f $shareValue.id, $targetValue.id, $shareValue.linuxProfileId)
            }
        }
    }

    if ($normalizedConfig.publish.azure.enabled) {
        if ([string]::IsNullOrWhiteSpace($normalizedConfig.publish.azure.accountName)) {
            throw 'publish.azure.accountName is required when Azure publishing is enabled.'
        }

        if ([string]::IsNullOrWhiteSpace($normalizedConfig.publish.azure.containerName)) {
            throw 'publish.azure.containerName is required when Azure publishing is enabled.'
        }
    }

    $extensionIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($extensionValue in $normalizedConfig.extensions) {
        if ($extensionValue.ContainsKey('script') -or $extensionValue.ContainsKey('scriptBlock') -or $extensionValue.ContainsKey('inlineScript')) {
            throw 'Extensions must reference trusted local script files. Inline script content is not supported.'
        }

        if ([string]::IsNullOrWhiteSpace($extensionValue.id)) {
            throw 'Each extension requires an id.'
        }

        if (-not $extensionIds.Add([string]$extensionValue.id)) {
            throw ('Duplicate extension id: {0}' -f $extensionValue.id)
        }

        if ([string]::IsNullOrWhiteSpace($extensionValue.path)) {
            throw ('Extension {0} requires a path.' -f $extensionValue.id)
        }

        if (-not $extensionValue.ContainsKey('entryPoint') -or [string]::IsNullOrWhiteSpace($extensionValue.entryPoint)) {
            $extensionValue.entryPoint = 'Invoke-PSConnMonExtension'
        }

        if (-not $extensionValue.ContainsKey('enabled')) {
            $extensionValue.enabled = $true
        } else {
            $extensionValue.enabled = [bool]$extensionValue.enabled
        }

        if ($extensionValue.ContainsKey('targets')) {
            $extensionValue.targets = ConvertTo-PSConnMonArray -InputObject $extensionValue.targets
        } else {
            $extensionValue.targets = @()
        }

        if ($extensionValue.enabled) {
            [void](Resolve-PSConnMonExtensionPath -Config $normalizedConfig -Extension $extensionValue)
        }
    }

    if ($PassThru) {
        return $normalizedConfig
    }

    return $true
}

function Export-PSConnMonSampleConfig {
    # .SYNOPSIS
    # Writes a sample PSConnMon configuration to disk.
    #
    # .DESCRIPTION
    # Creates an example configuration file that demonstrates the canonical
    # PSConnMon configuration model.
    #
    # .PARAMETER Path
    # The destination path for the sample configuration.
    #
    # .PARAMETER Force
    # Overwrites the file when it already exists.
    #
    # .EXAMPLE
    # Export-PSConnMonSampleConfig -Path '.\config\sample.psconnmon.yaml' -Force
    #
    # .INPUTS
    # None. You can't pipe objects to Export-PSConnMonSampleConfig.
    #
    # .OUTPUTS
    # System.String. The written path.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$Force
    )

    $sampleConfig = @{
        schemaVersion = '1.0'
        agent = @{
            agentId = 'branch-01'
            siteId = 'default-site'
            spoolDirectory = 'data/spool'
            batchSize = 250
            publishIntervalSeconds = 30
            configPollIntervalSeconds = 60
            cycleIntervalSeconds = 30
            maxRuntimeMinutes = 0
            cleanupAfterDays = 7
        }
        publish = @{
            mode = 'local'
            format = 'jsonl'
            csvMirror = $true
            azure = @{
                enabled = $false
                accountName = 'psconnmonstorage'
                containerName = 'telemetry'
                blobPrefix = 'events'
                configBlobPath = 'configs/branch-01.json'
                authMode = 'managedIdentity'
                sasToken = ''
            }
        }
        tests = @{
            enabled = @('ping', 'dns', 'share', 'internetQuality', 'traceroute')
            pingTimeoutMs = 3000
            pingPacketSize = 56
            shareAccessTimeoutSeconds = 15
            tracerouteTimeoutSeconds = 20
            tracerouteProbeTimeoutSeconds = 3
            internetQualitySampleCount = 4
        }
        auth = @{
            linuxSmbMode = 'currentContext'
            secretReference = ''
            linuxProfiles = @()
        }
        targets = @(
            @{
                id = 'fs01'
                fqdn = 'fs01.corp.local'
                address = '10.10.20.15'
                roles = @('fileserver')
                tags = @('default', 'primary')
                dnsServers = @('10.10.0.10')
                shares = @(
                    @{
                        id = 'plant'
                        path = '\\fs01.corp.local\Plant'
                    }
                )
                tests = @('ping', 'dns', 'share', 'internetQuality', 'traceroute')
                externalTraceTarget = '8.8.8.8'
            }
        )
        extensions = @()
    }

    $directoryPath = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        [void](New-Item -Path $directoryPath -ItemType Directory -Force)
    }

    if ((Test-Path -Path $Path) -and (-not $Force)) {
        throw ('Path already exists. Use -Force to overwrite: {0}' -f $Path)
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Write sample PSConnMon config')) {
        $extension = ([System.IO.Path]::GetExtension($Path)).ToLowerInvariant()
        if ($extension -in @('.yaml', '.yml')) {
            if (-not (Get-Command -Name ConvertTo-Yaml -ErrorAction SilentlyContinue)) {
                throw 'YAML export requires PowerShell 7 with ConvertTo-Yaml.'
            }

            $sampleConfig | ConvertTo-Yaml -OutFile $Path -Force
        } else {
            $sampleConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
        }
    }

    return $Path
}

function Write-PSConnMonEvent {
    # .SYNOPSIS
    # Writes an event to a JSONL batch file.
    #
    # .DESCRIPTION
    # Persists a canonical event to the batch file used for local retention and
    # optional cloud publishing. When requested, a CSV mirror is also written for
    # operator convenience.
    #
    # .PARAMETER Event
    # The event object to write.
    #
    # .PARAMETER BatchPath
    # The JSON Lines batch file path.
    #
    # .PARAMETER WriteCsvMirror
    # Writes a CSV mirror file beside the batch.
    #
    # .EXAMPLE
    # Write-PSConnMonEvent -Event $event -BatchPath '.\data\spool\pending\cycle.jsonl'
    #
    # .INPUTS
    # None. You can't pipe objects to Write-PSConnMonEvent.
    #
    # .OUTPUTS
    # System.String. The batch file path.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Event,
        [Parameter(Mandatory = $true)][string]$BatchPath,
        [Parameter(Mandatory = $false)][switch]$WriteCsvMirror
    )

    $parentPath = Split-Path -Path $BatchPath -Parent
    [void](New-Item -Path $parentPath -ItemType Directory -Force)
    Add-Content -Path $BatchPath -Value ($Event | ConvertTo-Json -Compress -Depth 10) -Encoding UTF8

    if ($WriteCsvMirror) {
        $csvPath = [System.IO.Path]::ChangeExtension($BatchPath, '.csv')
        if (-not (Test-Path -Path $csvPath)) {
            Set-Content -Path $csvPath -Value 'timestampUtc,agentId,siteId,targetId,fqdn,targetAddress,testType,probeName,result,latencyMs,loss,errorCode,details' -Encoding UTF8
        }

        $csvLine = '"{0}","{1}","{2}","{3}","{4}","{5}","{6}","{7}","{8}","{9}","{10}","{11}","{12}"' -f `
            $Event.timestampUtc, $Event.agentId, $Event.siteId, $Event.targetId, $Event.fqdn, `
            $Event.targetAddress, $Event.testType, $Event.probeName, $Event.result, `
            $Event.latencyMs, $Event.loss, $Event.errorCode, ($Event.details -replace '"', '""')
        Add-Content -Path $csvPath -Value $csvLine -Encoding UTF8
    }

    return $BatchPath
}

function Test-PSConnMonPing {
    # .SYNOPSIS
    # Executes an ICMP probe for one target.
    #
    # .DESCRIPTION
    # Sends a single ICMP request using .NET so that the probe behaves
    # consistently across supported operating systems.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonPing -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonPing.
    #
    # .OUTPUTS
    # System.Object[]. One event describing the probe outcome.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $pingSender = New-Object System.Net.NetworkInformation.Ping
    $bufferValue = [byte[]]::CreateInstance([byte], [int]$Config.tests.pingPacketSize)

    try {
        $replyValue = $pingSender.Send($Target.address, [int]$Config.tests.pingTimeoutMs, $bufferValue)
        if ($replyValue.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' `
                    -ProbeName 'Ping.Primary' -Result 'SUCCESS' -LatencyMs ([double]$replyValue.RoundtripTime) `
                    -Details ('Reply from {0}' -f $replyValue.Address.IPAddressToString)
            )
        }

        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' -ProbeName 'Ping.Primary' `
                -Result 'FAILURE' -ErrorCode $replyValue.Status.ToString() -Details ('Ping status: {0}' -f $replyValue.Status)
        )
    } catch {
        if (-not $script:PSConnMonIsWindows -and (Get-Command -Name ping -ErrorAction SilentlyContinue)) {
            try {
                $timeoutSeconds = [Math]::Max([int][Math]::Ceiling(([double]$Config.tests.pingTimeoutMs / 1000)), 1)
                $nativeOutput = @(ping -c 1 -W $timeoutSeconds $Target.address 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    $latencyMatch = ($nativeOutput | Select-String -Pattern 'time[=<]([0-9\.]+)\s*ms' | Select-Object -First 1)
                    $nativeLatency = if ($null -ne $latencyMatch) { [double]$latencyMatch.Matches[0].Groups[1].Value } else { 0.0 }
                    return @(
                        Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                            -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' `
                            -ProbeName 'Ping.Primary' -Result 'SUCCESS' -LatencyMs $nativeLatency `
                            -Details (($nativeOutput | Select-Object -Last 1).ToString())
                    )
                }

                return @(
                    Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' -ProbeName 'Ping.Primary' `
                        -Result 'FAILURE' -ErrorCode 'NativePingFailure' -Details (($nativeOutput | Out-String).Trim())
                )
            } catch {
                return @(
                    Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' -ProbeName 'Ping.Primary' `
                        -Result 'FATAL' -ErrorCode 'NativePingException' -Details $_.Exception.Message
                )
            }
        }

        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' -ProbeName 'Ping.Primary' `
                -Result 'FATAL' -ErrorCode 'PingException' -Details $_.Exception.Message
        )
    } finally {
        $pingSender.Dispose()
    }
}

function Test-PSConnMonDnsQuery {
    # .SYNOPSIS
    # Resolves a target FQDN against one or more DNS servers.
    #
    # .DESCRIPTION
    # Uses Resolve-DnsName when available or falls back to dig/nslookup so that
    # the same logical probe can run on both Windows and Linux.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonDnsQuery -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonDnsQuery.
    #
    # .OUTPUTS
    # System.Object[]. DNS probe events.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $eventValues = New-Object System.Collections.Generic.List[object]
    $dnsServers = if ($Target.dnsServers.Count -gt 0) {
        @($Target.dnsServers)
    } else {
        $primaryDnsServer = Get-PSConnMonPrimaryDnsServer -OSIsWindows $script:PSConnMonIsWindows
        if ([string]::IsNullOrWhiteSpace($primaryDnsServer)) {
            @('system-default')
        } else {
            @($primaryDnsServer)
        }
    }

    foreach ($dnsServer in $dnsServers) {
        try {
            $resolvedAddress = ''
            $failureDetails = 'DNS query returned no address.'
            if (($script:PSConnMonIsWindows) -and (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) -and ($dnsServer -ne 'system-default')) {
                $resolvedAddress = (Resolve-DnsName -Name $Target.fqdn -Server $dnsServer -Type A -DnsOnly | Select-Object -First 1 -ExpandProperty IPAddress)
            } elseif ((Get-Command -Name dig -ErrorAction SilentlyContinue) -and ($dnsServer -ne 'system-default')) {
                $digOutput = @(dig +short "@$dnsServer" $Target.fqdn 2>&1)
                $digLines = @($digOutput | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $resolvedAddress = @(
                    $digLines |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -match '^(\d{1,3}(\.\d{1,3}){3}|[0-9A-Fa-f:]+)$' } |
                        Select-Object -First 1
                ) -join ''

                if ([string]::IsNullOrWhiteSpace($resolvedAddress) -and ($digLines.Count -gt 0)) {
                    $failureDetails = ($digLines -join [System.Environment]::NewLine)
                }
            } elseif (Get-Command -Name nslookup -ErrorAction SilentlyContinue) {
                $nslookupOutput = if ($dnsServer -eq 'system-default') {
                    nslookup $Target.fqdn 2>&1
                } else {
                    nslookup $Target.fqdn $dnsServer 2>&1
                }
                $resolvedAddress = (($nslookupOutput | Select-String -Pattern 'Address:\s+(\d{1,3}(\.\d{1,3}){3})').Matches | Select-Object -Last 1).Groups[1].Value
            } else {
                $resolvedAddress = ([System.Net.Dns]::GetHostAddresses($Target.fqdn) | Select-Object -First 1).IPAddressToString
            }

            if ([string]::IsNullOrWhiteSpace($resolvedAddress)) {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'dns' -ProbeName 'DNS.Lookup' `
                        -Result 'FAILURE' -DnsServer $dnsServer -ErrorCode 'NoAddress' -Details $failureDetails)
                ) | Out-Null
            } else {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'dns' -ProbeName 'DNS.Lookup' `
                        -Result 'SUCCESS' -DnsServer $dnsServer -Details ('Resolved to {0}' -f $resolvedAddress))
                ) | Out-Null
            }
        } catch {
            $eventValues.Add(
                (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'dns' -ProbeName 'DNS.Lookup' `
                    -Result 'FATAL' -DnsServer $dnsServer -ErrorCode 'DnsQueryFailure' -Details $_.Exception.Message)
            ) | Out-Null
        }
    }

    return $eventValues.ToArray()
}

function Test-PSConnMonShare {
    # .SYNOPSIS
    # Tests share accessibility for one target.
    #
    # .DESCRIPTION
    # Uses ThreadJob to bound potentially long-running filesystem or smbclient
    # access tests so that a single hung share does not stall the monitoring
    # agent.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonShare -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonShare.
    #
    # .OUTPUTS
    # System.Object[]. Share probe events.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    Assert-PSConnMonDependency -DependencyName 'ThreadJob' -DependencyType 'Module'

    if ($Target.shares.Count -eq 0) {
        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                -Result 'SKIPPED' -ErrorCode 'NoSharesConfigured' -Details 'Target has no configured shares.'
        )
    }

    $eventValues = New-Object System.Collections.Generic.List[object]
    foreach ($shareValue in $Target.shares) {
        $jobValue = $null
        $metadataValue = @{
            shareId = $shareValue.id
            sharePath = $shareValue.path
        }
        try {
            if ($script:PSConnMonIsWindows) {
                $jobValue = Start-ThreadJob -ScriptBlock {
                    $itemValue = Get-ChildItem -Path $args[0] -Force -ErrorAction Stop | Select-Object -First 1
                    return @{
                        result = if ($null -eq $itemValue) { 'EMPTY' } else { 'SUCCESS' }
                        details = if ($null -eq $itemValue) { 'Share probe succeeded but returned no visible items.' } else { 'Share access confirmed.' }
                        errorCode = $null
                    }
                } -ArgumentList $shareValue.path
            } else {
                $linuxProfileContext = Resolve-PSConnMonLinuxAuthProfileContext -Config $Config -Target $Target -Share $shareValue
                if (-not [string]::IsNullOrWhiteSpace($linuxProfileContext.id)) {
                    $metadataValue.linuxProfileId = $linuxProfileContext.id
                }

                if (-not (Get-Command -Name smbclient -ErrorAction SilentlyContinue)) {
                    $eventValues.Add(
                        (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                            -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                            -Result 'SKIPPED' -ErrorCode 'SmbClientMissing' -Details 'smbclient is required for Linux share probes.' `
                            -Metadata $metadataValue)
                    ) | Out-Null
                    continue
                }

                if (($linuxProfileContext.mode -eq 'kerberosKeytab') -and (-not (Get-Command -Name kinit -ErrorAction SilentlyContinue))) {
                    $eventValues.Add(
                        (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                            -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                            -Result 'SKIPPED' -ErrorCode 'LinuxKinitMissing' -Details 'kinit is required for keytab-backed Linux share probes.' `
                            -Metadata $metadataValue)
                    ) | Out-Null
                    continue
                }

                $linuxSharePath = Convert-PSConnMonSharePathToLinux -SharePath $shareValue.path
                $jobValue = Start-ThreadJob -ScriptBlock {
                    $sharePath = [string]$args[0]
                    $profileContext = $args[1]
                    $commandOutput = @()
                    $exitCode = 0

                    if ($profileContext.mode -eq 'currentContext') {
                        $commandOutput = @(smbclient $sharePath -g -k -c 'ls' 2>&1)
                        $exitCode = [int]$LASTEXITCODE
                    } elseif ($profileContext.mode -eq 'kerberosKeytab') {
                        $credentialCacheDirectory = Split-Path -Path $profileContext.ccachePath -Parent
                        if (-not [string]::IsNullOrWhiteSpace($credentialCacheDirectory)) {
                            [void](New-Item -Path $credentialCacheDirectory -ItemType Directory -Force)
                        }

                        $env:KRB5CCNAME = $profileContext.ccachePath
                        $null = @(kinit -k -t $profileContext.keytabPath $profileContext.principal 2>&1)
                        if ([int]$LASTEXITCODE -ne 0) {
                            return @{
                                result = 'FAILURE'
                                errorCode = 'LinuxKerberosAcquireFailed'
                                details = 'Kerberos ticket acquisition failed for the Linux share probe.'
                            }
                        }

                        $commandOutput = @(smbclient $sharePath -g -k -c 'ls' 2>&1)
                        $exitCode = [int]$LASTEXITCODE
                    } elseif ($profileContext.mode -eq 'usernamePassword') {
                        $tempAuthPath = [System.IO.Path]::GetTempFileName()
                        try {
                            $authLines = New-Object System.Collections.Generic.List[string]
                            if (-not [string]::IsNullOrWhiteSpace($profileContext.domain)) {
                                $authLines.Add(('domain = {0}' -f $profileContext.domain)) | Out-Null
                            }

                            $authLines.Add(('username = {0}' -f $profileContext.username)) | Out-Null
                            $authLines.Add(('password = {0}' -f $profileContext.password)) | Out-Null
                            Set-Content -LiteralPath $tempAuthPath -Value $authLines.ToArray() -Encoding Ascii

                            if (Get-Command -Name chmod -ErrorAction SilentlyContinue) {
                                chmod 600 $tempAuthPath 2>&1 | Out-Null
                            }

                            $commandOutput = @(smbclient $sharePath -g -A $tempAuthPath -c 'ls' 2>&1)
                            $exitCode = [int]$LASTEXITCODE
                        } finally {
                            Remove-Item -LiteralPath $tempAuthPath -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        return @{
                            result = 'FAILURE'
                            errorCode = 'LinuxAuthModeUnsupported'
                            details = 'Linux share probe profile mode is not supported.'
                        }
                    }

                    if ($exitCode -ne 0) {
                        return @{
                            result = 'FAILURE'
                            errorCode = 'LinuxShareAccessFailed'
                            details = ('smbclient returned exit code {0}.' -f $exitCode)
                        }
                    }

                    return @{
                        result = if ($null -eq $commandOutput -or [string]::IsNullOrWhiteSpace(($commandOutput | Out-String).Trim())) { 'EMPTY' } else { 'SUCCESS' }
                        details = if ($null -eq $commandOutput -or [string]::IsNullOrWhiteSpace(($commandOutput | Out-String).Trim())) { 'Share probe succeeded but returned no visible items.' } else { 'Share access confirmed.' }
                        errorCode = $null
                    }
                } -ArgumentList $linuxSharePath, $linuxProfileContext
            }

            if (-not (Wait-Job -Job $jobValue -Timeout ([int]$Config.tests.shareAccessTimeoutSeconds))) {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                        -Result 'TIMEOUT' -ErrorCode 'ShareTimeout' `
                        -Details ('Share probe exceeded {0} seconds.' -f $Config.tests.shareAccessTimeoutSeconds) `
                        -Metadata $metadataValue)
                ) | Out-Null
                continue
            }

            $jobOutput = Receive-Job -Job $jobValue -Wait -ErrorAction Stop
            if (-not ($jobOutput -is [System.Collections.IDictionary])) {
                throw (New-PSConnMonProbeException -ErrorCode 'ShareProbeFailure' -Message 'Share probe returned an unexpected result payload.')
            }

            $eventValues.Add(
                (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                    -Result ([string]$jobOutput.result) -ErrorCode ([string]$jobOutput.errorCode) -Details ([string]$jobOutput.details) `
                    -Metadata $metadataValue)
            ) | Out-Null
        } catch {
            $errorCode = if ($_.Exception.Data.Contains('PSConnMonErrorCode')) {
                [string]$_.Exception.Data['PSConnMonErrorCode']
            } else {
                'ShareProbeFailure'
            }
            $eventValues.Add(
                (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                    -Result 'FATAL' -ErrorCode $errorCode -Details $_.Exception.Message `
                    -Metadata $metadataValue)
            ) | Out-Null
        } finally {
            if ($null -ne $jobValue) {
                Stop-Job -Job $jobValue -ErrorAction SilentlyContinue
                Remove-Job -Job $jobValue -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $eventValues.ToArray()
}

function Test-PSConnMonDomainAuth {
    # .SYNOPSIS
    # Validates Linux Kerberos auth health for one target.
    #
    # .DESCRIPTION
    # Confirms that a Linux collector can use its effective Kerberos-backed auth
    # profile for one target. Current-context probes validate the active ticket
    # cache, while keytab-backed profiles acquire and validate a ticket. Explicit
    # username/password profiles remain SMB-only and are skipped.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonDomainAuth -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonDomainAuth.
    #
    # .OUTPUTS
    # System.Object[]. Domain auth probe events.
    #
    # .NOTES
    # Version: 0.3.20260412.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    Assert-PSConnMonDependency -DependencyName 'ThreadJob' -DependencyType 'Module'

    if ($script:PSConnMonIsWindows) {
        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                -Result 'SKIPPED' -ErrorCode 'DomainAuthUnsupportedPlatform' `
                -Details 'domainAuth is supported on Linux collectors only.'
        )
    }

    $jobValue = $null
    $metadataValue = @{}
    try {
        $linuxProfileContext = Resolve-PSConnMonLinuxAuthProfileContext -Config $Config -Target $Target
        if (-not [string]::IsNullOrWhiteSpace($linuxProfileContext.id)) {
            $metadataValue.linuxProfileId = $linuxProfileContext.id
        }

        if ($linuxProfileContext.mode -eq 'usernamePassword') {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                    -Result 'SKIPPED' -ErrorCode 'DomainAuthUnsupportedProfileMode' `
                    -Details 'domainAuth requires currentContext or kerberosKeytab Linux auth.' `
                    -Metadata $metadataValue
            )
        }

        if (-not (Get-Command -Name klist -ErrorAction SilentlyContinue)) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                    -Result 'SKIPPED' -ErrorCode 'LinuxKlistMissing' `
                    -Details 'klist is required for Linux domainAuth probes.' `
                    -Metadata $metadataValue
            )
        }

        if (($linuxProfileContext.mode -eq 'kerberosKeytab') -and (-not (Get-Command -Name kinit -ErrorAction SilentlyContinue))) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                    -Result 'SKIPPED' -ErrorCode 'LinuxKinitMissing' `
                    -Details 'kinit is required for keytab-backed Linux domainAuth probes.' `
                    -Metadata $metadataValue
            )
        }

        $jobValue = Start-ThreadJob -ScriptBlock {
            $profileContext = $args[0]

            if ($profileContext.mode -eq 'currentContext') {
                $null = @(klist -s 2>&1)
                if ([int]$LASTEXITCODE -eq 0) {
                    return @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Kerberos ticket cache is available in the current Linux context.'
                    }
                }

                return @{
                    result = 'FAILURE'
                    errorCode = 'LinuxKerberosTicketMissing'
                    details = 'Kerberos ticket cache validation failed for the current Linux context.'
                }
            }

            $credentialCacheDirectory = Split-Path -Path $profileContext.ccachePath -Parent
            if (-not [string]::IsNullOrWhiteSpace($credentialCacheDirectory)) {
                [void](New-Item -Path $credentialCacheDirectory -ItemType Directory -Force)
            }

            $env:KRB5CCNAME = $profileContext.ccachePath
            $null = @(kinit -k -t $profileContext.keytabPath $profileContext.principal 2>&1)
            if ([int]$LASTEXITCODE -ne 0) {
                return @{
                    result = 'FAILURE'
                    errorCode = 'LinuxKerberosAcquireFailed'
                    details = 'Kerberos ticket acquisition failed for the Linux domainAuth probe.'
                }
            }

            $null = @(klist -s 2>&1)
            if ([int]$LASTEXITCODE -ne 0) {
                return @{
                    result = 'FAILURE'
                    errorCode = 'LinuxKerberosTicketMissing'
                    details = 'Kerberos ticket cache validation failed after keytab acquisition.'
                }
            }

            return @{
                result = 'SUCCESS'
                errorCode = $null
                details = 'Kerberos ticket acquisition and validation succeeded.'
            }
        } -ArgumentList $linuxProfileContext

        if (-not (Wait-Job -Job $jobValue -Timeout ([int]$Config.tests.shareAccessTimeoutSeconds))) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                    -Result 'TIMEOUT' -ErrorCode 'DomainAuthTimeout' `
                    -Details ('domainAuth probe exceeded {0} seconds.' -f $Config.tests.shareAccessTimeoutSeconds) `
                    -Metadata $metadataValue
            )
        }

        $jobOutput = Receive-Job -Job $jobValue -Wait -ErrorAction Stop
        if (-not ($jobOutput -is [System.Collections.IDictionary])) {
            throw (New-PSConnMonProbeException -ErrorCode 'DomainAuthProbeFailure' -Message 'domainAuth probe returned an unexpected result payload.')
        }

        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                -Result ([string]$jobOutput.result) -ErrorCode ([string]$jobOutput.errorCode) -Details ([string]$jobOutput.details) `
                -Metadata $metadataValue
        )
    } catch {
        $errorCode = if ($_.Exception.Data.Contains('PSConnMonErrorCode')) {
            [string]$_.Exception.Data['PSConnMonErrorCode']
        } else {
            'DomainAuthProbeFailure'
        }

        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'domainAuth' -ProbeName 'DomainAuth.Kerberos' `
                -Result 'FATAL' -ErrorCode $errorCode -Details $_.Exception.Message `
                -Metadata $metadataValue
        )
    } finally {
        if ($null -ne $jobValue) {
            Stop-Job -Job $jobValue -ErrorAction SilentlyContinue
            Remove-Job -Job $jobValue -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-PSConnMonInternetQuality {
    # .SYNOPSIS
    # Measures internet-facing latency and packet loss for one target.
    #
    # .DESCRIPTION
    # Sends multiple ICMP samples to the target's configured external trace
    # address and emits a single summary event suitable for dashboarding.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonInternetQuality -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonInternetQuality.
    #
    # .OUTPUTS
    # System.Object[]. One summary event.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $sampleTarget = $Target.externalTraceTarget
    $sampleCount = [int]$Config.tests.internetQualitySampleCount
    $latencies = New-Object System.Collections.Generic.List[double]

    for ($index = 0; $index -lt $sampleCount; $index++) {
        $probeEvents = Test-PSConnMonPing -Target @{ id = $Target.id; fqdn = $Target.fqdn; address = $sampleTarget } -Config $Config
        $probeEvent = $probeEvents[0]
        if ($probeEvent.result -eq 'SUCCESS' -and $null -ne $probeEvent.latencyMs) {
            $latencies.Add([double]$probeEvent.latencyMs)
        }
    }

    $lossValue = (($sampleCount - $latencies.Count) / [double]$sampleCount) * 100
    if ($latencies.Count -eq 0) {
        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $sampleTarget -TestType 'internetQuality' `
                -ProbeName 'InternetQuality.SampleSet' -Result 'FAILURE' -Loss $lossValue `
                -ErrorCode 'AllSamplesFailed' -Details 'Every sample failed.'
        )
    }

    $averageLatency = ($latencies | Measure-Object -Average).Average
    $detailsValue = 'Average latency {0:N2} ms across {1}/{2} successful samples.' -f $averageLatency, $latencies.Count, $sampleCount
    return @(
        Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
            -Fqdn $Target.fqdn -TargetAddress $sampleTarget -TestType 'internetQuality' `
            -ProbeName 'InternetQuality.SampleSet' -Result 'SUCCESS' -LatencyMs $averageLatency `
            -Loss $lossValue -Details $detailsValue
    )
}

function Test-PSConnMonTraceroute {
    # .SYNOPSIS
    # Executes a traceroute for one target.
    #
    # .DESCRIPTION
    # Runs the platform-specific traceroute command in a ThreadJob, applies a
    # timeout, and emits hop-level path events suitable for PingPlotter-style
    # visualization.
    #
    # .PARAMETER Target
    # The target definition.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Test-PSConnMonTraceroute -Target $config.targets[0] -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Test-PSConnMonTraceroute.
    #
    # .OUTPUTS
    # System.Object[]. Hop events or one failure event.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    Assert-PSConnMonDependency -DependencyName 'ThreadJob' -DependencyType 'Module'

    $traceTarget = $Target.externalTraceTarget
    $jobValue = $null
    try {
        if ($script:PSConnMonIsWindows) {
            $jobValue = Start-ThreadJob -ScriptBlock {
                tracert -d -w ($args[1] * 1000) $args[0] 2>&1
            } -ArgumentList $traceTarget, ([int]$Config.tests.tracerouteProbeTimeoutSeconds)
        } else {
            if (-not (Get-Command -Name traceroute -ErrorAction SilentlyContinue)) {
                return @(
                    Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $traceTarget -TestType 'traceroute' `
                        -ProbeName 'Traceroute.Path' -Result 'SKIPPED' -ErrorCode 'TracerouteMissing' `
                        -Details 'traceroute command is not available on this host.'
                )
            }

            $jobValue = Start-ThreadJob -ScriptBlock {
                traceroute -n -w $args[1] $args[0] 2>&1
            } -ArgumentList $traceTarget, ([int]$Config.tests.tracerouteProbeTimeoutSeconds)
        }

        if (-not (Wait-Job -Job $jobValue -Timeout ([int]$Config.tests.tracerouteTimeoutSeconds))) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $traceTarget -TestType 'traceroute' `
                    -ProbeName 'Traceroute.Path' -Result 'TIMEOUT' -ErrorCode 'TracerouteTimeout' `
                    -Details ('Traceroute exceeded {0} seconds.' -f $Config.tests.tracerouteTimeoutSeconds)
            )
        }

        $outputLines = [string[]]@(
            Receive-Job -Job $jobValue -Wait -ErrorAction Stop |
                ForEach-Object {
                    if ($null -ne $_) {
                        $_.ToString()
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $parsedEvents = @()
        if ($outputLines.Count -gt 0) {
            $parsedEvents = @(Get-PSConnMonTracerouteHopEvent -OutputLines $outputLines -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -Target $Target -TargetAddress $traceTarget)
        }
        if ($parsedEvents.Count -gt 0) {
            return $parsedEvents
        }

        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $traceTarget -TestType 'traceroute' `
                -ProbeName 'Traceroute.Path' -Result 'FAILURE' -ErrorCode 'NoPathData' `
                -Details 'Traceroute completed but no hop data was parsed.'
        )
    } catch {
        return @(
            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                -Fqdn $Target.fqdn -TargetAddress $traceTarget -TestType 'traceroute' `
                -ProbeName 'Traceroute.Path' -Result 'FATAL' -ErrorCode 'TracerouteFailure' `
                -Details $_.Exception.Message
        )
    } finally {
        if ($null -ne $jobValue) {
            Stop-Job -Job $jobValue -ErrorAction SilentlyContinue
            Remove-Job -Job $jobValue -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-PSConnMonCycle {
    # .SYNOPSIS
    # Executes one monitoring cycle across all configured targets.
    #
    # .DESCRIPTION
    # Runs the enabled probes for each target, writes events to the current JSONL
    # batch, and returns the collected events to the caller for publishing or
    # assertions.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .PARAMETER BatchPath
    # The destination batch file path.
    #
    # .EXAMPLE
    # Start-PSConnMonCycle -Config $config -BatchPath '.\data\spool\pending\cycle.jsonl'
    #
    # .INPUTS
    # None. You can't pipe objects to Start-PSConnMonCycle.
    #
    # .OUTPUTS
    # System.Object[]. The events written during the cycle.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$BatchPath
    )

    $allEvents = New-Object System.Collections.Generic.List[object]
    foreach ($targetValue in $Config.targets) {
        foreach ($testName in $targetValue.tests) {
            $probeEvents = switch ($testName) {
                'ping' { @(Test-PSConnMonPing -Target $targetValue -Config $Config) }
                'dns' { @(Test-PSConnMonDnsQuery -Target $targetValue -Config $Config) }
                'share' { @(Test-PSConnMonShare -Target $targetValue -Config $Config) }
                'domainAuth' { @(Test-PSConnMonDomainAuth -Target $targetValue -Config $Config) }
                'internetQuality' { @(Test-PSConnMonInternetQuality -Target $targetValue -Config $Config) }
                'traceroute' { @(Test-PSConnMonTraceroute -Target $targetValue -Config $Config) }
                default {
                    $extensionValue = $Config.extensions | Where-Object { $_.id -eq $testName -and $_.enabled } | Select-Object -First 1
                    if ($null -ne $extensionValue) {
                        if (($extensionValue.targets.Count -gt 0) -and ($targetValue.id -notin $extensionValue.targets)) {
                            @(
                                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $targetValue.id `
                                    -Fqdn $targetValue.fqdn -TargetAddress $targetValue.address -TestType $testName `
                                    -ProbeName $extensionValue.entryPoint -Result 'SKIPPED' -ErrorCode 'ExtensionTargetExcluded' `
                                    -Details ('Extension {0} is not enabled for target {1}.' -f $testName, $targetValue.id) `
                                    -Metadata @{ extensionId = $extensionValue.id }
                            )
                        } else {
                            @(Invoke-PSConnMonExtensionProbe -Target $targetValue -Config $Config -Extension $extensionValue)
                        }
                    } else {
                        @(
                            Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $targetValue.id `
                                -Fqdn $targetValue.fqdn -TargetAddress $targetValue.address -TestType $testName `
                                -ProbeName 'Probe.Unknown' -Result 'SKIPPED' -ErrorCode 'UnsupportedProbe' `
                                -Details ('Probe {0} is not implemented.' -f $testName)
                        )
                    }
                }
            }

            foreach ($probeEvent in $probeEvents) {
                if ($PSCmdlet.ShouldProcess($BatchPath, 'Write PSConnMon cycle event')) {
                    [void](Write-PSConnMonEvent -Event $probeEvent -BatchPath $BatchPath -WriteCsvMirror:([bool]$Config.publish.csvMirror))
                    $allEvents.Add($probeEvent) | Out-Null
                }
            }
        }
    }

    return $allEvents.ToArray()
}

function Get-PSConnMonAzureAccessToken {
    # .SYNOPSIS
    # Requests an Azure Storage access token using managed identity.
    #
    # .DESCRIPTION
    # Calls the Azure Instance Metadata Service to acquire a token that can be
    # used against the Azure Storage REST API.
    #
    # .PARAMETER Resource
    # The resource identifier for the token request.
    #
    # .EXAMPLE
    # Get-PSConnMonAzureAccessToken -Resource 'https://storage.azure.com/'
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonAzureAccessToken.
    #
    # .OUTPUTS
    # System.String. The bearer token.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)][string]$Resource = 'https://storage.azure.com/'
    )

    $tokenResponse = Invoke-RestMethod -Method Get `
        -Uri ('http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource={0}' -f [System.Web.HttpUtility]::UrlEncode($Resource)) `
        -Headers @{ Metadata = 'true' }
    return $tokenResponse.access_token
}

function Get-PSConnMonAzureBlobText {
    # .SYNOPSIS
    # Reads a text blob from Azure Storage.
    #
    # .DESCRIPTION
    # Uses managed identity or a caller-supplied SAS token to retrieve a blob's
    # text content for command-and-control configuration updates.
    #
    # .PARAMETER AzureConfig
    # The Azure publish configuration block.
    #
    # .PARAMETER BlobPath
    # The blob path to read.
    #
    # .EXAMPLE
    # Get-PSConnMonAzureBlobText -AzureConfig $config.publish.azure -BlobPath 'configs/site-a.json'
    #
    # .INPUTS
    # None. You can't pipe objects to Get-PSConnMonAzureBlobText.
    #
    # .OUTPUTS
    # System.String. The blob body.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$AzureConfig,
        [Parameter(Mandatory = $true)][string]$BlobPath
    )

    $baseUri = 'https://{0}.blob.core.windows.net/{1}/{2}' -f $AzureConfig.accountName, $AzureConfig.containerName, $BlobPath
    $headers = @{
        'x-ms-version' = '2023-11-03'
    }

    if ($AzureConfig.authMode -eq 'managedIdentity') {
        $headers.Authorization = 'Bearer ' + (Get-PSConnMonAzureAccessToken)
    }

    $uriValue = if ($AzureConfig.authMode -eq 'sasToken' -and (-not [string]::IsNullOrWhiteSpace($AzureConfig.sasToken))) {
        '{0}?{1}' -f $baseUri, $AzureConfig.sasToken.TrimStart('?')
    } else {
        $baseUri
    }

    return (Invoke-RestMethod -Method Get -Uri $uriValue -Headers $headers)
}

function Publish-PSConnMonPendingBatch {
    # .SYNOPSIS
    # Publishes pending JSONL batches to Azure Storage.
    #
    # .DESCRIPTION
    # Uploads each pending batch file to Azure Blob Storage and moves successful
    # uploads to the uploaded folder so that retries remain deterministic.
    #
    # .PARAMETER Config
    # The normalized PSConnMon configuration.
    #
    # .EXAMPLE
    # Publish-PSConnMonPendingBatch -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Publish-PSConnMonPendingBatch.
    #
    # .OUTPUTS
    # System.Int32. The number of uploaded batches.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    if (-not $Config.publish.azure.enabled) {
        return 0
    }

    $spoolRoot = Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'pending'
    $uploadedRoot = Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'uploaded'
    [void](New-Item -Path $uploadedRoot -ItemType Directory -Force)

    $uploadedCount = 0
    $headers = @{
        'x-ms-blob-type' = 'BlockBlob'
        'x-ms-version' = '2023-11-03'
    }

    if ($Config.publish.azure.authMode -eq 'managedIdentity') {
        $headers.Authorization = 'Bearer ' + (Get-PSConnMonAzureAccessToken)
    }

    foreach ($fileValue in (Get-ChildItem -Path $spoolRoot -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        $blobPath = '{0}/{1}/{2}' -f $Config.publish.azure.blobPrefix.Trim('/'), $Config.agent.siteId, $fileValue.Name
        $baseUri = 'https://{0}.blob.core.windows.net/{1}/{2}' -f $Config.publish.azure.accountName, $Config.publish.azure.containerName, $blobPath
        $uriValue = if ($Config.publish.azure.authMode -eq 'sasToken' -and (-not [string]::IsNullOrWhiteSpace($Config.publish.azure.sasToken))) {
            '{0}?{1}' -f $baseUri, $Config.publish.azure.sasToken.TrimStart('?')
        } else {
            $baseUri
        }

        Invoke-RestMethod -Method Put -Uri $uriValue -Headers $headers -InFile $fileValue.FullName -ContentType 'application/x-ndjson'
        Move-Item -Path $fileValue.FullName -Destination (Join-Path -Path $uploadedRoot -ChildPath $fileValue.Name) -Force
        $uploadedCount++
    }

    return $uploadedCount
}

function Update-PSConnMonConfigFromAzure {
    # .SYNOPSIS
    # Polls Azure Storage for a newer configuration.
    #
    # .DESCRIPTION
    # Retrieves the configured blob path, validates the downloaded content, and
    # writes the last known good version to disk for rollback and audit.
    #
    # .PARAMETER Config
    # The current normalized configuration.
    #
    # .EXAMPLE
    # Update-PSConnMonConfigFromAzure -Config $config
    #
    # .INPUTS
    # None. You can't pipe objects to Update-PSConnMonConfigFromAzure.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. The updated configuration or the original one.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    if (-not $Config.publish.azure.enabled) {
        return $Config
    }

    if ([string]::IsNullOrWhiteSpace($Config.publish.azure.configBlobPath)) {
        return $Config
    }

    try {
        $blobText = Get-PSConnMonAzureBlobText -AzureConfig $Config.publish.azure -BlobPath $Config.publish.azure.configBlobPath
        $blobExtension = ([System.IO.Path]::GetExtension($Config.publish.azure.configBlobPath)).ToLowerInvariant()
        if ($blobExtension -in @('.yaml', '.yml')) {
            if (-not (Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
                throw 'YAML config polling requires ConvertFrom-Yaml support on the current runtime.'
            }

            $candidate = ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Yaml -Yaml $blobText)
        } else {
            $candidate = ConvertTo-PSConnMonHashtable -InputObject (ConvertFrom-Json -InputObject $blobText)
        }
        $candidate._runtime = @{
            configDirectory = $Config._runtime.configDirectory
        }
        $validatedConfig = Test-PSConnMonConfig -Config $candidate -PassThru

        $lastKnownGoodPath = Join-Path -Path $Config.agent.spoolDirectory -ChildPath 'last-known-good.json'
        [void](New-Item -Path (Split-Path -Path $lastKnownGoodPath -Parent) -ItemType Directory -Force)
        if ($PSCmdlet.ShouldProcess($lastKnownGoodPath, 'Write last-known-good configuration')) {
            $validatedConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $lastKnownGoodPath -Encoding UTF8
        }
        return $validatedConfig
    } catch {
        Write-Warning ('Azure config poll failed. Continuing with current configuration. Details: {0}' -f $_.Exception.Message)
        return $Config
    }
}

function Invoke-PSConnMon {
    # .SYNOPSIS
    # Starts the PSConnMon monitoring agent.
    #
    # .DESCRIPTION
    # Validates configuration, runs monitoring cycles on a fixed cadence, polls
    # Azure Storage for config changes, and publishes completed batches when cloud
    # publishing is enabled.
    #
    # .PARAMETER ConfigPath
    # The YAML or JSON configuration path.
    #
    # .PARAMETER Config
    # An in-memory PSConnMon configuration hashtable.
    #
    # .PARAMETER RunOnce
    # Executes only one monitoring cycle.
    #
    # .PARAMETER MaxRuntimeMinutes
    # Optional runtime override in minutes.
    #
    # .EXAMPLE
    # Invoke-PSConnMon -ConfigPath '.\config\psconnmon.yaml'
    #
    # .INPUTS
    # None. You can't pipe objects to Invoke-PSConnMon.
    #
    # .OUTPUTS
    # System.Int32. Exit code semantics: 0 for clean completion, 1 for fatal
    # execution errors.
    #
    # .NOTES
    # Version: 0.2.20260409.0

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ConfigPath')][string]$ConfigPath,
        [Parameter(Mandatory = $true, ParameterSetName = 'ConfigObject')][hashtable]$Config,
        [Parameter(Mandatory = $false)][switch]$RunOnce,
        [Parameter(Mandatory = $false)][int]$MaxRuntimeMinutes = 0
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ConfigObject') {
            $currentConfig = Test-PSConnMonConfig -Config $Config -PassThru
        } else {
            $currentConfig = Test-PSConnMonConfig -Path $ConfigPath -PassThru
        }

        if ($MaxRuntimeMinutes -gt 0) {
            $currentConfig.agent.maxRuntimeMinutes = $MaxRuntimeMinutes
        }

        $startTime = (Get-Date).ToUniversalTime()
        $lastConfigPoll = [datetime]::MinValue

        while ($true) {
            $pendingRoot = Join-Path -Path $currentConfig.agent.spoolDirectory -ChildPath 'pending'
            [void](New-Item -Path $pendingRoot -ItemType Directory -Force)
            $batchPath = Join-Path -Path $pendingRoot -ChildPath ('cycle-{0}.jsonl' -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')))

            [void](Start-PSConnMonCycle -Config $currentConfig -BatchPath $batchPath)
            [void](Publish-PSConnMonPendingBatch -Config $currentConfig)

            if ($RunOnce) {
                break
            }

            if ($currentConfig.agent.maxRuntimeMinutes -gt 0) {
                if ((((Get-Date).ToUniversalTime()) - $startTime).TotalMinutes -ge [double]$currentConfig.agent.maxRuntimeMinutes) {
                    break
                }
            }

            if ((((Get-Date).ToUniversalTime()) - $lastConfigPoll).TotalSeconds -ge [double]$currentConfig.agent.configPollIntervalSeconds) {
                $currentConfig = Update-PSConnMonConfigFromAzure -Config $currentConfig
                $lastConfigPoll = (Get-Date).ToUniversalTime()
            }

            Start-Sleep -Seconds ([int]$currentConfig.agent.cycleIntervalSeconds)
        }

        return 0
    } catch {
        Write-Error ('PSConnMon failed: {0}' -f $_.Exception.Message)
        return 1
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-PSConnMonConfig',
    'Export-PSConnMonSampleConfig',
    'Invoke-PSConnMon',
    'Start-PSConnMonCycle',
    'Test-PSConnMonConfig',
    'Test-PSConnMonDnsQuery',
    'Test-PSConnMonDomainAuth',
    'Test-PSConnMonInternetQuality',
    'Test-PSConnMonPing',
    'Test-PSConnMonShare',
    'Test-PSConnMonTraceroute',
    'Write-PSConnMonEvent'
)
