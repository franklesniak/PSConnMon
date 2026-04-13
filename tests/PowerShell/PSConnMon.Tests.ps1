BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../PSConnMon/PSConnMon.psd1'
    Import-Module -Name $modulePath -Force
}

function script:New-PSConnMonTestConfig {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $false)][string[]]$EnabledTests = @('ping')
    )

    return @{
        schemaVersion = '1.0'
        agent = @{
            agentId = 'agent-01'
            siteId = 'site-01'
            spoolDirectory = (Join-Path -Path $TempRoot -ChildPath 'spool')
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
            enabled = $EnabledTests
            pingTimeoutMs = 3000
            pingPacketSize = 56
            shareAccessTimeoutSeconds = 15
            tracerouteTimeoutSeconds = 20
            internetQualitySampleCount = 4
        }
        auth = @{
            linuxSmbMode = 'currentContext'
            secretReference = ''
            linuxProfiles = @()
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
                tests = $EnabledTests
                externalTraceTarget = '127.0.0.1'
                linuxProfileId = ''
            }
        )
        extensions = @()
        _runtime = @{
            configDirectory = $TempRoot
        }
    }
}

function script:New-PSConnMonLinuxSecretArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot
    )

    $secretRoot = Join-Path -Path $TempRoot -ChildPath 'secrets'
    [void](New-Item -Path $secretRoot -ItemType Directory -Force)

    $keytabPath = Join-Path -Path $secretRoot -ChildPath 'svc-psconnmon.keytab'
    'not-a-real-keytab' | Set-Content -Path $keytabPath -Encoding ASCII

    $kerberosSecretPath = Join-Path -Path $secretRoot -ChildPath 'kerberos.json'
    @{
        principal = 'svc-psconnmon@CORP.EXAMPLE.COM'
        keytabPath = './svc-psconnmon.keytab'
    } | ConvertTo-Json | Set-Content -Path $kerberosSecretPath -Encoding UTF8

    $smbSecretPath = Join-Path -Path $secretRoot -ChildPath 'smb.json'
    @{
        username = 'svc-psconnmon'
        password = 'CorrectHorseBatteryStaple!'
        domain = 'CORP'
    } | ConvertTo-Json | Set-Content -Path $smbSecretPath -Encoding UTF8

    return @{
        kerberosSecretReference = './secrets/kerberos.json'
        smbSecretReference = './secrets/smb.json'
        password = 'CorrectHorseBatteryStaple!'
    }
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

Describe 'Linux auth profile validation' {
    It 'Accepts linuxProfiles, linuxProfileId, and domainAuth targets' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $secretArtifacts = New-PSConnMonLinuxSecretArtifacts -TempRoot $tempRoot
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('share', 'domainAuth')

        $config.auth.linuxProfiles = @(
            @{
                id = 'dc-keytab'
                mode = 'kerberosKeytab'
                secretReference = $secretArtifacts.kerberosSecretReference
            },
            @{
                id = 'share-creds'
                mode = 'usernamePassword'
                secretReference = $secretArtifacts.smbSecretReference
            }
        )
        $config.targets[0].linuxProfileId = 'dc-keytab'
        $config.targets[0].shares = @(
            @{
                id = 'plant'
                path = '\\fs01.corp.local\Plant'
                linuxProfileId = 'share-creds'
            }
        )

        $normalized = Test-PSConnMonConfig -Config $config -PassThru

        $normalized.auth.linuxProfiles.Count | Should -Be 2
        $normalized.targets[0].tests | Should -Contain 'domainAuth'
        $normalized.targets[0].linuxProfileId | Should -Be 'dc-keytab'
        $normalized.targets[0].shares[0].linuxProfileId | Should -Be 'share-creds'
    }

    It 'Rejects missing secret references for credential-backed linux profiles' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot
        $config.auth.linuxProfiles = @(
            @{
                id = 'broken'
                mode = 'usernamePassword'
                secretReference = ''
            }
        )

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
    }

    It 'Rejects unsupported linux auth profile modes' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot
        $config.auth.linuxProfiles = @(
            @{
                id = 'broken'
                mode = 'servicePrincipal'
                secretReference = './secrets/ignored.json'
            }
        )

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
    }

    It 'Rejects unknown linuxProfileId references' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot
        $config.targets[0].linuxProfileId = 'missing-profile'

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
    }

    It 'Rejects secret references outside the allowlisted roots' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        $outsideRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-outside-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        [void](New-Item -Path $outsideRoot -ItemType Directory -Force)

        $outsideSecretPath = Join-Path -Path $outsideRoot -ChildPath 'smb.json'
        @{
            username = 'svc'
            password = 'bad'
        } | ConvertTo-Json | Set-Content -Path $outsideSecretPath -Encoding UTF8

        $config = New-PSConnMonTestConfig -TempRoot $tempRoot
        $config.auth.linuxProfiles = @(
            @{
                id = 'outside'
                mode = 'usernamePassword'
                secretReference = $outsideSecretPath
            }
        )

        { Test-PSConnMonConfig -Config $config -PassThru } | Should -Throw
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

