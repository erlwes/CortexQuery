
#   Module for running XQL-queries vs. Palo Alto Cortex/XSIAM API using PowerShell.

#   * Set-CortexAuthHeader
#       - Purpose
#           ~ Prepares authorization request header
#       - API-reference:
#           ~ https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/API-Reference
#       - Parameters
#           ~ keyId -> The ID of the API key generated in Cortex/XSIAM
#           ~ key   -> The secret key from API
#           ~ fqdn  -> Base-URL of you Cortex/XIAM tenant. Example: https://api-customer.xdr.eu.paloaltonetworks.com


#   * Invoke-CortexQueryRequest
#       - Purpose
#           ~ Starts XQL-query, pass the query id directly to "Invoke-CortexQueryResults"
#           ~ The query ID is also stored in a script scope variable, so that it is not needed to specify this when running "Invoke-CortexQueryResults"
#       - API-reference:
#          ~ https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Start-an-XQL-Query
#       - Parameters
#           ~ query -> XQL query. Example: "dataset=microsoft_eventlog_raw | limit 100"
#           ~ relativeTime -> 1m (1 min), 2h (2 hours), 3d (3 days)
#           ~ resultlimit -> max number of returned results


#   * Invoke-CortexQueryResults
#       - Purpose
#           ~ Get x-number of results of XQL-query, by providing a query id and a result limit. If the result exeeds 1000, the steam_id is passed directly on to "Invoke-CortexQueryResultsStream", else the results is outputted.
#       - API-reference:
#          ~ https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Get-XQL-Query-Results
#       - Parameters
#           ~ lastQueryId   -> XQL query
#           ~ limit         -> Limit the number of results

#   * Invoke-CortexQueryResultsStream
#       - Yadayada ... reads bytestream for results greater than 1000.. converts stream to Uff8 and then convert each line from json -> psobject

Function Write-Log {
    param([string]$File, [ValidateSet(0, 1, 2, 3, 4)][int]$Level, [Parameter(Mandatory=$true)][string]$Message, [switch]$Silent)
    $Message = $Message.Replace("`r",'').Replace("`n",' ')
    switch ($Level) {
        0 { $Status = 'Info'    ;$FGColor = 'White'   }
        1 { $Status = 'Success' ;$FGColor = 'Green'   }
        2 { $Status = 'Warning' ;$FGColor = 'Yellow'  }
        3 { $Status = 'Error'   ;$FGColor = 'Red'     }
        4 { $Status = 'Console' ;$FGColor = 'Gray'    }
        Default { $Status = ''  ;$FGColor = 'Black'   }
    }
    if (-not $Silent) {
        Write-Host "$((Get-Date).ToString()) " -ForegroundColor 'DarkGray' -NoNewline
        Write-Host "$Status" -ForegroundColor $FGColor -NoNewline

        if ($level -eq 4) {
            Write-Host ("`t " + $Message) -ForegroundColor 'Cyan'
        }
        else {
            Write-Host ("`t " + $Message) -ForegroundColor 'White'
        }
    }
    if ($Level -eq 3) {
        $LogErrors += $Message
    }
    if ($File) {
        try {
            if ($Clear) {
                Out-File -FilePath "$File" -Force
            }
            (Get-Date).ToString() + "`t$($Script:ScriptUser)@$env:COMPUTERNAME`t$Status`t$Message" | Out-File -Append -FilePath "$File" -ErrorAction Stop
        } catch {
            Write-Host "Failed to write log! ($($_.Exception.Message))" -ForegroundColor Red
        }
    }
}

Function Set-CortexAuthHeader {
    param(
        [parameter(mandatory=$true)][int]$keyId,
        [parameter(mandatory=$true)][string]$key,
        [parameter(mandatory=$true)][string]$fqdn
    )
    
    # Prepare auth-header with API Key and Key Id for functions that do API-calls
    $script:headers = @{
        "x-xdr-auth-id" = $keyID
        "Authorization" = $key
        "Content-Type" = "application/json"
        "Accept-Encoding" = "gzip"
    }

    # Make fqdn avaliable for other functions that do API-calls    
    $script:fqdn = [string]$fqdn
}

Function Test-CortexAuthHeader {
    if (!$script:headers -or !$script:fqdn) {
        Write-Log -Level 2 -Message 'Check - Header and required parameters is not set'        
        Set-CortexAuthHeader
    }
    else {
        # Ok
    }
}

