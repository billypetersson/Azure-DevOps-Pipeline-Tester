#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local Azure DevOps Pipeline Tester - Plan and Validation Only
.DESCRIPTION
    A script that replicates your actual Azure DevOps pipeline plan stage locally:
    - Bicep build and validation
    - Azure provider checks
    - What-if analysis
    - PSRule compliance testing
.PARAMETER Step
    Pipeline step to run: Build, Validate, WhatIf, PSRule, or All (default: All)
.PARAMETER Environment
    Environment to test: dev, tst, uat, prod (auto-detects from branch/folder if not specified)
.PARAMETER SkipBuild
    Skip Bicep build step
.PARAMETER SkipValidation
    Skip Azure validation step
.PARAMETER SkipWhatIf
    Skip what-if analysis
.PARAMETER SkipPSRule
    Skip PSRule analysis
.PARAMETER Verbose
    Enable verbose logging
.PARAMETER KeepAllFiles
    Keep all generated files after execution
.PARAMETER NoCleanup
    Skip file cleanup entirely
.EXAMPLE
    .\test-pipeline.ps1
    .\test-pipeline.ps1 -Step Build -Environment dev
    .\test-pipeline.ps1 -Step All -Environment prod -Verbose
#>

param(
    [ValidateSet("Build", "Validate", "WhatIf", "PSRule", "All")]
    [string]$Step = "All",
    
    [ValidateSet("dev", "tst", "uat", "prod")]
    [string]$Environment,
    
    [string]$Location = "West Europe",
    
    [switch]$SkipBuild,
    [switch]$SkipValidation,
    [switch]$SkipWhatIf,
    [switch]$SkipPSRule,
    [switch]$Verbose,
    [switch]$KeepAllFiles,
    [switch]$NoCleanup
)

# Initialize logging
$script:LogEntries = @()
$script:StartTime = Get-Date
$script:CurrentPath = Get-Location
$script:ErrorCount = 0
$script:WarningCount = 0
$script:OutputDir = Join-Path $script:CurrentPath "pipeline-outputs"

# Pipeline configuration - Dynamic loading from config files
$script:PipelineConfig = @{}

function Initialize-PipelineConfig {
    # Look for Azure DevOps pipeline files in common locations
    $pipelineLocations = @(
        # Root directory files
        @{
            Path = "."
            Patterns = @(
                "azure-pipelines.yml",
                "azure-pipelines.yaml", 
                "azure-pipeline.yml",
                "azure-pipeline.yaml",
                "*pipeline*.yml",
                "*pipeline*.yaml"
            )
        },
        # .pipelines folder (common Azure DevOps structure)
        @{
            Path = ".pipelines"
            Patterns = @(
                "*.yml",
                "*.yaml"
            )
        },
        # pipelines folder (alternative structure)
        @{
            Path = "pipelines"
            Patterns = @(
                "*.yml",
                "*.yaml"
            )
        },
        # .azure-pipelines folder
        @{
            Path = ".azure-pipelines"
            Patterns = @(
                "*.yml",
                "*.yaml"
            )
        }
    )
    
    $pipelineFile = $null
    
    foreach ($location in $pipelineLocations) {
        if (Test-Path $location.Path) {
            foreach ($pattern in $location.Patterns) {
                $searchPath = Join-Path $location.Path $pattern
                $files = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
                if ($files) {
                    $pipelineFile = $files[0].FullName
                    Write-PipelineLog "Found pipeline file: $pipelineFile"
                    break
                }
            }
            if ($pipelineFile) { break }
        }
    }
    
    if (-not $pipelineFile) {
        Write-PipelineLog "No Azure DevOps pipeline file found" -Level Warning
        Write-PipelineLog "Searched in: root directory, .pipelines/, pipelines/, .azure-pipelines/" -Level Warning
        Write-PipelineLog "Looking for: *.yml, *.yaml, azure-pipelines.yml, etc." -Level Warning
        New-DefaultConfig
        return $true
    }
    
    Write-PipelineLog "Reading pipeline configuration from: $pipelineFile"
    
    try {
        $pipelineContent = Get-Content $pipelineFile -Raw
        ConvertFrom-PipelineVariables -content $pipelineContent
        Write-PipelineLog "✓ Configuration loaded from pipeline file" -Level Success
        return $true
    }
    catch {
        Write-PipelineLog "✗ Failed to parse pipeline file: $($_.Exception.Message)" -Level Error
        New-DefaultConfig
        return $true
    }
}

