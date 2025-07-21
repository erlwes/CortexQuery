<#
.SYNOPSIS
    Module for running XQL-queries vs. Palo Alto Cortex/XSIAM API using PowerShell.

.DESCRIPTION
    The module takes nessasary input with 'Set-CortexAuthHeader'. The header, along with an XQL-query is then requested to start vs. Cortex API.
    The scripts then polls the results, waiting for the query to be executed, before presenting the results directly, or parsing raw-bytestream into if more than 1000 results are returned.

.AUTHOR
    Erlend Westervik

.COPYRIGHT
    None

.LICENSE
    None

.VERSION
    1.0.0

.NOTES
    - Works in PowerShell Core and Windows PowerShell (5.1)
    - API-reference, auth: https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/API-Reference
    - API-reference, start XQL-query:  https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Start-an-XQL-Query

.EXAMPLE
    Prepare the context for the API connection and auth

    $keyid = '99' #API key-ID
    $fqdn = 'https://api-[CUSTOMER ID].xdr.eu.paloaltonetworks.com' #API URL
    $key = '[Your 128 char long API key]' #API key/secret

    Set-CortexAuthHeader -keyId $keyid -fqdn $fqdn -key $key

.EXAMPLE
    Run a query to get events from the last hour, with detailed output of every step to the console.
    Then extract the 'raw_log'-property and convert it from JSON

    $query = @'
        dataset = cloud_audit_logs
        | filter log_name = "azure_ad_signin_logs"
        | limit 1
    '@

    $results = Invoke-CortexQuery -Query $query -relativeTime 1h -VerboseLogging
    $results.raw_log | ConvertFrom-Json

#>

