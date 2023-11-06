using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security;
using MySql.Data.MySqlClient;
using System.Threading.Tasks;
using System.Security.Policy;
using System.Threading;

class Program
{
    static async Task Main(string[] args)
    {
        Console.WriteLine("**********************************************");
        Console.WriteLine("*    Azure MySQL Perfromance Checker V1.0    *");
        Console.WriteLine("**********************************************");

        // Console Input
        Console.Write("Enter MySQL host: ");
        string host = Console.ReadLine();

        Console.Write("Enter MySQL username: ");
        string username = Console.ReadLine();

        Console.Write("Enter MySQL password: ");
        SecureString password = GetPassword();

        Console.Write("Allow Azure OpenAI access to the result for auto analysis? (Y/N): ");
        string allowAIAccess = Console.ReadLine();

        string connectionString = $"Server={host};Uid={username};Pwd={ConvertToUnsecureString(password)};";

        using (MySqlConnection connection = new MySqlConnection(connectionString))
        {
            try
            {
                Console.WriteLine("");
                Console.WriteLine("Start to test connecivity to target MySQL!");

                await connection.OpenAsync();
                                
                if (connection.State == System.Data.ConnectionState.Open)
                {

                    
                    Console.WriteLine($"Connection made to {host} is successful.\n");
                    Console.WriteLine("Starting to collect performance status... \n");
                    Console.WriteLine("");

                    // Perf Query to be run
                    string query_processlist = "SELECT * FROM information_schema.processlist Order by TIME DESC;";
                    string query_innodb_status = "SHOW ENGINE INNODB STATUS;";

                    string serverVersion = await GetServerVersionAsync(connectionString);
                    Console.WriteLine($"Target MySQL Version is {serverVersion}.\n");
                    Console.WriteLine("");

                    string query_blocks;
                    if (serverVersion.StartsWith("8."))
                    {
                        // for version 8+
                        query_blocks = "SELECT\r\n  r.trx_wait_started AS wait_started,\r\n  TIMEDIFF (NOW(), r.trx_wait_started) AS wait_age,\r\n  TIMESTAMPDIFF (SECOND, r.trx_wait_started, NOW()) AS wait_age_secs,\r\n  CONCAT(r1.OBJECT_SCHEMA, '.', r1.OBJECT_NAME) AS locked_table,\r\n  r1.INDEX_NAME AS locked_index,\r\n  r1.LOCK_TYPE AS locked_type,\r\n  r.trx_id AS waiting_trx_id,\r\n  r.trx_started AS waiting_trx_started,\r\n  TIMEDIFF (NOW(), r.trx_started) AS waiting_trx_age,\r\n  r.trx_rows_locked AS waiting_trx_rows_locked,\r\n  r.trx_rows_modified AS waiting_trx_rows_modified,\r\n  r.trx_mysql_thread_id AS waiting_pid,\r\n  r.trx_query AS waiting_query,\r\n  r1.ENGINE_LOCK_ID AS waiting_lock_id,\r\n  r1.LOCK_MODE AS waiting_lock_mode,\r\n  b.trx_id AS blocking_trx_id,\r\n  b.trx_mysql_thread_id AS blocking_pid,\r\n  b.trx_query AS blocking_query,\r\n  b1.ENGINE_LOCK_ID AS blocking_lock_id,\r\n  b1.LOCK_MODE AS blocking_lock_mode,\r\n  b.trx_started AS blocking_trx_started,\r\n  TIMEDIFF (NOW(), b.trx_started) AS blocking_trx_age,\r\n  b.trx_rows_locked AS blocking_trx_rows_locked,\r\n  b.trx_rows_modified AS blocking_trx_rows_modified,\r\n  CONCAT('KILL QUERY ', b.trx_mysql_thread_id) AS sql_ki11_blocking_query,\r\n  CONCAT('KILL ', b.trx_mysql_thread_id) AS sql_kill_blocking_connection\r\nFROM\r\n  performance_schema.data_lock_waits w\r\n  INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID\r\n  INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID\r\n  INNER JOIN performance_schema.data_locks b1 ON b1.ENGINE_LOCK_ID = w.BLOCKING_ENGINE_LOCK_ID\r\n  INNER JOIN performance_schema.data_locks r1 ON r1.ENGINE_LOCK_ID = w.REQUESTING_ENGINE_LOCK_ID\r\nORDER BY  r.trx_wait_started;";
                    }
                    else
                    {
                        // innodb_lock_waits only exists prior to MySQL 5.7
                        query_blocks = "SELECT\r\n  r.trx_wait_started AS wait_started,\r\n  TIMEDIFF (NOW(), r.trx_wait_started) AS wait_age,\r\n  TIMESTAMPDIFF (SECOND, r.trx_wait_started, NOW()) AS wait_age_secs,\r\n  r1.lock_table AS locked_table,\r\n  r1.lock_index AS locked_index,\r\n  r1.lock_type AS locked_type,\r\n  r.trx_id AS waiting_trx_id,\r\n  r.trx_started AS waiting_trx_started,\r\n  TIMEDIFF (NOW(), r.trx_started) AS waiting_trx_age,\r\n  r.trx_rows_locked AS waiting_trx_rows_locked,\r\n  r.trx_rows_modified AS waiting_trx_rows_modified,\r\n  r.trx_mysql_thread_id AS waiting_pid,\r\n  sys.format_statement(r.trx_query) AS waiting_query,\r\n  r1.lock_id AS waiting_lock_id,\r\n  r1.lock_mode AS waiting_lock_mode,\r\n  b.trx_id AS blocking_trx_id,\r\n  b.trx_mysql_thread_id AS blocking_pid,\r\n  sys.format_statement(b.trx_query) AS blocking_query,\r\n  b1.lock_id AS blocking_lock_id,\r\n  b1.lock_mode AS blocking_lock_mode,\r\n  b.trx_started AS blocking_trx_started,\r\n  TIMEDIFF (NOW(), b.trx_started) AS blocking_trx_age,\r\n  b.trx_rows_locked AS blocking_trx_rows_locked,\r\n  b.trx_rows_modified AS blocking_trx_rows_modified,\r\n  CONCAT('KILL QUERY ', b.trx_mysql_thread_id) AS sql_ki11_blocking_query,\r\n  CONCAT('KILL ', b.trx_mysql_thread_id) AS sql_kill_blocking_connection\r\nFROM\r\n  information_schema.innodb_lock_waits w\r\n  INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id\r\n  INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id\r\n  INNER JOIN information_schema.innodb_locks b1 ON b1.lock_id = w.blocking_lock_id\r\n  INNER JOIN information_schema.innodb_locks r1 ON r1.lock_id = w.requested_lock_id\r\nORDER BY  r.trx_wait_started;\r\n ";
                    }

                    string query_mdl = "SELECT\r\n  g.object_schema AS object_schema,\r\n  g.object_name AS object_name,\r\n  pt.thread_id AS waiting_thread_id,\r\n  pt.processlist_id AS waiting_pid,\r\n  sys.ps_thread_account(p.owner_thread_id) AS waiting_account,\r\n  p.lock_type AS waiting_lock_type,\r\n  p.lock_duration AS waiting_lock_duration,\r\n  sys.format_statement(pt.processlist_info) AS waiting_query,\r\n  pt.processlist_time AS waiting_query_secs,\r\n  ps.rows_affected AS waiting_query_rows_affected,\r\n  ps.rows_examined AS waiting_query_rows_examined,\r\n  gt.thread_id AS blocking_thread_id,\r\n  gt.processlist_id AS blocking_pid,\r\n  sys.ps_thread_account(g.owner_thread_id) AS blocking_account,\r\n  g.lock_type AS blocking_lock_type,\r\n  g.lock_duration AS blocking_lock_duration,\r\n  CONCAT ('KILL QUERY ', gt.processlist_id) AS sql_kill_blocking_query,\r\n  CONCAT ('KILL ', gt.processlist_id) AS sql_kill_blocking_connection\r\nFROM\r\n  performance_schema.metadata_locks g\r\n  INNER JOIN performance_schema.metadata_locks p ON g.object_type = p.object_type\r\n  AND g.object_schema = p.object_schema\r\n  AND g.object_name = p.object_name\r\n  AND g.lock_status = 'GRANTED'\r\n  AND p.lock_status = 'PENDING'\r\n  INNER JOIN performance_schema.threads gt ON g.owner_thread_id = gt.thread_id\r\n  INNER JOIN performance_schema.threads pt ON p.owner_thread_id = pt.thread_id\r\n  LEFT JOIN performance_schema.events_statements_current gs ON g.owner_thread_id = gs.thread_id\r\n  LEFT JOIN performance_schema.events_statements_current ps ON p.owner_thread_id = ps.thread_id\r\nWHERE\r\n  g.object_type = 'TABLE';\r\n";                  
                    string query_current_wait = "select sys.format_time(SUM(TIMER_WAIT)) as TIMER_WAIT_SEC, sys.format_bytes(SUM(NUMBER_OF_BYTES)) as NUMBER_OF_BYTES, EVENT_NAME, OPERATION from performance_schema.events_waits_current where EVENT_NAME != 'idle' group by EVENT_NAME,OPERATION order by TIMER_WAIT_SEC desc; ";
                    string query_stmt_fulltablescan = "SELECT\r\n  sys.format_Statement(DIGEST_TEXT) AS query,\r\n  SCHEMA_NAME AS db,\r\n  COUNT_STAR AS EXEC_COUNT,\r\n  sys.format_time(SUM_TIMER_WAIT) AS total_latency,\r\n  SUM_NO_INDEX_USED AS NO_index_used_count,\r\n  SUM_NO_GOOD_INDEX_USED AS no_good_index_used_count,\r\n  ROUND (\r\n    ifnull(SUM_NO_INDEX_USED / NULLIF (COUNT_STAR, 0), 0) * 100\r\n  ) AS NO_index_used_pct,\r\n  SUM_ROWS_SENT AS rows_sent,\r\n  SUM_ROWS_EXAMINED AS rows_examined,\r\n  ROUND (SUM_ROWS_SENT / COUNT_STAR) AS rows_sent_avg,\r\n  ROUND (SUM_ROWS_EXAMINED / COUNT_STAR) AS rows_examined_avg,\r\n  FIRST_SEEN AS first_seen,\r\n  LAST_SEEN AS last_seen,\r\n  DIGEST AS digest\r\nFROM\r\n  performance_schema.events_statements_summary_by_digest\r\nWHERE\r\n  (\r\n    SUM_NO_INDEX_USED > 0\r\n    OR SUM_NO_GOOD_INDEX_USED > 0\r\n  )\r\n  AND DIGEST_TEXT NOT LIKE 'SHOW%'\r\nORDER BY\r\n  no_index_used_pct DESC,\r\n  total_latency DESC;";
                    string query_stmt_filesort = "SELECT\r\n  sys.format_statement (DIGEST_TEXT) AS query,\r\n  SCHEMA_NAME db,\r\n  COUNT_STAR AS EXEC_COUNT,\r\n  sys.format_TIME(SUM_TIMER_WAIT) AS total_Latency,\r\n  SUM_SORt_MERGE_PASSES AS sort_merge_passes,\r\n  ROUND (\r\n    IFNULL(SUM_SORT_MERGE_PASSES / NULLIF(COUNT_STAR, 0), 0)\r\n  ) AS avg_sort_merges,\r\n  SUM_SORT_SCAN AS sorts_using_scans,\r\n  SUM_SORT_RANGE AS sort_using_range,\r\n  SUM_SORT_ROWS AS rows_sorted,\r\n  ROUND (IFNULL(SUM_SORT_ROWS / NULLIF(COUNT_STAR, 0), 0)) AS avg_rows_sorted,\r\n  FIRST_SEEN AS first_seen,\r\n  LAST_SEEN AS last_seen,\r\n  DIGEST AS digest\r\nFROM\r\n  performance_schema.events_statements_summary_by_digest\r\nWHERE\r\n  SUM_SORT_ROWS > 0\r\nORDER BY\r\n  SUM_TIMER_WAIT DESC;";
                    string query_stmt_tmptable = "SELECT\r\n  sys.format_statement (DIGEST_TEXT) AS query,\r\n  SCHEMA_NAME AS db,\r\n  COUNT_STAR AS exec_count,\r\n  sys.format_time(SUM_TIMER_WAIT) AS total_latency,\r\n  SUM_CREATED_TMP_TABLES AS memory_tmp_tables,\r\n  SUM_CREATED_TMP_DISK_TABLES AS disk_tmp_tables,\r\n  ROUND (\r\n    IFNULL(SUM_CREATED_TMP_TABLES / NULLIF (COUNT_STAR, 0), 0)\r\n  ) AS avg_tmp_tables_per_query,\r\n  ROUND (\r\n    IFNULL (\r\n      SUM_CREATED_TMP_DISK_TABLES / NULLIF(SUM_CREATED_TMP_TABLES, 0),\r\n      0\r\n    ) * 100\r\n  ) AS tmp_tables_to_disk_pct,\r\n  FIRST_SEEN AS first_seen,\r\n  LAST_SEEN AS last_seen,\r\n  DIGEST AS digest\r\nFROM\r\n  performance_schema.events_statements_summary_bY_digest\r\nWHERE\r\n  SUM_CREATED_TMP_TABLES > 0\r\nORDER BY\r\n  SUM_CREATED_TMP_DISK_TABLES DESC,\r\n  SUM_CREATED_TMP_TABLES DESC;";
                    string query_file_io = "Select * from sys.io_global_by_file_by_bytes;\r\n";
                    string query_table_buffer = "Select * from sys.schema_table_statistics_with_buffer;\r\n";


                    string result_processlist = await ExecuteQueryAsync(connectionString, query_processlist);
                    string result_innodb_status = await ExecuteQueryAsync(connectionString, query_innodb_status);
                    string result_blocks = await ExecuteQueryAsync(connectionString, query_blocks);
                    string result_mdl = await ExecuteQueryAsync(connectionString, query_mdl);
                    string result_current_wait = await ExecuteQueryAsync(connectionString, query_current_wait);
                    string result_stmt_fulltablescan = await ExecuteQueryAsync(connectionString, query_stmt_fulltablescan);
                    string result_stmt_filesort = await ExecuteQueryAsync(connectionString, query_stmt_filesort);
                    string result_stmt_tmptable = await ExecuteQueryAsync(connectionString, query_stmt_tmptable);
                    string result_file_io = await ExecuteQueryAsync(connectionString, query_file_io);
                    string result_table_buffer = await ExecuteQueryAsync(connectionString, query_table_buffer);


                    string disclamer_ai_access = "Need permission to access output. Currently no result because permisson is denied. (N is selected) ";

                    string summary_processlist = disclamer_ai_access;
                    string summary_innodb_status = disclamer_ai_access;
                    string summary_blocks = disclamer_ai_access;
                    string summary_mdl = disclamer_ai_access;
                    string summary_current_wait = disclamer_ai_access;
                    string summary_stmt_fulltablescan = disclamer_ai_access;
                    string summary_stmt_filesort = disclamer_ai_access;
                    string summary_stmt_tmptable = disclamer_ai_access;
                    if (allowAIAccess == "Y")
                    {
                        Console.WriteLine("You have granted permission to Azure OpenAI to access the query output for auto analysis!");
                        Console.WriteLine("Below summary under each query result would be provided by Azure OpenAI. Please use carefully and seek advices with professional MySQL DBAs!");

                        summary_processlist = await AskGPT.GetOutputAnalysis(result_processlist);
                        summary_innodb_status = await AskGPT.GetOutputAnalysis(result_innodb_status);
                        summary_blocks = await AskGPT.GetOutputAnalysis(result_blocks);
                        summary_current_wait = await AskGPT.GetOutputAnalysis(result_current_wait);
                        summary_mdl = await AskGPT.GetOutputAnalysis(result_mdl);
                        summary_stmt_fulltablescan = await AskGPT.GetOutputAnalysis(result_stmt_fulltablescan);
                        summary_stmt_filesort = await AskGPT.GetOutputAnalysis(result_stmt_filesort);
                        summary_stmt_tmptable = await AskGPT.GetOutputAnalysis(result_stmt_tmptable);
                    }


                    Console.WriteLine("==================");
                    Console.WriteLine("SHOW PROCESSLIST :");
                    string sqlExplain_processlist = await AskGPT.GetSqlExplanation(query_processlist);
                    Console.WriteLine(sqlExplain_processlist);
                    Console.WriteLine("==================");
                    Console.WriteLine(result_processlist);
                    Console.WriteLine("");                    
                    Console.WriteLine("Summary of processlist:");
                    Console.WriteLine(summary_processlist);
                    Console.WriteLine("");

                    Console.WriteLine("===========================");
                    Console.WriteLine("SHOW ENGINE INNODB STATUS :");
                    string sqlExplain_innodb_status = await AskGPT.GetSqlExplanation(query_innodb_status);
                    Console.WriteLine(sqlExplain_innodb_status);
                    Console.WriteLine("===========================");
                    Console.WriteLine(result_innodb_status);
                    Console.WriteLine("");       
                    Console.WriteLine("Summary of InnoDB Status:");
                    Console.WriteLine(summary_innodb_status);
                    Console.WriteLine("");

                    Console.WriteLine("=======================");
                    Console.WriteLine("SHOW CURRENT BLOCKINGS:");
                    string sqlExplain_blocks = await AskGPT.GetSqlExplanation(query_blocks);
                    Console.WriteLine(sqlExplain_blocks);
                    Console.WriteLine("=======================");
                    Console.WriteLine(result_blocks);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of Current blockings:");
                    Console.WriteLine(summary_blocks);
                    Console.WriteLine("");

                    Console.WriteLine("============================");
                    Console.WriteLine("SHOW CURRENT WAITING EVENTS:");
                    string sqlExplain_current_wait = await AskGPT.GetSqlExplanation(query_current_wait);
                    Console.WriteLine(sqlExplain_current_wait);
                    Console.WriteLine("============================");
                    Console.WriteLine(result_current_wait);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of current wait events:");
                    Console.WriteLine(summary_current_wait);
                    Console.WriteLine("");

                    Console.WriteLine("=================");
                    Console.WriteLine("SHOW CURRENT MDL:");
                    string sqlExplain_mdl = await AskGPT.GetSqlExplanation(query_mdl);
                    Console.WriteLine(sqlExplain_mdl);
                    Console.WriteLine("=================");
                    Console.WriteLine(result_mdl);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of MDL:\n");
                    Console.WriteLine(summary_mdl);
                    Console.WriteLine("");

                    Console.WriteLine("=====================================");
                    Console.WriteLine("SHOW Statements used Full Table Scan:");
                    string sqlExplain_stmt_fulltablescan = await AskGPT.GetSqlExplanation(query_stmt_fulltablescan);
                    Console.WriteLine(sqlExplain_stmt_fulltablescan);
                    Console.WriteLine("=====================================");
                    Console.WriteLine(result_stmt_fulltablescan);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of full table scan statements:");
                    Console.WriteLine(summary_stmt_fulltablescan);
                    Console.WriteLine("");

                    Console.WriteLine("==============================");
                    Console.WriteLine("SHOW Statement used File Sort:");
                    string sqlExplain_stmt_filesort = await AskGPT.GetSqlExplanation(query_stmt_filesort);
                    Console.WriteLine(sqlExplain_stmt_filesort);
                    Console.WriteLine("==============================");
                    Console.WriteLine(result_stmt_filesort);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of file sort statements:\n");
                    Console.WriteLine(summary_stmt_filesort);
                    Console.WriteLine("");

                    Console.WriteLine("===============================");
                    Console.WriteLine("SHOW Statement used Tmp Table:");
                    string sqlExplain_stmt_tmptable = await AskGPT.GetSqlExplanation(query_stmt_tmptable);
                    Console.WriteLine(sqlExplain_stmt_tmptable);
                    Console.WriteLine("===============================");
                    Console.WriteLine(result_stmt_tmptable);
                    Console.WriteLine("");
                    Console.WriteLine("Summary of statements using tmp tables:\n");
                    Console.WriteLine(summary_stmt_tmptable);
                    Console.WriteLine("");

                    // Create folder in Temp directory and subfolder named based on UTC timestamp
                    string folderPath = Path.Combine(Path.GetTempPath(), "AzureMySQLPerfCheckerResults", $"{DateTime.UtcNow:yyyyMMddHHmmss}");
                    Directory.CreateDirectory(folderPath);

                    // Save each result in independent file
                    string file_processlist = Path.Combine(folderPath, "processlist.csv");
                    string file_innodb_status = Path.Combine(folderPath, "innodb_status.log");
                    string file_blocks = Path.Combine(folderPath, "blocks.csv");
                    string file_current_wait = Path.Combine(folderPath, "current_wait.csv");
                    string file_mdl = Path.Combine(folderPath, "mdl.csv");
                    string file_stmt_filesort = Path.Combine(folderPath, "stmt_filesort.csv");
                    string file_stmt_fulltablescan = Path.Combine(folderPath, "stmt_fulltablescan.csv");
                    string file_stmt_tmptable = Path.Combine(folderPath, "stmt_tmptable.csv");
                    string file_file_io = Path.Combine(folderPath, "file_io.csv");
                    string file_table_buffer = Path.Combine(folderPath, "table_buffer.csv");


                    await File.WriteAllTextAsync(file_processlist, result_processlist);
                    await File.WriteAllTextAsync(file_innodb_status, result_innodb_status);
                    await File.WriteAllTextAsync(file_mdl, result_mdl);
                    await File.WriteAllTextAsync(file_blocks, result_blocks);
                    await File.WriteAllTextAsync(file_current_wait, result_current_wait);
                    await File.WriteAllTextAsync(file_stmt_filesort, result_stmt_filesort);
                    await File.WriteAllTextAsync(file_stmt_fulltablescan, result_stmt_fulltablescan);
                    await File.WriteAllTextAsync(file_stmt_tmptable, result_stmt_tmptable);
                    await File.WriteAllTextAsync(file_file_io, result_file_io);
                    await File.WriteAllTextAsync(file_table_buffer, result_table_buffer);


                    Console.WriteLine("");
                    Console.WriteLine("==========================================================================================");
                    Console.WriteLine($"Results were written to Temp directory.");
                    Console.WriteLine($"For Windows OS, the folder will be openned once logging completed.");
                    Console.WriteLine($"For Linux OS, please find the log files in path /tmp/AzureMySQLPerfCheckerResults.");
                    

                    // Open folder once completed (in WinOS)
                    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    {
                        Process.Start(new ProcessStartInfo()
                        {
                            FileName = folderPath,
                            UseShellExecute = true,
                            Verb = "open"
                        });
                    }
                }
                else
                {
                    Console.WriteLine("Failed to connect to MySQL Server.");
                    Console.WriteLine("Please double check the connection string and confirm network/firewall settings");
                    Console.WriteLine("You can leverage https://github.com/ShawnXxy/AzMySQL-Connectivity-Checker to further examine connectivity.");
                }
            } catch (Exception ex)
            {
                Console.WriteLine($"An error occurred: {ex.Message}");
            }
        }

        
    }

