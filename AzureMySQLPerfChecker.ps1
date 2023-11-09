using namespace System
using namespace MySql.Data.MySqlClient

$RepositoryBranch = 'master'

$summaryLog = New-Object -TypeName "System.Text.StringBuilder"

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
  
    $connection = [MySql.Data.MySqlClient.MySqlConnection]@{connectionString = $connectionString }
    try {  
        Write-Host
        Write-Host ([string]::Format("Testing MySQL connection to server {0} (please wait):", $mysqlHost)) -ForegroundColor Yellow
        $connection.Open()  
        if ($connection.State -ne 'Open') {  
            throw "Failed to connect to MySQL Server"  
        }
        else {
            Write-Host
            Write-Host ([string]::Format("The connection to server {0} succeeded.", $mysqlHost)) -ForegroundColor Green
        }
    }  
    catch  [MySql.Data.MySqlClient.MySqlException] {  
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

    try {
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

        if ($result.length -eq 0) {
            $result = @(" ")
        }

        $result  

    }
    catch {  
        Write-Error "An error occurred: $($_.Exception.Message)"

    }
    finally {  

        $connection.Close()  
        
    }
  
} 


function Get-SqlExplanation {  
    param (  
        [Parameter(Mandatory = $true)]  
        [string] $query  
    )  
  
    $OPENAI_API_BASE = "https://orcas-my-perf.openai.azure.com/"  
    $OPENAI_API_KEY = "f34be517035d4c64bcb993256a5b5130"  
    $deployments = "orcas-gpt35-intruct"  
  
    $temperature = 0.8  
    $max_tokens = 300  
    $top_n = 0.95  
    $frequency_penalty = 0  
    $presence_penalty = 0  
  
    $prompt = "Below is a MySQL SQL statement. Please explain the purpose of the query from a professional MySQL DBA prospect within 100 words.[start of SQL]" + $query + "[end of SQL]"  
  
    $chatCompletions = @{  
        "prompt"            = $prompt  
        "temperature"       = $temperature  
        "max_tokens"        = $max_tokens  
        "top_p"             = $top_n  
        "frequency_penalty" = $frequency_penalty  
        "presence_penalty"  = $presence_penalty  
    }  

  
    $headers = @{  
        "api-key" = $OPENAI_API_KEY
    }  
  
    $url = $OPENAI_API_BASE + "openai/deployments/" + $deployments + "/completions?api-version=2023-07-01-preview"
    $response = Invoke-RestMethod -Method Post -Uri $url -Body ($chatCompletions | ConvertTo-Json -Depth 2) -ContentType "application/json" -Headers $headers  
  
    return $response.choices[0].text  
}  

function Get-OutputAnalysis {  
    param (  
        [Parameter(Mandatory = $true)]  
        [string] $output  
    )  
  
    $OPENAI_API_BASE = "https://orcas-my-perf.openai.azure.com/"  
    $OPENAI_API_KEY = "f34be517035d4c64bcb993256a5b5130"  
    $deployments = "orcas-gpt35-intruct"  
  
    $temperature = 0.75  
    $max_tokens = 800  
    $top_n = 0.95  
    $frequency_penalty = 0  
    $presence_penalty = 0  
  
    $prompt = "Below is an output returned from MySQL system table used to analyze MySQL performance status. Please intepret and summarize the output from an experienced MySQL DBA prospect following below instructions: 1-Highlight the key information of the output; 2-highlight the potential performance impact based on the data returned in the ouput; 3-gave professional suggestions; 3-if no data output returned or passed in, please ignore above instructions and respond no data returned.[start of Output]" + $output + "[end of Output]"  
  
    $chatCompletions = @{  
        "prompt"            = $prompt  
        "temperature"       = $temperature  
        "max_tokens"        = $max_tokens  
        "top_p"             = $top_n  
        "frequency_penalty" = $frequency_penalty  
        "presence_penalty"  = $presence_penalty  
    }  
  
    $headers = @{  
        "api-key" = $OPENAI_API_KEY
    }  
  
    $url = $OPENAI_API_BASE + "openai/deployments/" + $deployments + "/completions?api-version=2023-07-01-preview"
    $response = Invoke-RestMethod -Method Post -Uri $url -Body ($chatCompletions | ConvertTo-Json -Depth 2) -ContentType "application/json" -Headers $headers  
  
    return $response.choices[0].text  
}  
  
