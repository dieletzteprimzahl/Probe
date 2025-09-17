<#
    UiPath Orchestrator Job Monitor
    Example state.json structure created by this script:
    {
        "LastJobId": 0
    }
#>

# =====================
# Configuration Section
# =====================
$OrchestratorURL = 'https://orchestrator.example.com'   # Replace with your Orchestrator base URL
$Tenant          = 'Default'                             # Replace with your tenancy name
$Username        = 'john.doe@example.com'                # Replace with your username or email
$Password        = 'P@ssw0rd!'                           # Replace with your password
$TeamsWebhook    = 'https://outlook.office.com/webhook/...'  # Replace with your Teams Incoming Webhook URL

# Derived configuration
$AuthEndpoint  = "$OrchestratorURL/api/Account/Authenticate"
$JobsEndpoint  = "$OrchestratorURL/odata/Jobs?`$orderby=StartTime desc&`$top=5"
$StateFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'state.json'

# Ensure TLS 1.2+ is used for all outbound calls
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =====================
# Helper Functions
# =====================

function Get-UiPathAuthToken {
    <#
        Authenticates against UiPath Orchestrator and returns the bearer token.
    #>
    param ()

    $body = @{
        tenancyName            = $Tenant
        usernameOrEmailAddress = $Username
        password               = $Password
    } | ConvertTo-Json

    Write-Host "[$(Get-Date -Format o)] Authenticating to UiPath Orchestrator..."

    $response = Invoke-RestMethod -Method Post -Uri $AuthEndpoint -Body $body -ContentType 'application/json'

    $token = $null
    if ($response.result) {
        $token = $response.result
    }
    elseif ($response.access_token) {
        $token = $response.access_token
    }
    elseif ($response.token) {
        $token = $response.token
    }

    if (-not $token) {
        throw 'Authentication response did not contain a token.'
    }

    return $token
}

function Get-UiPathJobs {
    <#
        Retrieves the latest jobs from UiPath Orchestrator using the provided token.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $Token
    )

    $headers = @{ Authorization = "Bearer $Token" }

    Write-Host "[$(Get-Date -Format o)] Retrieving latest jobs..."

    $response = Invoke-RestMethod -Method Get -Uri $JobsEndpoint -Headers $headers -ContentType 'application/json'

    return $response.value
}

function Load-State {
    <#
        Loads the state.json file if it exists. Returns a hashtable with LastJobId.
    #>
    if (Test-Path -Path $StateFilePath) {
        try {
            $json = Get-Content -Path $StateFilePath -Raw | ConvertFrom-Json
            return @{ LastJobId = [long]$json.LastJobId }
        }
        catch {
            Write-Warning "Failed to read state file. Resetting state. Error: $_"
            return @{ LastJobId = 0 }
        }
    }
    else {
        return @{ LastJobId = 0 }
    }
}

function Save-State {
    <#
        Persists the state hashtable to state.json.
    #>
    param (
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $State | ConvertTo-Json | Set-Content -Path $StateFilePath -Encoding utf8
}

function Send-TeamsAlert {
    <#
        Sends a notification to Microsoft Teams via the configured webhook.
    #>
    param (
        [Parameter(Mandatory)] [string] $ReleaseName,
        [Parameter(Mandatory)] [string] $State,
        [Parameter(Mandatory)] [string] $StartTime,
        [Parameter(Mandatory)] [string] $EndTime
    )

    $payload = @{
        title = 'UiPath Orchestrator Alert'
        text  = "🚨 Job $ReleaseName failed! Status: $State, Start: $StartTime, End: $EndTime"
    } | ConvertTo-Json

    Write-Host "[$(Get-Date -Format o)] Sending Teams alert for job '$ReleaseName'."

    Invoke-RestMethod -Method Post -Uri $TeamsWebhook -Body $payload -ContentType 'application/json'
}

# =====================
# Initialization
# =====================

$state = Load-State
$bearerToken = $null

if (-not (Test-Path -Path $StateFilePath)) {
    Save-State -State $state
}

Write-Host "[$(Get-Date -Format o)] Starting UiPath job monitor..."
Write-Host "[$(Get-Date -Format o)] Monitoring every 5 minutes. Press Ctrl+C to exit."

# =====================
# Main Monitoring Loop
# =====================

while ($true) {
    try {
        if (-not $bearerToken) {
            $bearerToken = Get-UiPathAuthToken
        }

        $jobs = Get-UiPathJobs -Token $bearerToken

        if (-not $jobs) {
            Write-Host "[$(Get-Date -Format o)] No jobs returned from Orchestrator."
        }
        else {
            # Order jobs ascending to process from oldest to newest
            $orderedJobs = $jobs | Sort-Object -Property Id

            foreach ($job in $orderedJobs) {
                $jobId = [long]$job.Id

                if ($jobId -le $state.LastJobId) {
                    continue
                }

                $releaseName = $job.ReleaseName
                $stateValue  = $job.State
                $startTime   = $job.StartTime
                $endTime     = $job.EndTime

                switch ($stateValue) {
                    'Faulted' {
                        Write-Warning "[$(Get-Date -Format o)] Job '$releaseName' (Id: $jobId) faulted. Triggering alert."
                        Send-TeamsAlert -ReleaseName $releaseName -State $stateValue -StartTime $startTime -EndTime $endTime
                    }
                    'Running' {
                        Write-Host "[$(Get-Date -Format o)] Job '$releaseName' (Id: $jobId) is running."
                    }
                    'Successful' {
                        Write-Host "[$(Get-Date -Format o)] Job '$releaseName' (Id: $jobId) completed successfully."
                    }
                    default {
                        Write-Host "[$(Get-Date -Format o)] Job '$releaseName' (Id: $jobId) has state '$stateValue'."
                    }
                }

                if ($jobId -gt $state.LastJobId) {
                    $state.LastJobId = $jobId
                }
            }

            Save-State -State $state
        }
    }
    catch [System.Net.WebException] {
        Write-Warning "[$(Get-Date -Format o)] Network error encountered: $($_.Exception.Message). Will retry after delay."
        $bearerToken = $null
    }
    catch {
        Write-Warning "[$(Get-Date -Format o)] Unexpected error: $($_.Exception.Message)."
        $bearerToken = $null
    }

    Write-Host "[$(Get-Date -Format o)] Sleeping for 5 minutes..."
    Start-Sleep -Seconds 300
}
