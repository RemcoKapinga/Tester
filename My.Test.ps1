
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
}

Scope 'ScopeWithSetupTeardown' {

    Before {
        $script:x = 12;
    }

    Scope 'Tests' {
        Test 'Test x' {
            if ($script:x -ne 12) {
                Throw "x should be 12 but is $($script:x)"
            }
        }
    }

    After {
        $script:x = $null;
    }
}
