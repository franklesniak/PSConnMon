BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../PSConnMon/PSConnMon.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Test-PSConnMonConfig' {
    It 'Returns normalized configuration for a valid config' {
        $config = @{
            schemaVersion = '1.0'
            agent = @{
                agentId = 'agent-01'
                siteId = 'site-01'
                spoolDirectory = 'data/test-spool'
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
                enabled = @('ping')
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
                    id = 'loopback'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @('test')
                    tags = @('local')
                    dnsServers = @()
                    shares = @()
                    tests = @('ping')
                    externalTraceTarget = '127.0.0.1'
                }
            )
            extensions = @()
        }

        $normalized = Test-PSConnMonConfig -Config $config -PassThru
        $normalized.agent.agentId | Should -Be 'agent-01'
        $normalized.targets.Count | Should -Be 1
        $normalized.tests.enabled | Should -Contain 'ping'
    }

    It 'Throws on duplicate target ids' {
        $config = @{
            schemaVersion = '1.0'
            agent = @{
                agentId = 'agent-01'
                siteId = 'site-01'
                spoolDirectory = 'data/test-spool'
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
                enabled = @('ping')
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
                    id = 'dup'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @()
                    tags = @()
                    dnsServers = @()
                    shares = @()
                    tests = @('ping')
                    externalTraceTarget = '127.0.0.1'
                },
                @{
                    id = 'dup'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @()
                    tags = @()
                    dnsServers = @()
                    shares = @()
                    tests = @('ping')
                    externalTraceTarget = '127.0.0.1'
                }
            )
            extensions = @()
        }

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
    }

    It 'Loads YAML configuration files when YAML support is available' -Skip:(-not ((Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue) -or (Get-Module -ListAvailable -Name powershell-yaml))) {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        $configPath = Join-Path -Path $tempRoot -ChildPath 'config.yaml'
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)

        @'
schemaVersion: '1.0'
agent:
  agentId: yaml-agent
  siteId: yaml-site
  spoolDirectory: data/test-spool
publish:
  mode: local
  format: jsonl
  csvMirror: false
  azure:
    enabled: false
    accountName: ''
    containerName: ''
    blobPrefix: events
    configBlobPath: ''
    authMode: managedIdentity
    sasToken: ''
tests:
  enabled:
    - ping
  pingTimeoutMs: 3000
  pingPacketSize: 56
  shareAccessTimeoutSeconds: 15
  tracerouteTimeoutSeconds: 20
  internetQualitySampleCount: 4
auth:
  linuxSmbMode: currentContext
  secretReference: ''
targets:
  - id: loopback
    fqdn: localhost
    address: 127.0.0.1
    roles: []
    tags: []
    dnsServers: []
    shares: []
    tests:
      - ping
    externalTraceTarget: 127.0.0.1
extensions: []
'@ | Set-Content -Path $configPath -Encoding UTF8

        $normalized = Test-PSConnMonConfig -Path $configPath -PassThru
        $normalized.agent.agentId | Should -Be 'yaml-agent'
        $normalized.targets[0].id | Should -Be 'loopback'
    }

    It 'Rejects inline extension script content' {
        $config = @{
            schemaVersion = '1.0'
            agent = @{
                agentId = 'agent-01'
                siteId = 'site-01'
                spoolDirectory = 'data/test-spool'
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
                enabled = @('ping')
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
                    id = 'loopback'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @()
                    tags = @()
                    dnsServers = @()
                    shares = @()
                    tests = @('ping')
                    externalTraceTarget = '127.0.0.1'
                }
            )
            extensions = @(
                @{
                    id = 'custom'
                    path = './extensions/custom.ps1'
                    scriptBlock = 'Test-NetConnection localhost'
                }
            )
            _runtime = @{
                configDirectory = (Get-Location).Path
            }
        }

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
    }
}

Describe 'ConvertTo-PSConnMonConfig' {
    It 'Builds a normalized config from target objects and top-level section objects' {
        $config = ConvertTo-PSConnMonConfig -Targets @(
            [pscustomobject]@{
                id = 'loopback'
                fqdn = 'localhost'
                address = '127.0.0.1'
                tests = @('ping')
                tags = @('local')
            }
        ) -Agent @{
            agentId = 'object-agent'
            siteId = 'object-site'
            spoolDirectory = 'data/object-spool'
        } -Tests @{
            enabled = @('ping')
        }

        $config.agent.agentId | Should -Be 'object-agent'
        $config.targets.Count | Should -Be 1
        $config.targets[0].id | Should -Be 'loopback'
        $config.targets[0].tests | Should -Contain 'ping'
    }
}