function ConvertFrom-PipelineVariables {
    param([string]$content)
    
    # Parse YAML pipeline file for variables
    $lines = $content -split "`n"
    $inVariablesSection = $false
    $inConditionalBlock = $false
    $currentCondition = ""
    $environments = @{}
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        
        # Skip comments and empty lines
        if ($line -match "^\s*#" -or $line -eq "") { continue }
        
        # Detect variables section
        if ($line -match "^variables\s*:") {
            $inVariablesSection = $true
            continue
        }
        
        # Exit variables section when we hit another top-level section
        if ($inVariablesSection -and $line -match "^(stages|jobs|steps|trigger|pr|pool|resources)\s*:") {
            $inVariablesSection = $false
            continue
        }
        
        if ($inVariablesSection) {
            # Handle conditional blocks (compile-time)
            if ($line -match "^\s*-\s*\$\{\{\s*if\s+eq\(variables\['Build\.SourceBranch'\],\s*'([^']+)'\)\s*\}\}\s*:") {
                $branchRef = $matches[1]
                $currentCondition = $branchRef -replace "refs/heads/", ""
                $inConditionalBlock = $true
                $environments[$currentCondition] = @{}
                continue
            }
            
            # Handle variable assignments
            if ($line -match "^\s*-?\s*name\s*:\s*(.+)" -or $line -match "^\s*-?\s*(.+)\s*:") {
                $varLine = $line -replace "^\s*-?\s*", ""
                if ($varLine -match "^name\s*:\s*(.+)") {
                    $varName = $matches[1].Trim()
                    # Look for value on next line
                    if ($i + 1 -lt $lines.Count) {
                        $nextLine = $lines[$i + 1].Trim()
                        if ($nextLine -match "^\s*value\s*:\s*(.+)") {
                            $varValue = $matches[1].Trim().Trim('"')
                            if ($inConditionalBlock -and $currentCondition) {
                                $environments[$currentCondition][$varName] = $varValue
                            }
                        }
                    }
                }
                elseif ($varLine -match "^(.+?)\s*:\s*(.+)") {
                    $varName = $matches[1].Trim()
                    $varValue = $matches[2].Trim().Trim('"')
                    if ($inConditionalBlock -and $currentCondition) {
                        $environments[$currentCondition][$varName] = $varValue
                    }
                }
            }
        }
    }
    
    # Convert parsed data to expected format
    foreach ($env in $environments.Keys) {
        $envVars = $environments[$env]
        
        # Use proper null coalescing with fallback values
        $subscriptionId = if ($envVars["AZURE_SUBSCRIPTION_ID"]) { $envVars["AZURE_SUBSCRIPTION_ID"] } else { "" }
        $environment = if ($envVars["ENVIRONMENT"]) { $envVars["ENVIRONMENT"] } else { $env }
        $serviceConnection = if ($envVars["SERVICE_CONNECTION"]) { $envVars["SERVICE_CONNECTION"] } else { "sc-$env" }
        $template = if ($envVars["TEMPLATE"]) { $envVars["TEMPLATE"] } else { "main.bicep" }
        $templateParameters = if ($envVars["TEMPLATE_PARAMETERS"]) { $envVars["TEMPLATE_PARAMETERS"] } else { "$env.bicepparam" }
        $location = if ($envVars["LOCATION"]) { $envVars["LOCATION"] } else { "westeurope" }
        
        $script:PipelineConfig[$env] = @{
            AZURE_SUBSCRIPTION_ID = $subscriptionId
            ENVIRONMENT = $environment
            SERVICE_CONNECTION = $serviceConnection
            TEMPLATE = $template
            TEMPLATE_PARAMETERS = $templateParameters
            LOCATION = $location
        }
    }
    
    Write-PipelineLog "Parsed environments from pipeline: $($script:PipelineConfig.Keys -join ', ')"
    
    # Log the configurations found
    foreach ($env in $script:PipelineConfig.Keys) {
        $config = $script:PipelineConfig[$env]
        Write-PipelineLog "Environment '$env': Subscription=$($config.AZURE_SUBSCRIPTION_ID), Template=$($config.TEMPLATE)"
    }
}

function New-DefaultConfig {
    Write-PipelineLog "Creating default configuration based on detected files..." -Level Warning
    
    # Auto-detect environments from parameter files
    $paramFiles = Get-ChildItem -Filter "*.bicepparam" -ErrorAction SilentlyContinue
    
    if ($paramFiles.Count -eq 0) {
        # No parameter files found, create basic dev config
        $script:PipelineConfig["dev"] = @{
            AZURE_SUBSCRIPTION_ID = ""
            ENVIRONMENT = "development"
            SERVICE_CONNECTION = "sc-dev"
            TEMPLATE = "main.bicep"
            TEMPLATE_PARAMETERS = "dev.bicepparam"
            LOCATION = "westeurope"
        }
        Write-PipelineLog "No .bicepparam files found. Created default 'dev' configuration."
        Write-PipelineLog "Please update subscription ID and create dev.bicepparam file." -Level Warning
    }
    else {
        # Create configurations based on found parameter files
        foreach ($paramFile in $paramFiles) {
            $envName = $paramFile.BaseName
            
            # Map common environment names
            $environmentFullName = switch ($envName) {
                "dev" { "development" }
                "tst" { "test" }
                "test" { "test" }
                "uat" { "acceptance" }
                "prod" { "production" }
                default { $envName }
            }
            
            $script:PipelineConfig[$envName] = @{
                AZURE_SUBSCRIPTION_ID = ""
                ENVIRONMENT = $environmentFullName
                SERVICE_CONNECTION = "sc-$envName"
                TEMPLATE = "main.bicep"
                TEMPLATE_PARAMETERS = $paramFile.Name
                LOCATION = "westeurope"
            }
            
            Write-PipelineLog "Auto-detected environment '$envName' from $($paramFile.Name)"
        }
        
        Write-PipelineLog "Please update subscription IDs in your Azure DevOps pipeline file or provide them as parameters." -Level Warning
    }
}

