using module '.\Thread.psm1';

[CmdletBinding()]
param(
  [Parameter( Mandatory = $true )]
  [string]$ServerInstance,

  [Parameter( Mandatory = $true )]
  [string]$DatabaseName,

  [Parameter( Mandatory = $true )]
  [ValidateSet('100', '110', '120', '130', '140', '150')]
  [string]$TargetVersion,

  [Parameter( Mandatory = $true )]
  [string]$DotBacpacOutfilePath
)

#? GET DEPENDENCIES
Get-Deps | Out-Null

#? MAKE SURE USER KNOWS WE WILL DESTROY THINGS
if ( !$(Get-UserConsent -ServerInstance $ServerInstance -DatabaseName $DatabaseName)) {
  break Script;
}

#? GET A LOGGER
$console = Get-LoggerPlz

#? INITIATE CONNECTION WITH SOURCE DB
$console.info("Initiating connection with source database ...")
$db = Get-DatabaseSmo -ServerInstance $ServerInstance -DatabaseName $DatabaseName

#? RESET OWNERSHIP ON ALL SCHEMAS
$console.info("Resetting schema ownership ...")
Reset-SchemaOwnership -DatabaseSmo $db

#? DROP SCHEMAS (IF EXIST) ASSOC WITH INCOMPAT (i.e. ALL) USERS
$console.info("Dropping users and their owned schemas ...")
Remove-AllIncompatibleUsers -DatabaseSmo $db

#? EXPORT AND SCRIPT AND DROP AND REPEAT!
:secondchanceloop
for ($d = 0; $d -lt 4; $d++) {
  $console.info("===== PASS $($d + 1) =====")
  $console.info("===== PASS $($d + 1) =====")
  $console.info("===== PASS $($d + 1) =====")

  #? ATTEMPT BACPAC EXPORT; IF WE'RE LUCKY IT MAY WORK (this time?)!
  $console.info("Attempting BACPAC export, this will take a bit ...")

  Export-DatabaseToBackpack `
    -ServerInstance $ServerInstance `
    -DatabaseName $DatabaseName `
    -DotBacpacOutfilePath $DotBacpacOutfilePath `
    -ErrorAction SilentlyContinue

  if ( (Test-Path $DotBacpacOutfilePath) ) {
    $msg = "That seemed to work"

    switch ($d) {
      1 { $msg += ' this time'}
      2 { $msg += ' on the third try'}
      3 { $msg += ' finally'}
    }

    $console.success(
      [string]::Format("{0}. Grab the BACPAC file! {1}", $msg, $DotBacpacOutfilePath) );

    break secondchanceloop;

  } else {
    switch ($d) {
      { 0 -or 1 -or 2 } {
        $errdata = ( $Error | Where-Object {
          $_.ToString() -match 'Error SQL'
        } )

        $errdata | Out-File "${DatabaseName}-bacpac-errors-${d}.log" -Force

        $console.info("There are $($errdata.Count) errors we need to ""take care of""...")
        Start-Sleep 3

        #? BACKUP (SCRIPT) AND THEN DROP VIEWS, SPs and FUNCTIONS WE DON'T LIKE
        $console.info("Scripting and then dropping incompatible objects ...")
        Remove-IncompatibleSqlObjects `
          -ScriptTargetVersion $TargetVersion `
          -DatabaseSmo $db `
          -ErrorData $errdata

      }
      default {
        $console.warning( [string]::Format("There are still errors that need to be resolved manually " + `
          "before attempting another BACPAC export.") );
      }
    }
  }
}
