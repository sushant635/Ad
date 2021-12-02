Param (
    [Parameter(Mandatory=$true)]
    [string]$DWB_InactiveEmployees_output_CSV,
    [Parameter(Mandatory=$true)]
    [string]$company_Domain_CSV,
    [Parameter(Mandatory=$true)]
    [string]$azureAD_Auth_CSV
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
        [string]$LogFileName="Disable_ExistingUsers_in_AD"
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
    Write-Log "---------------------------------------------------------------------------"
    Write-Output ""
}

function Validate-ExtensionProperty ($ext_Name,$ext_Value,$userObjectId,$appName)
{
    try 
    {
        ## Get Azure AD application details
        $sp = Get-AzureADApplication -SearchString $appName
        $objId = $sp.objectId
        $appId = $sp.AppId

        #Write-Log "`nStep 1 - App Validation`n------------------------------------------------------------------------ "

        ## Step 1 - Check if the property already exists for the AD app
        $check = Get-AzureADApplicationExtensionProperty -ObjectId $objId | ?{$_.name -like "*$ext_Name*"}

        if ($check -eq $null) 
        {
            ## Add new extension property to the AD app
            #Write-Log "Creating new extension property [$ext_Name] for the application [$appName] in Azure AD."
            $ext_Info = New-AzureADApplicationExtensionProperty -ObjectId $objId -Name $ext_Name `
                                                                -DataType "String" -TargetObjects 'User'
        }
        else 
        {
            $ext_Info = $check
            #Write-Log "Extension property [$ext_Name] already exists for the application [$appName] in Azure AD."
        }
    
        #Write-Log "`nStep 2 - User Validation`n------------------------------------------------------------------------ "

        ## Step 2 - Check if the user already has the property added
        $user_ext_List = Get-AzureADUserExtension -ObjectId $userObjectId

        if ($user_ext_List.keys -notcontains "$($ext_Info.name)") 
        {
            ## Add new extension property for the user
            #Write-Log "Adding the extension property [$ext_Name] for the user with object Id [$userObjectId] in Azure AD."
            Set-AzureADUserExtension -ObjectId $userObjectId -ExtensionName $ext_Info.name -ExtensionValue $ext_Value
        }
        else 
        {
            #Write-Log "Extension property already exists for the user with object Id [$userObjectId] in Azure AD."
        }
    }
    catch 
    {
        Write-Log "Validate-ExtensionProperty ERROR:`n$_`n"
    }
}

function Format-LastWorkingDate ($input_Date)
{
    $fullDate = $input_Date -split '-'
    Write-Host "$fullDate"
    $MonthName = $($fullDate)[1]
    [int]$day = $($fullDate[0])
    [int]$yr = "$($fullDate[2])"
    switch ($MonthName)
    {
        'Jan' {[int]$MonthNum = 01}
        'Feb' {[int]$MonthNum = 02}
        'Mar' {[int]$MonthNum = 03}
        'Apr' {[int]$MonthNum = 04}
        'May' {[int]$MonthNum = 05}
        'Jun' {[int]$MonthNum = 06}
        'Jul' {[int]$MonthNum = 07}
        'Aug' {[int]$MonthNum = 08}
        'Sep' {[int]$MonthNum = 09}
        'Oct' {[int]$MonthNum = 10}
        'Nov' {[int]$MonthNum = 11}
        'Dec' {[int]$MonthNum = 12}
    }

    if ($($fullDate[2]).length -eq 2)
    {
        [int]$yr = "20$($fullDate[2])"
    }

    return $(get-date -day $day -month $MonthNum -year $yr)
}

function Disable-ADFS_User ($DarwinBox_Unique_Id,$lastWorkingDate)
{
    Write-Output ""
    Write-Log "Checking if the user exists in ADFS or not"
    
    ## Check if the user exists in AD based on darwinBox unique user ID filter
    $AD_User = get-aduser -filter {extensionAttribute15 -eq $DarwinBox_Unique_Id}

    ## If user found in ADFS
    if ($AD_User -ne $null)
    {
        Write-Log "Founded user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"

        $ADFS_Date = Format-LastWorkingDate -input_Date $lastWorkingDate

        ## Filter users based on last working date from darwinBox
        if ($(Get-Date) -gt $($ADFS_Date.AddDays(+1)))
        {        
            Write-Log "Disabling account for the existing user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"
                  
            ## Disable the user and Update lastworking date extension attribute
            Set-ADUser -Identity $AD_User.samAccountName -Enabled $false -Replace @{'extensionAttribute14'= $lastWorkingDate}

            Write-Log "Account DISABLED successfully."
        }
        else
        {
            Write-Log "Skipping the disable operation for the existing user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"
        }
    }
    else
    {
        Write-Log "User with DarwinBox unique user Id set to $DarwinBox_Unique_Id NOT FOUND in ADFS"
    }
}

function Disable-AzureAD_User ($DarwinBox_Unique_Id,$lastWorkingDate)
{

    Write-Output ""
    Write-Log "Checking if the user exists in Azure AD or not"

    ## Check if the user exists in AD based on employeeId filter
    $AzAD_User = Get-AzureADUser -All $True | Where-Object `
                    { `
                        $_.extensionProperty.extension_a5dbd68e85c0469f91aa5e908a20b136_DarwinBox_UniqueID -eq "$DarwinBox_Unique_Id" `
                    } | Select-Object *

    ## If user found in Azure AD
    if ($AzAD_User -ne $null)
    {
        Write-Log "Founded user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"

        $AzAD_Date = Format-LastWorkingDate -input_Date $lastWorkingDate

        ## Filter users based on last working date from darwinBox
        if ($(Get-Date) -gt $($AzAD_Date.AddDays(+1)))
        {
            Write-Log "Disabling account for the existing user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"
                        
            ## Update details for the existing user by disabling the account
            Set-AzureADUser -ObjectId $AzAD_User.ObjectId -AccountEnabled $false

            ## Update lastworking date extension attribute
            Validate-ExtensionProperty -ext_Name "LastWorkingDate" -ext_Value $lastWorkingDate `
                                       -userObjectId $AzAD_User.ObjectId -appName 'Azure_AD_Connect'

            Write-Log "Account DISABLED successfully."
        }
        else
        {
            Write-Log "Skipping the disable operation for the existing user with DarwinBox unique user Id set to $DarwinBox_Unique_Id"
        }
    }
    else
    {
        Write-Log "USER with DarwinBox unique user Id set to $DarwinBox_Unique_Id NOT FOUND in AZURE AD"
    }
}

#endregion

######################################################################################################

Write-Log "Script Execution Logs Start`n"

Write-Output ""
Write-Log "****************************************************************************************************"

Validate-ModuleDependencies

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

## Check if the Inactive Employees output CSV file exists
if (Test-Path $DWB_InactiveEmployees_output_CSV -PathType Leaf)
{    
    ## Check if the company domain input CSV file exists
    if (Test-Path $company_Domain_CSV -PathType Leaf)
    {
        ## Step 1 - Read DarwinBox employees details from Inactive Employees CSV output
        Write-Output ""
        Write-Log "Reading Inactive DarwinBox employees info from output CSV file"
        $inactive_Emp_output = Import-Csv $DWB_InactiveEmployees_output_CSV
        
        ## Step 2 - Read the details for company and domain Info
        Write-Output ""
        Write-Log "Reading Domain and Company info from CSV file"
        $Domain_Info = Import-Csv $company_Domain_CSV

        Write-Output ""
        Write-Log "======================================================================================="

        if ($inactive_Emp_output -ne $null)
        {
            ## Step 3 - Loop through the Inactive Employees CSV output and Disable the users 1 day after the last working date 
            foreach ($DWB_Info in $inactive_Emp_output)
            {            
                Write-Output ""
                Write-Log "DarwinBox Unique Id for User - $($DWB_Info.user_unique_id)"
                                         
                #region Disable User in respective domain

                Write-Output ""
                Write-Log "Determining the domain type from the group company name"

                ## Check whether domain is ADFS or Azure
                $Domain_Type = ($Domain_Info | ?{$_.GroupCompany -eq $DWB_Info.group_company}).DomainType

                ## Determine the user based on domain type
                if ($Domain_Type -eq "ADFS")
                {                  
                    Write-Log "Domain Type - ADFS"
                    Disable-ADFS_User -DarwinBox_Unique_Id $DWB_Info.user_unique_id -lastWorkingDate $DWB_Info.date_of_exit
                }
                else
                {
                    Write-Log "Domain Type - AzureAD"
                    Disable-AzureAD_User -DarwinBox_Unique_Id $DWB_Info.user_unique_id -lastWorkingDate $DWB_Info.date_of_exit       
                }

                Write-Output ""
                Write-Log "======================================================================================="

                #endregion
            }
        }
        else
        {
            Write-Log "The output CSV file for Inactive Employees CONTAINS NO RECORDS." -Level Warn
        }
    }
    else
    {
        Write-Log "Input CSV file for companies and domain info NOT FOUND." -Level Error
    }
}
else
{
    Write-Log "Inactive Employees Output CSV file NOT FOUND." -Level Error
}

Write-Output ""
Write-Output ""
Write-Log "****************************************************************************************************"
Write-Output ""
Write-Output ""

Write-Log "Script Execution Logs End `n`n"

#endregion

######################################################################################################
