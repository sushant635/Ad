#region Variables

###############################################################################
################################## VARIABLES ##################################
###############################################################################

## Base variables
$resourcesPath           = "$PSScriptRoot\Resources"
$date                    = $(Get-Date -Format "ddMMyyyy")
$logPath                 = "$PSScriptRoot\Logs\$date"
$fullLogPath             = "$logPath\FullScript_Log_$(Get-Date -Format "ddMMyyyy_hhmmss_tt").txt"

# Script Paths
$script_for_Step1        = "$resourcesPath\Step_1_Get_Active_Employees_From_DarwinBox.ps1"
$script_for_Step2        = "$resourcesPath\Step_2_CreateNew_Or_UpdateExisting_Users_in_AD.ps1"
$script_for_Step3        = "$resourcesPath\Step_3_Get_Inactive_Employees_From_DarwinBox.ps1"
$script_for_Step4        = "$resourcesPath\Step_4_Disable_ExistingUsers_in_AD.ps1"
$script_for_Step5        = "$resourcesPath\Step_5_Update_Employee_Email_in_DarwinBox.ps1"

# Input CSV Files
$AzureAD_AuthFile        = "$resourcesPath\Auth_Details.csv"
$Domain_Info_File        = "$resourcesPath\Companies_and_Domain_Mapping.csv"

## DarwinBox API details
$DarwinBox_admin_Email   = "darwinbox@map.co.id"
$DarwinBox_secretKey     = "df0721e297148f3d5ffb7e0148dd8e51"
$DarwinBox_UID           = "TTEO50S99ERCL"

## Step 1 variables
$Active_datasetKey       = "53628590d67949960834383adc6da5d643ba288710139c433e942b262a98b2b7782d5b791d67625fe62c3a8bcc5d06ac316f60d64e38fb4a5e536a07aaba9d25"
$ActiveEmployees_CSV     = "$PSScriptRoot\Output\Active_DarwinBoxEmployees.csv"

## Step 2 variables
$AD_User_Password        = $(ConvertTo-SecureString '7ohnT4ri9@n' -AsPlainText -Force)

## Step 3 variables
$Inactive_datasetKey     = "be8726da261b5b8e70e9995fa1026ee773561316755c63ca7d2f8c9123fb8b09af344de5b3f3ffd3b726efc226505e7dfbad6bea87c27baae952f4f40c102261"
$InactiveEmployees_CSV   = "$PSScriptRoot\Output\Inactive_DarwinBoxEmployees.csv"

## Step 5 variables
$Monitoring_Users_CSV    = "$PSScriptRoot\Output\Users_to_Monitor_For_Email_Update.csv"
$Success_Mail_Update_CSV = "$PSScriptRoot\Output\Users_with_Mail_Update_Success.csv"
$AD_Users_Missing_CSV    = "$PSScriptRoot\Output\Users_NotFound_in_AD.csv"

###############################################################################
###############################################################################
###############################################################################

#endregion

#region Functions

function RunStep($number)
{
    $scriptPath = Get-Variable -Name $("script_for_Step" + "$number") -ValueOnly
    $arguments = Get-Variable -Name $("argumentList_" + "$number") -ValueOnly

    if (Test-Path "$scriptPath")
    {
        #Write-Host "Invoke-Expression `"& '$scriptPath' $arguments`"" ## Script call
        Invoke-Expression "& '$scriptPath' $arguments"
    }
    else
    {
        Write-Output "Script for Step $number does not exists. Hence, terminating the operation."
    }
}

#endregion

#region Validate path creation

# If attempting to write to a log file in a folder/path that doesn't exist to create the file include path. 
if (!(Test-Path $fullLogPath)) { 
    Write-Verbose "Creating $fullLogPath."
	$NewLogFile = New-Item $fullLogPath -Force 
}

if (!(Test-Path "$PSScriptRoot\Output"))
{
	New-Item "$PSScriptRoot\Output" -Force | Out-Null    
}

#endregion

#region Script Execution

Start-Transcript -Path $fullLogPath

Write-Output "Script starts at $(Get-Date -format 'dd-MM-yyyy hh:mm:ss')`n------------------------------------------------------------------------------------"