Describe 'Write-PSConnMonEvent' {
    It 'Writes JSONL batches' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        $batchPath = Join-Path -Path $tempRoot -ChildPath 'pending/cycle.jsonl'
        $connMonEvent = [pscustomobject]@{
            timestampUtc = '2026-04-09T00:00:00Z'
            agentId = 'agent-01'
            siteId = 'site-01'
            targetId = 'target-01'
            fqdn = 'localhost'
            targetAddress = '127.0.0.1'
            testType = 'ping'
            probeName = 'Ping.Primary'
            result = 'SUCCESS'
            latencyMs = 1.2
            loss = 0
            errorCode = $null
            details = 'ok'
            dnsServer = $null
            hopIndex = $null
            hopAddress = $null
            hopName = $null
            hopLatencyMs = $null
            pathHash = $null
            metadata = @{}
        }

        $writtenPath = Write-PSConnMonEvent -Event $connMonEvent -BatchPath $batchPath
        $writtenPath | Should -Be $batchPath
        (Test-Path -Path $batchPath) | Should -BeTrue
        (Get-Content -Path $batchPath -Raw) | Should -Match '"result":"SUCCESS"'
    }
}

Describe 'Start-PSConnMonCycle' {
    It 'Runs a ping-only cycle and emits an event' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        $config = @{
            schemaVersion = '1.0'
            agent = @{
                agentId = 'agent-01'
                siteId = 'site-01'
                spoolDirectory = $tempRoot
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
                enabled = @('ping')
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
                    id = 'loopback'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @('test')
                    tags = @('local')
                    dnsServers = @()
                    shares = @()
                    tests = @('ping')
                    externalTraceTarget = '127.0.0.1'
                }
            )
            extensions = @()
        }

        $batchPath = Join-Path -Path $tempRoot -ChildPath 'pending/cycle.jsonl'
        $events = @(Start-PSConnMonCycle -Config $config -BatchPath $batchPath)

        $events.Count | Should -Be 1
        $events[0].testType | Should -Be 'ping'
        (Test-Path -Path $batchPath) | Should -BeTrue
    }

    It 'Runs a trusted local extension probe and normalizes the event' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        $extensionRoot = Join-Path -Path $tempRoot -ChildPath 'extensions'
        $extensionPath = Join-Path -Path $extensionRoot -ChildPath 'Invoke-CustomProbe.ps1'
        [void](New-Item -Path $extensionRoot -ItemType Directory -Force)

        @'
function Invoke-CustomProbe {
    param(
        [hashtable]$Target,
        [hashtable]$Config,
        [hashtable]$Extension
    )

    return @{
        result = 'SUCCESS'
        details = 'Custom probe succeeded.'
        metadata = @{
            emittedBy = $Extension.id
        }
    }
}
'@ | Set-Content -Path $extensionPath -Encoding UTF8

        $config = @{
            schemaVersion = '1.0'
            agent = @{
                agentId = 'agent-01'
                siteId = 'site-01'
                spoolDirectory = $tempRoot
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
                enabled = @('customProbe')
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
                    id = 'loopback'
                    fqdn = 'localhost'
                    address = '127.0.0.1'
                    roles = @('test')
                    tags = @('local')
                    dnsServers = @()
                    shares = @()
                    tests = @('customProbe')
                    externalTraceTarget = '127.0.0.1'
                }
            )
            extensions = @(
                @{
                    id = 'customProbe'
                    path = './extensions/Invoke-CustomProbe.ps1'
                    entryPoint = 'Invoke-CustomProbe'
                    enabled = $true
                    targets = @('loopback')
                }
            )
            _runtime = @{
                configDirectory = $tempRoot
            }
        }

        $normalizedConfig = Test-PSConnMonConfig -Config $config -PassThru
        $batchPath = Join-Path -Path $tempRoot -ChildPath 'pending/cycle.jsonl'
        $events = @(Start-PSConnMonCycle -Config $normalizedConfig -BatchPath $batchPath)

        $events.Count | Should -Be 1
        $events[0].testType | Should -Be 'customProbe'
        $events[0].result | Should -Be 'SUCCESS'
        $events[0].metadata.extensionId | Should -Be 'customProbe'
    }
}

Describe 'Watch-Network.ps1' {
    It 'Accepts direct target-object input' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../../Watch-Network.ps1'
        $helperPath = Join-Path -Path $tempRoot -ChildPath 'invoke-object-input.ps1'

        $helperScript = @'
$targets = @(
    [pscustomobject]@{
        id = 'loopback'
        fqdn = 'localhost'
        address = '127.0.0.1'
        tests = @('ping')
        tags = @('local')
    }
)
$agent = @{
    agentId = 'object-agent'
    siteId = 'object-site'
    spoolDirectory = '__SPOOL__'
}
$tests = @{
    enabled = @('ping')
}

& '__SCRIPT__' -Targets $targets -Agent $agent -Tests $tests -RunOnce
'@
        $helperScript = $helperScript.Replace('__SPOOL__', (($tempRoot.Replace('\', '/')) + '/spool'))
        $helperScript = $helperScript.Replace('__SCRIPT__', $scriptPath.Replace('\', '/'))
        $helperScript | Set-Content -Path $helperPath -Encoding UTF8

        & pwsh -NoLogo -NoProfile -File $helperPath | Out-Null
        $LASTEXITCODE | Should -Be 0

        $spoolRoot = Join-Path -Path $tempRoot -ChildPath 'spool/pending'
        (Get-ChildItem -Path $spoolRoot -Filter '*.jsonl' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
}
