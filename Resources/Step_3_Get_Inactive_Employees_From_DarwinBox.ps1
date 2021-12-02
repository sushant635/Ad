Param (
    [Parameter(Mandatory=$true)]
    [string]$DWB_adminEmail,
    [Parameter(Mandatory=$true)]
    [string]$DWB_secretKey,
    [Parameter(Mandatory=$true)]
    [string]$DWB_UID,
    [Parameter(Mandatory=$true)]
    [string]$DWB_inactive_dts_key,
    [Parameter(Mandatory=$true)]
    [string]$DWB_InactiveEmployees_output_CSV
)

#region FUNCTIONS

function Write-Log 
{ 
    [CmdletBinding()] 
    [OutputType([int])] 
    Param ( 
        # The string to be written to the log.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
 
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, Position=3)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info",

        [Parameter(Mandatory=$false)]
        [string]$LogFileName="Inactive_Employees_from_DarwinBox"
    ) 
 
    $date = Get-Date -Format "ddMMyyyy"
    $subdate = Get-Date -Format "hhmmss_tt"
    $Path = "$PSScriptRoot\..\Logs\$date\$($LogFileName)_Log.txt"
 
    # If attempting to write to a log file in a folder/path that doesn't exist to create the file include path. 
    if (!(Test-Path $Path)) { 
        Write-Verbose "Creating $Path."
		$NewLogFile = New-Item $Path -Force -ItemType File 
    }

    $Message = "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $($Level): $Message"

    # Write message to console.
    Write-Output $Message

    # Write message to file.
    Write-Output $Message | Out-File -FilePath $Path -Append -Encoding ascii

    #Write-Host "The log file is saved at $Path" -ForegroundColor Green  
}

function Get-StringHash 
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String]$inputString
    )

    $hasher = New-Object -TypeName "System.Security.Cryptography.SHA512CryptoServiceProvider"
    $encoding = [System.Text.Encoding]::UTF8

    $hash = ($hasher.ComputeHash($encoding.GetBytes($inputString)) | % {
        "{0:X2}" -f $_
    }) -join ""

    $output = [String]$hash.toLower()
    return $output
}

function Get-AllEmployees
{
    [CmdletBinding()] 
    Param (
        ## DarwinBox admin Email
        [Parameter(Mandatory=$true)]
        [string]$admin_Email,
        ## DarwinBox secret Key
        [Parameter(Mandatory=$true)]
        [string]$secretKey,
        ## DarwinBox UID
        [Parameter(Mandatory=$true)]
        [string]$UID,
        ## DarwinBox Dataset Key
        [Parameter(Mandatory=$true)]
        [string]$datasetKey
    )

    try 
    {
        ## Get current epoch timestamp in seconds
        $timestamp = [long] (Get-Date -Date ((Get-Date).ToUniversalTime()) -UFormat %s)

        ## Generate hash
        $mixedString = $admin_Email + $secretKey + $timestamp
        $computedHash = Get-StringHash -inputString $mixedString

        ## Request headers
        $req_headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $req_headers.Add("Content-Type", "application/json")

        ## Request body
        $req_body = @"
        {
            "Uid":"$UID",
            "hash":"$computedHash",
            "timestamp":"$timestamp",
            "datasetKey":"$datasetKey"
        }
"@

        ## API call to get all employees
        $api_URL = "https://map.darwinbox.com/masterapi/employee"
        $response = Invoke-RestMethod -Uri $api_URL -Method POST -Headers $req_headers -Body $req_body
        #$response = $response | ConvertTo-Json -Depth 8
        return $response
    }
    catch
    {        
        $err_msg = "Error while retrieving employees from DarwinBox`n Error Message : $_"
        Write-Log $err_msg -Level Error      
    }
}

#endregion

######################################################################################################

Write-Log "Script Execution Logs Start`n"

Write-Output ""
Write-Log "****************************************************************************************************"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Get Inactive DarwinBox Employees and Export to CSV

Write-Log "Getting Inactive Employees from DarwinBox ..."

$Inactive_EmployeesList = Get-AllEmployees -admin_Email $DWB_adminEmail -secretKey $DWB_secretKey `
                                           -UID $DWB_UID -datasetKey $DWB_inactive_dts_key

if ($Inactive_EmployeesList.status -ne 0)
{
    $Inactive_EmployeesList.employee_data | Export-CSV $DWB_InactiveEmployees_output_CSV -NoTypeInformation -Encoding UTF8

    Write-Log "Employees exported successfully to CSV file"
}
else
{
    Write-Log "No users found in the list of Inactive DarwinBox Employees." -Level Warn
}

Write-Output ""
Write-Output ""
Write-Log "****************************************************************************************************"
Write-Output ""
Write-Output ""

Write-Log "Script Execution Logs End `n`n"

#endregion

######################################################################################################