    // In this code, the GetPassword method reads the password character by character, and appends it to a SecureString.
    // The password characters are not displayed in the console - instead a '*' is displayed for each character
    private static SecureString GetPassword()
    {
        SecureString password = new SecureString();

        ConsoleKeyInfo keyInfo;
        do
        {
            keyInfo = Console.ReadKey(intercept: true);
            if (!char.IsControl(keyInfo.KeyChar))
            {
                password.AppendChar(keyInfo.KeyChar);
                Console.Write("*");
            }
            else if (keyInfo.Key == ConsoleKey.Backspace && password.Length > 0)
            {
                password.RemoveAt(password.Length - 1);
                Console.Write("\b \b");
            }
        } while (keyInfo.Key != ConsoleKey.Enter);
        Console.WriteLine();

        return password;
    }

    private static string ConvertToUnsecureString(SecureString securePassword)
    {
        if (securePassword == null)
            throw new ArgumentNullException("securePassword");

        IntPtr unmanagedString = IntPtr.Zero;
        try
        {
            unmanagedString = Marshal.SecureStringToGlobalAllocUnicode(securePassword);
            return Marshal.PtrToStringUni(unmanagedString);
        }
        finally
        {
            Marshal.ZeroFreeGlobalAllocUnicode(unmanagedString);
        }
    }