try {
    $canWriteFiles = $true
    try {
        $logsFolderName = 'AzureMySQLPerfCheckerResults'
        Set-Location -Path $env:TEMP
        If (!(Test-Path $logsFolderName)) {
            New-Item $logsFolderName -ItemType directory | Out-Null

            Write-Host
            Write-Host 'The folder' $logsFolderName 'was created and all logs will be sent to this folder.'
        }
        else {
            Write-Host
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

        Write-Host "Please select below option cautiously:" -ForegroundColor Yellow
        Write-Host "    - if you select 'Y', meaning you willaAllow Azure OpenAI to analyze the output and provide auto-analysis. Please note, ONLY returned output will be used for Azure OpenAI analysis." -ForegroundColor Yellow
        Write-Host "    - if you select 'N' or any other answers(leave it blank), meaning you will NOT allow Azure OpenAI to analyze the output and provide auto-analysis. The output will be saved in the log file but no auto-analysis will be provided." -ForegroundColor Yellow
        $allowAzOpenAI = Read-Host "Allow Azure OpenAI to analyze the output? (Y/N)"
        if ($allowAzOpenAI -eq "Y") {
            $allowAzOpenAI = $true
            Write-Host "You have granted permission to allow Azure OpenAI to access the query output for auto analysis!" -ForegroundColor Yellow
        }
        else {
            $allowAzOpenAI = $false            
            Write-Host "You have NOT granted permission to Azure OpenAI to access the query output for auto analysis!" -ForegroundColor Yellow
        }
        $disclamer_ai_access = "Need permission to access output. Currently no result because permisson is denied. (N is selected) "

        # Test connection before running queries  
        Test-MySQLConnection -mysqlHost $mysqlHost -credential $credential  

        $serverVersionResult = ExecuteMyQuery -mysqlHost $mysqlHost -credential $credential -query "SELECT VERSION();"
        Write-Host "MySQL Server Version: " $serverVersionResult[0].'VERSION()'
        Write-Host

        Write-Host "Preparing to run queries..." -ForegroundColor Yellow

        # Perf Query to be run
        $query_processlist = "SELECT * FROM information_schema.processlist Order by TIME DESC;"
        $query_innodb_status = "SHOW ENGINE INNODB STATUS;"

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
        }
        else {
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

        $summary_processlist = $disclamer_ai_access
        $summary_innodb_status = $disclamer_ai_access
        $summary_blocks = $disclamer_ai_access
        $summary_mdl = $disclamer_ai_access
        $summary_current_wait = $disclamer_ai_access
        $summary_stmt_fulltablescan = $disclamer_ai_access
        $summary_stmt_filesort = $disclamer_ai_access
        $summary_stmt_tmptables = $disclamer_ai_access
        if ($allowAzOpenAI) {
            Write-Host "Since you selected Y to allow Azure OpenAI to analyze the output, please wait for a few minutes for the auto-analysis to complete."
            $summary_processlist = Get-OutputAnalysis -output ($result_processlist | Format-Table | Out-String)
            $summary_innodb_status = Get-OutputAnalysis -output ($result_innodb_status | Format-Table | Out-String)
            $summary_blocks = Get-OutputAnalysis -output ($result_blocks | Format-Table | Out-String)
            $summary_mdl = Get-OutputAnalysis -output ($result_mdl | Format-Table | Out-String)
            $summary_current_wait = Get-OutputAnalysis -output ($result_current_wait | Format-Table | Out-String)
            $summary_stmt_fulltablescan = Get-OutputAnalysis -output ($result_stmt_fulltablescan | Format-Table | Out-String)
            $summary_stmt_filesort = Get-OutputAnalysis -output ($result_stmt_filesort | Format-Table | Out-String)
            $summary_stmt_tmptables = Get-OutputAnalysis -output ($result_stmt_tmptables | Format-Table | Out-String)  
        } 
        Write-Host

        $sqlExplain_processlist = Get-SqlExplanation -query $query_processlist
        Write-Host "#################################################################################"
        Write-Host "Start to print processlist result. " -ForegroundColor Yellow
        Write-Host $sqlExplain_processlist
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_processlist | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_processlist -ForegroundColor Gray
        Write-Host

        $sqlExplain_innodb_status = Get-SqlExplanation -query $query_innodb_status
        Write-Host "#################################################################################"
        Write-Host "Start to print InnoDB Status." -ForegroundColor Yellow
        Write-Host $sqlExplain_innodb_status
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host $result_innodb_status
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_innodb_status -ForegroundColor Gray
        Write-Host

        $sqlExplain_blocks = Get-SqlExplanation -query $query_blocks
        Write-Host "#################################################################################"
        Write-Host "Start to collect current blockings." -ForegroundColor Yellow
        Write-Host $sqlExplain_blocks
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_blocks | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_blocks -ForegroundColor Gray
        Write-Host

        $sqlExplain_mdl = Get-SqlExplanation -query $query_mdl
        Write-Host "#################################################################################"
        Write-Host "Start to collect current MDL." -ForegroundColor Yellow
        Write-Host $sqlExplain_mdl
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_mdl | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_mdl -ForegroundColor Gray
        Write-Host

        $sqlExplain_current_wait = Get-SqlExplanation -query $query_current_wait
        Write-Host "#################################################################################"
        Write-Host "Start to print current wait events. " -ForegroundColor YelloW     
        Write-Host $sqlExplain_current_wait       
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_current_wait | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_current_wait -ForegroundColor Gray
        Write-Host

        $sqlExplain_stmt_fulltablescan = Get-SqlExplanation -query $query_stmt_fulltablescan
        Write-Host "#################################################################################"
        Write-Host "Start to print SQL statements with full-table-scan. " -ForegroundColor Yellow
        Write-Host $sqlExplain_stmt_fulltablescan
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_stmt_fulltablescan | Format-Table | Out-String)
        Write-Host
        Write-Host $summary_stmt_fulltablescan -ForegroundColor Gray
        Write-Host

        $sqlExplain_stmt_filesort = Get-SqlExplanation -query $query_stmt_filesort           
        Write-Host "#################################################################################"
        Write-Host "Start to print SQL statements with file-sort." -ForegroundColor Yellow
        Write-Host $sqlExplain_stmt_filesort
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_stmt_filesort | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_stmt_filesort -ForegroundColor Gray
        Write-Host

        $sqlExplain_stmt_tmptables = Get-SqlExplanation -query $query_stmt_tmptables
        Write-Host "#################################################################################"
        Write-Host "Start to print SQL statements used temp tables. Please wait..." -ForegroundColor Yellow
        Write-Host $sqlExplain_stmt_tmptables
        Write-Host "Please wait..." -ForegroundColor Yellow
        Write-Host "#################################################################################"
        Write-Host ($result_stmt_tmptables | Format-Table | Out-String)
        Write-Host
        Write-Host "Auto-Analysis:" -ForegroundColor Yellow
        Write-Host $summary_stmt_tmptables -ForegroundColor Gray
        Write-Host

    
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

            Write-Host
            Write-Host "#################################################################################"
            Write-Host Log file can be found at (Get-Location).Path
            Write-Host $"For Windows OS, the folder will be openned once logging completed."
            Write-Host 

            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {  
                Start-Process $folderPath  
            }

            if ($PSVersionTable.Platform -eq 'Unix') {
                
                Get-ChildItem
            }
            else {
                Invoke-Item (Get-Location).Path
            }

        }    

           
    }
    catch {
        Write-Host
        Write-Error "Script Execution Terminated Due to Exceptions: $($_.Exception.Message)"
        Write-Host 'No logs are saved' -ForegroundColor Yellow
    }
    finally {
        if ($canWriteFiles) {
            
            Remove-Item ".\MySql.Data.dll" -Force
        }

    }
} 
catch {
    Write-Host
    Write-Host 'Something goes wrong...' -ForegroundColor Yellow
    Write-Error $($_.Exception.Message)
}










