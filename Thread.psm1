using module '.\Log.psm1';

function Export-DatabaseToBackpack {
  [CmdletBinding()]
  param (
    [Parameter()]
    [string]$ServerInstance,
    [Parameter()]
    [string]$DatabaseName,
    [Parameter()]
    [string]$DotBacpacOutfilePath
  )

  $job = @{
    Name = "$DatabaseName-DacStore-Export"
    ArgumentList = @($ServerInstance, $DatabaseName, $DotBacpacOutfilePath, $BinPath)
    ScriptBlock = {
      $( ./bin/sqlpackage/sqlpackage.exe `
          /a:Export `
          /p:CompressionOption=SuperFast `
          /ssn:"$($args[0])" `
          /sdn:"$($args[1])" `
          /tf:"$($args[2])" `
          /sec:Optional )
    }
  }
  # /p:VerifyExtraction=False `

  $exportThread = Start-ThreadJob @job;
  $exportThread.Error

  return ( Get-Job -Id $exportThread.Id `
    | Receive-Job -WriteEvents -Wait -AutoRemoveJob )
}

function Remove-IncompatibleSqlObjects {
  [CmdletBinding()]
  param (
    [Parameter()]
    [String]$ScriptTargetVersion,
    [Parameter()]
    [Object]$DatabaseSmo,
    [Parameter()]
    [Object]$ErrorData
  )

  $DatabaseName = $DatabaseSmo.Name

  $scriptOptions = [Microsoft.SqlServer.Management.Smo.ScriptingOptions]@{
    TargetServerVersion = "Version${ScriptTargetVersion}"
    Encoding = [Text.Encoding]::UTF8
    ScriptForCreateDrop = $true
    IncludeIfNotExists = $true
    ContinueScriptingOnError = $true
  }

  $scriptedObjects = [System.Collections.ArrayList]::new();
  $sqlrestorelist = ".\${DatabaseName}-dropped-object-list.log"
  New-Item $sqlrestorelist -ItemType File -ErrorAction SilentlyContinue | Out-Null

  $sqlobjrgx = [regex]::new('(Procedure|View|Function):\s((?:\[\w+\]\.)+\[([\w]+)\])')
  $incompatSqlObjects = $sqlobjrgx.Matches($ErrorData)

  :otloop
  foreach ($ot in $incompatSqlObjects) {
    $op = $ot.Groups[1].Value
    $to = $ot.Groups[2].Value
    $pln = $ot.Groups[3].Value

    # duplicates
    if ($scriptedObjects."$op") {
      if ($scriptedObjects."$op".Contains($to)) {
        continue otloop;
      }
    }

    switch ($op) {
      'View' {
        $thisObj = ($DatabaseSmo.Views | Where-Object { $_.Name -eq $pln })
      }
      'Procedure' {
        $thisObj = ($DatabaseSmo.StoredProcedures | Where-Object { $_.Name -eq $pln })
      }
      'Function' {
        $thisObj = ($DatabaseSmo.UserDefinedFunctions | Where-Object { $_.Name -eq $pln })
      }
      'Type' {
        $thisObj = ($DatabaseSmo.UserDefinedTypes | Where-Object { $_.Name -eq $pln })
      }
    }

    try {
      Write-Host "Generating script for ${op}: ${pln}" -f green
      $scriptedObjects.Add(@{$op = $to}) | Out-Null
      $createLine = $thisObj.Script($scriptOptions)
    } catch {
      Write-Warning "Not dropping the ${op} named ${to}. Failed to generate its CREATE script."
      Write-Host $_ -f yellow
      continue
    }

    if($null -ne $createLine) {
      $content = ( $createLine |
        ForEach-Object {
          switch -Regex ($_) {
            # '^SET ANSI|^SET QUOTED' {}
            'END$' { return "${_}`n" }
            default { return $_ }
          }
        }
      );

      try {
        $sqlrestorescript = ".\generated_scripts\${DatabaseName}.${op}.${pln}.sql"
        New-Item $sqlrestorescript -ItemType File -ErrorAction SilentlyContinue | Out-Null
        Add-Content $sqlrestorescript $content -ErrorAction Stop
        Add-Content $sqlrestorelist ( [string]::Format('{0}.{1}', $op, $to) ) -ErrorAction Stop

        Start-Sleep -Milliseconds 250

        $q = [string]::Format('DROP {0} IF EXISTS {1}', $op, $to)
        Write-Host ($q) -f Blue
        $DatabaseSmo.ExecuteNonQuery($q);
      } catch {
        $err = $_
        Write-Warning "Not dropping the ${op} named ${to}. Failed to generate its CREATE script."
        Write-Host $err -f yellow
      }

    } else {
      Write-Warning "No Script, NO DROP!"
    }
  }
  return $incompatSqlObjects
}

