<#
    File: Get-AzMachineLearningData.ps1
    Author: Christian Bortone (@xybytes) - 2025
    Description: PowerShell functions for dumping Azure Machine Learning Workspace information.
#>

function Get-AzMachineLearningData {

<#
    .SYNOPSIS
        PowerShell function for dumping information from Azure Machine Learning Workspaces.
    .DESCRIPTION
        The function will dump available information for an Azure ML Workspace. This includes compute instances, resources, models, keys, jobs, endpoints, etc.
    .PARAMETER ResourceGroupName
        Resource group name to use.
    .PARAMETER Subscription
        Subscription to use.
    .PARAMETER folder
        The folder to output to.
    .EXAMPLE
        PS C:\> Get-AzMachineLearningData -ResourceGroupName "ML-ResourceGroup" -folder MLOutput -Verbose
        VERBOSE: Logged In as christin.b@xybytes.com
        VERBOSE: Dumping Workspaces from the "main-subscription" Subscription
        VERBOSE:  1 Workspace(s) Enumerated
        VERBOSE:   Attempting to dump data from the space03 workspace
        VERBOSE:    Attempting to dump keys
        VERBOSE:     Attempting to dump compute data
        VERBOSE:    3 Compute Resource(s) Enumerated
        VERBOSE:     Attempting to dump endpoint data
        VERBOSE:    0 Endpoint(s) Enumerated
        VERBOSE:    Attempting to dump keys
        VERBOSE:     Compute Endpoint(s) Enumerated
        VERBOSE:     Attempting to dump jobs data
        VERBOSE:     Job(s) Enumerated
        VERBOSE:     Job(s) Enumerated
        VERBOSE:    2 Compute Job(s) Enumerated
        VERBOSE:    3 Compute Model(s) Enumerated
        VERBOSE:   Completed dumping of the space03 workspace
#>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Resource group name.")]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$false, HelpMessage="Subscription to use.")]
        [string]$Subscription = "",

        [Parameter(Mandatory=$false, HelpMessage="Folder to output to.")]
        [string]$folder = ""
    )

    # Check login status and authenticate if necessary
    $LoginStatus = Get-AzContext
    $accountName = ($LoginStatus.Account).Id
    if ($LoginStatus.Account -eq $null) {
        Write-Warning "No active login. Prompting for login."
        try {
            Connect-AzAccount -ErrorAction Stop
        } catch {
            Write-Warning "Login process failed."
        }
    }

    # Ensure subscription context is set
    if ($Subscription) {
        Select-AzSubscription -SubscriptionName $Subscription | Out-Null
    } else {
        # Prompt user to select subscription(s) if not provided
        $Subscriptions = Get-AzSubscription -WarningAction SilentlyContinue
        $subChoice = $Subscriptions | Out-GridView -Title "Select One or More Subscriptions" -PassThru
        foreach ($sub in $subChoice) {
            Get-AzBatchAccountData -Subscription $sub -folder $folder
        }
        return
    }

    Write-Verbose "Logged In as $accountName"

    # Setup output folder, create if it does not exist
    if ($folder -ne "") {
        if (!(Test-Path $folder)) {
            New-Item -ItemType Directory $folder | Out-Null
        }
    } else {
        $folder = $PWD.Path
    }

    # Suppress breaking change warnings from Az module
    Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null

    Write-Verbose -Message ('Dumping Workspaces from the "' + (Get-AzContext).Subscription.Name + '" Subscription')

    # Retrieve all ML Workspaces in the specified resource group
    $workspaces = Get-AzMLWorkspace -ResourceGroupName $ResourceGroupName

    Write-Verbose "`t$($workspaces.Count) Workspace(s) Enumerated"

    # Iterate through each workspace
    $workspaces | ForEach-Object {

        $currentWorkspace = $_.Name

        Write-Verbose "`t`tAttempting to dump data from the $currentWorkspace workspace"

        # Retrieve and save workspace keys
        try {
            Write-Verbose "`t`t`tAttempting to dump keys"
            $workspaceKeys = Get-AzMLWorkspaceKey -ResourceGroupName $ResourceGroupName -Name $_.Name
            $workspaceKeys | Out-File -Append "$folder\$currentWorkspace-Keys.txt"
        } catch {
            Write-Warning "Failed to retrieve keys for workspace : $currentWorkspace"
        }

        # Retrieve and save compute resources
        try {
            Write-Verbose "`t`t`t`tAttempting to dump compute data"
            $computes = Get-AzMLWorkspaceCompute -ResourceGroupName $ResourceGroupName -WorkspaceName $_.Name |
                ForEach-Object {
                    $propAsObj = $_.Property | ConvertFrom-Json

                    [PSCustomObject]@{
                        Name                                 = $_.Name
                        computeType                          = $propAsObj.properties.computeType
                        Id                                   = $_.Id
                        IdentityType                         = $_.IdentityType
                        Location                             = $_.Location
                        createdOn                            = $propAsObj.createdOn
                        modifiedOn                           = $propAsObj.modifiedOn
                        isAttachedCompute                    = $propAsObj.isAttachedCompute
                        disableLocalAuth                     = $propAsObj.disableLocalAuth
                        subnet                               = $propAsObj.properties.subnet.id
                        sshPublicAccess                      = $propAsObj.properties.sshSettings.sshPublicAccess
                        adminUserName                        = $propAsObj.properties.sshSettings.adminUserName
                        sshPort                              = $propAsObj.properties.sshSettings.sshPort
                        publicIpAddress                      = $propAsObj.properties.connectivityEndpoints.publicIpAddress
                        privateIpAddress                     = $propAsObj.properties.connectivityEndpoints.privateIpAddress
                        lastOperation                        = $propAsObj.properties.lastOperation.operationTime
                        schedules                            = $propAsObj.properties.schedules.computeStartStop
                        vmSize                               = $propAsObj.properties.vmSize
                        applicationSharingPolicy             = $propAsObj.properties.applicationSharingPolicy
                        endpointUri                          = $propAsObj.properties.applications.endpointUri
                        state                                = $propAsObj.properties.state
                    }
                }

            Write-Verbose "`t`t`t$($computes.Count) Compute Resource(s) Enumerated"
            $computes | Out-File -Append "$folder\$currentWorkspace-Computes.txt"
        } catch {
            Write-Warning "Failed to retrieve compute instances for workspace: $currentWorkspace"
        }

        # Retrieve and save online endpoints
        try {
            Write-Verbose "`t`t`t`tAttempting to dump endpoint data"
            $workspace_name = $_.Name
            $endpoints = Get-AzMLWorkspaceOnlineEndpoint -ResourceGroupName $ResourceGroupName -WorkspaceName $workspace_name |
                ForEach-Object {

                    $propAsObj = $_.EndpointPropertiesBaseProperty | ConvertFrom-Json
                    $sysdataAsObj = $_.SystemData | ConvertFrom-Json
                    $keys = Get-AzMLWorkspaceOnlineEndpointKey -ResourceGroupName $ResourceGroupName -WorkspaceName $workspace_name -Name $_.Name

                    [PSCustomObject]@{
                        Name                            = $_.Name
                        Id                              = $_.Id
                        Description                     = $_.Description
                        AuthMode                        = $_.AuthMode
                        Type                            = $_.Type
                        ScoringUri                      = $_.ScoringUri
                        SwaggerUri                      = $_.SwaggerUri
                        CreatedBy                       = $sysdataAsObj.createdBy
                        CreatedAt                       = $sysdataAsObj.createdAt
                        LastModifiedAt                  = $sysdataAsObj.lastModifiedAt
                        SystemDataCreatedAt             = $_.SystemDataCreatedAt
                        Onlineendpointid                = $propAsObj.'azureml.onlineendpointid'
                        AzureAsyncOperationUri          = $propAsObj.AzureAsyncOperationUri
                        PrimaryKey                      = $keys.PrimaryKey
                        SecondaryKey                    = $keys.SecondaryKey
                    }
                }

            Write-Verbose "`t`t`t$($endpoints.Count) Compute Endpoint(s) Enumerated"
            $endpoints | Out-File -Append "$folder\$currentWorkspace-Endpoints.txt"
        } catch {
            Write-Warning "Failed to retrieve endpoints for workspace: $currentWorkspace"
        }

        # Retrieve and save jobs
        try {
            Write-Verbose "`t`t`t`tAttempting to dump jobs data"
            $jobs = Get-AzMLWorkspaceJob -ResourceGroupName $ResourceGroupName -WorkspaceName $_.Name |
                ForEach-Object {

                    $propAsObj = $_.Property | ConvertFrom-Json

                    [PSCustomObject]@{
                        Name                            = $_.Name
                        Id                              = $_.Id
                        SystemDataCreatedAt             = $_.SystemDataCreatedAt
                        SystemDataCreatedBy             = $_.SystemDataCreatedBy
                        jobType                         = $propAsObj.jobType
                        endpoint                        = $propAsObj.services.Studio.endpoint
                        command                         = $propAsObj.command
                        environmentId                   = $propAsObj.environmentId
                        outputs                         = $propAsObj.outputs.default
                    }
                }

            Write-Verbose "`t`t`t$($jobs.Count) Compute Job(s) Enumerated"
            $jobs | Out-File -Append "$folder\$currentWorkspace-Jobs.txt"
        } catch {
            Write-Warning "Failed to retrieve jobs for workspace: $currentWorkspace"
        }

        # Retrieve and save models
        try {
            $models = Get-AzMLWorkspaceModelContainer -ResourceGroupName $ResourceGroupName -WorkspaceName $_.Name |
                ForEach-Object {

                    [PSCustomObject]@{
                        Name                            = $_.Name
                        Id                              = $_.Id
                        SystemDataCreatedAt             = $_.SystemDataCreatedAt
                        Type                            = $_.Type
                        ProvisioningState               = $_.ProvisioningState
                        IsArchived                      = $_.IsArchived
                    }
                }

            Write-Verbose "`t`t`t$($models.Count) Compute Model(s) Enumerated"
            $models | Out-File -Append "$folder\$currentWorkspace-Models.txt"
        } catch {
            Write-Warning "Failed to retrieve models for workspace: $currentWorkspace"
        }

        # Retrieve and save storage account keys
        try {
            $storagekey = Get-AzMLWorkspaceStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $_.Name
            $storagekey | Out-File -Append "$folder\$currentWorkspace-Storagekey.txt"
        } catch {
            Write-Warning "Failed to retrieve storage account keys for workspace: $currentWorkspace"
        }

        Write-Verbose "`t`tCompleted dumping of the $currentWorkspace workspace"
    }
}
