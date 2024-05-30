## 30/May/2024
# https://chatgpt.com/c/2de6180e-1064-460d-ad39-6fb741c1290c
#
# Define variables
$octopusURL = "https://puru1.octopus.app"
$apiKey = "API-SSHAV55JWETPAP6UAIM1ZQ4IBQRITSHZ"
$header = @{ "X-Octopus-ApiKey" = $apiKey }
$sourceVariableFile = "variable-2.json"
$projectName = "test"
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

# Initialize destination matched variables
$destinationMatchedVariables = @()

foreach ($sourceVariable in $sourceVariables.Variables) {
    $name = $sourceVariable.Name
    $value = $sourceVariable.Value
    $scopeEnvironments = $sourceVariable.Scope.Environment

    $destinationVariable = $projectVariables.Variables | Where-Object { $_.Name -eq $name }

    if ($destinationVariable) {
        foreach ($destVar in $destinationVariable) {
            $destScopeEnvironments = $destVar.Scope.Environment

            if ($scopeEnvironments -and ($scopeEnvironments -join ',') -eq ($destScopeEnvironments -join ',')) {
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
