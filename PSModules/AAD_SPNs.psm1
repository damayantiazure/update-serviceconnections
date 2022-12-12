#===================================================================
# DISCLAIMER:
#
# This sample is provided as-is and is not meant for use on a
# production environment. It is provided only for illustrative
# purposes. The end user must test and modify the sample to suit
# their target environment.
#
# Microsoft can make no representation concerning the content of
# this sample. Microsoft is providing this information only as a
# convenience to you. This is to inform you that Microsoft has not
# tested the sample and therefore cannot make any representations
# regarding the quality, safety, or suitability of any code or
# information found here.
#
#===================================================================

# Return a list of existing secret keys for the service connection
function Get-ExistingKeys {
    param (
        [Parameter(Mandatory=$true)]$sc
    )
    # Get existing secret key/s
    try
    {
        $existingKeys = (Get-AzADAppCredential -ApplicationId $sc.authorization.parameters.serviceprincipalid).KeyId
        Write-Host "Obtained existing secrets for future removal."
    }
    catch
    {
        Write-Host "Failed to get existing secret key/s for `"$($sc.name)`"."
        Write-Host "##vso[task.logissue type=error;]Failed to get existing secret key/s for `"$($sc.name)`"."
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
        Write-Host "##vso[task.complete result=Failed;]"
        Exit
    }
    # Return the list of keys
    return $existingKeys
}

# Generate a new secret for the service connection using Graph API
function New-Secret {
    param (
        [Parameter(Mandatory=$true)]$sc
    )
    try
    {
        # Generate a random password
        $today = (Get-Date).ToUniversalTime()
        $pass = (New-AzADAppCredential -ApplicationId $sc.authorization.parameters.serviceprincipalid -StartDate $today -EndDate $today.AddMonths(6)).SecretText | ConvertTo-SecureString -AsPlainText -Force

        Write-Host "New secret successfully created."
    }
    catch
    {
        Write-Host "Failed to create new secret." -ForegroundColor Red
        Write-Host "##vso[task.logissue type=error;]Failed to create new secret."
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
        Write-Host "##vso[task.complete result=Failed;]"
        Exit
    }
    # Return the generated secure string password
    return $pass
}

# Remove existing secrets
function Remove-ExistingSecrets {
    param (
        [Parameter(Mandatory=$true)]$keys,
        [Parameter(Mandatory=$true)]$sc
    )
    if($keys -gt 0)
    {
        Write-Host "Removing $($keys.Count) previous SPN secrets..."
        foreach($key in $keys)
        {
            try
            {
               Remove-AzADAppCredential -ApplicationId $sc.authorization.parameters.serviceprincipalid -KeyId $key
            }
            catch
            {
                Write-Host "Failed to remove secret with keyId `"$($key)`"."
                Write-Host "##vso[task.logissue type=error;]Failed to remove secret with keyId `"$($key)`"."
                Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
                Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
                Write-Host "##vso[task.complete result=Failed;]"
                Exit
            }
        }
        Write-Host "There is/are now $($(Get-AzADAppCredential -ApplicationId $sc.authorization.parameters.serviceprincipalid).Count) secret/s for `"$($sc.name)`"."
    }
    else
    {
        Write-Host "There were no previous secrets to remove. Nothing left to do."
    }
}

# Exposed by default, but it's a good idea to be explicit
Export-ModuleMember -Function Get-ExistingKeys
Export-ModuleMember -Function New-Secret
Export-ModuleMember -Function Remove-ExistingSecrets