try
{

    #region Step 1 and 2
    
    ## Step 1 
    #====================================
    # Arguments
    $argumentList_1 = @()
    $argumentList_1 += ("-DWB_adminEmail", "'$DarwinBox_admin_Email'")
    $argumentList_1 += ("-DWB_secretKey", "'$DarwinBox_secretKey'")
    $argumentList_1 += ("-DWB_UID", "'$DarwinBox_UID'")
    $argumentList_1 += ("-DWB_active_dts_key", "'$Active_datasetKey'")
    $argumentList_1 += ("-DWB_ActiveEmployees_output_CSV", "'$ActiveEmployees_CSV'")
    
    Write-Output "Performing Step 1 : [ Get Active Employees From DarwinBox ]"

    # 1
    #RunStep -number 1

    if (Test-Path $ActiveEmployees_CSV -PathType Leaf)
    {
        Write-Output "Active Employees CSV file exists. Proceeding with step 2"
        
        Copy-Item -Path $ActiveEmployees_CSV -Destination "$logPath\Active_Employees_$(Get-Date -Format "ddMMyyyy_hhmmss_tt").csv"

        ## Step 2
        #====================================
        # Arguments
        $argumentList_2 = @()
        $argumentList_2 += ("-DWB_ActiveEmployees_output_CSV", "'$ActiveEmployees_CSV'")
        $argumentList_2 += ("-company_Domain_CSV", "'$Domain_Info_File'")
        $argumentList_2 += ("-azureAD_Auth_CSV", "'$AzureAD_AuthFile'")
        $argumentList_2 += ("-Monitor_Users_output_CSV", "'$Monitoring_Users_CSV'")
        $argumentList_2 += ("-newUser_Pwd", $AD_User_Password)

        Write-Output ""
        Write-Output "Performing Step 2 : [ Create New Or Update Existing Users in AD ]"

        # 2
        RunStep -number 2

        ## Keep only unique records in CSV file
        $unique_entries = Import-Csv $Monitoring_Users_CSV | Select-Object * -Unique
        $unique_entries | Export-Csv -Path $Monitoring_Users_CSV -Encoding Utf8 -NoTypeInformation

        if ($success_info -ne $null)
        {
            $success_info | Export-Csv -Path $Success_Mail_Update_CSV -Encoding Utf8 -NoTypeInformation
        }
    }
    else
    {
        Write-Output "Active Employees CSV file not found."
    }

    #endregion

    #region Step 3 and 4

    ## Step 3
    #====================================
    # Arguments
    $argumentList_3 = @()
    $argumentList_3 += ("-DWB_adminEmail", "'$DarwinBox_admin_Email'")
    $argumentList_3 += ("-DWB_secretKey", "'$DarwinBox_secretKey'")
    $argumentList_3 += ("-DWB_UID", "'$DarwinBox_UID'")
    $argumentList_3 += ("-DWB_inactive_dts_key", "'$Inactive_datasetKey'")
    $argumentList_3 += ("-DWB_InactiveEmployees_output_CSV", "'$InactiveEmployees_CSV'")

    Write-Output ""
    Write-Output "Performing Step 3 : [ Get Inactive Employees From DarwinBox ]"

    # 3
    #RunStep -number 3

    if (Test-Path $InactiveEmployees_CSV -PathType Leaf)
    {
        Write-Output "Inactive Employees CSV file exists. Proceeding with step 4"
        
        Copy-Item -Path $InactiveEmployees_CSV -Destination "$logPath\Inactive_Employees_$(Get-Date -Format "ddMMyyyy_hhmmss_tt").csv"

        ## Step 4
        #====================================
        # Arguments
        $argumentList_4 = @()
        $argumentList_4 += ("-DWB_InactiveEmployees_output_CSV", "'$InactiveEmployees_CSV'")
        $argumentList_4 += ("-company_Domain_CSV", "'$Domain_Info_File'")
        $argumentList_4 += ("-azureAD_Auth_CSV", "'$AzureAD_AuthFile'")

        Write-Output ""
        Write-Output "Performing Step 4 : [ Disable Existing Users in AD ]"

        # 4
        RunStep -number 4
    }
    else
    {
        Write-Output "Inactive Employees CSV file not found."
    }

    #endregion

    #region Step 5

    ## Step 5
    #====================================
    # Arguments
    $argumentList_5 = @()
    $argumentList_5 += ("-DWB_admin_Email", "'$DarwinBox_admin_Email'")
    $argumentList_5 += ("-DWB_secret", "'$DarwinBox_secretKey'")
    $argumentList_5 += ("-DWB_UID", "'$DarwinBox_UID'")
    $argumentList_5 += ("-company_Domain_CSV", "'$Domain_Info_File'")
    $argumentList_5 += ("-azureAD_Auth_CSV", "'$AzureAD_AuthFile'")
    $argumentList_5 += ("-Monitor_Users_output_CSV", "'$Monitoring_Users_CSV'")
    $argumentList_5 += ("-mail_update_Success_CSV", "'$Success_Mail_Update_CSV'")
    $argumentList_5 += ("-missing_AD_Users_CSV", "'$AD_Users_Missing_CSV'")

    Write-Output ""
    Write-Output "Performing Step 5 : [ Update Employee Email From AD to DarwinBox ]"

    # 5
    RunStep -number 5

    #endregion

}
catch 
{
    Write-Output $_
}

Write-Output "------------------------------------------------------------------------------------`nScript ends at $(Get-Date -format 'dd-MM-yyyy hh:mm:ss')"

Stop-Transcript

## Format the log output by removing the unnecessary info
$finalOutput = gc $fullLogPath | Select-Object -Skip 18 | Select-Object -SkipLast 4 

$finalOutput | Out-File $fullLogPath -Force

#endregion
