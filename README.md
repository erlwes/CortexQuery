# PSCortexXQL
Run XQL-queries vs. Palo Alto Cortex/XSIAM API using PowerShell.

Work in progress ...

```PowerShell
. .\Cortex-module.ps1
Set-CortexAuthHeader -keyID $key_id -key $key -fqdn $fqdn
$query = 'dataset=microsoft_eventlog_raw | filter _raw_log contains "SRV-DC-02"'
$results = Invoke-CortexQueryRequest -Query $query -resultLimit 8000 -relativeTime 30m
$results | Out-GridView
```
