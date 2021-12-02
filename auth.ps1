 $auth_Obj = Import-Csv "D:\UAT\Resources\Auth_Details.csv"
    # Login to Azure PowerShell with your Service Principal and Certificate    
    Connect-AzureAD -TenantId $auth_Obj.Tenant_ID `                    
    -ApplicationId $auth_Obj.App_ID `
    -CertificateThumbprint $auth_Obj.Cert_Thumbprint | Out-Null