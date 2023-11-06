# AzMySQL-Perf-Checker
This is a console app that will 
1. connect to a MySQL server based on the host and username user provided 
1. query detailed metadata from `information_schema` and/or `performance_schema` to get result of MySQL runtime status and performance details like InnoDB status, wait events, blocking chains, etc.
1. save result into a temp directory for later analysis. Subfoldes wll be organized based on execution timestamp (UTC)

## Prerequisite
The code is developed with .NET Core 6.0. Install .NET Core on a Linux VM where is allowed to connected to the target MySQL. Refer to https://docs.microsoft.com/dotnet/core/install/linux-package-manager-ubuntu-1804
```bash
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo add-apt-repository universe
sudo apt-get update
sudo apt-get install apt-transport-https
sudo apt-get update
sudo apt-get install dotnet-sdk-6.0
```


## Detail usage instructions:
**LINUX** <br>
Checkout the sample code and run :
```bash
git clone https://github.com/ShawnXxy/AzMySQL-Perf-Checker.git
cd AzMySQL-Perf-Checker
dotnet build
sudo dotnet run
```

**Windows** <br>
Paste the following in a Powershell console in Windows:
```powershell
$ProgressPreference = "SilentlyContinue";
$scriptFile = '/AzureMySQLPerfChecker.ps1'
$scriptUrlBase = 'https://raw.githubusercontent.com/ShawnXxy/AzMySQL-Perf-Checker/master'
cls
Write-Host 'Trying to download the script file from GitHub (https://github.com/ShawnXxy/AzMySQL-Perf-Checker), please wait...'
Write-Host "Source file address:" $scriptUrlBase$scriptFile
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    Invoke-Expression (Invoke-WebRequest -Uri ($scriptUrlBase + $scriptFile) -UseBasicParsing).Content
    }
catch {
    Write-Host 'ERROR: The script file could not be downloaded or the script execution failed:' -ForegroundColor Red
    $_.Exception
    Write-Host 'Confirm this machine can access https://github.com/ShawnXxy/AzMySQL-Perf-Checker/' -ForegroundColor Yellow
    Write-Host 'or use a machine with Internet access to see how to run this from machines without Internet. See how at https://github.com/ShawnXxy/AzMySQL-Perf-Checker/' -ForegroundColor Yellow
    Write-Host 'or raise your issue at https://github.com/ShawnXxy/AzMySQL-Perf-Checker/issues if the script execution fails..' -ForegroundColor Yellow
}
#end of script
```

## Limitations:
Due to the API limitaiton, if you selected to run in a PowerShell mode, Azure OpenAI would not be able to run analyze the output. 

>Disclaimer: This sample code is available AS IS with no warranties and support from Microsoft. Please raise an issue in Github if you encounter any issues and I will try our best to address it.











