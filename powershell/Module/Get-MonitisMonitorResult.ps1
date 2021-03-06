function Get-MonitisMonitorResult
{
    <#
    .Synopsis
        Gets results from a monitor in Monitis
    .Description
        Gets results from eiher a custom monitor or in Monitis
    .Example
        Get-MonitisExternalMonitor |
            Get-MonitisMonitorResult
    #>
    [CmdletBinding(DefaultParameterSetName='Date')]
    param(
    # The name of the monitor to remove.
    [string]$Name,
    
    # The testID of the monitor
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Alias('MonitisTestId')]    
    [int[]]$TestId,
            
    # The datetime to get the results
    [Parameter(ParameterSetName="Date")]
    [DateTime]$Date = [Datetime]::Now,
    
    # The date to get the results, starting from today and going backward
    [Parameter(Mandatory=$true,ParameterSetName="Since")]
    [DateTime]$Since,
    
    # The last number of days 
    [Parameter(Mandatory=$true,ParameterSetName="Last")]    
    [TimeSpan]$Last,

    # The start of a range
    [Parameter(Mandatory=$true,ParameterSetName="Range")]
    [DateTime]$Start,
    
    # The end of a range
    [Parameter(Mandatory=$true,ParameterSetName="Range")]
    [DateTime]$End,
    
    # The Monitis API key.  
    # If any command connects to Monitis, the ApiKey and SecretKey will be cached    

    [string]$ApiKey,
    
    # The Monitis Secret key.  
    # If any command connects to Monitis, the ApiKey and SecretKey will be cached    

    [string]$SecretKey
    )
    
    begin {
        $xmlHttp = New-Object -ComObject Microsoft.XMLHTTP
        Set-StrictMode -Off
        function ConvertFrom-Json
        {
            param([Parameter(ValueFromPipeline=$true)]
            [string]$Json)

            begin {
                function ConvertFrom-Hashtable
                {
                    param($results)
                    if (-not $results -or -not $results.Count) { return} 
                    $psObject = New-Object PSObject
                    foreach ($key in $results.Keys) {
                        $result = $null
                        if ($results[$key] -is [Hashtable]) {
                            $result = ConvertFrom-Hashtable $results[$key]
                        } elseif ($results[$key] -is [Array]) {
                            $result = foreach ($result in $results[$key]){
                                if ($result -is [Hashtable]) {
                                    ConvertFrom-Hashtable $result
                                } else {
                                    $result
                                }
                            }
                        } else {
                            $result = $results[$key]
                        }
                        
                        $psObject.psObject.Properties.Add(
                            (New-Object Management.Automation.PSNoteProperty $key, $result)
                        )
                    }
                    $psobject
                }
            }
            process {
                
                $script = 
                $json -replace 
                    '":', '"=' -replace 
                    "\[\[", "@(@(" -replace 
                    "\]\]", "))" -replace 
                    ',\[', ",$([Environment]::NewLine)@(" -replace 
                    "\],",")," -replace 
                    '{"', "@{$([Environment]::NewLine)`"" -replace 
                    "\[\]", "@()" -replace             
                    "=([^=]+),",'=$1;' -replace
                    "=(\w)*(\[)", '=@(' -replace 
                    "true", '$true' -replace
                    "false", '$false' -replace
                    "null", '$null' 

                if ($script.Startswith("["))
                {
                    $script = "@("  + $script.Substring(1).TrimEnd("]") + ")"
                }
                $results = $null    
                $results = Invoke-Expression "data { $script } "
                foreach ($result in $results) {ConvertFrom-Hashtable $result } 
            }        
        }        
    }
        
    process {
        if ($psCmdlet.ParameterSetName -eq 'Date') {
            #region Reconnect To Monitis
            if ($psBoundParameters.ApiKey -and $psBoundParameters.SecretKey) {
                Connect-Monitis -ApiKey $ApiKey -SecretKey $SecretKey
            } elseif ($script:ApiKey -and $script:SecretKey) {
                Connect-Monitis -ApiKey $script:ApiKey -SecretKey $script:SecretKey
            }
            
            if (-not $apiKey) { $apiKey = $script:ApiKey } 
            
            if (-not $script:AuthToken) 
            {
                Write-Error "Must connect to Monitis first.  Use Connect-Monitis to connect"
                return
            } 
            #endregion

            if (-not $testid) {
                if ($name) {
                    $null = $psboundParameters.Remove($name)
                    $testId += Get-MonitisCustomMonitor -Name $name | 
                        ForEach-Object { $_.MonitisTestId -as [int] }
                } else {
                    $testId += Get-MonitisCustomMonitor  | 
                        ForEach-Object { $_.MonitisTestId -as [int] }                        
                }
            } else {
                $customMonitor = Get-MonitisCustomMonitor | 
                    Where-Object { $testId -contains ($_.MonitisTestId -as [int])
                    }
                    
            }
            
            $timeZone = [Datetime]::Now - [TimeZone]::CurrentTimeZone.ToUniversalTime([Datetime]::Now)
            $timeZone = $timeZone.TotalMinutes
            
            if ($testId -and (Get-MonitisCustomMonitor -TestId $testId -ErrorAction SilentlyContinue)) {
                $universalDate = $date.TouniversalTime()
                $year=$universalDate.year 
                $month=$universalDate.Month
                $day=$universalDate.Day
                foreach ($tid in $testId) {            
                    
                    $xmlHttp.Open("GET", "http://www.monitis.com/customMonitorApi?apikey=$ApiKey&version=2&action=getMonitorResults&monitorId=$tid&year=$year&month=$month&day=$day", $false)
                    $xmlHttp.Send()
                    $response = ConvertFrom-Json $xmlHttp.responseText   
                    foreach ($r in $response) {
                        $gmtCheckTime = $r.checkTimeInGMT                    
                        $r.psobject.properties.remove("checkTimeInGMT")
                        $r.psobject.properties.remove("Checktime")
                        $rtime = [Datetime]"1/1/1970Z" + [Timespan]::FromMilliseconds($gmtCheckTime)
                        $noteProp =New-Object Management.Automation.PSNoteProperty "CheckTime", $rtime
                        $r.psobject.properties.Add($noteProp)
                        $r
                    }
                }
            } elseif ($testId -and (Get-MonitisExternalMonitor -TestId $testId -ErrorAction SilentlyContinue)) {
                $universalDate = $date.TouniversalTime()
                $year=$universalDate.year 
                $month=$universalDate.Month
                $day=$universalDate.Day
                foreach ($tid in $testId) {            
                    Write-Progress "Getting Results for Test Id $tid" "For $($date.ToLongDateString())"
                    $xmlHttp.Open("GET", "http://www.monitis.com/api?apikey=$ApiKey&version=2&action=testresult&testId=$tid&year=$year&month=$month&day=$day", $false)
                    $xmlHttp.Send()
                    $response = $xmlHttp.responseText   
                    if ($response) {
                        $response = ConvertFrom-Json $response
                        foreach ($location in $response) {
                            if (-not $location.Data) { continue } 
                            $location.data = for ($i =0; $i-lt $location.data.count; $i+=3) {
                                New-Object PSObject -Property @{
                                    CheckTime = [DAtetime]$location.data[$i]
                                    Latency = [Timespan]::FromMilliseconds($location.data[$i + 1])
                                    Response = $location.data[$i + 2]
                                }
                            }
                            $location
                        }
                    }
                }
            }
            
            
            return
        } elseif ($pscmdlet.ParameterSetName -eq 'Since') {
            $days = [Datetime]::Now - $Since
            $day  =[Datetime]::Now
            for ($i = 0; $i -lt $days.TotalDays; $i++) {
                $day = $day.AddDays(-1)
                $null = $psBoundParameters.Remove('Since')
                $psBoundParameters.Date = $day 
                Get-MonitisMonitorResult @psBoundParameters
            }            
        } elseif ($pscmdlet.ParameterSetName -eq 'Range') {
            $days = $end - $start
            $day  =$end 
            for ($i = 0; $i -lt $days.TotalDays; $i++) {
                $day = $day.AddDays(-1)
                $null = $psBoundParameters.Remove('Start')
                $null = $psBoundParameters.Remove('End')
                $psBoundParameters.Date = $day 
                Get-MonitisMonitorResult @psBoundParameters
            }            
        } elseif ($pscmdlet.ParameterSetName -eq 'Last') {
            $end = Get-Date
            $start = $end - $last
            $days = $end - $start
            $day  =$end 
            for ($i = 0; $i -lt $days.TotalDays; $i++) {
                $day = $day.AddDays(-1)
                $null = $psBoundParameters.Remove('Last')                
                $psBoundParameters.Date = $day 
                Get-MonitisMonitorResult @psBoundParameters
            }            
        }                   
    }
    
    
} 
