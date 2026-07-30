# PSScriptAnalyzer settings for this repository.
#
# Run with:  Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
#
# The excluded rules below are not oversights. This is a teaching repository of demo code, and each
# exclusion records a decision that is documented in AGENTS.md.

@{
    IncludeDefaultRules = $true

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # The demo password is public on purpose. Every container is local and throwaway, and showing
        # the credential handling in plain sight is part of the demo.
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingUserNameAndPasswordParams'

        # The lib/ functions are thin ADO.NET wrappers written for demos. -WhatIf and -Confirm would
        # add noise to every call without adding anything to the story being told.
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseShouldProcessForStateChangingVerbs'

        # The demo scripts print to the console on purpose. Inside lib/ the rule is Write-PSFMessage,
        # and that is enforced by review rather than by this analyzer.
        'PSAvoidUsingWriteHost'

        # Demo scripts assign variables that are then only inspected interactively while stepping
        # through the file. "Unused" is exactly the point.
        'PSUseDeclaredVarsMoreThanAssignments'
    )

    # The formatter rules (PSUseConsistentIndentation, PSAlignAssignmentStatement,
    # PSUseConsistentWhitespace, PSPlaceOpenBrace, PSPlaceCloseBrace) are deliberately left off.
    # They were tried and produced 87 additional findings, almost all of them false positives on
    # script blocks passed as arguments, such as the progress handler in Write-SqlTable.ps1. Acting
    # on them would mean reformatting files nobody is otherwise touching, and it would bury the
    # findings that matter. Indentation and line endings are covered by .editorconfig instead.
}
