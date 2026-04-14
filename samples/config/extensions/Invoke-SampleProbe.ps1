function Invoke-SampleProbe {
    # .SYNOPSIS
    # Sample PSConnMon extension probe that emits an INFO result for
    # demonstration purposes.
    #
    # .DESCRIPTION
    # Illustrates the contract that PSConnMon extension scripts must honor: the
    # function receives hashtables describing the current target, the active
    # agent configuration, and the extension invocation, and returns a
    # hashtable describing the probe result. This sample does no real probing
    # work; it is a starting point for authoring custom extensions that comply
    # with the trust boundary documented in ADR-0003.
    #
    # .PARAMETER Target
    # Hashtable describing the target currently under evaluation. The 'id'
    # entry is interpolated into the returned details string.
    #
    # .PARAMETER Config
    # Hashtable containing the active agent configuration. The 'agent.siteId'
    # entry is echoed back in the returned metadata.
    #
    # .PARAMETER Extension
    # Hashtable describing the extension invocation. The 'id' entry is echoed
    # back as the emittedBy value in the returned metadata.
    #
    # .EXAMPLE
    # $result = Invoke-SampleProbe -Target $target -Config $config -Extension $extension
    # # $result.result = 'INFO'
    # # $result.details starts with 'Sample extension executed for target '
    # # $result.metadata contains emittedBy and siteId
    #
    # .INPUTS
    # None. You can't pipe objects to Invoke-SampleProbe.
    #
    # .OUTPUTS
    # System.Collections.Hashtable. Hashtable with keys:
    #   result   [string]    Always 'INFO' for this sample.
    #   details  [string]    Human-readable description including the target id.
    #   metadata [hashtable] Keys: emittedBy (extension id), siteId (agent site id).
    #
    # .NOTES
    # This function/script supports positional parameters:
    #   Position 0: Target
    #   Position 1: Config
    #   Position 2: Extension
    # Version: 0.1.20260414.0

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
