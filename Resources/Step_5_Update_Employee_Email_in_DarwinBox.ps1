Param (
    [Parameter(Mandatory=$true)]
    [string]$DWB_admin_Email,
    [Parameter(Mandatory=$true)]
    [string]$DWB_secret,
    [Parameter(Mandatory=$true)]
    [string]$DWB_UID,
    [Parameter(Mandatory=$true)]
    [string]$company_Domain_CSV,
    [Parameter(Mandatory=$true)]
    [string]$azureAD_Auth_CSV,
    [Parameter(Mandatory=$true)]
    [string]$Monitor_Users_output_CSV,
    [Parameter(Mandatory=$true)]
    [string]$mail_update_Success_CSV,
    [Parameter(Mandatory=$true)]
    [string]$missing_AD_Users_CSV
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
        [string]$LogFileName="Update_Employee_Email_in_DarwinBox"
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

function Update-Employee_MailAddress
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
        ## Unique ID of the DarwinBox user
        [Parameter(Mandatory=$true)]
        [string]$user_uniqueID,
        ## Employee ID of the user
        [Parameter(Mandatory=$true)]
        [string]$employee_Email
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
            "user_id":"$user_uniqueID",
            "email_id":"$employee_Email"
        }
"@

        ## API call to get all employees
        $api_URL = "https://map.darwinbox.com/UpdateEmployeeDetails/update"
        $response = Invoke-RestMethod -Uri $api_URL -Method POST -Headers $req_headers -Body $req_body
        return $response
    }
    catch
    {        
        $err_msg = "Error while updating DarwinBox employee with unique user Id - $user_uniqueID `n Error Message : $_"
        Write-Log $err_msg      
    }
}

function Validate-ModuleDependencies
{
    ## Check if Azure AD PowerShell module is installed. ##
    ## If not, install all modules/dependencies required for successful execution of the script. ##

    Write-Output ""
    Write-Log "Validating module dependencies for the script..."

    #-- Check & Install the AzureAD module --#
    if ((Get-Module -Name "AzureAD" -ListAvailable) -eq $null)
    {
        Write-Log "Installing module AzureAD"
        Install-Module -Name "AzureAD" -AllowClobber -Force
    }

    #-- Check & Install the ActiveDirectory module --#
    if ((Get-Module -Name "ActiveDirectory" -ListAvailable) -eq $null)
    {
        Write-Log "Installing module ActiveDirectory"
        Install-Module -Name "ActiveDirectory" -AllowClobber -Force
    }

    #-- Import the module to use in the script --#
    Import-Module -Name "AzureAD"
    Import-Module -Name "ActiveDirectory"

    Write-Log "All dependencies validated successfully. Proceeding with the other steps..."
    Write-Output ""
    Write-Log "---------------------------------------------------------------------------`n"
}

#endregion

######################################################################################################

Write-Log "Script Execution Logs Start`n"

Write-Output ""
Write-Log "****************************************************************************************************"

Validate-ModuleDependencies
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## Lists
## ------
$Update_Success_List = @()
$Update_Failure_List = @()
$Records_NotFound    = @()

#region Connect to AzureAD using Service Principal

if (Test-Path $azureAD_Auth_CSV)
{
    $auth_Obj = Import-Csv $azureAD_Auth_CSV

    Write-Log "Connecting to Azure AD ..."

    # Login to Azure PowerShell with your Service Principal and Certificate
    Connect-AzureAD -TenantId $auth_Obj.Tenant_ID `
                    -ApplicationId $auth_Obj.App_ID `
                    -CertificateThumbprint $auth_Obj.Cert_Thumbprint | Out-Null

    Write-Log "Connection successful."
}
else
{
    Write-Log "Cannot connect to Azure AD as the auth CSV file is not found."
}

Write-Output ""
Write-Log "---------------------------------------------------------------------------"

#endregion

#region Execution

