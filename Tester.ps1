
function Invoke-Test {
    [OutputType('Tester.TestResult')]
    [CmdletBinding(ConfirmImpact='Low', SupportsShouldProcess, DefaultParameterSetName='ByPath')]
    Param(
        [Parameter(ParameterSetName='ByPath')]
        [string] $Path = '.',

        [Parameter(ParameterSetName='ByPath')]
        [string] $Filter = '*.Tester.ps1',

        [Parameter(ParameterSetName='ByPath')]
        [string] $Include,

        [Parameter(ParameterSetName='ByPath')]
        [string] $Exclude,

        [Parameter(ParameterSetName='ByPath')]
        [switch] $Recurse,

        [Parameter(ParameterSetName='ByPath')]
        [int] $Depth,

        [Parameter(ParameterSetName='ByScope', Mandatory, ValueFromPipeline, Position=0)]
        [PSTypeName('Tester.Scope')] $Scope,

        [Parameter(ParameterSetName='ByTest', Mandatory, ValueFromPipeline, Position=0)]
        [PSTypeName('Tester.Test')] $Test,

        [Parameter(ParameterSetName='ByScope')]
        [Parameter(ParameterSetName='ByTest')]
        [switch] $Skip,

        [Parameter()]
        [string[]] $ExcludeTag
    )

    Begin {
        $stopWatch = New-Object -TypeName 'System.Diagnostics.Stopwatch'
    }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName)) -Skip $Skip"

        switch($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess("Script '$Path'")) {

                    $files = Get-ChildItem -File -Path:$Path -Filter:$Filter -Include:$Include -Exclude:$Exclude -Recurse:$Recurse -Depth:$Depth

                    Foreach($file in $files) {
                        $fileScope = New-Scope -Path $file.FullName
                        $fileScope | Invoke-Test -ExcludeTag:$ExcludeTag # <--
                    }
                 }
            }

            'ByScope' {

                $skipScope = $Skip -or $Scope.Skip
                $skipScope = $skipScope -or (($Null -NE $ExcludeTag) -and ($Scope.Tag -in $ExcludeTag))

                if ($PSCmdlet.ShouldProcess("Scope '$($Scope.Name)'")) {

                    Try {
                        if (-not $skipScope) {
                            if ($SCope.Before) {
                                # $Scope.Before
                            }
                        }

                        # Recurse Tests
                        $Scope.Tests  | Invoke-Test -Skip:$skipScope -ExcludeTag:$ExcludeTag  # <--

                        # Recurse Scopes
                        $Scope.Scopes | Invoke-Test -Skip:$skipScope -ExcludeTag:$ExcludeTag  # <--

                    }
                    Finally {
                        if (-not $skipScope) {
                            if ($Scope.After) {
                                # $Scope.After
                            }
                        }
                    }
                }
            }

            'ByTest' {

                if ($PSCmdlet.ShouldProcess("Test '$($Test.Name)'")) {

                    $skipTest = $Skip -or $Test.Skip
                    $skipTest = $skipTest -or (($Null -NE $ExcludeTag) -and ($Scope.Tag -in $ExcludeTag))

                    if ($skipTest) {
                        New-TestResult -Test $Test -Result 'Skipped' # <--
                    }
                    else {
                        [string[]] $output = @()

                        $stopWatch.Start()
                        Try {
                            Try {
                                $output = @( Invoke-Command -ScriptBlock $Test.Test ) 2>&1
                            }
                            Finally {
                                $stopWatch.Stop()
                            }

                            New-TestResult -Test $Test -Result 'Passed' -Duration $stopWatch.Elapsed -Output $output # <--
                        }
                        Catch {
                            New-TestResult -Test $Test -Result 'Failed' -Duration $stopWatch.Elapsed -Output $output -Error $_.Exception # <--
                        }
                    }
                }
            }
        }
    }
}

function New-Scope {
    [OutputType('Tester.Scope')]
    [CmdletBinding(ConfirmImpact='Low', SupportsShouldProcess, DefaultParameterSetName='ByCode')]
    Param(
        [Parameter(Mandatory, ParameterSetName='ByPath')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName='ByCode', Position=0)]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName='ByCode', Position=1)]
        [ScriptBlock] $Code,

        [Parameter()]
        [switch] $Skip,

        [Parameter()]
        [string[]] $Tag
    )

    Begin {
        if ($null -EQ $script:currentScopeName) {
            $script:currentScopeName = '(script)'
        }
        $savedScope = $script:currentScopeName
    }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess($Path)) {
                    $Path = Resolve-Path $Path
                    $script:currentScopeName = $Path

                    New-Scope -Name $Path -Skip:$Skip -Tag:$Tag -Code (Get-command $Path | Select-Object -ExpandProperty ScriptBlock ) # <--
                 }
            }

            default {

                if ($PSCmdlet.ShouldProcess($Name)) {

                    if ($script:currentScopeName -NE $Name) {
                        $script:currentScopeName = Join-Path -Path $script:currentScopeName -ChildPath $Name
                    }

                    $output = @( Invoke-Command -ScriptBlock $Code ) 2>&1

                    # $before = $output | Where { 'Tester.Before' -IN $_.PsObject.TypeNames } | Select -First 1
                    # $after  = $output | Where { 'Tester.After'  -IN $_.PsObject.TypeNames } | Select -First 1
                    $scopes = $output | Where { 'Tester.Scope'  -IN $_.PsObject.TypeNames }
                    $tests  = $output | Where { 'Tester.Test'   -IN $_.PsObject.TypeNames }

                    [PSCustomObject] $result = [PSCustomObject] @{
                        PSTypeName  = 'Tester.Scope'
                        Name        = $Name
                        Scope       = $script:currentScopeName
                        Skip        = $Skip
                        # Code        = $Code
                        Tag         = $Tag
                        # Before      = $before
                        # After       = $after
                        Scopes      = $scopes
                        Tests       = $tests
                    }

                    $result # <--
                }
            }
        }
    }

    End {
        $script:currentScopeName = $savedScope
    }
}

function New-Test {
    [OutputType('Tester.Test')]
    [CmdletBinding(ConfirmImpact='Low', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position=0)]
        [string] $Name,

        [Parameter(Mandatory, Position=1)]
        [ScriptBlock] $Code,

        [Parameter()]
        [switch] $Skip,

        [Parameter()]
        [string[]] $Tag
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) $Name"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName  = 'Tester.Test'
                Name        = $Name
                Scope       = $script:currentScopeName
                Skip        = $Skip
                Test        = $Code
                Tag         = $Tag
            }

            $result # <--
        }
    }
}

function New-TestResult {
    [OutputType('Tester.TestResult')]
    [CmdletBinding(ConfirmImpact='None', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory)]
        [PSTypeName('Tester.Test')] $Test,

        [Parameter(Mandatory)]
        [string] $Result,

        [Parameter()]
        [System.TimeSpan] $Duration,

        [Parameter()]
        [string[]] $Output,

        [Parameter()]
        [System.Exception] $Error
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) $($Test.Name)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName  = 'Tester.TestResult'
                Name        = $Test.Name
                Scope       = $Test.Scope
                Result      = $Result
                Duration    = $Duration
                Output      = $Output | Out-String
                Error       = $Error  | Out-String
            }

            $result # <--
        }
    }
}

New-Alias -Name 'Scope'     -Value 'New-Scope'          -Force
New-Alias -Name 'Test'      -Value 'New-Test'           -Force

Update-FormatData -AppendPath .\Tester.ps1xml
