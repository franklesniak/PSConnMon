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
    # with a deterministic path fingerprint.
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
                $hopName = $Matches[1]
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
            internetQualitySampleCount = 4
        }
        auth = @{
            linuxSmbMode = 'currentContext'
            secretReference = ''
        }
        targets = @()
        extensions = @()
    }

    $normalizedConfig = Merge-PSConnMonHashtable -DefaultValue $defaultConfig -OverrideValue $Config
    $normalizedConfig.targets = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.targets
    $normalizedConfig.extensions = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.extensions
    $normalizedConfig.tests.enabled = ConvertTo-PSConnMonArray -InputObject $normalizedConfig.tests.enabled

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
            internetQualitySampleCount = 4
        }
        auth = @{
            linuxSmbMode = 'currentContext'
            secretReference = ''
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
            if (($script:PSConnMonIsWindows) -and (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) -and ($dnsServer -ne 'system-default')) {
                $resolvedAddress = (Resolve-DnsName -Name $Target.fqdn -Server $dnsServer -Type A -DnsOnly | Select-Object -First 1 -ExpandProperty IPAddress)
            } elseif ((Get-Command -Name dig -ErrorAction SilentlyContinue) -and ($dnsServer -ne 'system-default')) {
                $resolvedAddress = (dig +short "@$dnsServer" $Target.fqdn | Select-Object -First 1).Trim()
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
                        -Result 'FAILURE' -DnsServer $dnsServer -ErrorCode 'NoAddress' -Details 'DNS query returned no address.')
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
        try {
            if ($script:PSConnMonIsWindows) {
                $jobValue = Start-ThreadJob -ScriptBlock {
                    Get-ChildItem -Path $args[0] -Force -ErrorAction Stop | Select-Object -First 1
                } -ArgumentList $shareValue.path
            } else {
                if (-not (Get-Command -Name smbclient -ErrorAction SilentlyContinue)) {
                    $eventValues.Add(
                        (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                            -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                            -Result 'SKIPPED' -ErrorCode 'SmbClientMissing' -Details 'smbclient is required for Linux share probes.' `
                            -Metadata @{ shareId = $shareValue.id; sharePath = $shareValue.path })
                    ) | Out-Null
                    continue
                }

                $linuxSharePath = Convert-PSConnMonSharePathToLinux -SharePath $shareValue.path
                $jobValue = Start-ThreadJob -ScriptBlock {
                    if ($args[1] -ne 'currentContext') {
                        throw 'Only currentContext Linux SMB mode is currently supported.'
                    }

                    smbclient $args[0] -g -k -c 'ls' 2>&1
                } -ArgumentList $linuxSharePath, $Config.auth.linuxSmbMode
            }

            if (-not (Wait-Job -Job $jobValue -Timeout ([int]$Config.tests.shareAccessTimeoutSeconds))) {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                        -Result 'TIMEOUT' -ErrorCode 'ShareTimeout' `
                        -Details ('Share probe exceeded {0} seconds.' -f $Config.tests.shareAccessTimeoutSeconds) `
                        -Metadata @{ shareId = $shareValue.id; sharePath = $shareValue.path })
                ) | Out-Null
                continue
            }

            $jobOutput = Receive-Job -Job $jobValue -Wait -ErrorAction Stop
            if ($null -eq $jobOutput) {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                        -Result 'EMPTY' -Details 'Share probe succeeded but returned no visible items.' `
                        -Metadata @{ shareId = $shareValue.id; sharePath = $shareValue.path })
                ) | Out-Null
            } else {
                $eventValues.Add(
                    (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                        -Result 'SUCCESS' -Details 'Share access confirmed.' `
                        -Metadata @{ shareId = $shareValue.id; sharePath = $shareValue.path })
                ) | Out-Null
            }
        } catch {
            $eventValues.Add(
                (Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                    -Result 'FATAL' -ErrorCode 'ShareProbeFailure' -Details $_.Exception.Message `
                    -Metadata @{ shareId = $shareValue.id; sharePath = $shareValue.path })
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
            } -ArgumentList $traceTarget, ([int]$Config.tests.tracerouteTimeoutSeconds)
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
            } -ArgumentList $traceTarget, ([int]$Config.tests.tracerouteTimeoutSeconds)
        }

        if (-not (Wait-Job -Job $jobValue -Timeout ([int]$Config.tests.tracerouteTimeoutSeconds))) {
            return @(
                Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                    -Fqdn $Target.fqdn -TargetAddress $traceTarget -TestType 'traceroute' `
                    -ProbeName 'Traceroute.Path' -Result 'TIMEOUT' -ErrorCode 'TracerouteTimeout' `
                    -Details ('Traceroute exceeded {0} seconds.' -f $Config.tests.tracerouteTimeoutSeconds)
            )
        }

        $outputLines = @(Receive-Job -Job $jobValue -Wait -ErrorAction Stop | ForEach-Object { $_.ToString() })
        $parsedEvents = @(Get-PSConnMonTracerouteHopEvent -OutputLines $outputLines -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -Target $Target -TargetAddress $traceTarget)
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
    'Test-PSConnMonInternetQuality',
    'Test-PSConnMonPing',
    'Test-PSConnMonShare',
    'Test-PSConnMonTraceroute',
    'Write-PSConnMonEvent'
)
