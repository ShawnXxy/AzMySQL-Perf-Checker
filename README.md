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

## Limitation
Currently, only supports MySQL 5.7 as some dictionay table changed in MySQL 8.0

>Disclaimer: This sample code is available AS IS with no warranties and support from Microsoft. Please raise an issue in Github if you encounter any issues and I will try our best to address it.











