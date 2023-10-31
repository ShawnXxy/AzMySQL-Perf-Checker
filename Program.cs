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
        // Console Input
        Console.Write("Enter MySQL host: ");
        string host = Console.ReadLine();

        Console.Write("Enter MySQL username: ");
        string username = Console.ReadLine();

        Console.Write("Enter MySQL password: ");
        SecureString password = GetPassword();

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
                    string query_blocks = "";
                    if (serverVersion.StartsWith("8."))
                    {
                        // for version 8+
                        query_blocks = "SELECT r.trx_id waiting_trx_id, r.trx_mysql_thread_id waiting_thread, r.trx_query waiting_query, b.trx_id blocking_trx_id, b.trx_mysql_thread_id blocking_thread,  b.trx_query blocking_query FROM  performance_schema.data_lock_waits w INNER JOIN information_schema.innodb_trx b ON  b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID INNER JOIN  information_schema.innodb_trx r ON  r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID;";
                    }
                    else
                    {
                        // innodb_lock_waits only exists prior to MySQL 5.7
                        query_blocks = "SELECT r.trx_mysql_thread_id waiting_thread, r.trx_query waiting_query, concat(timestampdiff(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP()), 's') AS duration, b.trx_mysql_thread_id blocking_thread, t.processlist_command state, b.trx_query blocking_current_query, e.sql_text blocking_last_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id JOIN performance_schema.threads t on t.processlist_id = b.trx_mysql_thread_id JOIN performance_schema.events_statements_current e USING(thread_id); ";
                    }

                    string query_mdl = "SELECT OBJECT_TYPE, OBJECT_SCHEMA, OBJECT_NAME, LOCK_TYPE, LOCK_STATUS, THREAD_ID, PROCESSLIST_ID, PROCESSLIST_INFO FROM performance_schema.metadata_locks INNER JOIN performance_schema.threads ON THREAD_ID = OWNER_THREAD_ID WHERE PROCESSLIST_ID<> CONNECTION_ID(); ";
                    string query_concurrent_ticket = "SELECT OBJECT_TYPE, OBJECT_SCHEMA, OBJECT_NAME, LOCK_TYPE, LOCK_STATUS, THREAD_ID, PROCESSLIST_ID, PROCESSLIST_INFO FROM performance_schema.metadata_locks INNER JOIN performance_schema.threads ON THREAD_ID = OWNER_THREAD_ID WHERE PROCESSLIST_ID<> CONNECTION_ID(); ";
                    string query_current_wait = "select sys.format_time(SuM(TIMER_WAIT)) as TIMER_WAIT_SEC, sys.format_bytes(SUM(NUMBER_OF_BYTES)) as NUMBER_OF_BYTES, EVENT_NAME, OPERATION from performance_schema.events_waits_current where EVENT_NAME != 'idle' group by EVENT_NAME,OPERATION order by TIMER_WAIT_SEC desc; ";

                    string result_processlist = await ExecuteQueryAsync(connectionString, query_processlist);
                    string result_innodb_status = await ExecuteQueryAsync(connectionString, query_innodb_status);
                    string result_blocks = await ExecuteQueryAsync(connectionString, query_blocks);
                    string result_mdl = await ExecuteQueryAsync(connectionString, query_mdl);
                    string result_concurrent_ticket = await ExecuteQueryAsync(connectionString, query_concurrent_ticket);
                    string result_current_wait = await ExecuteQueryAsync(connectionString, query_current_wait);

                    Console.WriteLine("========================");
                    Console.WriteLine("SHOW PROCESSLIST Result:");
                    Console.WriteLine("========================");
                    Console.WriteLine(result_processlist);
                    Console.WriteLine("");
                    string summary_processlist = await AskGPT.GetResponse(result_processlist);
                    Console.WriteLine("Summary of processlist:\n");
                    Console.WriteLine(summary_processlist);
                    Console.WriteLine("");

                    Console.WriteLine("=================================");
                    Console.WriteLine("SHOW ENGINE INNODB STATUS Result:");
                    Console.WriteLine("=================================");
                    Console.WriteLine(result_innodb_status);
                    Console.WriteLine("");
                    string summary_innodb_status = await AskGPT.GetResponse(result_innodb_status);
                    Console.WriteLine("Summary of InnoDB Status:\n");
                    Console.WriteLine(summary_innodb_status);
                    Console.WriteLine("");

                    Console.WriteLine("");
                    Console.WriteLine("==============================");
                    Console.WriteLine("SHOW CURRENT BLOCKINGS Result:");
                    Console.WriteLine("==============================");
                    Console.WriteLine(result_blocks);
                    Console.WriteLine("");
                    string summary_blocks = await AskGPT.GetResponse(result_blocks);
                    Console.WriteLine("Summary of InnoDB Status:\n");
                    Console.WriteLine(summary_blocks);
                    Console.WriteLine("");

                    Console.WriteLine("");
                    Console.WriteLine("===================================");
                    Console.WriteLine("SHOW CURRENT WAITING EVENTS Result:");
                    Console.WriteLine("===================================");
                    Console.WriteLine(result_current_wait);
                    Console.WriteLine("");
                    string summary_current_wait = await AskGPT.GetResponse(result_current_wait);
                    Console.WriteLine("Summary of current wait events:\n");
                    Console.WriteLine(summary_current_wait);

                    Console.WriteLine("");
                    Console.WriteLine("========================");
                    Console.WriteLine("SHOW CURRENT MDL Result:");
                    Console.WriteLine("========================");
                    Console.WriteLine(result_mdl);
                    Console.WriteLine("");
                    string summary_mdl = await AskGPT.GetResponse(result_mdl);
                    Console.WriteLine("Summary of InnoDB Status:\n");
                    Console.WriteLine(summary_mdl);

                    Console.WriteLine("");
                    Console.WriteLine("===============================");
                    Console.WriteLine("SHOW CONCURRENT TICKETS Result:");
                    Console.WriteLine("===============================");
                    Console.WriteLine(result_concurrent_ticket);
                    Console.WriteLine("");
                    string summary_concurrent_ticket = await AskGPT.GetResponse(result_concurrent_ticket);
                    Console.WriteLine("Summary of InnoDB Status:\n");
                    Console.WriteLine(summary_concurrent_ticket);

                    // Create folder in Temp directory and subfolder named based on UTC timestamp
                    string folderPath = Path.Combine(Path.GetTempPath(), "AzureMySQLPerfCheckerResults", $"{DateTime.UtcNow:yyyyMMddHHmmss}");
                    Directory.CreateDirectory(folderPath);

                    // Save each result in independent file
                    string file_processlist = Path.Combine(folderPath, "processlist.csv");
                    string file_innodb_status = Path.Combine(folderPath, "innodb_status.log");
                    string file_blocks = Path.Combine(folderPath, "blocks.csv");
                    string file_current_wait = Path.Combine(folderPath, "current_wait.csv");
                    string file_mdl = Path.Combine(folderPath, "mdl.csv");
                    string file_concurrent_ticket = Path.Combine(folderPath, "concurrent_ticket.csv");

                    await File.WriteAllTextAsync(file_processlist, result_processlist);
                    await File.WriteAllTextAsync(file_innodb_status, result_innodb_status);
                    await File.WriteAllTextAsync(file_mdl, result_mdl);
                    await File.WriteAllTextAsync(file_blocks, result_blocks);
                    await File.WriteAllTextAsync(file_current_wait, result_current_wait);
                    await File.WriteAllTextAsync(file_concurrent_ticket, result_concurrent_ticket);

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


