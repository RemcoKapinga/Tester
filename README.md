# Tester
Quick and Dirty PowerShell Testrunner with a focus on true PowerShell nativity.

`Scopes`, `Tests` and `TestResults` are native PowerShell objects, and all commands embrace the pipeline concept. Tester embraces and uses the PowerShell pipeline to invoke `Tests`, and returns `TestResult` objects.

Since Tester is focused on beeing a Testrunner, there is no real functionallity beyond describing, discovering and invoking Tests. Feel free to use your preferred `Assertions` library (as long as it generates default PowerShell errors or Exceptions), or your preferred `Mocking` framework in addition to Tester. (To enable use of Mocking, Tester will add support for `Before` and `After` (setup/teardown logic) on Scopes in a future update).

## Usage
### Write your Tests in a .Test.ps1 file

    Scope 'MyScope' {
        Test 'This is a Test' {
            ...
        }
    }

### Invoke-Test
    > Invoke-Test

### Evaluate the Results
Test results are native PowerShell objects. They are listed in the same manner as you would expect from other PowerShell commands, sush as `Get-ChildItem`. Testresults can be grouped, sorted, filtered, etc.. to your liking, using native PowerShell commands.
