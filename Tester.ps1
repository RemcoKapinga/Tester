[CmdletBinding()]
Param(
    [Parameter()]
    [switch] $UpdateFormatData
)

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
        [uint] $Depth = [uint]::MaxValue,

        [Parameter(ParameterSetName='ByFile', Mandatory, ValueFromPipeline)]
        [string] $File,

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

    Process {
        Write-Debug -Message "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch($PSCmdlet.ParameterSetName) {

            'ByPath' {
                $Path = Resolve-Path -Path $Path
                Write-Debug -Message "-Path '$Path'"

                if ($PSCmdlet.ShouldProcess($Path, 'Loading and Invoking Unit Test(s) from file(s)')) {
                    $files = Get-ChildItem -File -Path:$Path -Filter:$Filter -Include:$Include -Exclude:$Exclude -Recurse:$Recurse -Depth:$Depth
                    $files | Invoke-Test -SkipTag:$SkipTag
                }
            }

            'ByFile' {
                $File = Resolve-Path $File
                Write-Debug -Message "-File '$File'"

                if ($PSCmdlet.ShouldProcess($File, 'Loading and Invoking Unit Test(s) from file')) {
                    $fileScope = New-Scope -File $File -Confirm:$false
                    $fileScope | Invoke-Test -SkipTag:$SkipTag -Confirm:$false
                }
            }

            'ByScope' {

                if ($PSCmdlet.ShouldProcess($Scope.Name, 'Invoke Unit Test(s)')) {

                    $skipScope = $Skip -or $Scope.Skip

                    if ((-not $skipScope) -and ($Null -NE $SkipTag)) {
                        if ($Null -NE $Scope.Tag) {
                            $skipScope = ($Scope.Tag -in $SkipTag)
                        }
                    }

                    Try {
                        if (-not $skipScope) {
                            if ($null -ne $Scope.Before) {
                                $output = @( Invoke-Command -ScriptBlock $Scope.Before.Script ) 2>&1
                            }
                        }

                        # Recurse Tests
                        $Scope.Tests  | Invoke-Test -Skip:$skipScope -SkipTag:$SkipTag -Confirm:$false

                        # Recurse Scopes
                        $Scope.Scopes | Invoke-Test -Skip:$skipScope -SkipTag:$SkipTag -Confirm:$false
                    }
                    Finally {
                        if (-not $skipScope) {
                            if ($null -ne $Scope.After) {
                                $output = @( Invoke-Command -ScriptBlock $Scope.After.Script ) 2>&1
                            }
                        }

                    }
                }
            }

            'ByTest' {

                if ($PSCmdlet.ShouldProcess($Test.Name, 'Invoke Unit Test')) {

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
                        $stopWatch.Start()
                        Try {
                            Try {
                                $output = @( Invoke-Command -ScriptBlock $Test.Script ) 2>&1
                            }
                            Finally {
                                $stopWatch.Stop()
                            }

                            New-TestResult -Test $Test -Result 'Passed' -Duration $stopWatch.Elapsed -Output $output
                        }
                        Catch {
                            New-TestResult -Test $Test -Result 'Failed' -Duration $stopWatch.Elapsed -Output $output -Exception $_.Exception
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
        [Parameter(ParameterSetName='ByFile', Mandatory, ValueFromPipeline)]
        [string] $File,

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
        Write-Debug -Message "$($MyInvocation.MyCommand) ($($PSCmdlet.ParameterSetName))"

        switch($PSCmdlet.ParameterSetName) {

            'ByFile' {
                $File = Resolve-Path -Path $File

                if ($PSCmdlet.ShouldProcess($File, 'Load Unit Test(s)')) {
                    New-Scope -Name $File -Skip:$Skip -Tag:$Tag -Script (Get-Command $File | Select-Object -ExpandProperty ScriptBlock )
                 }
            }

            default {

                if ($PSCmdlet.ShouldProcess($Name)) {

                    if ($script:currentScopeName -EQ '') {
                        $script:currentScopeName = $Name
                    }
                    elseif ($script:currentScopeName -NE $Name) {
                        $script:currentScopeName = $script:currentScopeName + ' > ' + $Name
                    }

                    $output = @( Invoke-Command -ScriptBlock $SCript ) 2>&1

                    $before = $output | Where-Object { 'Tester.Before' -IN $_.PsObject.TypeNames } | Select -First 1
                    $after  = $output | Where-Object { 'Tester.After'  -IN $_.PsObject.TypeNames } | Select -First 1
                    $scopes = $output | Where-Object { 'Tester.Scope'  -IN $_.PsObject.TypeNames }
                    $tests  = $output | Where-Object { 'Tester.Test'   -IN $_.PsObject.TypeNames }

                    [PSCustomObject] $result = [PSCustomObject] [Ordered] @{
                        PSTypeName  = 'Tester.Scope'
                        Path        = $Script.File
                        Scope       = $script:currentScopeName
                        Name        = $Name
                        # Script      = $Script
                        Skip        = $Skip
                        Tag         = $Tag
                        Before      = $before
                        After       = $after
                        Scopes      = $scopes
                        Tests       = $tests
                    }

                    $result
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
    [CmdletBinding(ConfirmImpact='None', SupportsShouldProcess)]
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
        Write-Debug -Message "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] [Ordered] @{
                PSTypeName  = 'Tester.Test'
                Path        = $Script.File
                Scope       = $script:currentScopeName
                Name        = $Name
                Script      = $Script
                Skip        = $Skip
                Tag         = $Tag
            }

            $result
        }
    }
}

function New-Before {
    [OutputType('Tester.Before')]
    [CmdletBinding(ConfirmImpact='None', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position=0)]
        [ScriptBlock] $Script
    )

    Process {
        Write-Debug -Message "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] [Ordered] @{
                PSTypeName  = 'Tester.Before'
                Path        = $Script.File
                Scope       = $script:currentScopeName
                Script      = $Script
            }

            $result
        }
    }
}

function New-After {
    [OutputType('Tester.After')]
    [CmdletBinding(ConfirmImpact='None', SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory, Position=0)]
        [ScriptBlock] $Script
    )

    Process {
        Write-Debug -Message "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] [Ordered] @{
                PSTypeName  = 'Tester.After'
                Path        = $Script.File
                Scope       = $script:currentScopeName
                Script      = $Script
            }

            $result
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
        Write-Debug -Message "$($MyInvocation.MyCommand)"

        if ($PSCmdlet.ShouldProcess($Name)) {
            [PSCustomObject] $result = [PSCustomObject] [Ordered] @{
                PSTypeName  = 'Tester.TestResult'
                Path        = $Test.Path
                Scope       = $Test.Scope
                Name        = $Test.Name
                Result      = $Result
                Duration    = $Duration
                Output      = $Output    | Out-String
                Exception   = $Exception | Out-String
            }

            $result
        }
    }
}

New-Alias -Name 'Scope'     -Value 'New-Scope'          -Force
New-Alias -Name 'Before'    -Value 'New-Before'         -Force
New-Alias -Name 'After'     -Value 'New-After'          -Force
New-Alias -Name 'Test'      -Value 'New-Test'           -Force

if ($UpdateFormatData) {
    Write-Debug "Updating FormatData with '$PsScriptRoot\Tester.ps1xml'"
    Update-FormatData -AppendPath "$PsScriptRoot\Tester.ps1xml"
}
