Param (
    [Parameter(Mandatory=$true)]
    [string]$DWB_ActiveEmployees_output_CSV,
    [Parameter(Mandatory=$true)]
    [string]$company_Domain_CSV,
    [Parameter(Mandatory=$true)]
    [string]$azureAD_Auth_CSV,
    [Parameter(Mandatory=$true)]
    [string]$Monitor_Users_output_CSV,
    [Parameter(Mandatory=$true)]
    $newUser_Pwd
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
        [string]$LogFileName="Create_Or_Update_Users_in_AD"
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
    Write-Output $Message | Out-File -FilePath $Path -Append -Encoding ascii -Force

    #Write-Host "The log file is saved at $Path" -ForegroundColor Green  
}

function ToNullIfWhiteSpace ($str)
{
	if ([System.String]::IsNullOrWhiteSpace($str)) 
    {
		$str = 'null'
	}	
	return $str
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

function Validate-ADFS_SamAccountName ($samaccountName,$employeeId,$Name)
{
    $final_sam = $samaccountName
    $new_name = $Name
    
    $sam_check = get-aduser -filter { samAccountName -eq $samaccountName }

    if ($sam_check -ne $null)
    {
        $final_sam = $($samaccountName.Substring( 0, $samaccountName.Length - $($employeeId.ToString().Length))) + "$employeeId"
        $new_name = $Name + "$employeeId"
    }

    $op_obj = New-Object psobject
    $op_obj | Add-Member -MemberType NoteProperty -Name "NewName" -Value $new_name
    $op_obj | Add-Member -MemberType NoteProperty -Name "NewSAM" -Value $final_sam

    return $op_obj
}

function Validate-AzureAD_UserPrincipalName ($upn,$employeeId)
{
    $final_upn = $upn

    $upn_check = Get-AzureADUser -All $True | Where-Object { $_.userPrincipalName -eq "$upn" } | Select-Object *

    if ($upn_check -ne $null)
    {
        $pos = $upn.LastIndexOf('@')
        $leftpart = $upn.Substring(0,$pos)
        $rightpart = $upn.Substring($pos+1)

        $final_upn = $leftpart + $employeeId + "@" + $rightpart
    }

    return $final_upn
}

function Validate-ADFS_UserManager ($manager_empID)
{
    $mgr_Identity = $null
    $mgr_info  = get-aduser -filter {employeeID -eq $manager_empID}

    if ($mgr_info -ne $null)
    {
        $mgr_Identity = $mgr_info.SamAccountName
    }

    return $mgr_Identity
}

#endregion

######################################################################################################

Write-Log "Script Execution Logs Start`n"

Write-Output ""
Write-Log "****************************************************************************************************"

Validate-ModuleDependencies
$monitoring_list = @()

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

## Check if the Active Employees output CSV file exists
if (Test-Path $DWB_ActiveEmployees_output_CSV -PathType Leaf)
{    
    ## Check if the company domain input CSV file exists
    if (Test-Path $company_Domain_CSV -PathType Leaf)
    {
        ## Step 1 - Read DarwinBox employees details from Active Employees output CSV
        Write-Output ""
        Write-Log "Reading DarwinBox employees info from Active Employees output CSV file"
        $Active_Emp_output = Import-Csv $DWB_ActiveEmployees_output_CSV
        
        ## Step 2 - Read the details for company and domain Info
        Write-Output ""
        Write-Log "Reading Domain and Company info from CSV file"
        $Domain_Info = Import-Csv $company_Domain_CSV

        Write-Output ""
        Write-Log "======================================================================================="

        if ($Active_Emp_output -ne $null)
        {
            ## Step 3 - Loop through the details from Active Employees CSV output
            foreach ($DWB_Info in $Active_Emp_output)
            {
                Write-Output ""
                Write-Log "DarwinBox Unique Id for User - $($DWB_Info.user_unique_id)"
                
                #region Map Variables

                ## Map the variables between ADFS, AzureAD and DarwinBox
                $ADFS_CostCenter = $AzureAD_extension_CostCenter = $DWB_Info.office_location_cost_center
                $ADFS_Company = $AzureAD_CompanyName = $DWB_Info.group_company
                $ADFS_Department = $AzureAD_Department = $DWB_Info.department_name
                $ADFS_EmployeeID = $AzureAD_employeeId = $DWB_Info.employee_id
                $ADFS_EmploymentStatus = $AzureAD_extension_EmploymentStatus = $DWB_Info.employee_type
                $ADFS_CN = $AzureAD_DisplayName = $DWB_Info.full_name
                $ADFS_locationType = $AzureAD_extension_LocationType = $DWB_Info.location_type
                $ADFS_Manager = $AzureAD_extension_Manager = $DWB_Info.direct_manager_name
                $ADFS_GivenName = $AzureAD_GivenName = $DWB_Info.first_name
                $ADFS_sn = $AzureAD_Surname = $DWB_Info.last_name
                $ADFS_Title = $AzureAD_JobTitle = $DWB_Info.designation_name
                $ADFS_extensionAttribute12 = $AzureAD_extension_BusinessUnit = $DWB_Info.business_unit
                $ADFS_extensionAttribute13 = $AzureAD_extension_JoinDate = $DWB_Info.date_of_joining
                $ADFS_extensionAttribute14 = $AzureAD_extension_LastWorkingDate = $DWB_Info.date_of_exit
                $ADFS_extensionAttribute15 = $AzureAD_extension_DarwinBox_UniqueID = $DWB_Info.user_unique_id
                $ADFS_Modified = $AzureAD_LastDirSyncTime = $DWB_Info.latest_modified_any_attribute
                $ADFS_samaccountname = $AzureAD_onPremisesDistinguishedName = $DWB_Info.first_name_last_name
                $ADFS_manager_uniqueID = $AzureAD_managerUniqueID = $DWB_Info.direct_manager_employee_id
            
                #endregion

                #region Determine AD from GroupCompany
                ## Determine AD domain based on group company
                if (($DWB_Info.group_company -eq 'PT Panen Lestari Indonesia') -and ($DWB_Info.location_type -like "*office*"))
                {
                    $Domain_to_Use = "pli-indonesia.co.id"
                }
                else
                {
                    $Domain_to_Use = ($Domain_Info | ?{$_.GroupCompany -eq $DWB_Info.group_company}).Domain
                }
                #endregion

                #region Create/Update User in respective domain
                
                Write-Output ""
                Write-Log "Determining the domain type from the group company name"

                ## Check whether domain is ADFS or Azure
                $Domain_Type = ($Domain_Info | ?{$_.GroupCompany -eq $DWB_Info.group_company}).DomainType

                ## Determine the user based on domain type
                if ($Domain_Type -eq "ADFS")
                {
                    Write-Log "Domain Type - ADFS"

                    #region Create or Update ADFS user

                    Write-Output ""
                    Write-Log "Checking if the user exists in ADFS or not"

                    ## Check if the user exists in AD based on employee ID filter
                    $AD_User = get-aduser -filter {extensionAttribute15 -eq $ADFS_extensionAttribute15}
                    

                    $SAM_temp = "$ADFS_GivenName.$ADFS_sn" -replace ' ',''
                    $SAM = $SAM_temp[0..19] -join ''
                    $SAM = Validate-ADFS_SamAccountName -samaccountName $SAM -employeeId $ADFS_extensionAttribute15 -Name $ADFS_CN

                    ## Build extension attributes for update
                    $ext_Attributes = @{ 
                                    'extensionAttribute12' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute12)
                                    'extensionAttribute13' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute13)
                                    'extensionAttribute14' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute14)
                                    'extensionAttribute15' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute15)
                                    'CostCenter' = $(ToNullIfWhiteSpace -str $ADFS_CostCenter)
                                    'EmploymentStatus' = $(ToNullIfWhiteSpace -str $ADFS_EmploymentStatus)
                                    'locationType' = $(ToNullIfWhiteSpace -str $ADFS_locationType)
                                }

                    ## If user found
                    if ($AD_User -ne $null)
                    {
                        Write-Log "User with DarwinBox unique user Id set to $ADFS_extensionAttribute15 already exists"

                        $DWB_Date = Format-LastWorkingDate -input_Date $ADFS_Modified
                        $DWB_Date

                        ## Filter users based on last modified date from darwinBox as one day before
                        if ($DWB_Date -gt (Get-Date).AddHours(-25))
                        {
                            Write-Log "Updating details for the existing user with unique ID $ADFS_extensionAttribute15"
                        
                            $ADFS_args_update = @{   
	                            Company = $(ToNullIfWhiteSpace -str $ADFS_Company)
                                Department = $(ToNullIfWhiteSpace -str $ADFS_Department)
                                EmployeeID = $(ToNullIfWhiteSpace -str $ADFS_EmployeeID)
	                            Enabled = $false
                                GivenName = $(ToNullIfWhiteSpace -str $ADFS_GivenName)
                                Identity = $SAM.NewSAM
                                Surname = $(ToNullIfWhiteSpace -str $ADFS_sn)
                                Title = $(ToNullIfWhiteSpace -str $ADFS_Title)
                                SamAccountName = $SAM.NewSAM
                                DisplayName = $("$ADFS_GivenName" + " " + "$ADFS_sn")
                            }
 
                             ## Check if the manager property returned from DarwinBox is not null
                            $mgr = $(ToNullIfWhiteSpace -str $ADFS_manager_uniqueID)
                            if ($mgr -ne 'null')
                            {
                                $found = Validate-ADFS_UserManager -manager_empID $ADFS_manager_uniqueID

                                if ($found -ne $null)
                                {                               
                                    $ADFS_args_update.Add('Manager',"$found")
                                }
                            }                          
                            
                            ## Update details for the existing user
                            Set-ADUser @ADFS_args_update -Replace $ext_Attributes

                            Write-Log "User details updated successfully"
                        }
                        else
                        {
                            Write-Log "Update operation will be skipped for the existing user with unique ID $ADFS_extensionAttribute15 as it wasn't modified a day before."
                        }

                        $monitoring_list += $DWB_Info
                    }
                    ## If user doesn't exist already
                    else
                    {
                        Write-Log "Creating new user with samAccountName as $($SAM.NewSAM)"

                        $ADFS_args_create = @{   
                            AccountPassword = $(ConvertTo-SecureString "$newUser_Pwd" -AsPlainText -Force)
	                        Company = $(ToNullIfWhiteSpace -str $ADFS_Company)
                            Department = $(ToNullIfWhiteSpace -str $ADFS_Department)
                            EmployeeID = $(ToNullIfWhiteSpace -str $ADFS_EmployeeID)
	                        Enabled = $false
                            Name = $(ToNullIfWhiteSpace -str $SAM.NewName)
                            GivenName = $(ToNullIfWhiteSpace -str $ADFS_GivenName)
                            Surname = $(ToNullIfWhiteSpace -str $ADFS_sn)
                            Title = $(ToNullIfWhiteSpace -str $ADFS_Title)
                            SamAccountName = $SAM.NewSAM
                            Path = "OU=Users, OU=MAP, DC=map, DC=co, DC=id"
                            DisplayName = $("$ADFS_GivenName" + " " + "$ADFS_sn")
                            OtherAttributes = @{ 
                                'extensionAttribute12' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute12)
                                'extensionAttribute13' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute13)
                                'extensionAttribute14' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute14)
                                'extensionAttribute15' = $(ToNullIfWhiteSpace -str $ADFS_extensionAttribute15)
                                'CostCenter' = $(ToNullIfWhiteSpace -str $ADFS_CostCenter)
                                'EmploymentStatus' = $(ToNullIfWhiteSpace -str $ADFS_EmploymentStatus)
                                'locationType' = $(ToNullIfWhiteSpace -str $ADFS_locationType)
                            }
                            W
                        }

                        ## Check if the manager property returned from DarwinBox is not null
                        $mgr_1 = $(ToNullIfWhiteSpace -str $ADFS_manager_uniqueID)
                        if ($mgr_1 -ne 'null')
                        {
                            $found_1 = Validate-ADFS_UserManager -manager_empID $ADFS_manager_uniqueID

                            if ($found_1 -ne $null)
                            {                               
                                $ADFS_args_create.Add('Manager',"$found_1")
                            }                          
                        }

                        New-ADUser @ADFS_args_create

                        Write-Log "User created successfully in ADFS."

                        $monitoring_list += $DWB_Info
                    }

                    #endregion
                }
                else
                {
                    Write-Log "Domain Type - AzureAD"

                    #region Build User Args
                
                    $userPrincipalName = "$AzureAD_GivenName.$AzureAD_Surname@$Domain_to_Use" -replace ' ',''
                    $userPrincipalName = Validate-AzureAD_UserPrincipalName -upn $userPrincipalName -employeeId $AzureAD_extension_DarwinBox_UniqueID

                    # Create user profile on Azure AD
                    $PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
                    $PasswordProfile.Password = $(ConvertTo-SecureString "$newUser_Pwd" -AsPlainText -Force)

                    ## Build new user args
                    $AzureAD_args = @{
                        AccountEnabled = $false
                        PasswordProfile = $PasswordProfile
                        UserPrincipalName = $userPrincipalName 
                        CompanyName = $(ToNullIfWhiteSpace -str $AzureAD_CompanyName)
                        Department = $(ToNullIfWhiteSpace -str $AzureAD_Department)
                        DisplayName = $(ToNullIfWhiteSpace -str $AzureAD_DisplayName)
                        GivenName = $(ToNullIfWhiteSpace -str $AzureAD_GivenName)
                        Surname = $(ToNullIfWhiteSpace -str $AzureAD_Surname)
                        JobTitle = $(ToNullIfWhiteSpace -str $AzureAD_JobTitle)
                        mailNickname = $AzureAD_GivenName -replace ' ',''
                    }

                    ## Build new user extension properties
                    $AzureAD_ExtensionProperties = new-object psobject
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "employeeId" -Value $(ToNullIfWhiteSpace -str "$AzureAD_employeeId")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "CostCenter" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_CostCenter")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "EmploymentStatus" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_EmploymentStatus")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "LocationType" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_LocationType")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "Manager" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_Manager")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "BusinessUnit" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_BusinessUnit")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "JoinDate" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_JoinDate")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "LastWorkingDate" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_LastWorkingDate")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "onPremisesDistinguishedName" -Value $(ToNullIfWhiteSpace -str "$AzureAD_onPremisesDistinguishedName")
                    $AzureAD_ExtensionProperties | Add-Member -MemberType NoteProperty -Name "DarwinBox_UniqueID" -Value $(ToNullIfWhiteSpace -str "$AzureAD_extension_DarwinBox_UniqueID")

                    #endregion

                    #region Check and Create AzureAD user

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

                        $userInfo = $AzAD_User

                        $DWB_Date = Format-LastWorkingDate -input_Date $AzureAD_LastDirSyncTime

                        ## Filter users based on last modified date from darwinBox as one day before
                        if ($DWB_Date -gt (Get-Date).AddHours(-25))
                        {
                            Write-Log "Updating details for the existing user with DarwinBox unique user Id set to $AzureAD_extension_DarwinBox_UniqueID"
                        
                            ## Update details for the existing user
                            Set-AzureADUser -ObjectId $AzAD_User.ObjectId -UserPrincipalName $userPrincipalName `
                                            -CompanyName $AzureAD_CompanyName -Department $AzureAD_Department `
                                            -DisplayName $AzureAD_DisplayName -GivenName $AzureAD_GivenName `
                                            -Surname $AzureAD_Surname -JobTitle $AzureAD_JobTitle `
                                            -MailNickName $($AzureAD_GivenName -replace ' ','')
                            
                            ## Update extension properties for the existing user
                            foreach ($prop in ($($AzureAD_ExtensionProperties | gm -MemberType NoteProperty).Name))
                            {
                                Validate-ExtensionProperty -ext_Name $prop -ext_Value $($AzureAD_ExtensionProperties.$prop) `
                                                           -userObjectId $AzAD_User.objectId -appName 'Azure_AD_Connect'
                            }

                            Write-Log "User details updated successfully"
                        }
                        else
                        {
                            Write-Log "Update operation will be skipped for the existing user with unique ID $AzureAD_extension_DarwinBox_UniqueID as it wasn't modified a day before."
                        }

                        $monitoring_list += $DWB_Info
                    }
                    ## If user doesn't exist already
                    else
                    {
                        Write-Log "Creating new user with samAccountName as $userPrincipalName"

                        ## Create new User
                        $userInfo = New-AzureADUser @AzureAD_args

                        Write-Log "User created successfully in Azure AD"

                        Write-Output ""
                        Write-Log "Setting the extension properties for the user"

                        ## Add extension properties to the newly created user
                        foreach ($prop in ($($AzureAD_ExtensionProperties | gm -MemberType NoteProperty).Name))
                        {
                            Validate-ExtensionProperty -ext_Name $prop -ext_Value $($AzureAD_ExtensionProperties.$prop) `
                                                       -userObjectId $userInfo.objectId -appName 'Azure_AD_Connect'
                        }
                        #endregion
                    
                        Write-Log "Extension properties validated successfully"  

                        $monitoring_list += $DWB_Info
                    }         
                }
                #endregion

                Write-Output ""
                Write-Log "======================================================================================="
            }

            Write-Output ""
            Write-Log "Exporting the newly created users to Monitoring CSV file for Email updation purposes"
            $monitoring_list | Export-Csv -Path $Monitor_Users_output_CSV -Encoding UTF8 -NoTypeInformation
            Write-Log "Users exported successfully."
        }
        else
        {
            Write-Log "The output CSV file for Active Employees CONTAINS NO RECORDS." -Level Warn
        }
    }
    else
    {
        Write-Log "Input CSV file for companies and domain info NOT FOUND at $company_Domain_CSV." -Level Error
    }
}
else
{
    Write-Log "Active Employees Output CSV file NOT FOUND at $azureAD_Auth_CSV." -Level Error
}

Write-Output ""
Write-Output ""
Write-Log "****************************************************************************************************"
Write-Output ""
Write-Output ""

Write-Log "Script Execution Logs End `n`n"

#endregion

######################################################################################################