Function Write-Console {
    param(
        [ValidateSet(0, 1, 2, 3, 4)]
        [int]$Level = 0,

        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $Message = $Message.Replace("`r",'').Replace("`n",' ')
    switch ($Level) {
        0 { $Status = 'Info'        ;$FGColor = 'White'   }
        1 { $Status = 'Success'     ;$FGColor = 'Green'   }
        2 { $Status = 'Warning'     ;$FGColor = 'Yellow'  }
        3 { $Status = 'Error'       ;$FGColor = 'Red'     }
        4 { $Status = 'Debug'       ;$FGColor = 'Gray'    }
        Default { $Status = ''      ;$FGColor = 'Black'   }
    }
    if ($VerboseLogging) {
        Write-Host "$((Get-Date).ToString()) " -ForegroundColor 'DarkGray' -NoNewline
        Write-Host "$Status" -ForegroundColor $FGColor -NoNewline

        if ($level -eq 4) {
            Write-Host ("`t " + $Message) -ForegroundColor 'Cyan'
        }
        else {
            Write-Host ("`t " + $Message) -ForegroundColor 'White'
        }
    }
}

Function Set-CortexAuthHeader {
    param(
        [parameter(mandatory=$true)][int]$keyId,
        [parameter(mandatory=$true)][string]$key,
        [parameter(mandatory=$true)][string]$fqdn
    )
    
    if ($fqdn -notmatch 'paloaltonetworks.com') {
        Write-Warning "Set-CortexAuthHeader - The FQDN '$fqdn' does not contain 'paloaltonetworks.com'"
    }

    # Prepare auth-header with API Key and Key Id for functions that do API-calls
    $script:headers = @{
        "x-xdr-auth-id" = $keyID
        "Authorization" = $key
        "Content-Type" = "application/json"
        "Accept-Encoding" = "gzip"
    }

    # Make FQDN avaliable for other cmdlets inside module to use.
    $script:fqdn = [string]$fqdn
}

Function Test-CortexAuthHeader {
    if (!$script:headers -or !$script:fqdn) {
        Write-Console -Level 2 -Message "Test-CortexAuthHeader - Header and required parameters is not set. Please run 'Set-CortexAuthHeader'"
    }
    else {
        Write-Console -Level 1 -Message "Test-CortexAuthHeader - Header and FQDN seems ok."
    }
}

Function Invoke-CortexQuery {
    [CmdletBinding()]
    param (
        $Query,
        $relativeTime = '1d',
        $resultLimit = 100,
        [switch]$VerboseLogging
    )

    # Test to see if auth context is avaliable. Simple tests, just to see that there are values, not verifying that the key length is 128-bits etc.
    Test-CortexAuthHeader

    # Function for converting relative time into unix timstamps. No need for re-use, so I'm keeping it inside this function.
    Function Get-RelativeUnixTimestamp {
        param(
            [Parameter(Mandatory = $true)]
            [string]$TimeString
        )

        # Regular expression to match format like 1d, 2h, 15m
        if ($TimeString -match '^(\d+)([dhm])$') {
            $value = [int]$matches[1]
            $unit  = $matches[2]
    
            switch ($unit) {
                'd' { $milliseconds = $value * 24 * 60 * 60 * 1000 }
                'h' { $milliseconds = $value * 60 * 60 * 1000 }
                'm' { $milliseconds = $value * 60 * 1000 }
                default {
                    Write-Console -Level 2 -Message "Unsupported time unit: $unit"
                }
            }
            Write-Console -Level 0 -Message "Converted from relative time string to ms. '$TimeString' -> '$milliseconds'"
            return @{ relativeTime = $milliseconds }
        }
        else {
            Write-Console -Level 2 -Message "Invalid time format. Use formats like '1d', '2h', '15m'."
        }
    }

    $Collection = (Get-RelativeUnixTimestamp -TimeString $relativeTime).Values
    [long]$relativeTime = $Collection.GetEnumerator() | Select-Object -First 1

    # Prepare a XQL query request
    $requestData = @{
        request_data = @{
            query = $query
            timeframe = @{
                relativeTime = [long]$relativeTime
            }
        }
    }

    # Convert the request to JSON
    $jsonRequest = $requestData | ConvertTo-Json -Depth 3

    # Build URL for "Start an XQL Query"
    $apiName = "xql"
    $callName = "start_xql_query"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    Write-Console -Level 0 -Message "Start XQL-query - Endpoint: '$Script:fqdn/public_api/v1/'"

    # Send the request (POST)
    try {
        $responseStart = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $jsonRequest
        if ($responseStart.StatusCode -eq 200) {
            Write-Console -Level 1 -Message "Start XQL-query - Call name '$callName'. Statuscode: $($responseStart.StatusCode)"
        }
        else {
            Write-Console -Level 3 -Message "Start XQL-query - Call name '$callName'. Unexpected response. Statuscode: $($responseStart.StatusCode)"
            Return
        }
    }
    catch {
        Write-Console -Level 3 -Message "Start XQL-query - Failed to do call '$callName'. Error: $($_.Exception.Message)"
    }

    # Get the ID of the queued query
    $script:QueryId = ($responseStart.Content | ConvertFrom-Json).Reply
    Write-Console -Level 0 -Message "Start XQL-query - Got query id from response ($script:QueryId)"    
    Invoke-CortexQueryResults -QueryId $script:QueryId -limit $resultLimit
}

Function Invoke-CortexQueryResults {
    [CmdletBinding()]
    param (
        [string]$QueryId,
        [int]$Limit = 2000
    )

    # Prepare request for query results
    $RequestData = @{
        request_data = @{
            query_id = "$QueryId"
            pending_flag = $True #True (default): The call returns immediately with status PENDING / False: The API will block until query completes and results are ready to be returned.
            limit = $Limit
            format = "json"
        }
    }

    # Convert the request to JSON
    $JSONRequest = $RequestData | ConvertTo-Json -Depth 3

    # Build URL for "Get XQL Query Result"
    $apiName = "xql"
    $callName = "get_query_results"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    # Send the request (POST)
    try {
        $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $JSONRequest -ErrorAction Stop
        $responseResultsStatus = $(($responseResults.content | ConvertFrom-Json).Reply.Status)
        Write-Console -Level 1 -Message "Get XQL-query results - Invoke-WebRequest"
    }
    catch {
        Write-Console -Level 3 -Message "Get XQL-query results - Invoke-WebRequest: Error $($_.Exception.Message)"
    }

    # Wait for it to be done, if not already done
    While ($responseResultsStatus -ne 'SUCCESS') {
        Start-Sleep -Seconds 2
        $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $JSONRequest
        $responseResultsStatus = $(($responseResults.content | ConvertFrom-Json).Reply.Status)
        Write-Console -Level 0 -Message "Get XQL-query results - Invoke-WebRequest: Status is '$responseResultsStatus' (waiting 2s)"
        if ($responseResultsStatus -eq 'FAIL') {
            Write-Console -Level 3 -Message "Get XQL-query results - Aborting. Query failed:"
            $responseResults | Format-List *
            Break
        }
    }

    # Output results as PSObject
    $convertedResponseResults = $responseResults.content | ConvertFrom-Json
    $resultCount = ($convertedResponseResults.reply.results.data).count

    # See if we got any results-data
    if ($resultCount -ge 1) {

        # If we get data, this means it was less than 1k results
        if ($convertedResponseResults.reply.results.data) {
            Write-Console -Level 0 -Message "Get XQL-query results - $resultCount results returned"
            Return $convertedResponseResults.reply.results.data
        }

        # If there the resultsize is bigger than 1k, we get a stream id in response, and have to fetch a bytestream instead to get all results
        elseif ($convertedResponseResults.reply.results.stream_id) {
            Write-Console -Level 0 -Message "More than 1k results. Making query vs. stream (stream_id: $($convertedResponseResults.reply.results.stream_id))"
            Write-Host $convertedResponseResults.reply.results.stream_id -ForegroundColor Cyan
            Invoke-CortexQueryResultsStream -StreamID $convertedResponseResults.reply.results.stream_id
        }
    }
    else {
        Write-Console -Level 0 -Message "No results returned"
        Return $null
    }
}

Function Invoke-CortexQueryResultsStream {
    [CmdletBinding()]
    param (
        [string]$StreamID
    )

    # Prepare request for query results
    $RequestData = @{
        request_data = @{
            stream_id = "$StreamID"
            is_gzip_compressed = $false
        }
    }

    # Convert the request to JSON
    $JSONRequest = $RequestData | ConvertTo-Json -Depth 3

    # Build URL for "Get XQL Query Result Stream"
    $apiName = "xql"
    $callName = "get_query_results_stream"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    # Send the request (POST)
    try {
        $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $JSONRequest -ErrorAction Stop        
        Write-Console -Level 1 -Message "Get XQL-query results stream - Invoke-WebRequest: Status code $($responseResults.StatusCode)"
    }
    catch {
        Write-Console -Level 3 -Message "Get XQL-query results stream - Invoke-WebRequest: Error $($_.Exception.Message)"
    }

    # Output results as PSObject, after encoding bytestream and converting it from JSON.
    if ($responseResults.StatusCode -eq 200) {        
        $rawBytes = $responseResults.Content

        # If it's actually a string, convert to bytes:
        if (-not ($rawBytes -is [byte[]])) {
            $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($rawBytes)
        }

        # Convert the raw bytes to a UTF-8 strings
        $jsonLines = [System.Text.Encoding]::UTF8.GetString($rawBytes)

        # Newline-delimited JSON objects are splitted and then converted to PSObjects
        $Objects = $jsonLines -split "`n" | ForEach-Object {
            $_ | ConvertFrom-Json
        }
        Write-Console -Level 1 -Message "Get XQL-query results stream - Process: $($Objects.count) JSON-objects converted to PS-objects."
        Return $Objects
    }
    else {
        Write-Console -Level 3 -Message "Get XQL-query results stream - Invoke-WebRequest: Status code $($responseResults.StatusCode)"
        Return $null
    }
}

# The other functions are support functions and does not need to be called directly.
Export-ModuleMember -Function 'Set-CortexAuthHeader', 'Invoke-CortexQuery'