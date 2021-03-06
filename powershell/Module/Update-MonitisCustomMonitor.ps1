function Update-MonitisCustomMonitor {
    <#
    .Synopsis
        Updates a custom monitor in Monitis
    .Description
        Updates a custom monitor in Monitis, adding a new set of results.
        
        You can use Update-CustomMonitor directly, or you can use Add-CustomMonitorCommand to create
        a command to update your custom monitor, or use Watch-CustomMonitor to schedule an update.
    .Example
        Add-MonitisCustomMonitor
    .Link
        Get-MonitisCustomMonitor
    .Link
        Add-MonitisCustomMonitorCommand    
    #>
    [CmdletBinding(DefaultParameterSetName='Name')]
    param(
    # The name of the monitor
    [Parameter(Mandatory=$true,ParameterSetName='Name')]
    [string]
    $Name,        
       
    # The ID of the monitor to remove
    [Parameter(Mandatory=$true,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName='TestId')]
    [Alias('MonitisTestId')]    
    [int]$TestId,       
    
    # The values for the monitor
    [Parameter(Mandatory=$true)]
    [Hashtable]
    $value,        
    
    [DateTime]$CheckTime=  [Datetime]::Now,
    
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
    }
    
    process {
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
        if ($psCmdlet.ParameterSetName -eq 'Name') {
            $null = $psBoundParameters.Remove('Name')
            Get-MonitisCustomMonitor | 
                Where-Object { $_.Name -eq $name } | 
                Update-MonitisCustomMonitor @psBoundParameters
        } else {
            $xmlHttp.Open("POST", "http://www.monitis.com/customMonitorApi", $false)
            $xmlHttp.SetRequestHeader("Content-Type","application/x-www-form-urlencoded")
            
            
            Add-Type -AssemblyName System.Web
            if (-not $TestId) { return }
            $monitor = Get-MonitisCustomMonitor -TestId $testId
            
            $monitorParameters = @($monitor.ParameterName)
            $monitorTypes = @($monitor.ParameterType)
            $valueFields = for ($i =0; $i -lt $monitorParameters.Count;$i++) {           
                $valueName = $monitorParameters[$i]
                $valueType  = $monitorTypes[$i]
                $encodedValue = $value[$valueName]
                if ($encodedValue -like "*;*" -or $encodedValue -like "*:*") {
                    $encodedValue = [Web.HttpUtility]::UrlEncode($value[$valueName], [Text.Encoding]::UTF8)
                }
                if ($valueName -like "*;*" -or $encodedValue -like "*:*") {
                    $valueName = [Web.HttpUtility]::UrlEncode($valueName, [Text.Encoding]::UTF8)
                }
                if ($valueType -eq [float]) {                    
                    "${valueName}:${encodedValue}"                                
                } elseif ($valueType  -eq [int]) {
                    
                    "${valueName}:${encodedValue}"                                
                } elseif ($valueType  -eq [bool]) {
                    "${valueName}:${encodedValue}"                                
                } else {
                    "${valueName}:${encodedValue}"                                
                }
            }
            
            
            
            $order = 'apiKey', 'authToken', 'validation', 'timestamp', 'output', 
                'version', 'action', 'monitorId', 'checktime', 'results'
            $postFields = @{
                apiKey = $script:ApiKey
                authToken = $script:AuthToken
                validation = "token"
                timestamp = (Get-Date).ToUniversalTime().ToString("s").Replace("T", " ")
                output = "xml"
                version = "2"
                checktime = [long]($CheckTime.ToUniversalTime() - ([Datetime]"1970-01-01T00:00:00z").ToUniversaltime()).TotalMilliseconds
                action = "addResult"
                monitorId = "$($TestId)"
                results =  "$($valueFields -join ";")"
            }
            
            $postData =  New-Object Text.Stringbuilder
            foreach ($kv in $order) {
                $null = $postData.Append("$($kv)=$($postFields[$kv])&")
            }
            $postData = "$postData".TrimEnd("&")
            
            $xmlHttp.Send($postData)
            $response = $xmlHttp.ResponseText
            $responseXml = $response -as [xml]
            if ($responseXml.Error) {
                Write-Error -Message $responseXml.Error
            } elseif ($responseXml.Result.Status -and $responseXml.Result.Status -ne "OK") {
                Write-Error -Message $responseXml.Result.Status
            }
        }
    }
}