function Update-GlobalConfig {
    # Look for global configuration in pipeline files across all locations
    $pipelineLocations = @(".", ".pipelines", "pipelines", ".azure-pipelines")
    
    foreach ($location in $pipelineLocations) {
        if (Test-Path $location) {
            $searchPath = Join-Path $location "*pipeline*.y*ml"
            $pipelineFiles = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
            
            foreach ($file in $pipelineFiles) {
                try {
                    $content = Get-Content $file.FullName -Raw
                    
                    # Extract global variables from pipeline
                    if ($content -match "AZURE_PROVIDERS[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.AZURE_PROVIDERS = $matches[1].Trim()
                    }
                    if ($content -match "SCOPE[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.SCOPE = $matches[1].Trim()
                    }
                    if ($content -match "RULE_BASELINE[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.RULE_BASELINE = $matches[1].Trim()
                    }
                    if ($content -match "RULE_MODULES[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.RULE_MODULES = $matches[1].Trim()
                    }
                    if ($content -match "RULE_OPTION[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.RULE_OPTION = $matches[1].Trim()
                    }
                    if ($content -match "LOG_SEVERITY[^:]*:\s*[""']?([^""'\r\n]+)") {
                        $script:GlobalConfig.LOG_SEVERITY = $matches[1].Trim()
                    }
                    
                    Write-PipelineLog "✓ Global configuration updated from: $($file.Name)" -Level Success
                    return
                }
                catch {
                    Write-PipelineLog "Could not read global config from $($file.Name): $($_.Exception.Message)" -Level Warning
                }
            }
        }
    }
}

$script:GlobalConfig = @{
    AZURE_PROVIDERS = "Microsoft.Advisor,Microsoft.AlertsManagement,Microsoft.Authorization,Microsoft.Consumption,Microsoft.EventGrid,microsoft.insights,Microsoft.ManagedIdentity,Microsoft.Management,Microsoft.Network,Microsoft.PolicyInsights,Microsoft.ResourceHealth,Microsoft.Resources,Microsoft.Security"
    AZURE_PROVIDER_WAIT_SECONDS = 10
    AZURE_PROVIDER_WAIT_COUNT = 30
    COST_THRESHOLD = -1
    CURRENCY = "EUR"
    LOG_SEVERITY = "INFO"
    RULE_BASELINE = "Azure.Default"
    RULE_MODULES = "Az.Resources,PSRule.Rules.Azure"
    RULE_OPTION = ""
    SCOPE = "sub"
    VERSION_ACE_TOOL = "1.6"
    WORKFLOW_VERSION = "v1"
}

function Write-PipelineLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogEntries += $logEntry
    
    switch ($Level) {
        "Info" { Write-Host $logEntry -ForegroundColor Cyan }
        "Warning" { 
            Write-Host $logEntry -ForegroundColor Yellow
            $script:WarningCount++
        }
        "Error" { 
            Write-Host $logEntry -ForegroundColor Red
            $script:ErrorCount++
        }
        "Success" { Write-Host $logEntry -ForegroundColor Green }
    }
}

function Show-Header {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║            Azure DevOps Pipeline Tester v2.0                ║" -ForegroundColor Blue
    Write-Host "║                 Plan Stage Testing Only                      ║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
    Write-PipelineLog "Starting pipeline tests in: $($script:CurrentPath)"
    Write-PipelineLog "Pipeline step: $Step"
    Write-PipelineLog "Execution started at: $($script:StartTime)"
    Write-Host ""
}

function Get-EnvironmentConfig {
    if (-not $Environment) {
        # Auto-detect environment from folder/branch context
        $folderName = Split-Path $script:CurrentPath -Leaf
        $gitBranch = ""
        
        try {
            $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
        } catch { }
        
        if ($gitBranch -eq "dev" -or $folderName -like "*dev*") {
            $Environment = "dev"
        } elseif ($gitBranch -eq "tst" -or $folderName -like "*test*") {
            $Environment = "tst"
        } elseif ($gitBranch -eq "uat" -or $folderName -like "*uat*") {
            $Environment = "uat"
        } elseif ($gitBranch -eq "prod" -or $gitBranch -eq "main" -or $gitBranch -eq "master" -or $folderName -like "*prod*") {
            $Environment = "prod"
        } else {
            $Environment = "dev"  # Default
        }
        
        Write-PipelineLog "Auto-detected environment: $Environment"
    }
    
    $config = $script:PipelineConfig[$Environment].Clone()
    
    # Auto-detect actual file paths in current directory
    $mainBicep = @("main.bicep", "network/main.bicep", "mdp/network/main.bicep") | Where-Object { Test-Path $_ } | Select-Object -First 1
    $paramFile = @("$Environment.bicepparam", "network/$Environment.bicepparam", "mdp/network/$Environment.bicepparam") | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($mainBicep) {
        $config.TEMPLATE = $mainBicep
        Write-PipelineLog "Found template: $mainBicep"
    } else {
        Write-PipelineLog "Template file not found, using default: $($config.TEMPLATE)" -Level Warning
    }
    
    if ($paramFile) {
        $config.TEMPLATE_PARAMETERS = $paramFile
        Write-PipelineLog "Found parameters: $paramFile"
    } else {
        Write-PipelineLog "Parameter file not found, using default: $($config.TEMPLATE_PARAMETERS)" -Level Warning
    }
    
    return $config
}

