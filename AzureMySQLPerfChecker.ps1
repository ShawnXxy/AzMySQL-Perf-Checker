$RepositoryBranch = 'master'

$CustomerRunningInElevatedMode = $false
if ($PSVersionTable.Platform -eq 'Unix') {
    if ((id -u) -eq 0) {
        $CustomerRunningInElevatedMode = $true
    }
}
else {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $CustomerRunningInElevatedMode = $true
    }
}
  
function Test-MySQLConnection {  
    param(  
        [string]$mysqlHost,  
        [System.Management.Automation.PSCredential]$credential  
    )  
  
    $username = $credential.UserName  
    $password = $credential.GetNetworkCredential().Password  
  
    $connectionString = "Server=$mysqlHost;Uid=$username;Pwd=$password;"  
  
    $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)  
    try {  
        $connection.Open()  
        if ($connection.State -ne 'Open') {  
            throw "Failed to connect to MySQL Server"  
        }  
    }  
    catch {  
        Write-Error "An error occurred: $($_.Exception.Message)"  
        Write-Host 
        Write-Host "Please double check the connection string and confirm network/firewall settings." -ForegroundColor Yellow
        Write-Host "You can leverage https://github.com/ShawnXxy/AzMySQL-Connectivity-Checker to further examine connectivity." 

        exit  
    }  
    finally {  
        $connection.Close()  
    }  
}  
function ExecuteMyQuery {  
    param(  
        [string]$mysqlHost,  
        [System.Management.Automation.PSCredential]$credential,  
        [string]$query  
    )  
  
    if ($null -eq $credential) {  
        Write-Error "No credentials provided, exiting..."  
        exit  
    }  
  
    $username = $credential.UserName  
    $password = $credential.GetNetworkCredential().Password  
  
    if ($null -eq $password) {  
        Write-Error "No password provided, exiting..."  
        exit  
    }  
  
    $connectionString = "Server=$mysqlHost;Uid=$username;Pwd=$password;"  
  
    $connection = New-Object MySql.Data.MySqlClient.MySqlConnection($connectionString)  
    $connection.Open()  
  
    $command = New-Object MySql.Data.MySqlClient.MySqlCommand($query, $connection)  
    $reader = $command.ExecuteReader()  
  
    $result = @()  
    while ($reader.Read()) {  
        $row = New-Object PSObject  
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {  
            $row | Add-Member -MemberType NoteProperty -Name $reader.GetName($i) -Value $reader.GetValue($i)  
        }  
        $result += $row  
    }  
  
    $connection.Close()  
  
    $result  
}  

Write-Host
Write-Host '********************************************' -ForegroundColor Green
Write-Host '*   Azure MySQL Performance Checker v1.0   *' -ForegroundColor Green
Write-Host '********************************************' -ForegroundColor Green
Write-Host
  
$mysqlHost = Read-Host "Enter MySQL host"  
$credential = Get-Credential -Message "Enter MySQL username and password"  
  
if ($null -eq $credential) {  
    Write-Error "No credentials provided, exiting..."  
    exit  
}  
  
if ($null -eq $credential.GetNetworkCredential().Password) {  
    Write-Error "No password provided, exiting..."  
    exit  
}  

# Test connection before running queries  
Test-MySQLConnection -mysqlHost $mysqlHost -credential $credential  

# Perf Query to be run
$query_processlist = "SELECT * FROM information_schema.processlist Order by TIME DESC;"
$query_innodb_status = "SHOW ENGINE INNODB STATUS;"