Function Invoke-CortexQueryRequest {
    param (
        $Query,
        $relativeTime = '1d',
        $resultLimit = 100
    )

    #Test to see if auth context is avaliable
    Test-CortexAuthHeader

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
                    throw "Unsupported time unit: $unit"
                }
            }
            Write-Log -Level 0 -Message "Converted from relative time string to ms. '$TimeString' -> '$milliseconds'"
            return @{ relativeTime = $milliseconds }
        }
        else {
            throw "Invalid time format. Use formats like '1d', '2h', '15m'."
        }
    }

    $Collection = (Get-RelativeUnixTimestamp -TimeString $relativeTime).Values
    [int]$relativeTime = $Collection.GetEnumerator() | Select-Object -First 1

    # Prepare a XQL query request
    $requestData = @{
        request_data = @{
            query = $query
            timeframe = @{
                relativeTime = [int]$relativeTime
            }
        }
    }

    # Convert the request to JSON
    $jsonRequest = $requestData | ConvertTo-Json -Depth 3

    # Build URL for "Start an XQL Query"
    $apiName = "xql"
    $callName = "start_xql_query"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    # Send the request (POST)
    $responseStart = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $jsonRequest

    # Get the ID of the queued query
    $script:lastQueryId = ($responseStart.Content | ConvertFrom-Json).Reply
    $script:lastQueryId
    Invoke-CortexQueryResults -lastQueryId $script:lastQueryId -limit $resultLimit
}

Function Invoke-CortexQueryResults {
    param (
        [string]$lastQueryId,        
        [int]$limit = 2000
    )
    
    #Test to see if auth context is avaliable
    Test-CortexAuthHeader

    # Prepare request for query results
    $requestData = @{
        request_data = @{
            query_id = "$lastQueryId"      
            pending_flag = $True #True (default): The call returns immediately with status PENDING / False: The API will block until query completes and results are ready to be returned.
            limit = $limit
            format = "json"
        }
    }

    # Convert the request to JSON
    $jsonRequest = $requestData | ConvertTo-Json -Depth 3

    # Build URL for "Get XQL Query Result"
    $apiName = "xql"
    $callName = "get_query_results"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    # Send the request (POST)
    $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $jsonRequest

    # Wait for it to be done
    Write-Host 'Waiting ' -NoNewline
    While (($responseResults.content | ConvertFrom-Json).Reply.Status -eq 'Pending') {
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
        $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $jsonRequest 
    }

    # Output results as PSObject
    $convertedResponseResults = $responseResults.content | ConvertFrom-Json

    if ($convertedResponseResults.reply.results.data) {
        Return $convertedResponseResults.reply.results.data
    }
    elseif ($convertedResponseResults.reply.results.stream_id) {
        Write-Host $convertedResponseResults.reply.results.stream_id -ForegroundColor Cyan
        Invoke-CortexQueryResultsStream -stream_id $convertedResponseResults.reply.results.stream_id
    }
}

Function Invoke-CortexQueryResultsStream {
    param (
        [string]$stream_id        
    )
    
    #Test to see if auth context is avaliable
    Test-CortexAuthHeader

    # Prepare request for query results
    $requestData = @{
        request_data = @{
            stream_id = "$stream_id"
            is_gzip_compressed = $false
        }
    }

    # Convert the request to JSON
    $jsonRequest = $requestData | ConvertTo-Json -Depth 3

    # Build URL for "Get XQL Query Result"
    $apiName = "xql"
    $callName = "get_query_results_stream"
    $url = "$Script:fqdn/public_api/v1/$apiName/$callName/"

    # Send the request (POST)
    $responseResults = Invoke-WebRequest -Uri $url -Method Post -Headers $Script:headers -Body $jsonRequest
    
    # Output results as PSObject
    if ($responseResults.StatusCode -eq 200) {
           #$responseResults.Content
           $rawBytes = $responseResults.Content
            # If it's actually a string, convert to bytes:
            if (-not ($rawBytes -is [byte[]])) {
                $rawBytes = [System.Text.Encoding]::UTF8.GetBytes($rawBytes)
            }

            # Convert the raw bytes to a UTF-8 string
            $jsonLines = [System.Text.Encoding]::UTF8.GetString($rawBytes)

            # (Optional) If it's newline-delimited JSON objects, split and parse:
            $Objects = $jsonLines -split "`n" | ForEach-Object { $_ | ConvertFrom-Json }

            # Parse the JSON (if it's a single JSON blob)            
            $Objects
            
    }    
}