## Check if the Users Monitoring output CSV file exists
if (Test-Path $Monitor_Users_output_CSV -PathType Leaf)
{    
    ## Check if the company domain input CSV file exists
    if (Test-Path $company_Domain_CSV -PathType Leaf)
    {
        ## Step 1 - Read DarwinBox employees details from Users Monitoring output CSV
        Write-Output ""
        Write-Log "Reading data from Users Monitoring output CSV file"
        $usr_output = Import-Csv $Monitor_Users_output_CSV
        
        ## Step 2 - Read the details for company and domain Info
        Write-Output ""
        Write-Log "Reading Domain and Company info from CSV file"
        $Domain_Info = Import-Csv $company_Domain_CSV

        Write-Output ""
        Write-Log "======================================================================================="

        if ($usr_output -ne $null)
        {
            ## Step 3 - Loop through the details from Users Monitoring CSV output and Check for their mail attribute
            foreach ($DWB_Info in $usr_output)
            {
                ## Map Variables            
                $ADFS_extensionAttribute15 = $AzureAD_extension_DarwinBox_UniqueID = $DWB_Info.user_unique_id

                #region Get user info from respective domain
                
                Write-Output ""
                Write-Log "Determining the domain type from the group company name"

                ## Check whether domain is ADFS or Azure
                $Domain_Type = ($Domain_Info | ?{$_.GroupCompany -eq $DWB_Info.group_company}).DomainType

                ## Determine the user based on domain type
                if ($Domain_Type -eq "ADFS")
                {
                    Write-Log "Domain Type - ADFS"

                    #region Check and Update existing ADFS user mail from ADFS in DarwinBox

                    Write-Output ""
                    Write-Log "Checking if the user exists in ADFS or not"

                    ## Check if the user exists in AD based on employee ID filter
                    $AD_User = get-aduser -filter {extensionAttribute15 -eq $ADFS_extensionAttribute15} -properties EmailAddress

                    ## If user found
                    if ($AD_User -ne $null)
                    {
                        Write-Log "User with DarwinBox unique user Id set to $ADFS_extensionAttribute15 already exists"
                        
                        ## Update mail address for the user in DarwinBox
                        $ADFS_updateResult = Update-Employee_MailAddress -admin_Email $DWB_admin_Email -UID $DWB_UID `
                                                                    -secretKey $DWB_secret -user_uniqueID $ADFS_extensionAttribute15 `
                                                                    -employee_Email "$($AD_User.SamAccountName)@map.co.id"                       

                        if ($ADFS_updateResult.message -eq "Employee Data Updated Successfully")
                        {
                            Write-Log "Mail address has been updated in DarwinBox for the user with unique ID $ADFS_extensionAttribute15"
                            $Update_Success_List += $DWB_Info
                        }
                        else
                        {
                            Write-Log "Email Update operation failed for the ADFS user with unique ID $ADFS_extensionAttribute15 with the ERROR message - $ADFS_updateResult"
                            $Update_Failure_List += $DWB_Info
                        }

                    }
                    else
                    {
                        Write-Log "User NOT FOUND with DarwinBox unique user Id set to $ADFS_extensionAttribute15"
                        $Records_NotFound += $DWB_Info
                    }

                    #endregion
                }
                else
                {
                    Write-Log "Domain Type - AzureAD"

                    #region Check and Update existing AzureAD user mail from Azure AD in DarwinBox

                    Write-Output ""
                    Write-Log "Checking if the user exists in Azure AD or not"

                    ## Check if the user exists in AD based on employeeId filter
                    $AzAD_User = Get-AzureADUser -All $True | Where-Object `
                                    { `
                                        $_.extensionProperty.extension_a5dbd68e85c0469f91aa5e908a20b136_DarwinBox_UniqueID -eq "$AzureAD_extension_DarwinBox_UniqueID" `
                                    } | Select-Object *

                    ## If user found
                    if ($AzAD_User -ne $null)
                    {
                        Write-Log "User with DarwinBox unique user Id set to $AzureAD_extension_DarwinBox_UniqueID already exists"

                        if ($AzAD_User.Mail -ne $null)
                        {
                            ## Update mail address for the user in DarwinBox
                            $AzAD_updateResult = Update-Employee_MailAddress -admin_Email $DWB_admin_Email -UID $DWB_UID `
                                                                        -secretKey $DWB_secret -user_uniqueID $AzureAD_extension_DarwinBox_UniqueID `
                                                                        -employee_Email $($AzAD_User.Mail)

                            if ($AzAD_updateResult.message -eq "Employee Data Updated Successfully")
                            {
                                Write-Log "Mail address has been updated in DarwinBox for the Azure AD user with unique ID $AzureAD_extension_DarwinBox_UniqueID"
                                $Update_Success_List += $DWB_Info
                            }
                            else
                            {
                                Write-Log "Email Update operation failed for the user with unique ID $AzureAD_extension_DarwinBox_UniqueID with the ERROR message - $AzAD_updateResult"
                                $Update_Failure_List += $DWB_Info
                            }
                        }
                        else
                        {
                            Write-Log "Mail Attribute is NULL in Azure AD for the user with unique ID $AzureAD_extension_DarwinBox_UniqueID"
                        }
                    }
                    else
                    {
                        Write-Log "User NOT FOUND with DarwinBox unique user Id set to $AzureAD_extension_DarwinBox_UniqueID"
                        $Records_NotFound += $DWB_Info
                    }

                    #endregion           
                }
                #endregion

                Write-Output ""
                Write-Log "======================================================================================="
            }
        
            ## Remove old monitoring file
            Get-ChildItem $Monitor_Users_output_CSV | Remove-Item -force 

            Write-Output ""
            Write-Log "Exporting the results to CSV files"

            ## Export the results to CSV file
            if ($Records_NotFound -ne $null)
            {
                $Records_NotFound | Export-CSV $missing_AD_Users_CSV -NoTypeInformation -Encoding UTF8 -Append
            }

            if ($Update_Success_List -ne $null)
            {
                $Update_Success_List | Export-CSV $mail_update_Success_CSV -NoTypeInformation -Encoding UTF8 -Append
            }

            if ($Update_Failure_List -ne $null)
            {
                $Update_Failure_List | Export-CSV $Monitor_Users_output_CSV -NoTypeInformation -Encoding UTF8
            }

            Write-Log "Export successful"
        }
        else
        {
            Write-Log "The output CSV file for Monitoring Users CONTAINS NO RECORDS." -Level Warn
        }
    }
    else
    {
        Write-Log "Input CSV file for companies and domain info NOT FOUND." -Level Error
    }
}
else
{
    Write-Log "Users Monitoring Output CSV file NOT FOUND." -Level Error
}

Write-Output ""
Write-Output ""
Write-Log "****************************************************************************************************"
Write-Output ""
Write-Output ""

Write-Log "Script Execution Logs End `n`n"

#endregion

######################################################################################################
