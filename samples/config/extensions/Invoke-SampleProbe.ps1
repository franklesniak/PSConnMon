function Invoke-SampleProbe {
    param(
        [hashtable]$Target,
        [hashtable]$Config,
        [hashtable]$Extension
    )

    return @{
        result = 'INFO'
        details = ('Sample extension executed for target {0}.' -f $Target.id)
        metadata = @{
            emittedBy = $Extension.id
            siteId = $Config.agent.siteId
        }
    }
}
