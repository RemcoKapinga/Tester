
function Invoke-Test {
    [OutputType('Tester.TestResult')]
    [CmdletBinding(ConfirmImpact='Low', SupportsShouldProcess, DefaultParameterSetName='ByPath')]
    Param(
        [Parameter(ParameterSetName='ByPath')]
        [string] $Path = '.',

        [Parameter(ParameterSetName='ByPath')]
        [string] $Filter = '*.Test.ps1',

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
        [string[]] $SkipTag
    )

    Begin {
        $stopWatch = New-Object -TypeName 'System.Diagnostics.Stopwatch'
    }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess("Script '$Path'")) {

                    $files = Get-ChildItem -File -Path:$Path -Filter:$Filter -Include:$Include -Exclude:$Exclude -Recurse:$Recurse -Depth:$Depth

                    Foreach($file in $files) {
                        $fileScope = New-Scope -Path $file.FullName
                        $fileScope | Invoke-Test -SkipTag:$SkipTag # <--
                    }
                 }
            }

            'ByScope' {

                if ($PSCmdlet.ShouldProcess("Scope '$($Scope.Name)'")) {

                    $skipScope = $Skip -or $Scope.Skip

                    if ((-not $skipScope) -and ($Null -NE $SkipTag)) {
                        if ($Null -NE $Scope.Tag) {
                            $skipScope = ($Scope.Tag -in $SkipTag)
                        }
                    }

                    Try {
                        if (-not $skipScope) {
                            if ($null -NE $SCope.Before) {
                                # $Scope.Before
                            }
                        }

                        # Recurse Tests
                        $Scope.Tests  | Invoke-Test -Skip:$skipScope -SkipTag:$SkipTag # <--

                        # Recurse Scopes
                        $Scope.Scopes | Invoke-Test -Skip:$skipScope -SkipTag:$SkipTag # <--
                    }
                    Finally {
                        if (-not $skipScope) {
                            if ($null -NE $Scope.After) {
                                # $Scope.After
                            }
                        }
                    }
                }
            }

            'ByTest' {

                if ($PSCmdlet.ShouldProcess("Test '$($Test.Name)'")) {

                    $skipTest = $Skip -or $Test.Skip

                    if ((-not $skipTest) -and ($Null -NE $SkipTag)) {
                        if ($Null -NE $Test.Tag) {
                            $skipTest = ($Test.Tag -in $SkipTag)
                        }
                    }

                    if ($skipTest) {
                        New-TestResult -Test $Test -Result 'Skipped' # <--
                    }
                    else {
                        [string[]] $output = @()

                        $stopWatch.Restart()
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
                            New-TestResult -Test $Test -Result 'Failed' -Duration $stopWatch.Elapsed -Output $output -Exception $_.Exception # <--
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
        [ScriptBlock] $Script,

        [Parameter()]
        [switch] $Skip,

        [Parameter()]
        [string[]] $Tag
    )

    Begin {
        if ($null -EQ $script:currentScopeName) {
            $script:currentScopeName = ''
        }
        $savedScope = $script:currentScopeName
    }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess($Path)) {
                    $Path = Resolve-Path $Path

                    New-Scope -Name $Path -Skip:$Skip -Tag:$Tag -Script (Get-command $Path | Select-Object -ExpandProperty ScriptBlock ) # <--
                 }
            }

            default {

                if ($PSCmdlet.ShouldProcess($Name)) {

                    if ($script:currentScopeName -EQ '') {
                        $script:currentScopeName = $Name
                    }
                    elseif ($script:currentScopeName -NE $Name) {
                        $script:currentScopeName = $script:currentScopeName + ' | ' + $Name
                    }

                    $output = @( Invoke-Command -ScriptBlock $SCript ) 2>&1

                    # $before = $output | Where-Object { 'Tester.Before' -IN $_.PsObject.TypeNames } | Select -First 1
                    # $after  = $output | Where-Object { 'Tester.After'  -IN $_.PsObject.TypeNames } | Select -First 1
                    $scopes = $output | Where-Object { 'Tester.Scope'  -IN $_.PsObject.TypeNames }
                    $tests  = $output | Where-Object { 'Tester.Test'   -IN $_.PsObject.TypeNames }

                    [PSCustomObject] $result = [PSCustomObject] @{
                        PSTypeName  = 'Tester.Scope'
                        Path        = $Script.File
                        Scope       = $script:currentScopeName
                        Name        = $Name
                        Skip        = $Skip
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
        [ScriptBlock] $Script,

        [Parameter()]
        [switch] $Skip,

        [Parameter()]
        [string[]] $Tag
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName  = 'Tester.Test'
                Path        = $Script.File
                Scope       = $script:currentScopeName
                Name        = $Name
                Skip        = $Skip
                Test        = $Script
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
        [System.Exception] $Exception
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName  = 'Tester.TestResult'
                Path        = $Test.Path
                Scope       = $Test.Scope
                Name        = $Test.Name
                Result      = $Result
                Duration    = $Duration
                Output      = $Output    | Out-String
                Exception   = $Exception | Out-String
            }

            $result # <--
        }
    }
}

New-Alias -Name 'Scope'     -Value 'New-Scope'          -Force
New-Alias -Name 'Test'      -Value 'New-Test'           -Force

Update-FormatData -AppendPath .\Tester.ps1xml
