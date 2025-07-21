# CortexQuery
A PowerShell module for running XQL queries against Palo Alto Networks Cortex XSIAM/XDR APIs.

## 📦 Installation

Install the module from PowerShell Gallery:

```powershell
Install-Module -Name CortexQuery
```

---

## 🚀 Quickstart

```powershell
# Step 1: Set up API authentication context
$keyId = 99
$fqdn = "https://api-[CUSTOMER_ID].xdr.eu.paloaltonetworks.com"
$key = "[Your 128-character API key]"

Set-CortexAuthHeader -keyId $keyId -fqdn $fqdn -key $key

# Step 2: Define and run a query
$query = @'
    dataset = cloud_audit_logs
    | filter log_name = "azure_ad_signin_logs"
    | limit 1
'@

$results = Invoke-CortexQuery -Query $query -relativeTime 1h -VerboseLogging

# Step 3: Parse a raw JSON result
$results.raw_log | ConvertFrom-Json
```

---

## 💻 Cmdlets

### `Set-CortexAuthHeader`

Sets the authentication context for Cortex/XSIAM API access.

| Parameter | Type   | Required | Description                               |
|-----------|--------|----------|-------------------------------------------|
| `keyId`   | Int    | Yes      | API key ID                                |
| `key`     | String | Yes      | Secret API key string (128 characters)    |
| `fqdn`    | String | Yes      | Base API URL (e.g., `https://api-xxx.xdr.eu.paloaltonetworks.com`) |

---

### `Invoke-CortexQuery`

Submits an XQL query and retrieves results.

| Parameter        | Type   | Required | Description                                                          |
|------------------|--------|----------|----------------------------------------------------------------------|
| `Query`          | String | Yes      | The XQL query to execute                                             |
| `relativeTime`   | String | No       | Time window (e.g. `1d`, `2h`, `30m`) — default is `1d`               |
| `resultLimit`    | Int    | No       | Maximum results to return — default is `100`                        |
| `VerboseLogging` | Switch | No       | Enables detailed debug output during request and polling            |

---

## 📚 References
These API calls are used: `start_xql_query`, `get_query_results` and `get_query_results_stream` along with auth header
- [Cortex XDR API Docs - Auth](https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/API-Reference)
- [Start XQL Query](https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Start-an-XQL-Query)
- [Get XQL Query Results](https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Get-XQL-Query-Results)
- [Get XQL Query Results Steam]([https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Get-XQL-Query-Results](https://docs-cortex.paloaltonetworks.com/r/Cortex-XDR-REST-API/Get-XQL-Query-Results-Stream)

---