Describe 'Linux share and domain auth probes' {
    It 'Preserves currentContext Linux share probing behavior' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('share')
        $config.targets[0].shares = @(
            @{
                id = 'sysvol'
                path = '\\dc01.corp.local\SYSVOL'
            }
        )

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                $script:capturedLinuxShareScript = ''
                $script:capturedLinuxShareArgs = $null

                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}
                Mock -ModuleName PSConnMon Get-Command {
                    [pscustomobject]@{ Name = $Name }
                } -ParameterFilter { $Name -eq 'smbclient' }
                Mock -ModuleName PSConnMon Start-ThreadJob {
                    $script:capturedLinuxShareScript = $ScriptBlock.ToString()
                    $script:capturedLinuxShareArgs = $ArgumentList
                    return (Start-Job -ScriptBlock { return $null })
                }
                Mock -ModuleName PSConnMon Wait-Job { $true }
                Mock -ModuleName PSConnMon Receive-Job {
                    @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Share access confirmed.'
                    }
                }
                Mock -ModuleName PSConnMon Stop-Job {}
                Mock -ModuleName PSConnMon Remove-Job {}

                $events = Test-PSConnMonShare -Target $configValue.targets[0] -Config $configValue

                $events.Count | Should -Be 1
                $events[0].result | Should -Be 'SUCCESS'
                $events[0].metadata.shareId | Should -Be 'sysvol'
                ($events[0].metadata.ContainsKey('linuxProfileId')) | Should -BeFalse
                $script:capturedLinuxShareArgs[1].mode | Should -Be 'currentContext'
                $script:capturedLinuxShareScript | Should -Match 'smbclient \$sharePath -g -k -c'
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Builds keytab-backed Linux share probes with kinit before smbclient' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $secretArtifacts = New-PSConnMonLinuxSecretArtifacts -TempRoot $tempRoot
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('share')
        $config.auth.linuxProfiles = @(
            @{
                id = 'dc-keytab'
                mode = 'kerberosKeytab'
                secretReference = $secretArtifacts.kerberosSecretReference
            }
        )
        $config.targets[0].linuxProfileId = 'dc-keytab'
        $config.targets[0].shares = @(
            @{
                id = 'sysvol'
                path = '\\dc01.corp.local\SYSVOL'
            }
        )
        $config = Test-PSConnMonConfig -Config $config -PassThru

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                $script:capturedKerberosShareScript = ''
                $script:capturedKerberosShareArgs = $null

                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}
                Mock -ModuleName PSConnMon Get-Command {
                    [pscustomobject]@{ Name = $Name }
                } -ParameterFilter { $Name -in @('smbclient', 'kinit') }
                Mock -ModuleName PSConnMon Start-ThreadJob {
                    $script:capturedKerberosShareScript = $ScriptBlock.ToString()
                    $script:capturedKerberosShareArgs = $ArgumentList
                    return (Start-Job -ScriptBlock { return $null })
                }
                Mock -ModuleName PSConnMon Wait-Job { $true }
                Mock -ModuleName PSConnMon Receive-Job {
                    @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Share access confirmed.'
                    }
                }
                Mock -ModuleName PSConnMon Stop-Job {}
                Mock -ModuleName PSConnMon Remove-Job {}

                $events = Test-PSConnMonShare -Target $configValue.targets[0] -Config $configValue

                $events[0].result | Should -Be 'SUCCESS'
                $events[0].metadata.linuxProfileId | Should -Be 'dc-keytab'
                $script:capturedKerberosShareArgs[1].mode | Should -Be 'kerberosKeytab'
                $script:capturedKerberosShareArgs[1].principal | Should -Be 'svc-psconnmon@CORP.EXAMPLE.COM'
                $script:capturedKerberosShareScript | Should -Match '(?s)elseif \(\$profileContext\.mode -eq ''kerberosKeytab''\).*?kinit -k -t.*?smbclient \$sharePath -g -k -c ''ls'''
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Builds usernamePassword Linux share probes without inline password arguments' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $secretArtifacts = New-PSConnMonLinuxSecretArtifacts -TempRoot $tempRoot
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('share')
        $config.auth.linuxProfiles = @(
            @{
                id = 'share-creds'
                mode = 'usernamePassword'
                secretReference = $secretArtifacts.smbSecretReference
            }
        )
        $config.targets[0].shares = @(
            @{
                id = 'public'
                path = '\\fileshare01\Public'
                linuxProfileId = 'share-creds'
            }
        )
        $config = Test-PSConnMonConfig -Config $config -PassThru

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                $script:capturedPasswordShareScript = ''

                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}
                Mock -ModuleName PSConnMon Get-Command {
                    [pscustomobject]@{ Name = $Name }
                } -ParameterFilter { $Name -in @('smbclient', 'chmod') }
                Mock -ModuleName PSConnMon Start-ThreadJob {
                    $script:capturedPasswordShareScript = $ScriptBlock.ToString()
                    return (Start-Job -ScriptBlock { return $null })
                }
                Mock -ModuleName PSConnMon Wait-Job { $true }
                Mock -ModuleName PSConnMon Receive-Job {
                    @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Share access confirmed.'
                    }
                }
                Mock -ModuleName PSConnMon Stop-Job {}
                Mock -ModuleName PSConnMon Remove-Job {}

                $events = Test-PSConnMonShare -Target $configValue.targets[0] -Config $configValue

                $events[0].result | Should -Be 'SUCCESS'
                $events[0].metadata.linuxProfileId | Should -Be 'share-creds'
                $events[0].details | Should -Not -Match 'CorrectHorseBatteryStaple!'
                $script:capturedPasswordShareScript | Should -Match '-A \$tempAuthPath'
                $script:capturedPasswordShareScript | Should -Not -Match '--password'
                $script:capturedPasswordShareScript | Should -Not -Match '\s-U\s'
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Returns successful domainAuth results for currentContext Linux probes' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('domainAuth')

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                $script:capturedDomainAuthScript = ''

                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}
                Mock -ModuleName PSConnMon Get-Command {
                    [pscustomobject]@{ Name = $Name }
                } -ParameterFilter { $Name -eq 'klist' }
                Mock -ModuleName PSConnMon Start-ThreadJob {
                    $script:capturedDomainAuthScript = $ScriptBlock.ToString()
                    return (Start-Job -ScriptBlock { return $null })
                }
                Mock -ModuleName PSConnMon Wait-Job { $true }
                Mock -ModuleName PSConnMon Receive-Job {
                    @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Kerberos ticket cache is available in the current Linux context.'
                    }
                }
                Mock -ModuleName PSConnMon Stop-Job {}
                Mock -ModuleName PSConnMon Remove-Job {}

                $events = Test-PSConnMonDomainAuth -Target $configValue.targets[0] -Config $configValue

                $events.Count | Should -Be 1
                $events[0].result | Should -Be 'SUCCESS'
                $script:capturedDomainAuthScript | Should -Match 'klist -s'
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Returns successful domainAuth results for keytab-backed Linux probes' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $secretArtifacts = New-PSConnMonLinuxSecretArtifacts -TempRoot $tempRoot
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('domainAuth')
        $config.auth.linuxProfiles = @(
            @{
                id = 'dc-keytab'
                mode = 'kerberosKeytab'
                secretReference = $secretArtifacts.kerberosSecretReference
            }
        )
        $config.targets[0].linuxProfileId = 'dc-keytab'
        $config = Test-PSConnMonConfig -Config $config -PassThru

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                $script:capturedKeytabDomainAuthScript = ''

                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}
                Mock -ModuleName PSConnMon Get-Command {
                    [pscustomobject]@{ Name = $Name }
                } -ParameterFilter { $Name -in @('kinit', 'klist') }
                Mock -ModuleName PSConnMon Start-ThreadJob {
                    $script:capturedKeytabDomainAuthScript = $ScriptBlock.ToString()
                    return (Start-Job -ScriptBlock { return $null })
                }
                Mock -ModuleName PSConnMon Wait-Job { $true }
                Mock -ModuleName PSConnMon Receive-Job {
                    @{
                        result = 'SUCCESS'
                        errorCode = $null
                        details = 'Kerberos ticket acquisition and validation succeeded.'
                    }
                }
                Mock -ModuleName PSConnMon Stop-Job {}
                Mock -ModuleName PSConnMon Remove-Job {}

                $events = Test-PSConnMonDomainAuth -Target $configValue.targets[0] -Config $configValue

                $events[0].result | Should -Be 'SUCCESS'
                $events[0].metadata.linuxProfileId | Should -Be 'dc-keytab'
                $script:capturedKeytabDomainAuthScript | Should -Match '(?s)\$env:KRB5CCNAME = \$profileContext\.ccachePath.*?kinit -k -t.*?klist -s'
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Skips domainAuth for usernamePassword Linux profiles' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $secretArtifacts = New-PSConnMonLinuxSecretArtifacts -TempRoot $tempRoot
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('domainAuth')
        $config.auth.linuxProfiles = @(
            @{
                id = 'share-creds'
                mode = 'usernamePassword'
                secretReference = $secretArtifacts.smbSecretReference
            }
        )
        $config.targets[0].linuxProfileId = 'share-creds'
        $config = Test-PSConnMonConfig -Config $config -PassThru

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config } {
            param($ConfigValue)
            $originalIsWindows = $script:PSConnMonIsWindows
            try {
                $script:PSConnMonIsWindows = $false
                Mock -ModuleName PSConnMon Assert-PSConnMonDependency {}

                $events = Test-PSConnMonDomainAuth -Target $configValue.targets[0] -Config $configValue

                $events.Count | Should -Be 1
                $events[0].result | Should -Be 'SKIPPED'
                $events[0].errorCode | Should -Be 'DomainAuthUnsupportedProfileMode'
            } finally {
                $script:PSConnMonIsWindows = $originalIsWindows
            }
        }
    }

    It 'Continues the cycle when a share probe fails alongside another probe' {
        $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('psconnmon-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)
        $config = New-PSConnMonTestConfig -TempRoot $tempRoot -EnabledTests @('share', 'ping')
        $config.targets[0].shares = @(
            @{
                id = 'sysvol'
                path = '\\dc01.corp.local\SYSVOL'
            }
        )

        InModuleScope PSConnMon -Parameters @{ ConfigValue = $config; TempRootValue = $tempRoot } {
            param($ConfigValue, $TempRootValue)
            Mock -ModuleName PSConnMon Test-PSConnMonShare {
                @(
                    Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'share' -ProbeName 'Share.Access' `
                        -Result 'FAILURE' -ErrorCode 'LinuxShareAccessFailed' -Details 'share failed'
                )
            }
            Mock -ModuleName PSConnMon Test-PSConnMonPing {
                @(
                    Get-PSConnMonEventRecord -AgentId $Config.agent.agentId -SiteId $Config.agent.siteId -TargetId $Target.id `
                        -Fqdn $Target.fqdn -TargetAddress $Target.address -TestType 'ping' -ProbeName 'Ping.Primary' `
                        -Result 'SUCCESS' -Details 'ping ok'
                )
            }

            $batchPath = Join-Path -Path $tempRootValue -ChildPath 'pending/cycle.jsonl'
            $events = @(Start-PSConnMonCycle -Config $configValue -BatchPath $batchPath)

            $events.Count | Should -Be 2
            ($events | Where-Object { $_.testType -eq 'share' }).result | Should -Be 'FAILURE'
            ($events | Where-Object { $_.testType -eq 'ping' }).result | Should -Be 'SUCCESS'
        }
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
