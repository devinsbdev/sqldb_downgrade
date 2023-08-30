# better logging is better

class Log {
  [string]$LogPath
  [string]$LogDir
  [string]$TimeFormat = 'yyyy-MM-ddTHH:mm:ssZ'
  [string]$CallerName
  [string]$Encoding = 'utf8'

  # [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8

  Log( [string]$LogPath, [string]$Caller )
  {
      $this.CallerName = $Caller

      if ( ![string]::IsNullOrWhiteSpace($LogPath) )
      {
          $this.LogPath = $LogPath
          $LogPathParts = $LogPath -split '\\'
          $this.LogDir = $LogPathParts[0..($LogPathParts.Length - 2)] -join '\'

        #   New-Item $this.LogDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
          New-Item $this.LogPath -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
      }
  }

  [void]debug( [string]$Message )
  {
      $lt = 'DEBUG'
      $color = [System.ConsoleColor]::Blue

      $dt = Get-Date -Format $this.TimeFormat
      $logline = "[${dt}]|[$($this.CallerName)]|[$lt]|${Message}"
      $logparts = $logline -split '\|'

      Write-Host "$($logparts[0]) " -no -f gray
      Write-Host "$($logparts[1]) " -no -f darkgray
      Write-Host "$($logparts[2]) " -no -f $color
      Write-Host "$($logparts[3]) " -f white

      $this.outfile($logparts -join ' ')
  }

  [void]info( [string]$Message )
  {
      $lt = 'INFO'
      $color = [System.ConsoleColor]::Cyan

      $dt = Get-Date -Format $this.TimeFormat
      $logline = "[${dt}]|[$($this.CallerName)]|[$lt]|${Message}"
      $logparts = $logline -split '\|'

      Write-Host "$($logparts[0]) " -no -f gray
      Write-Host "$($logparts[1]) " -no -f darkgray
      Write-Host "$($logparts[2]) " -no -f $color
      Write-Host "$($logparts[3]) " -f white

      $this.outfile($logparts -join ' ')
  }

  [void]success( [string]$Message )
  {
      $lt = 'SUCCESS'
      $color = [System.ConsoleColor]::Green

      $dt = Get-Date -Format $this.TimeFormat
      $logline = "[${dt}]|[$($this.CallerName)]|[$lt]|${Message}"
      $logparts = $logline -split '\|'

      Write-Host "$($logparts[0]) " -no -f gray
      Write-Host "$($logparts[1]) " -no -f darkgray
      Write-Host "$($logparts[2]) " -no -f $color
      Write-Host "$($logparts[3]) " -f white

      $this.outfile($logparts -join ' ')
  }

  [void]warning( [string]$Message )
  {
      $lt = 'WARNING'
      $color = [System.ConsoleColor]::Yellow

      $dt = Get-Date -Format $this.TimeFormat
      $logline = "[${dt}]|[$($this.CallerName)]|[$lt]|${Message}"
      $logparts = $logline -split '\|'

      Write-Host "$($logparts[0]) " -no -f gray
      Write-Host "$($logparts[1]) " -no -f darkgray
      Write-Host "$($logparts[2]) " -no -f $color
      Write-Host "$($logparts[3]) " -f white

      $this.outfile($logparts -join ' ')
  }

  [void]error( [string]$Message )
  {
      $lt = 'ERROR'
      $color = [System.ConsoleColor]::Red

      $dt = Get-Date -Format $this.TimeFormat
      $logline = "[${dt}]|[$($this.CallerName)]|[$lt]|${Message}"
      $logparts = $logline -split '\|'

      Write-Host "$($logparts[0]) " -no -f gray
      Write-Host "$($logparts[1]) " -no -f darkgray
      Write-Host "$($logparts[2]) " -no -f $color
      Write-Host "$($logparts[3]) " -f white

      $this.outfile($logparts -join ' ')
  }

  [void]outfile( [string]$Message )
  {
      if ($this.LogPath)
      {
          ( "$Message" | Out-File -FilePath $this.LogPath -Encoding $this.Encoding `
              -Append -ErrorAction SilentlyContinue -WhatIf:$false )
      }
  }
}