function Test-Prerequisites {
    Write-PipelineLog "Checking prerequisites..."
    
    # Initialize dynamic configuration
    if (!(Initialize-PipelineConfig)) {
        Write-PipelineLog "Failed to initialize pipeline configuration" -Level Error
        return $false
    }
    
    # Update global configuration from config file
    Update-GlobalConfig
    
    $prerequisites = @(
        @{ Name = "Azure CLI"; Command = "az" },
        @{ Name = "PowerShell 7+"; Command = "pwsh" }
    )
    
    $missing = @()
    
    foreach ($prereq in $prerequisites) {
        try {
            $null = Get-Command $prereq.Command -ErrorAction Stop
            Write-PipelineLog "✓ $($prereq.Name) is installed" -Level Success
        } catch {
            Write-PipelineLog "✗ $($prereq.Name) is missing" -Level Error
            $missing += $prereq
        }
    }
    
    # Check Azure CLI authentication
    try {
        $account = az account show --query "name" -o tsv 2>$null
        if ($account) {
            Write-PipelineLog "✓ Azure CLI authenticated as: $account" -Level Success
        } else {
            Write-PipelineLog "✗ Azure CLI not authenticated. Run 'az login'" -Level Error
            $missing += @{ Name = "Azure Authentication" }
        }
    } catch {
        Write-PipelineLog "✗ Azure CLI authentication check failed" -Level Error
        $missing += @{ Name = "Azure Authentication" }
    }
    
    # Check Bicep
    try {
        $bicepVersion = az bicep version 2>$null
        if ($bicepVersion) {
            Write-PipelineLog "✓ Bicep CLI is available" -Level Success
        } else {
            Write-PipelineLog "Installing Bicep CLI..." -Level Warning
            az bicep install
        }
    } catch {
        Write-PipelineLog "Installing Bicep CLI..." -Level Warning
        az bicep install
    }
    
    # Check PSRule modules (only if not skipping)
    if (-not $SkipPSRule) {
        $psruleModules = @("PSRule", "PSRule.Rules.Azure")
        foreach ($module in $psruleModules) {
            if (Get-Module -ListAvailable -Name $module) {
                Write-PipelineLog "✓ $module module is available" -Level Success
            } else {
                Write-PipelineLog "Installing $module module..." -Level Warning
                try {
                    Install-Module $module -Force -AllowClobber -Scope CurrentUser
                    Write-PipelineLog "✓ $module module installed successfully" -Level Success
                } catch {
                    Write-PipelineLog "✗ Failed to install $module module" -Level Error
                    $missing += @{ Name = "$module PowerShell Module" }
                }
            }
        }
    }
    
    return $missing.Count -eq 0
}

function Invoke-BicepBuild {
    param($config)
    
    Write-Host ""
    Write-PipelineLog "═══ BICEP BUILD ═══" -Level Info
    
    $template = $config.TEMPLATE
    $templateParams = $config.TEMPLATE_PARAMETERS
    
    if (!(Test-Path $template)) {
        Write-PipelineLog "✗ Template file not found: $template" -Level Error
        return $false
    }
    
    $success = $true
    
    # Build main template
    if ($template.EndsWith('.bicep')) {
        $outputFile = $template -replace '\.bicep$', '.json'
        Write-PipelineLog "Building Bicep template: $template"
        
        try {
            $result = az bicep build --file $template --outfile $outputFile 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-PipelineLog "✓ Built successfully: $outputFile" -Level Success
                
                # Copy to outputs
                if (!(Test-Path $script:OutputDir)) {
                    New-Item -ItemType Directory -Path $script:OutputDir | Out-Null
                }
                Copy-Item $outputFile $script:OutputDir -Force
            } else {
                Write-PipelineLog "✗ Build failed: $template" -Level Error
                Write-PipelineLog "Error: $result" -Level Error
                $success = $false
            }
        } catch {
            Write-PipelineLog "✗ Build error: $($_.Exception.Message)" -Level Error
            $success = $false
        }
    }
    
    # Build parameters if it's a .bicepparam file
    if ($templateParams.EndsWith('.bicepparam')) {
        $paramsOutputFile = $templateParams -replace '\.bicepparam$', '.parameters.json'
        Write-PipelineLog "Building Bicep parameter file: $templateParams"
        
        try {
            $result = az bicep build-params --file $templateParams --outfile $paramsOutputFile 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-PipelineLog "✓ Parameters built successfully: $paramsOutputFile" -Level Success
                
                # Copy to outputs
                Copy-Item $paramsOutputFile $script:OutputDir -Force
            } else {
                Write-PipelineLog "✗ Parameters build failed: $templateParams" -Level Error
                Write-PipelineLog "Error: $result" -Level Error
                $success = $false
            }
        } catch {
            Write-PipelineLog "✗ Parameters build error: $($_.Exception.Message)" -Level Error
            $success = $false
        }
    }
    
    return $success
}

function Invoke-Validation {
    param($config)
    
    Write-Host ""
    Write-PipelineLog "═══ VALIDATION ═══" -Level Info
    
    $template = $config.TEMPLATE
    $templateParams = $config.TEMPLATE_PARAMETERS
    $subscriptionId = $config.AZURE_SUBSCRIPTION_ID
    $location = $config.LOCATION
    
    Write-PipelineLog "Validating deployment..."
    Write-PipelineLog "Template: $template"
    Write-PipelineLog "Parameters: $templateParams"
    Write-PipelineLog "Subscription: $subscriptionId"
    Write-PipelineLog "Location: $location"
    
    try {
        # Set subscription context
        az account set -s $subscriptionId
        
        # Build validation command
        $deploymentName = "validate_$(Get-Date -Format 'yyyyMMddHHmmss')"
        $cmd = "az deployment sub validate --name $deploymentName --location $location --template-file $template"
        
        if ($templateParams) {
            $cmd += " --parameters $templateParams"
        }
        
        Write-PipelineLog "Running: $cmd"
        
        # Execute and capture both stdout and stderr
        $result = & cmd /c "$cmd 2>&1"
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-PipelineLog "✓ Validation passed" -Level Success
            
            # Extract resource providers if possible
            try {
                $resultJson = $result -join "`n" | ConvertFrom-Json
                if ($resultJson.properties.providers) {
                    $providers = $resultJson.properties.providers | ForEach-Object { $_.namespace }
                    Write-PipelineLog "Resource providers discovered: $($providers -join ', ')"
                    return @{ Success = $true; Providers = $providers }
                }
            } catch {
                Write-PipelineLog "Could not extract providers from validation result" -Level Warning
            }
            
            return @{ Success = $true; Providers = @() }
        } else {
            Write-PipelineLog "✗ Validation failed" -Level Error
            
            # Show the full error message
            if ($result) {
                $errorMsg = $result -join "`n"
                Write-PipelineLog "Full error details:" -Level Error
                Write-Host $errorMsg -ForegroundColor Red
                
                # Save error to file for debugging
                $errorFile = Join-Path $script:OutputDir "validation-error.txt"
                $errorMsg | Out-File -FilePath $errorFile -Encoding UTF8
                Write-PipelineLog "Error details saved to: $errorFile" -Level Info
            }
            
            return @{ Success = $false; Providers = @() }
        }
    } catch {
        Write-PipelineLog "✗ Validation error: $($_.Exception.Message)" -Level Error
        return @{ Success = $false; Providers = @() }
    }
}

