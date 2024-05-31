## 30/May/2024
# https://chatgpt.com/c/2de6180e-1064-460d-ad39-6fb741c1290c
#
# Define variables
$octopusURL = ""
$apiKey = ""
$header = @{ 
    "X-Octopus-ApiKey" = $apiKey
    "Content-Type" = "application/json" 
}
$sourceVariableFile = ""
$projectName = ""
$spaceName = "Default"
# Function to get environment ID by name
function Get-EnvironmentIdByName {
    param (
        [string]$environmentName,
        [array]$environmentList
    )

    foreach ($env in $environmentList) {
        if ($env.Name -eq $environmentName) {
            return $env.Id
        }
    }
    return $null
}
# Function to get environment ID by name
function Get-EnvironmentNameById {
    param (
        [string]$environmentId,
        [array]$environmentList
    )

    foreach ($env in $environmentList) {
        if ($env.Id -eq $environmentId) {
            return $env.Name
        }
    }
    return $null
}

# Get space
$spaces = Invoke-RestMethod -Method Get -Uri "$octopusURL/api/spaces/all" -Headers $header
$space = $spaces | Where-Object { $_.Name -eq $spaceName }

# Get environment list
$destinationEnvironmentList = Invoke-RestMethod -Method Get -Uri "$octopusURL/api/$($space.Id)/environments/all" -Headers $header

# Get destination project
$destinationProjects = Invoke-RestMethod -Method Get -Uri "$octopusURL/api/$($space.Id)/projects/all" -Headers $header
$destinationProject = $destinationProjects | Where-Object { $_.Name -eq "$projectName" } # Change "Your Project Name" accordingly

# Get project variables
$projectVariables = Invoke-RestMethod -Method Get -Uri "$octopusURL/api/$($space.Id)/projects/$($destinationProject.Id)/variables" -Headers $header

# Load source variable file
$sourceVariables = Get-Content -Path $sourceVariableFile | ConvertFrom-Json

# Load all variables into $destinationVariables
$destinationVariables = $projectVariables.Variables

foreach ($sourceVariable in $sourceVariables.Variables) {
    $name = $sourceVariable.Name
    $value = $sourceVariable.Value
    $type = $sourceVariable.Type
    $scopeEnvironments = $sourceVariable.Scope.Environment

    # Check for sensitive variables
    if ($sourceVariable.IsSensitive -eq $true) {
        Write-Host "Warning: Setting sensitive value for $($variableName) to DUMMY VALUE" -ForegroundColor Yellow
        $sourceVariable.Value = "DUMMY VALUE"
    }

    # Check for account type variables
    if ($sourceVariable.Type -match ".*Account") {
        if ($keepSourceAccountVariableValues -eq $false) {
            Write-Host "Warning: Cannot convert account type to destination account as keepSourceAccountVariableValues set to false. Setting to DUMMY VALUE" -ForegroundColor Yellow
            $sourceVariable.Value = "DUMMY VALUE"
        }
    }

    # Check for certificate type variables
    if ($sourceVariable.Type -match ".*Certificate") {
        if ($keepSourceAccountVariableValues -eq $false) {
            Write-Host "Warning: Cannot convert certificate type to destination certificate as keepSourceAccountVariableValues set to false. Setting to DUMMY VALUE" -ForegroundColor Yellow
            $sourceVariable.Value = "DUMMY VALUE"
        }
    }

    # The interpreter is loading only matched variable name and if any new variable from the json is not adding, need to fix the issue
    #$destinationVariable = $projectVariables.Variables | Where-Object { $_.Name -eq $name }

    if ($destinationVariables) {
        
        foreach ($destVar in $destinationVariables) {
            $destScopeEnvironmentsIds = $destVar.Scope.Environment
            # Get environment Names from project variable scope Environment
            $destScopeEnvironmentsNames = @()
            foreach ($destenvId in $destScopeEnvironmentsIds) {
                $destenvName = Get-EnvironmentNameById -environmentId $destenvId -environmentList $destinationEnvironmentList
                if ($destenvName) {
                    $destScopeEnvironmentsNames += $destenvName
                }
            }
            if ($scopeEnvironments -and ($scopeEnvironments -join ',') -eq ($destScopeEnvironmentsNames -join ',')) {
                if ($value -eq $destVar.Value) {
                    Write-Output "Variable '$name' with value '$value' already exists in environments: $($scopeEnvironments -join ', ')"
                } else {
                    Write-Warning "Variable '$name' has different value. Updating value to '$value' in environments: $($scopeEnvironments -join ', ')"
                    $destVar.Value = $value
                }
            }
        }
    } else {
        # Get environment IDs for scope
        $environmentIds = @()
        foreach ($envName in $scopeEnvironments) {
            $envId = Get-EnvironmentIdByName -environmentName $envName -environmentList $destinationEnvironmentList
            if ($envId) {
                $environmentIds += $envId
            }
        }
        # Add new variable
        $newVariable = @{
            Name = $name
            Value = $value
            Type  = $type
            Scope = @{
                Environment = $environmentIds
            }
        }
        $projectVariables.Variables += $newVariable
        Write-Output "Added new variable '$name' with value '$value' in environments: $($scopeEnvironments -join ', ')"
    }
}

# Update the project variables
Write-Host "Saving variables to $octopusURL$($destinationProject.Links.Variables)"
$updateResponse = Invoke-RestMethod -Method Put -Uri "$octopusURL$($destinationProject.Links.Variables)" -Headers $header -Body ($projectVariables | ConvertTo-Json -Depth 10)
Write-Output "Project variables updated successfully."