$serverVersionResult  = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query "SELECT VERSION();"
$query_blocks = @()
if ($serverVersionResult[0].'VERSION()'.StartsWith("8.")) {
    # for version 8+
    $query_blocks = "SELECT
    r.trx_wait_started AS wait_started,
    TIMEDIFF (NOW(), r.trx_wait_started) AS wait_age,
    TIMESTAMPDIFF (SECOND, r.trx_wait_started, NOW()) AS wait_age_secs,
    CONCAT(r1.OBJECT_SCHEMA, '.', r1.OBJECT_NAME) AS locked_table,
    r1.INDEX_NAME AS locked_index,
    r1.LOCK_TYPE AS locked_type,
    r.trx_id AS waiting_trx_id,
    r.trx_started AS waiting_trx_started,
    TIMEDIFF (NOW(), r.trx_started) AS waiting_trx_age,
    r.trx_rows_locked AS waiting_trx_rows_locked,
    r.trx_rows_modified AS waiting_trx_rows_modified,
    r.trx_mysql_thread_id AS waiting_pid,
    r.trx_query AS waiting_query,
    r1.ENGINE_LOCK_ID AS waiting_lock_id,
    r1.LOCK_MODE AS waiting_lock_mode,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_pid,
    b.trx_query AS blocking_query,
    b1.ENGINE_LOCK_ID AS blocking_lock_id,
    b1.LOCK_MODE AS blocking_lock_mode,
    b.trx_started AS blocking_trx_started,
    TIMEDIFF (NOW(), b.trx_started) AS blocking_trx_age,
    b.trx_rows_locked AS blocking_trx_rows_locked,
    b.trx_rows_modified AS blocking_trx_rows_modified,
    CONCAT('KILL QUERY ', b.trx_mysql_thread_id) AS sql_ki11_blocking_query,
    CONCAT('KILL ', b.trx_mysql_thread_id) AS sql_kill_blocking_connection
  FROM
    performance_schema.data_lock_waits w
    INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID
    INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
    INNER JOIN performance_schema.data_locks b1 ON b1.ENGINE_LOCK_ID = w.BLOCKING_ENGINE_LOCK_ID
    INNER JOIN performance_schema.data_locks r1 ON r1.ENGINE_LOCK_ID = w.REQUESTING_ENGINE_LOCK_ID
  ORDER BY  r.trx_wait_started;
  "
} else {
    # innodb_lock_waits only exists in MySQL 5.7
    $query_blocks = "SELECT
    r.trx_wait_started AS wait_started,
    TIMEDIFF (NOW(), r.trx_wait_started) AS wait_age,
    TIMESTAMPDIFF (SECOND, r.trx_wait_started, NOW()) AS wait_age_secs,
    r1.lock_table AS locked_table,
    r1.lock_index AS locked_index,
    r1.lock_type AS locked_type,
    r.trx_id AS waiting_trx_id,
    r.trx_started AS waiting_trx_started,
    TIMEDIFF (NOW(), r.trx_started) AS waiting_trx_age,
    r.trx_rows_locked AS waiting_trx_rows_locked,
    r.trx_rows_modified AS waiting_trx_rows_modified,
    r.trx_mysql_thread_id AS waiting_pid,
    sys.format_statement(r.trx_query) AS waiting_query,
    r1.lock_id AS waiting_lock_id,
    r1.lock_mode AS waiting_lock_mode,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_pid,
    sys.format_statement(b.trx_query) AS blocking_query,
    b1.lock_id AS blocking_lock_id,
    b1.lock_mode AS blocking_lock_mode,
    b.trx_started AS blocking_trx_started,
    TIMEDIFF (NOW(), b.trx_started) AS blocking_trx_age,
    b.trx_rows_locked AS blocking_trx_rows_locked,
    b.trx_rows_modified AS blocking_trx_rows_modified,
    CONCAT('KILL QUERY ', b.trx_mysql_thread_id) AS sql_ki11_blocking_query,
    CONCAT('KILL ', b.trx_mysql_thread_id) AS sql_kill_blocking_connection
  FROM
    information_schema.innodb_lock_waits w
    INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
    INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
    INNER JOIN information_schema.innodb_locks b1 ON b1.lock_id = w.blocking_lock_id
    INNER JOIN information_schema.innodb_locks r1 ON r1.lock_id = w.requested_lock_id
  ORDER BY  r.trx_wait_started;
  "
}

$query_mdl = "SELECT
g.object_schema AS object_schema,
g.object_name AS object_name,
pt.thread_id AS waiting_thread_id,
pt.processlist_id AS waiting_pid,
sys.ps_thread_account(p.owner_thread_id) AS waiting_account,
p.lock_type AS waiting_lock_type,
p.lock_duration AS waiting_lock_duration,
sys.format_statement(pt.processlist_info) AS waiting_query,
pt.processlist_time AS waiting_query_secs,
ps.rows_affected AS waiting_query_rows_affected,
ps.rows_examined AS waiting_query_rows_examined,
gt.thread_id AS blocking_thread_id,
gt.processlist_id AS blocking_pid,
sys.ps_thread_account(g.owner_thread_id) AS blocking_account,
g.lock_type AS blocking_lock_type,
g.lock_duration AS blocking_lock_duration,
CONCAT ('KILL QUERY ', gt.processlist_id) AS sql_kill_blocking_query,
CONCAT ('KILL ', gt.processlist_id) AS sql_kill_blocking_connection
FROM
performance_schema.metadata_locks g
INNER JOIN performance_schema.metadata_locks p ON g.object_type = p.object_type
AND g.object_schema = p.object_schema
AND g.object_name = p.object_name
AND g.lock_status = 'GRANTED'
AND p.lock_status = 'PENDING'
INNER JOIN performance_schema.threads gt ON g.owner_thread_id = gt.thread_id
INNER JOIN performance_schema.threads pt ON p.owner_thread_id = pt.thread_id
LEFT JOIN performance_schema.events_statements_current gs ON g.owner_thread_id = gs.thread_id
LEFT JOIN performance_schema.events_statements_current ps ON p.owner_thread_id = ps.thread_id
WHERE
g.object_type = 'TABLE';
"