function Invoke-ProviderCheck {
    param($config, $discoveredProviders)
    
    Write-Host ""
    Write-PipelineLog "═══ PROVIDER CHECK ═══" -Level Info
    
    $subscriptionId = $config.AZURE_SUBSCRIPTION_ID
    
    # Combine global providers with discovered ones
    $allProviders = @()
    $allProviders += $script:GlobalConfig.AZURE_PROVIDERS -split ','
    $allProviders += $discoveredProviders
    $allProviders = $allProviders | Where-Object { $_ -and $_.Trim() } | Sort-Object -Unique
    
    Write-PipelineLog "Checking $($allProviders.Count) resource providers..."
    
    try {
        az account set -s $subscriptionId
        
        # Get currently registered providers
        $registeredProviders = az provider list --query "[?registrationState=='Registered'].namespace" -o tsv
        
        $providersToRegister = @()
        
        foreach ($provider in $allProviders) {
            $provider = $provider.Trim()
            if ($registeredProviders -contains $provider) {
                Write-PipelineLog "✓ $provider - already registered" -Level Success
            } else {
                Write-PipelineLog "📝 $provider - needs registration" -Level Warning
                $providersToRegister += $provider
            }
        }
        
        if ($providersToRegister.Count -eq 0) {
            Write-PipelineLog "🎉 All required providers are already registered!" -Level Success
            return $true
        }
        
        Write-PipelineLog "Found $($providersToRegister.Count) provider(s) that need registration:" -Level Warning
        foreach ($provider in $providersToRegister) {
            Write-PipelineLog "  - $provider" -Level Warning
        }
        Write-PipelineLog "Note: This is a validation-only test. No providers will be registered." -Level Info
        
        return $true
        
    } catch {
        Write-PipelineLog "✗ Provider check failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Invoke-WhatIfAnalysis {
    param($config)
    
    Write-Host ""
    Write-PipelineLog "═══ WHAT-IF ANALYSIS ═══" -Level Info
    
    $template = $config.TEMPLATE
    $templateParams = $config.TEMPLATE_PARAMETERS
    $subscriptionId = $config.AZURE_SUBSCRIPTION_ID
    $location = $config.LOCATION
    
    try {
        az account set -s $subscriptionId
        
        $deploymentName = "whatif_$(Get-Date -Format 'yyyyMMddHHmmss')"
        $cmd = "az deployment sub what-if --name $deploymentName --location $location --template-file $template"
        
        if ($templateParams) {
            $cmd += " --parameters $templateParams"
        }
        
        $cmd += " --exclude-change-types Ignore NoChange"
        
        Write-PipelineLog "Running: $cmd"
        Write-PipelineLog "📋 What-if analysis results:"
        Write-Host "================================" -ForegroundColor Yellow
        
        $result = Invoke-Expression $cmd 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host $result
            Write-Host "================================" -ForegroundColor Yellow
            Write-PipelineLog "✓ What-if analysis completed successfully" -Level Success
            
            # Save results
            $result | Out-File -FilePath (Join-Path $script:OutputDir "whatif-results.txt") -Encoding UTF8
            
            return $true
        } else {
            Write-PipelineLog "✗ What-if analysis failed" -Level Error
            Write-PipelineLog "Error: $result" -Level Error
            return $false
        }
    } catch {
        Write-PipelineLog "✗ What-if analysis error: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Invoke-PSRuleAnalysis {
    param($config)
    
    if ($SkipPSRule) {
        Write-PipelineLog "Skipping PSRule analysis" -Level Warning
        return $true
    }
    
    Write-Host ""
    Write-PipelineLog "═══ PSRULE ANALYSIS ═══" -Level Info
    
    try {
        Import-Module PSRule.Rules.Azure -Force
        
        $ruleOption = $script:GlobalConfig.RULE_OPTION
        $ruleBaseline = $script:GlobalConfig.RULE_BASELINE
        
        # Look for ps-rule.yaml in common locations
        $psruleFiles = @("ps-rule.yaml", "ps-rule.yml", ".ps-rule/ps-rule.yaml", ".ps-rule/ps-rule.yml")
        $psruleFile = $psruleFiles | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if (-not $psruleFile) {
            Write-PipelineLog "No ps-rule.yaml file found. Using default PSRule configuration." -Level Warning
            Write-PipelineLog "Consider creating a ps-rule.yaml file for custom compliance rules." -Level Info
        } else {
            Write-PipelineLog "Using PSRule configuration from: $psruleFile"
            $ruleOption = $psruleFile
        }
        
        Write-PipelineLog "Running PSRule analysis..."
        Write-PipelineLog "Option file: $ruleOption"
        Write-PipelineLog "Baseline: $ruleBaseline"
        
        # Run PSRule analysis
        if ($psruleFile) {
            $results = Invoke-PSRule -InputPath . -Module PSRule.Rules.Azure -Option $ruleOption -Baseline $ruleBaseline
        } else {
            $results = Invoke-PSRule -InputPath . -Module PSRule.Rules.Azure -Baseline $ruleBaseline
        }
        
        # Analyze results
        $passed = ($results | Where-Object { $_.Outcome -eq "Pass" }).Count
        $failed = ($results | Where-Object { $_.Outcome -eq "Fail" }).Count
        $warnings = ($results | Where-Object { $_.Outcome -eq "Warning" }).Count
        
        Write-PipelineLog "PSRule Results: $passed passed, $failed failed, $warnings warnings"
        
        # Save results
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $script:OutputDir "psrule-results.json") -Encoding UTF8
        
        if ($failed -gt 0) {
            Write-PipelineLog "PSRule compliance check failed with $failed failures" -Level Error
            
            # Show top failures
            $failedRules = $results | Where-Object { $_.Outcome -eq "Fail" } | Select-Object -First 5
            foreach ($rule in $failedRules) {
                Write-PipelineLog "  ✗ $($rule.RuleName): $($rule.Synopsis)" -Level Error
            }
            
            return $false
        } else {
            Write-PipelineLog "✓ PSRule compliance check passed" -Level Success
            return $true
        }
        
    } catch {
        Write-PipelineLog "✗ PSRule analysis failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Invoke-PlanStage {
    param($config)
    
    Write-Host ""
    Write-Host "🎯 PLAN STAGE" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    
    $success = $true
    $stepNumber = 1
    
    # Step 1: Initialize job
    Write-Host ""
    Write-Host "[$stepNumber] Initialize job" -ForegroundColor Cyan
    Write-PipelineLog "Initialize job - Setting up pipeline environment"
    $stepNumber++
    
    # Step 2: Microsoft Defender (simulated)
    Write-Host "[$stepNumber] Microsoft Defender..." -ForegroundColor Cyan
    Write-PipelineLog "Microsoft Defender scan - Simulated (would run security scan)"
    $stepNumber++
    
    # Step 3: Checkout repos
    Write-Host "[$stepNumber] Checkout repositories..." -ForegroundColor Cyan
    Write-PipelineLog "Checkout repositories - Repository checkout completed"
    $stepNumber++
    
    # Step 4: Bicep Build
    Write-Host "[$stepNumber] Bicep build" -ForegroundColor Cyan
    if (-not $SkipBuild) {
        $buildSuccess = Invoke-BicepBuild -config $config
        $success = $success -and $buildSuccess
    } else {
        Write-PipelineLog "Bicep build skipped"
    }
    $stepNumber++
    
    # Step 5: Validation
    Write-Host "[$stepNumber] Validate" -ForegroundColor Cyan
    if (-not $SkipValidation) {
        $validationResult = Invoke-Validation -config $config
        $success = $success -and $validationResult.Success
    } else {
        Write-PipelineLog "Validation skipped"
        $validationResult = @{ Success = $true; Providers = @() }
    }
    $stepNumber++
    
    # Step 6: Register Azure providers (check only)
    Write-Host "[$stepNumber] Check Azure providers" -ForegroundColor Cyan
    $providerSuccess = Invoke-ProviderCheck -config $config -discoveredProviders $validationResult.Providers
    $success = $success -and $providerSuccess
    $stepNumber++
    
    # Step 7: What-If
    Write-Host "[$stepNumber] What-if analysis" -ForegroundColor Cyan
    if (-not $SkipWhatIf) {
        $whatIfSuccess = Invoke-WhatIfAnalysis -config $config
        $success = $success -and $whatIfSuccess
    } else {
        Write-PipelineLog "What-if analysis skipped"
    }
    $stepNumber++
    
    # Step 8: PSRule Analysis
    Write-Host "[$stepNumber] PSRule analysis" -ForegroundColor Cyan
    if (-not $SkipPSRule) {
        $psruleSuccess = Invoke-PSRuleAnalysis -config $config
        $success = $success -and $psruleSuccess
    } else {
        Write-PipelineLog "PSRule analysis skipped"
    }
    $stepNumber++
    
    # Step 9: Show debug information
    Write-Host "[$stepNumber] Show debug information" -ForegroundColor Cyan
    if ($Verbose -or $success -eq $false) {
        Invoke-DebugInfo -config $config
    } else {
        Write-PipelineLog "Show debug information - Skipped (use -Verbose to enable)"
    }
    $stepNumber++
    
    # Step 10: Upload pipeline logs
    Write-Host "[$stepNumber] Upload pipeline logs" -ForegroundColor Cyan
    Write-PipelineLog "Upload pipeline logs - Logs saved to pipeline-outputs directory"
    $stepNumber++
    
    # Step 11: Microsoft Defender (post-job)
    Write-Host "[$stepNumber] Microsoft Defender..." -ForegroundColor Cyan
    Write-PipelineLog "Microsoft Defender post-scan - Simulated"
    $stepNumber++
    
    # Step 12: Post-job cleanup
    Write-Host "[$stepNumber] Post-job cleanup" -ForegroundColor Cyan
    Write-PipelineLog "Post-job cleanup - Repository cleanup completed"
    $stepNumber++
    
    # Step 13: Finalize Job
    Write-Host "[$stepNumber] Finalize Job" -ForegroundColor Cyan
    Write-PipelineLog "Finalize Job - Plan stage completed"
    
    return $success
}

function Invoke-DebugInfo {
    param($config)
    
    Write-PipelineLog "═══ DEBUG INFORMATION ═══" -Level Info
    
    Write-Host ""
    Write-Host "🔍 Pipeline Debug Information" -ForegroundColor Yellow
    Write-Host "============================" -ForegroundColor Yellow
    
    Write-Host ""
    Write-Host "📋 Pipeline Context" -ForegroundColor Cyan
    Write-Host "Build ID: $(Get-Date -Format 'yyyyMMddHHmmss')" -ForegroundColor Gray
    
    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($branch) {
            Write-Host "Source Branch: $branch" -ForegroundColor Gray
        } else {
            Write-Host "Source Branch: unknown" -ForegroundColor Gray
        }
    } catch {
        Write-Host "Source Branch: unknown" -ForegroundColor Gray
    }
    
    Write-Host "Agent Name: $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "Agent OS: $($PSVersionTable.OS)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "🏗️ Infrastructure Configuration" -ForegroundColor Cyan
    Write-Host "TEMPLATE: $($config.TEMPLATE)" -ForegroundColor Gray
    Write-Host "TEMPLATE_PARAMETERS: $($config.TEMPLATE_PARAMETERS)" -ForegroundColor Gray
    Write-Host "SCOPE: $($script:GlobalConfig.SCOPE)" -ForegroundColor Gray
    Write-Host "LOCATION: $($config.LOCATION)" -ForegroundColor Gray
    Write-Host "SUBSCRIPTION_ID: $($config.AZURE_SUBSCRIPTION_ID)" -ForegroundColor Gray
    Write-Host "SERVICE_CONNECTION: $($config.SERVICE_CONNECTION)" -ForegroundColor Gray
    Write-Host "LOG_SEVERITY: $($script:GlobalConfig.LOG_SEVERITY)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "📏 PSRule Configuration" -ForegroundColor Cyan
    Write-Host "RULE_OPTION: $($script:GlobalConfig.RULE_OPTION)" -ForegroundColor Gray
    Write-Host "RULE_BASELINE: $($script:GlobalConfig.RULE_BASELINE)" -ForegroundColor Gray
    Write-Host "RULE_MODULES: $($script:GlobalConfig.RULE_MODULES)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "📁 File System Information" -ForegroundColor Cyan
    Write-Host "Working Directory: $(Get-Location)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Working Directory Contents:" -ForegroundColor Gray
    
    try {
        Get-ChildItem | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
    } catch {
        Write-Host "Could not list directory contents" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Pipeline Outputs:" -ForegroundColor Gray
    if (Test-Path $script:OutputDir) {
        try {
            Get-ChildItem $script:OutputDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
        } catch {
            Write-Host "Could not list output directory" -ForegroundColor Gray
        }
    } else {
        Write-Host "No outputs directory found" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "☁️ Azure CLI Information" -ForegroundColor Cyan
    Write-Host "Azure CLI Version:" -ForegroundColor Gray
    try {
        az version --output table 2>$null
    } catch {
        Write-Host "Could not get Azure CLI version" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Current Azure Account:" -ForegroundColor Gray
    try {
        az account show --output table 2>$null
    } catch {
        Write-Host "Could not get Azure account info" -ForegroundColor Gray
    }
    
    Write-Host ""
}

function Clear-OutputFiles {
    param(
        [switch]$KeepErrorFiles,
        [switch]$KeepLogFiles
    )
    
    Write-PipelineLog "🧹 Cleaning up generated files..."
    
    # Directories to clean (both output directory and project directories)
    $directoriesToClean = @()
    
    # Always clean the pipeline outputs directory
    if (Test-Path $script:OutputDir) {
        $directoriesToClean += $script:OutputDir
    }
    
    # Also clean the current directory and common project subdirectories
    $projectDirectories = @(
        ".",              # Current directory
        "network",        # Network folder (where your files are)
        "infrastructure", # Common infrastructure folder
        "bicep",          # Common bicep folder
        "templates"       # Common templates folder
    )
    
    foreach ($dir in $projectDirectories) {
        if (Test-Path $dir) {
            $directoriesToClean += $dir
        }
    }
    
    $totalCleanedCount = 0
    $totalKeptCount = 0
    
    foreach ($directory in $directoriesToClean) {
        Write-PipelineLog "Cleaning directory: $directory" -Level Info
        
        # Get all files in the directory (but not subdirectories to avoid going too deep)
        $allFiles = Get-ChildItem -Path $directory -File -ErrorAction SilentlyContinue | Where-Object {
            # Don't clean files that are likely source files
            $_.Name -notlike "*.bicep" -and 
            $_.Name -notlike "*.bicepparam" -and
            $_.Name -notlike "*.yml" -and
            $_.Name -notlike "*.yaml" -and
            $_.Name -notlike "*.md" -and
            $_.Name -notlike "*.ps1"
        }
        
        # Files to keep when preserving error information
        $errorPatterns = @(
            "*error*",          # Any file with 'error' in name
            "*failed*",         # Any file with 'failed' in name
            "*exception*"       # Any file with 'exception' in name
        )
        
        # Files to keep when preserving logs
        $logPatterns = @(
            "pipeline-log-*.txt",   # Pipeline execution logs
            "*-log.txt",            # Other log files
            "*.log"                 # Generic log files
        )
        
        $cleanedCount = 0
        $keptCount = 0
        
        foreach ($file in $allFiles) {
            $shouldKeep = $false
            $keepReason = ""
            
            # Check if file should be kept due to error content
            if ($KeepErrorFiles) {
                foreach ($errorPattern in $errorPatterns) {
                    if ($file.Name -like $errorPattern) {
                        $shouldKeep = $true
                        $keepReason = "contains error information"
                        break
                    }
                }
            }
            
            # Check if file should be kept due to log content
            if ($KeepLogFiles -and -not $shouldKeep) {
                foreach ($logPattern in $logPatterns) {
                    if ($file.Name -like $logPattern) {
                        $shouldKeep = $true
                        $keepReason = "is a log file"
                        break
                    }
                }
            }
            
            # Always clean up these file types (unless they match error/log patterns above)
            $alwaysCleanPatterns = @(
                "*.json",           # All JSON files (ARM templates, parameter files, results)
                "*.tmp",            # Temporary files
                "*.temp",           # Temporary files
                "*.parameters.json" # Parameter files specifically
            )
            
            $shouldClean = $false
            foreach ($cleanPattern in $alwaysCleanPatterns) {
                if ($file.Name -like $cleanPattern) {
                    $shouldClean = $true
                    break
                }
            }
            
            if ($shouldKeep) {
                Write-PipelineLog "  ✅ Keeping $($file.Name) - $keepReason" -Level Success
                $keptCount++
            } elseif ($shouldClean) {
                try {
                    Remove-Item $file.FullName -Force
                    Write-PipelineLog "  🗑️ Removed $directory\$($file.Name)"
                    $cleanedCount++
                } catch {
                    Write-PipelineLog "  ❌ Could not remove $($file.Name): $($_.Exception.Message)" -Level Warning
                }
            } else {
                # For any other files in pipeline-outputs, keep them but don't count as explicitly kept
                if ($directory -eq $script:OutputDir) {
                    Write-PipelineLog "  📄 Keeping $($file.Name) - other file type"
                }
            }
        }
        
        $totalCleanedCount += $cleanedCount
        $totalKeptCount += $keptCount
    }
    
    if ($totalCleanedCount -gt 0 -or $totalKeptCount -gt 0) {
        Write-PipelineLog "Cleanup completed: $totalCleanedCount files removed, $totalKeptCount files kept" -Level Success
    } else {
        Write-PipelineLog "No files to clean up"
    }
}

function Show-Summary {
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║                      PIPELINE SUMMARY                        ║" -ForegroundColor Blue
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    
    Write-PipelineLog "Pipeline execution completed"
    Write-PipelineLog "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-PipelineLog "Errors: $($script:ErrorCount)"
    Write-PipelineLog "Warnings: $($script:WarningCount)"
    Write-PipelineLog "Environment: $Environment"
    Write-PipelineLog "Step: $Step"
    
    if ($script:ErrorCount -eq 0) {
        Write-PipelineLog "✅ Pipeline completed successfully!" -Level Success
    } else {
        Write-PipelineLog "❌ Pipeline completed with errors" -Level Error
    }
    
    # Save log to file before cleanup
    if (!(Test-Path $script:OutputDir)) {
        New-Item -ItemType Directory -Path $script:OutputDir | Out-Null
    }
    
    $logFile = Join-Path $script:OutputDir "pipeline-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $script:LogEntries | Out-File -FilePath $logFile -Encoding UTF8
    Write-PipelineLog "📄 Log saved to: $logFile"
    
    # Clean up generated files based on parameters
    if (-not $NoCleanup) {
        if ($KeepAllFiles) {
            Write-PipelineLog "Keeping all files (KeepAllFiles specified)"
        } else {
            # Keep error files and logs by default, clean up temporary JSON files
            Clear-OutputFiles -KeepErrorFiles -KeepLogFiles
        }
    } else {
        Write-PipelineLog "Cleanup skipped (NoCleanup specified)"
    }
    
    Write-Host ""
    Write-Host "📁 Remaining files in: $script:OutputDir" -ForegroundColor Green
    if (Test-Path $script:OutputDir) {
        $remainingFiles = Get-ChildItem $script:OutputDir
        if ($remainingFiles) {
            foreach ($file in $remainingFiles) {
                $fileType = if ($file.Name -like "*error*" -or $file.Name -like "*failed*") {
                    " (Error file)" 
                } elseif ($file.Name -like "*log*") {
                    " (Log file)"
                } else {
                    ""
                }
                Write-Host "  - $($file.Name)$fileType" -ForegroundColor Gray
            }
        } else {
            Write-Host "  (All temporary files cleaned up)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
}

# Main execution
try {
    Show-Header
    
    if (!(Test-Prerequisites)) {
        Write-PipelineLog "Prerequisites check failed. Please install missing components." -Level Error
        exit 1
    }
    
    # Get environment configuration
    $config = Get-EnvironmentConfig
    if (-not $config) {
        Write-PipelineLog "Invalid environment configuration for: $Environment" -Level Error
        exit 1
    }
    
    # Create output directory
    if (!(Test-Path $script:OutputDir)) {
        New-Item -ItemType Directory -Path $script:OutputDir | Out-Null
    }
    
    $allSuccess = $true
    
    # Execute pipeline steps
    switch ($Step) {
        "Build" {
            $allSuccess = Invoke-BicepBuild -config $config
        }
        "Validate" {
            $validationResult = Invoke-Validation -config $config
            $allSuccess = $validationResult.Success
        }
        "WhatIf" {
            $allSuccess = Invoke-WhatIfAnalysis -config $config
        }
        "PSRule" {
            $allSuccess = Invoke-PSRuleAnalysis -config $config
        }
        "All" {
            $allSuccess = Invoke-PlanStage -config $config
        }
    }
    
    Show-Summary
    
    if ($allSuccess) {
        exit 0
    } else {
        exit 1
    }
    
} catch {
    Write-PipelineLog "Fatal error: $($_.Exception.Message)" -Level Error
    Write-PipelineLog "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}