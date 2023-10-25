[System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
  
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

function Execute-MySQLQuery {  
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

# Perf Query to be run
$query_processlist = "SHOW FULL PROCESSLIST;"
$query_innodb_status = "SHOW ENGINE INNODB STATUS;"
# innodb_lock_waits only exists in MySQL 5.7
$query_blocks = "SELECT r.trx_mysql_thread_id waiting_thread, r.trx_query waiting_query, concat(timestampdiff(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP()), 's') AS duration, b.trx_mysql_thread_id blocking_thread, t.processlist_command state, b.trx_query blocking_current_query, e.sql_text blocking_last_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id JOIN performance_schema.threads t on t.processlist_id = b.trx_mysql_thread_id JOIN performance_schema.events_statements_current e USING(thread_id); "
$query_mdl = "SELECT OBJECT_TYPE, OBJECT_SCHEMA, OBJECT_NAME, LOCK_TYPE, LOCK_STATUS, THREAD_ID, PROCESSLIST_ID, PROCESSLIST_INFO FROM performance_schema.metadata_locks INNER JOIN performance_schema.threads ON THREAD_ID = OWNER_THREAD_ID WHERE PROCESSLIST_ID<> CONNECTION_ID(); "
$query_concurrent_ticket = "SELECT OBJECT_TYPE, OBJECT_SCHEMA, OBJECT_NAME, LOCK_TYPE, LOCK_STATUS, THREAD_ID, PROCESSLIST_ID, PROCESSLIST_INFO FROM performance_schema.metadata_locks INNER JOIN performance_schema.threads ON THREAD_ID = OWNER_THREAD_ID WHERE PROCESSLIST_ID<> CONNECTION_ID(); "
$query_current_wait = "select sys.format_time(SuM(TIMER_WAIT)) as TIMER_WAIT_SEC, sys.format_bytes(SUM(NUMBER_OF_BYTES)) as NUMBER_OF_BYTES, EVENT_NAME, OPERATION from performance_schema.events_waits_current where EVENT_NAME != 'idle' group by EVENT_NAME,OPERATION order by TIMER_WAIT_SEC desc; "
  
try {
    Clear-Host
    $canWriteFiles = $true
    try {
        $logsFolderName = 'AzureMySQLPerfCheckerResults'
        Set-Location -Path $env:TEMP
        If (!(Test-Path $logsFolderName)) {
            New-Item $logsFolderName -ItemType directory | Out-Null
            Write-Host 'The folder' $logsFolderName 'was created and all logs will be sent to this folder.'
        }
        else {
            Write-Host 'The folder' $logsFolderName 'already exists and all logs will be sent to this folder.'
        }

        # Create folder in Temp directory and subfolder named based on UTC timestamp
        $folderPath = Join-Path $env:TEMP (logsFolderName + "\" + (Get-Date -Format "yyyyMMddHHmmss"))  
        New-Item -ItemType Directory -Force -Path $folderPath  

        $MySQLDllPath = Join-Path ((Get-Location).Path) "MySql.Data.dll"
        if ($Local) {
            Copy-Item -Path $($LocalPath + '/lib/MySql.Data.dll') -Destination $MySQLDllPath
        }
        else {
            #ShawnXxy/AzMySQL-Connectivity-Checker
            Invoke-WebRequest -Uri $('https://github.com/ShawnXxy/AzMySQL-Perf-Checker/raw/' + $RepositoryBranch + '/lib/MySql.Data.dll') -OutFile $MySQLDllPath -UseBasicParsing
        }
        $assembly = [System.IO.File]::ReadAllBytes($MySQLDllPath)
        [System.Reflection.Assembly]::Load($assembly) | Out-Null

    }
    catch {
        $canWriteFiles = $false
        Write-Host Warning: Cannot write log file -ForegroundColor Yellow
    }

    try {
        $result_processlist = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_processlist  
        $result_innodb_status = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_innodb_status  
        $result_blocks = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_blocks  
        $result_mdl = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_mdl  
        $result_concurrent_ticket = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_concurrent_ticket  
        $result_current_wait = Execute-MySQLQuery -mysqlHost $mysqlHost -credential $credential -query $query_current_wait  
    
    
    
        #  Save each result in independent file
        $file_processlist = Join-Path $folderPath "processlist.csv"  
        $file_innodb_status = Join-Path $folderPath "innodb_status.log"  
        $file_blocks = Join-Path $folderPath "blocks.csv"  
        $file_current_wait = Join-Path $folderPath "current_wait.csv"  
        $file_mdl = Join-Path $folderPath "mdl.csv"  
        $file_concurrent_ticket = Join-Path $folderPath "concurrent_ticket.csv"  
    
        
        $result_processlist | Export-Csv -Path $file_processlist -NoTypeInformation  
        $result_innodb_status | Export-Csv -Path $file_innodb_status -NoTypeInformation  
        $result_blocks | Export-Csv -Path $file_blocks -NoTypeInformation  
        $result_mdl | Export-Csv -Path $file_mdl -NoTypeInformation  
        $result_concurrent_ticket | Export-Csv -Path $file_concurrent_ticket -NoTypeInformation  
        $result_current_wait | Export-Csv -Path $file_current_wait -NoTypeInformation  
    
        
        if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {  
            Start-Process $folderPath  
        }  
        
    }
    catch {
        Write-Host
        Write-Host 'Script Execution Terminated Due to Exceptions' -ForegroundColor Yellow
    }
    
}
finally {
    if ($canWriteFiles) {
        Remove-Item ".\MySql.Data.dll" -Force
        Write-Host Log file can be found at (Get-Location).Path
        if ($PSVersionTable.PSVersion.Major -ge 5) {
            $destAllFiles = (Get-Location).Path + '/AllFiles.zip'
            Compress-Archive -Path ((Get-Location).Path + '/*.csv'), ((Get-Location).Path + '/*.log') -DestinationPath $destAllFiles -Force
            Write-Host 'A zip file with all the files can be found at' $destAllFiles -ForegroundColor Green
        }
        if ($PSVersionTable.Platform -eq 'Unix') {
            
            Get-ChildItem
        }
        else {
            Invoke-Item (Get-Location).Path
        }

       
    }
}