$query_current_wait = "select sys.format_time(SuM(TIMER_WAIT)) as TIMER_WAIT_SEC, sys.format_bytes(SUM(NUMBER_OF_BYTES)) as NUMBER_OF_BYTES, EVENT_NAME, OPERATION from performance_schema.events_waits_current where EVENT_NAME != 'idle' group by EVENT_NAME,OPERATION order by TIMER_WAIT_SEC desc; "

$query_stmt_fulltablescan = "SELECT
sys.format_Statement(DIGEST_TEXT) AS query,
SCHEMA_NAME AS db,
COUNT_STAR AS EXEC_COUNT,
sys.format_time(SUM_TIMER_WAIT) AS total_latency,
SUM_NO_INDEX_USED AS NO_index_used_count,
SUM_NO_GOOD_INDEX_USED AS no_good_index_used_count,
ROUND (
  ifnull(SUM_NO_INDEX_USED / NULLIF (COUNT_STAR, 0), 0) * 100
) AS NO_index_used_pct,
SUM_ROWS_SENT AS rows_sent,
SUM_ROWS_EXAMINED AS rows_examined,
ROUND (SUM_ROWS_SENT / COUNT_STAR) AS rows_sent_avg,
ROUND (SUM_ROWS_EXAMINED / COUNT_STAR) AS rows_examined_avg,
FIRST_SEEN AS first_seen,
LAST_SEEN AS last_seen,
DIGEST AS digest
FROM
performance_schema.events_statements_summary_by_digest
WHERE
(
  SUM_NO_INDEX_USED > 0
  OR SUM_NO_GOOD_INDEX_USED > 0
)
AND DIGEST_TEXT NOT LIKE 'SHOW%'
ORDER BY
no_index_used_pct DESC,
total_latency DESC;"

$query_stmt_filesort = "SELECT
sys.format_statement (DIGEST_TEXT) AS query,
SCHEMA_NAME db,
COUNT_STAR AS EXEC_COUNT,
sys.format_TIME(SUM_TIMER_WAIT) AS total_Latency,
SUM_SORt_MERGE_PASSES AS sort_merge_passes,
ROUND (
  IFNULL(SUM_SORT_MERGE_PASSES / NULLIF(COUNT_STAR, 0), 0)
) AS avg_sort_merges,
SUM_SORT_SCAN AS sorts_using_scans,
SUM_SORT_RANGE AS sort_using_range,
SUM_SORT_ROWS AS rows_sorted,
ROUND (IFNULL(SUM_SORT_ROWS / NULLIF(COUNT_STAR, 0), 0)) AS avg_rows_sorted,
FIRST_SEEN AS first_seen,
LAST_SEEN AS last_seen,
DIGEST AS digest
FROM
performance_schema.events_statements_summary_by_digest
WHERE
SUM_SORT_ROWS > 0
ORDER BY
SUM_TIMER_WAIT DESC;"

$query_stmt_tmptables = "SELECT
sys.format_statement (DIGEST_TEXT) AS query,
SCHEMA_NAME AS db,
COUNT_STAR AS exec_count,
sys.format_time(SUM_TIMER_WAIT) AS total_latency,
SUM_CREATED_TMP_TABLES AS memory_tmp_tables,
SUM_CREATED_TMP_DISK_TABLES AS disk_tmp_tables,
ROUND (
  IFNULL(SUM_CREATED_TMP_TABLES / NULLIF (COUNT_STAR, 0), 0)
) AS avg_tmp_tables_per_query,
ROUND (
  IFNULL (
    SUM_CREATED_TMP_DISK_TABLES / NULLIF(SUM_CREATED_TMP_TABLES, 0),
    0
  ) * 100
) AS tmp_tables_to_disk_pct,
FIRST_SEEN AS first_seen,
LAST_SEEN AS last_seen,
DIGEST AS digest
FROM
performance_schema.events_statements_summary_bY_digest
WHERE
SUM_CREATED_TMP_TABLES > 0
ORDER BY
SUM_CREATED_TMP_DISK_TABLES DESC,
SUM_CREATED_TMP_TABLES DESC;"

$query_file_io = "Select * from sys.io_global_by_file_by_bytes;"
$query_table_buffer = "Select * from sys.schema_table_statistics_with_buffer;"
  