    static async Task<string> ExecuteQueryAsync(string connectionString, string query)
    {
        //each ExecuteQueryAsync method now opens its own database connection instead of sharing one.This ensures that each query has its own independent connection and DataReader

        using (MySqlConnection connection = new MySqlConnection(connectionString))
        {
            await connection.OpenAsync();

            using (MySqlCommand command = new MySqlCommand(query, connection))
            {
                using (MySqlDataReader reader = (MySqlDataReader)await command.ExecuteReaderAsync())
                {
                    System.Text.StringBuilder sb = new System.Text.StringBuilder();
                    for (int i = 0; i < reader.FieldCount; i++)
                        sb.Append("\"" + reader.GetName(i) + "\",");
                    sb.AppendLine();

                    while (await reader.ReadAsync())
                    {
                        for (int i = 0; i < reader.FieldCount; i++)
                            sb.Append("\"" + reader[i] + "\",");
                        sb.AppendLine();
                    }

                    return sb.ToString();
                }
            }
        }
    }

    private static async Task<string> GetServerVersionAsync(string connectionString)
    {
        using (MySqlConnection connection = new MySqlConnection(connectionString))
        {
            await connection.OpenAsync();

            string serverVersion = connection.ServerVersion;
            return serverVersion;
        }
    }

}


