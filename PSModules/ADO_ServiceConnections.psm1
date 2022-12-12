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

# Get all service connections in project
function Get-ServiceConnections {
    param (
        [Parameter(Mandatory=$true)]$header,
        [Parameter(Mandatory=$true)]$org,
        [Parameter(Mandatory=$true)]$project
    )
    $script:header = $header
    $script:org = $org
    $script:project = $project
    try
    {
        Write-Host "Obtaining service connection data..."
        $endpoints = Invoke-RestMethod -Method Get -Uri "https://dev.azure.com/$($script:org)/$($script:project)/_apis/serviceendpoint/endpoints?api-version=6.0-preview.4" -Headers $script:header
    }
    catch
    {
        Write-Host "Failed to obtain service connection data." -ForegroundColor Red
        Write-Host "##vso[task.logissue type=error;]Failed to obtain service connection data."
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
        Write-Host "##vso[task.complete result=Failed;]"
        Exit
    }
    return $endpoints
}

# Validate and update service connection
function Update-ServiceConnection {
    param (
        [Parameter(Mandatory=$true)]$sc,
        [Parameter(Mandatory=$true)]$pass
    )
    # Get service connection
    try
    {
        $endpoint = Invoke-RestMethod -Method Get -Uri "https://dev.azure.com/$($script:org)/$($script:project)/_apis/serviceendpoint/endpoints/$($sc.id)?api-version=6.0-preview.4" -Headers $script:header
    }
    catch
    {
        Write-Host "Failed to get service connection." -ForegroundColor Red
        Write-Host "##vso[task.logissue type=error;]Failed to get service connection."
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
        Write-Host "##vso[task.complete result=Failed;]"
        Exit
    }

    # Add SPN key pair
    $endpoint.authorization.parameters | Add-Member -Name "serviceprincipalkey" -Value ($pass | ConvertFrom-SecureString -AsPlainText) -MemberType NoteProperty -Force | Out-Null

    # Create new placeholder parent object and add all content as a child
    $placeholder = New-Object -TypeName PSObject -Property @{ }
    $placeholder | Add-Member -Name "serviceEndpointDetails" -Value $endpoint -MemberType NoteProperty -Force | Out-Null

    # Add test connection properties for validation
    $testConnection = @{
        dataSourceName = "TestConnection"
    }
    $placeholder | Add-Member -Name "dataSourceDetails" -MemberType NoteProperty -Value $testConnection

    # Convert changes to JSON
    $new = $placeholder | ConvertTo-Json -Depth 100

    # Validate changes before saving
    # Give it 15 seconds to give an "ok" statusCode
    $timeout = New-TimeSpan -Seconds 15
    $sw = [diagnostics.stopwatch]::StartNew()
    do {
        # Validate changes
        try
        {
            $output = Invoke-RestMethod -Method Post -Uri "https://dev.azure.com/$($script:org)/$($script:project)/_apis/serviceendpoint/endpointproxy?endpointId=$($sc.id)&api-version=6.0-preview.1" -Headers $script:header -Body $new -UseBasicParsing -ContentType "application/json"
        }
        catch
        {
            Write-Host "Failed to post validation payload." -ForegroundColor Red
            Write-Host "##vso[task.logissue type=error;]Failed to post validation payload."
            Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
            Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
            Write-Host "##vso[task.complete result=Failed;]"
            Exit
        }
        if($output.statusCode -eq "ok")
        {
            Write-Host "Status code: $($output.statusCode)"
            Write-Host "Successfully validated new secret."
            break
        }

    } while(($sw.elapsed -lt $timeout) -and ($output.statusCode -ne "ok"))
    
    # After the timeout, if statusCode hasn't been "ok", it's failed
    if($output.statusCode -ne "ok")
    {
        Write-Host "New secret validation failed." -ForegroundColor Red
        if($output.errorMessage -like "*SubscriptionNotFound*") {
            Write-Host "Subscription not found. Needs cleaning up."
            return $true
        }
        else {
            Write-Host $output.statusCode
            Write-Host $output.errorMessage
            Write-Host "##vso[task.logissue type=error;]New secret validation failed."
            Write-Host "##vso[task.logissue type=error;]$($output.statusCode)"
            Write-Host "##vso[task.logissue type=error;]$($output.errorMessage)"
            Write-Host "##vso[task.complete result=Failed;]"
            Exit
        }
    }

    # Update service connection with the new secret
    Write-Host "Updating service connection with new secret..."
    $output = $null
    try
    {
        $output = Invoke-RestMethod -Method Put -Uri "https://dev.azure.com/$($script:org)/_apis/serviceendpoint/endpoints/$($sc.id)?api-version=6.0-preview.4" -Headers $script:header -Body ($endpoint | ConvertTo-Json -Depth 100) -ContentType "application/json" -UseBasicParsing
       
        Write-Host "Successfully updated service connection."
    }
    catch
    {
        Write-Host "Failed to update service connection." -ForegroundColor Red
        Write-Host "##vso[task.logissue type=error;]Failed to update service connection."
    
        Write-Host "$($output.statusCode)"
        Write-Host "$($output.errorMessage)"

        Write-Host "##vso[task.logissue type=error;]$($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.StackTrace)"
        Write-Host "##vso[task.logissue type=error;]$($_.Exception.ItemName)"
        Write-Host "##vso[task.complete result=Failed;]"
        Exit
    }
}


# Exposed by default, but it's a good idea to be explicit
Export-ModuleMember -Function Update-ServiceConnection
Export-ModuleMember -Function Get-ServiceConnections