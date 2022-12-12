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
Param(
    [Parameter(Mandatory=$true,
    HelpMessage="Please enter the organisation.")]
    $org,
    [Parameter(Mandatory=$true,
    HelpMessage="Please enter the project.")]
    $project,
    [Parameter(Mandatory=$true,
    HelpMessage="Please enter the name of the service connection running this task.")]
    $scRunning,
    [Parameter(Mandatory=$false,
    HelpMessage="Please enter the name of the service connection for this script to target.")]
    $scTarget
)
$ErrorActionPreference = 'Stop'

# List for service connections without a valid subscription
$subNotFound = New-Object -TypeName 'System.Collections.ArrayList'

# Function to check we should be processing the service connection
Function Confirm-TargetServiceConnection {
    param (
        [Parameter(Mandatory=$true)]$sc
    )
    # If the SC name contains DCX, skip
    if($sc.name -like "*DCX*") {
        Write-Host "$($sc.name) is a DCX service connection. Skipping."
        return $false
    }
    else { return $true }

    # If the SC name contains ServiceNow, skip
    if($sc.name -like "*ServiceNow*") {
        Write-Host "$($sc.name) is a Service Now connection. Skipping."
        return $false
    }
    else { return $true }

    # If the SC name contains DCX, skip
    if($sc.name -like "*snow*") {
        Write-Host "$($sc.name) is a Service Now connection. Skipping."
        return $false
    }
    else { return $true }
}

# Function to process service connections
function Start-ProcessServiceConnection {
    param (
        [Parameter(Mandatory=$true)]$sc
    )

    Write-Host "Processing `"$($sc.name)`"..."

    # Only proceed if the service connection is a manually created ARM service connection with SPN auth
    if($sc.type -eq "azurerm" -and $sc.data.creationMode -eq "Manual" -and $sc.authorization.parameters.authenticationType -eq "spnKey") {
        # Get existing secret key/s
        $existingKeys = Get-ExistingKeys -sc $sc

        if($null -ne $existingKeys) {
            # Create new secret for app registration
            Write-Host "Creating new secret for `"$($sc.name)`"..."
            $pass = New-Secret -sc $sc

            # Update service connection
            Write-Host "Attempting to validate new secret..."

            # If it failed because of subscription not found, add to the ArrayList
            if(Update-ServiceConnection -sc $sc -pass $pass) {
                $subNotFound.Add($sc.name)
                continue
            }
            else {
                # Remove all previous secrets for the service connection SPN
                Remove-ExistingSecrets -keys $existingKeys -sc $sc
                Write-Host "Finished processing `"$($sc.name)`".`n"
            }
        }
        else {
            Write-Host "$($sc.name) has no existing secrets. Skipping."
        }
    }
    else {
        Write-Host "Not a manually created ARM service connection with SPN authentication. Skipping."
    }
}
# Set up variables
$pat = $env:SYSTEM_ACCESSTOKEN

# Convert personal access token to a base64 string
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($pat)"))

# Add base64 token to authorization header
$header = @{authorization = "Basic $token"}

#region prerequisites
# Import custom modules
try
{
    Write-Host "Importing custom modules"
    Import-Module .\PSModules\AAD_SPNs.psm1 -Force
    Import-Module .\PSModules\ADO_ServiceConnections.psm1 -Force
    Write-Host "Custom modules imported successfully."
}
catch
{
    Write-Host "Failed to import custom modules."
    Write-Host "##vso[task.logissue type=warning;]Failed to import custom modules."
    Write-Host "##vso[task.logissue type=warning;]$($_.Exception.Message)"
    Write-Host "##vso[task.logissue type=warning;]$($_.Exception.ItemName)"
    Exit
}

# Install Az.Resources module if not already installed
if (!(Get-Module -ListAvailable -Name Az.Resources))
{
    try
    {
        Write-Host "Installing Az.Resources module..."
        Install-Module -Name Az.Resources -AllowClobber -Force -Scope CurrentUser
        Write-Host "Installed Az.Resources module successfully."
    }
    catch
    {
        Write-Host "Failed to install Az.Resources module."
        Write-Host "##vso[task.logissue type=warning;]Failed to install Az.Resources module."
        Write-Host "##vso[task.logissue type=warning;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=warning;]$($_.Exception.ItemName)"
        Exit
    }
}
else
{
    Write-Host "Az.Resources module already installed. No need to install."
}
# Login with SPN
try
{
    Write-Host "Trying login with SPN..."
    $pass = ConvertTo-SecureString $env:servicePrincipalKey -AsPlainText -Force
    $cred = New-Object -TypeName pscredential -ArgumentList $env:servicePrincipalId, $pass
    Login-AzAccount -Credential $cred -ServicePrincipal -TenantId $env:tenantId | Out-Null
    Write-Host "Login with SPN succeeded."
}
catch
{
    Write-Host "Failed to login with SPN."
    Write-Host "##vso[task.logissue type=warning;]Failed to login with SPN."
    Write-Host "##vso[task.logissue type=warning;]$($_.Exception.Message)"
    Write-Host "##vso[task.logissue type=warning;]$($_.Exception.ItemName)"
    Exit
}
#endregion



# Get all service connections in the project
$endpoints = Get-ServiceConnections -header $header -project $project -org $org

# Process each service connection
if($endpoints)
{
    # Service connection running this script
    $runningSC = $null

    foreach ($sc in $endpoints.value)
    {
        # If a target SC was specified, only process that one
        if($PSBoundParameters.ContainsKey('scTarget')) {
            if($scTarget -eq $sc.name) {
                Write-Host "Processing $($scTarget) and no others..."

                # Make sure it's not a service connection we should avoid
                if(Confirm-TargetServiceConnection -sc $sc) {
                    if($sc.authorization.scheme -ne "ServicePrincipal") {
                        Write-Host "Not using SPN auth. Skipping."
                        Exit
                    }
                    Start-ProcessServiceConnection -sc $sc
                    Exit
                }
                else {
                    Exit
                }
            }
        }
        else {
            Write-Host "Checking $($sc.name)..."

            # Make sure it's not a service connection we should avoid
            if(Confirm-TargetServiceConnection -sc $sc) {
            
                # Skip if not using SPN authorisation scheme
                if($sc.authorization.scheme -ne "ServicePrincipal") {
                    Write-Host "Not using SPN authorisation scheme. Skipping."
                    continue
                }
                # Leave the service connection running this until last
                if($scRunning -eq $sc.name -and $sc.authorization.parameters.serviceprincipalid -eq $env:servicePrincipalId)
                {
                    Write-Host "$($sc.name) is running this. Will process last."
                    $runningSC = $sc
                    continue
                }
                # If the service connection is using the same SPN as the one running this. Warn them and skip.
                if($sc.authorization.parameters.serviceprincipalid -eq $env:servicePrincipalId -and $runningSC -ne $sc.name) {
                    Write-Host "$($sc.name) is using the same SPN as the service connection running this task. Skipping."
                    continue
                }
                Write-Host "Not the service connection running this. Will continue."
                # Process service connection
                Start-ProcessServiceConnection -sc $sc
            }
            else {
                continue
            }
        }
    }
    if($null -ne $runningSC) {
        Write-Host "Finished all others. Now processing $($runningSC.name)..."
        # Last, but not least, process the service connection that's running this script
        Start-ProcessServiceConnection -sc $runningSC
    }
    if($null -ne $subNotFound) {
        Write-Host "Service connections with subscription not found:"
        foreach ($connection in $subNotFound) {
            Write-Host $connection
        }
    }
}
else
{
    Write-Host "There are no service connections in the specified project. Nothing to process."
}