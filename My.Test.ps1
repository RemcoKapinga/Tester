
. '.\Tester.ps1'

Test 'Without Scope' -Tag 'NoScope' {
}

Scope 'Outer' -Tag 'Outer' {

    Test 'Good test' {
        Write-Output 'Outer'
    }

    Scope 'Inner' -Tag 'Inner'  {

        ForEach($i in (0..2)) {

            Test "Good - $i" -Tag 'Good' {
                Write-Output "Good output $i"
            }

            Test "Skippy - $i" -Skip {
                Write-Output "Good output $i"
            }

            Test "Bad - $i" -Tag 'Bad' {
                Throw "Bad error $i"
            }
        }
    }

    Scope 'SkippedScope' -Skip {

        Test 'SkippedTest' {
            Throw 'Test should be Skipped'
        }
    }

    Scope 'Timing' -Tag 'Timing' {

        Test '1ms' {
            Start-Sleep -MilliSeconds 1
        }

        Test '200ms' {
            Start-Sleep -MilliSeconds 200
        }

        Test '1s' {
            Start-Sleep -Seconds 1
        }
    }
}
