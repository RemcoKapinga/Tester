
function Invoke-Test {
    [OutputType('Tester.TestResult')]
    [CmdletBinding(ConfirmImpact = 'Low', SupportsShouldProcess, DefaultParameterSetName = 'ByPath')]
    Param(
        [Parameter(ParameterSetName = 'ByPath')]
        [string] $Path = '.',

        [Parameter(ParameterSetName = 'ByPath')]
        [string] $Filter = '*.Test.ps1',

        [Parameter(ParameterSetName = 'ByPath')]
        [string] $Include,

        [Parameter(ParameterSetName = 'ByPath')]
        [string] $Exclude,

        [Parameter(ParameterSetName = 'ByPath')]
        [switch] $Recurse,

        [Parameter(ParameterSetName = 'ByPath')]
        [int] $Depth,

        [Parameter(ParameterSetName = 'ByScope', Mandatory, ValueFromPipeline, Position = 0)]
        [PSTypeName('Tester.Scope')] $Scope,

        [Parameter(ParameterSetName = 'ByTest', Mandatory, ValueFromPipeline, Position = 0)]
        [PSTypeName('Tester.Test')] $Test,

        [Parameter(ParameterSetName = 'ByScope')]
        [Parameter(ParameterSetName = 'ByTest')]
        [switch] $Skip,

        [Parameter()]
        [string[]] $SkipTag,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $ThrottleLimit = 10
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch ($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess("Script '$Path'")) {

                    $files = Get-ChildItem -File -Path:$Path -Filter:$Filter -Include:$Include -Exclude:$Exclude -Recurse:$Recurse -Depth:$Depth

                    Foreach ($file in $files) {
                        $fileScope = New-Scope -Path $file.FullName
                        $fileScope | Invoke-Test -SkipTag:$SkipTag -ThrottleLimit:$ThrottleLimit 
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
                            if ($Scope.Before) {
                                @( Invoke-Command -ScriptBlock $Scope.Before.Script )
                            }
                        }

                        # Invoke Scope.Tests
                        if ($Scope.Parallel -and ($ThrottleLimit -GT 1)) {
                            # Parallel
                            $Scope.Tests | ForEach-Object -ThrottleLimit:$ThrottleLimit -Parallel {
                                . "$($using:PsScriptroot)\Tester.ps1" # <-- this is problematic .. 
                                Invoke-Test -Test $_ -Skip:$using:skipScope -SkipTag:$using:SkipTag
                            }
                        }
                        
                        else {
                            # Sequential
                            $Scope.Tests | ForEach-Object {
                                Invoke-Test -Test $_ -Skip:$skipScope -SkipTag:$SkipTag
                            }
                        }

                        # Invoke Scope.Scopes (Recurse)
                        $Scope.Scopes | ForEach-Object {
                            Invoke-Test -Scope $_ -Skip:$skipScope -SkipTag:$SkipTag -ThrottleLimit:$ThrottleLimit 
                        }

                    }
                    Finally {
                        if (-not $skipScope) {
                            if ($Scope.After) {
                                @( Invoke-Command -ScriptBlock $Scope.After.Script )
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

                        $stopWatch = New-Object -TypeName 'System.Diagnostics.Stopwatch'
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
    [CmdletBinding(ConfirmImpact = 'Low', SupportsShouldProcess, DefaultParameterSetName = 'ByCode')]
    Param(
        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'ByCode', Position = 0)]
        [string] $Name,

        [Parameter(Mandatory, ParameterSetName = 'ByCode', Position = 1)]
        [ScriptBlock] $Script,

        [Parameter()]
        [switch] $Parallel,

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

        switch ($PSCmdlet.ParameterSetName) {

            'ByPath' {

                if ($PSCmdlet.ShouldProcess($Path)) {
                    $Path = Resolve-Path $Path
                    # $script:currentScopeName = $Path

                    New-Scope -Name $Path -Skip:$Skip -Tag:$Tag -Script (Get-Command $Path | Select-Object -ExpandProperty ScriptBlock ) # <--
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

                    $before = $output | Where-Object { 'Tester.Before' -IN $_.PsObject.TypeNames } | select -First 1
                    $after = $output | Where-Object { 'Tester.After' -IN $_.PsObject.TypeNames } | select -First 1
                    $scopes = $output | Where-Object { 'Tester.Scope' -IN $_.PsObject.TypeNames }
                    $tests = $output | Where-Object { 'Tester.Test' -IN $_.PsObject.TypeNames }

                    [PSCustomObject] $result = [PSCustomObject] @{
                        PSTypeName = 'Tester.Scope'
                        Path       = $Script.File
                        Scope      = $script:currentScopeName
                        Name       = $Name
                        Parallel   = $Parallel
                        Skip       = $Skip
                        Tag        = $Tag
                        Before     = $before
                        After      = $after
                        Scopes     = $scopes
                        Tests      = $tests
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
    [CmdletBinding(ConfirmImpact = 'Low', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [Parameter(Mandatory, Position = 1)]
        [ScriptBlock] $Script,

        [Parameter()]
        [switch] $Skip,

        [Parameter()]
        [string[]] $Tag
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand) '$Name'"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName = 'Tester.Test'
                Path       = $Script.File
                Scope      = $script:currentScopeName
                Name       = $Name
                Skip       = $Skip
                Test       = $Script
                Tag        = $Tag
            }

            $result # <--
        }
    }
}

function New-Before {
    [OutputType('Tester.Before')]
    [CmdletBinding(ConfirmImpact = 'Low', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position = 1)]
        [ScriptBlock] $Script
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess()) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName = 'Tester.Before'
                Path       = $Script.File
                Scope      = $script:currentScopeName
                Script     = $Script
            }

            $result # <--
        }
    }
}

function New-After {
    [OutputType('Tester.After')]
    [CmdletBinding(ConfirmImpact = 'Low', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position = 1)]
        [ScriptBlock] $Script
    )

    Process {
        Write-Verbose "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess()) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName = 'Tester.After'
                Path       = $Script.File
                Scope      = $script:currentScopeName
                Script     = $Script
            }

            $result # <--
        }
    }
}


function New-TestResult {
    [OutputType('Tester.TestResult')]
    [CmdletBinding(ConfirmImpact = 'None', SupportsShouldProcess)]
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
        Write-Verbose "$($MyInvocation.MyCommand) '$($Test.Name)' [$Result]"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] @{
                PSTypeName = 'Tester.TestResult'
                Path       = $Test.Path
                Scope      = $Test.Scope
                Name       = $Test.Name
                Result     = $Result
                Duration   = $Duration
                Output     = $Output    | Out-String
                Exception  = $Exception | Out-String
            }

            $result # <--
        }
    }
}

New-Alias -Name 'Scope'     -Value 'New-Scope'  -Force
New-Alias -Name 'Test'      -Value 'New-Test'   -Force
New-Alias -Name 'Before'    -Value 'New-Before' -Force
New-Alias -Name 'After'     -Value 'New-After'  -Force

Update-FormatData -AppendPath .\Tester.ps1xml
