
Test 'Without Scope' -Tag 'NoScope' {
}

Scope 'Outer' -Tag 'Outer' {

    Test 'Good test' {
        Write-Output 'Outer'
    }

    Scope 'Inner' -Tag 'Inner' {

        ForEach ($i in (0..2)) {

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

    Scope "Timing" -Tag 'Timing' -Parallel {

        0 .. 5 | % { 

            Test "10 ms $_" {
                Start-Sleep -Milliseconds 10
            }
        }
    }

    0 .. 5 | % { 

        Scope "Timing $_" -Tag 'Timing' -Parallel -Skip {

            Test "10 ms" {
                Start-Sleep -Milliseconds 10
            }

            Test "20 ms" {
                Start-Sleep -Milliseconds 20
            }

            Test "50 ms" {
                Start-Sleep -Milliseconds 50
            }

            Test "100 ms" {
                Start-Sleep -Milliseconds 100
            }

            Test "200 ms" {
                Start-Sleep -Milliseconds 200
            }

            Test "500 ms" {
                Start-Sleep -Milliseconds 500
            }
        }
    }
}