function Get-UserConsent {
  [CmdletBinding()]
  [OutputType([System.Boolean])]
  param (
    [Parameter()]
    [string]$ServerInstance,
    [Parameter()]
    [string]$DatabaseName
  )

  Write-Host ""
  Write-Host ""
  Write-Warning "ACHTUNG!"
  Write-Warning "ACHTUNG!"
  Write-Warning "ACHTUNG!"
  Write-Host ""
  Write-Host ""
  Write-Host "I SINCERELY HOPE YOU'VE MADE A COPY OF THE SOURCE DATABASE ( [${ServerInstance}].${DatabaseName} ) TO USE FOR THIS..." -f Magenta
  Write-Host ""
  Write-Host ""
  Write-Host "THE SCRIPT WILL *100% FOR SURE* DROP OBJECTS WITHOUT WARNING!" -f Magenta
  Write-Host ""
  Write-Host ""
  Write-Warning "ACHTUNG!"
  Write-Warning "ACHTUNG!"
  Write-Warning "ACHTUNG!"
  Write-Host ""
  Write-Host ""
  
  switch -Regex ($(Read-Host 'Sound good? [y/N]')) {
    '^[yY]$' { Write-Host "`n === OK GO! ===`n" -f Green; return $true }
    default { Write-Host "`nFAREWELL!`n" -f Magenta; return $false }
  }
}

function Reset-SchemaOwnership  {
  [CmdletBinding()]
  param (
    [Parameter()]
    [Object]$DatabaseSmo
  )

  $DatabaseSmo.Schemas | ForEach-Object {
    if ($_.Owner -ne $_.Name) {
      $q = "ALTER AUTHORIZATION ON SCHEMA::[$($_.Name)] TO [$($_.Name)]"
      Write-Host "$q (Previous Owner: $($_.Owner))" -f Blue
      $DatabaseSmo.ExecuteNonQuery($q);
    }
  }
}

function Get-DatabaseSmo  {
  [CmdletBinding()]
  param (
    [Parameter()]
    [string]$ServerInstance,
    [Parameter()]
    [string]$DatabaseName
  )

  $srv = [Microsoft.SqlServer.Management.Smo.Server]::new($ServerInstance);

  return ( $srv.Databases | Where-Object { $_.Name -eq $DatabaseName } );
}

function Remove-AllIncompatibleUsers {
  [CmdletBinding()]
  param (
    [Parameter()]
    [Object]$DatabaseSmo
  )

  for ($n = 0; $n -lt $DatabaseSmo.Users.Count; $n++) {
    $usr = $DatabaseSmo.Users[$n];
    if ($usr.Name -inotin @('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')) {
      $q = [string]::Format(@"
DROP SCHEMA IF EXISTS [{0}]
GO
DROP USER [{0}]
GO
"@, $usr.Name);
      Write-Host $q -f Blue
      $DatabaseSmo.ExecuteNonQuery($q)
    }
  }
}

function Get-LoggerPlz {
  $caller_name = 'mssql-downgrader'
  return ( [Log]::new( $null, $caller_name ) )
}

function Get-Deps {
  $modInstalled = Get-InstalledModule -Name SqlServer -AllVersions
  if (!$modInstalled -or ($modInstalled.Count -eq 0)) {
    Install-Module SqlServer -Repository PSGallery -Force -Confirm:$false
  }

  Import-Module SqlServer -DisableNameChecking -Force -ErrorAction SilentlyContinue
  [Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')
}