try {
    $canWriteFiles = $true
    try {
        $logsFolderName = 'AzureExecuteMyQueryResults'
        Set-Location -Path $env:TEMP
        If (!(Test-Path $logsFolderName)) {
            New-Item $logsFolderName -ItemType directory | Out-Null
            Write-Host 'The folder' $logsFolderName 'was created and all logs will be sent to this folder.'
        }
        else {
            Write-Host 'The folder' $logsFolderName 'already exists and all logs will be sent to this folder.'
        }

        # Create folder in Temp directory and subfolder named based on UTC timestamp
        $folderPath = Join-Path $env:TEMP ($logsFolderName + "\" + (Get-Date -Format "yyyyMMddHHmmss"))  
        New-Item -ItemType Directory -Force -Path $folderPath  

        $MySQLDllPath = Join-Path ((Get-Location).Path) "MySql.Data.dll"
        if ($Local) {
            Copy-Item -Path $($LocalPath + '/lib/MySql.Data.dll') -Destination $MySQLDllPath
        }
        else {
            #ShawnXxy/AzMySQL-Perf-Checker
            Invoke-WebRequest -Uri $('https://github.com/ShawnXxy/AzMySQL-Perf-Checker/raw/' + $RepositoryBranch + '/lib/MySql.Data.dll') -OutFile $MySQLDllPath -UseBasicParsing
        }
        $assembly = [System.IO.File]::ReadAllBytes($MySQLDllPath)
        [System.Reflection.Assembly]::Load($assembly) | Out-Null

    }
    catch {
        $canWriteFiles = $false
        Write-Host "Warning: Cannot write log file." -ForegroundColor Yellow
    }

    try {

        $result_processlist = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_processlist 
        $result_innodb_status = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_innodb_status  
        $result_blocks = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_blocks  
        $result_mdl = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_mdl  
        $result_current_wait = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_current_wait  
        $result_stmt_fulltablescan = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_stmt_fulltablescan  
        $result_stmt_filesort = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_stmt_filesort
        $result_stmt_tmptables = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_stmt_tmptables
        $result_file_io = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_file_io
        $result_table_buffer = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query $query_table_buffer
    
        #  Save each result in independent file
        $file_processlist = Join-Path $folderPath "processlist.csv"  
        $file_innodb_status = Join-Path $folderPath "innodb_status.log"  
        $file_blocks = Join-Path $folderPath "blocks.csv"  
        $file_current_wait = Join-Path $folderPath "current_wait.csv"  
        $file_mdl = Join-Path $folderPath "mdl.csv"  
        $file_stmt_fulltablescan = Join-Path $folderPath "stmt_fulltablescan.csv"
        $file_stmt_filesort = Join-Path $folderPath "stmt_filesort.csv"
        $file_stmt_tmptables = Join-Path $folderPath "stmt_tmptables.csv"
        $file_file_io = Join-Path $folderPath "file_io.csv"
        $file_table_buffer = Join-Path $folderPath "table_buffer.csv"
    
        $result_processlist | Export-Csv -Path $file_processlist -NoTypeInformation  
        $result_innodb_status | Export-Csv -Path $file_innodb_status -NoTypeInformation  
        $result_blocks | Export-Csv -Path $file_blocks -NoTypeInformation  
        $result_mdl | Export-Csv -Path $file_mdl -NoTypeInformation  
        $result_current_wait | Export-Csv -Path $file_current_wait -NoTypeInformation  
        $result_stmt_fulltablescan | Export-Csv -Path $file_stmt_fulltablescan -NoTypeInformation
        $result_stmt_filesort | Export-Csv -Path $file_stmt_filesort -NoTypeInformation
        $result_stmt_tmptables | Export-Csv -Path $file_stmt_tmptables -NoTypeInformation
        $result_file_io | Export-Csv -Path $file_file_io -NoTypeInformation
        $result_table_buffer | Export-Csv -Path $file_table_buffer -NoTypeInformation
        
    
        if ($canWriteFiles) {
            
            Write-Host Log file can be found at (Get-Location).Path

            Write-Host "=========================================================================================="
            Write-Host $"Results were written to Temp directory."
            Write-Host $"For Windows OS, the folder will be openned once logging completed."
            Write-Host $"For Linux OS, please find the log files in path /tmp/AzureExecuteMyQueryResults."
            Write-Host ""

            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {  
                Start-Process $folderPath  
            }

            if ($PSVersionTable.Platform -eq 'Unix') {
                
                Get-ChildItem
            }
            else {
                Invoke-Item (Get-Location).Path
            }

            Remove-Item ".\MySql.Data.dll" -Force
        }
    }
    catch {
        Write-Host
        Write-Host 'Script Execution Terminated Due to Exceptions' -ForegroundColor Yellow
        Write-Host 'No logs are saved' -ForegroundColor Yellow
    }
} 
catch {
    Write-Host
    Write-Host 'Something goes wrong...' -ForegroundColor Yellow
}










