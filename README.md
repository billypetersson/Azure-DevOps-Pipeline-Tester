# Azure DevOps Pipeline Tester

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Azure CLI](https://img.shields.io/badge/Azure%20CLI-Latest-blue.svg)](https://docs.microsoft.com/en-us/cli/azure/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A comprehensive local testing solution that replicates Azure DevOps pipeline execution for infrastructure-as-code validation. Test your Bicep templates, run compliance checks, and preview deployments locally before committing to your CI/CD pipeline.

## 🎯 Overview

The Azure DevOps Pipeline Tester mirrors the exact execution flow of your real Azure DevOps pipelines, providing:

- **18-step Plan Stage** matching your actual pipeline
- **12-step Deploy Stage** with approval gates
- **Real-time validation** against Azure subscriptions
- **Comprehensive compliance checking** with PSRule
- **What-if analysis** for deployment preview
- **Detailed logging and reporting** for troubleshooting

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Usage Examples](#-usage-examples)
- [Configuration](#-configuration)
- [Pipeline Stages](#-pipeline-stages)
- [Output Files](#-output-files)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

### 🔄 **Complete Pipeline Simulation**
- Exact step-by-step execution matching Azure DevOps
- Plan → Approval → Deploy workflow
- Real Azure CLI integration
- Authentic error handling

### 🏗️ **Infrastructure Validation**
- Bicep template compilation and validation
- Azure subscription-level deployment validation
- Resource provider registration checks
- What-if analysis with change preview

### 📏 **Compliance & Security**
- PSRule security baseline enforcement
- Azure Policy compliance checking
- Governance rule validation
- Custom compliance rule support

### 🎛️ **Environment Management**
- Multi-environment support (dev/test/uat)
- Automatic environment detection
- Git branch-based configuration
- Override capabilities

### 📊 **Comprehensive Reporting**
- Real-time progress display
- Detailed error logging
- Performance metrics
- Structured output files

## 🛠️ Prerequisites

### Required Software
- **PowerShell 7+** - Cross-platform PowerShell
- **Azure CLI** - Latest version with Bicep support
- **Git** (optional) - For automatic environment detection

### Azure Requirements
- Active Azure subscription
- Appropriate permissions for target subscription
- Azure CLI authentication configured

### PowerShell Modules
The script automatically installs missing modules:
- `PSRule` - Policy as Code framework
- `PSRule.Rules.Azure` - Azure-specific compliance rules

## 🚀 Quick Start

### 1. Download the Script
```powershell
# Save test-pipeline.ps1 to your infrastructure repository
# Make it executable
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 2. Authenticate with Azure
```powershell
az login
az account set --subscription "your-subscription-id"
```

### 3. Run Your First Test
```powershell
# Basic plan stage execution
.\test-pipeline.ps1

# With specific environment
.\test-pipeline.ps1 -Environment dev
```

### 4. Review Results
```powershell
# Check the pipeline-outputs directory for:
# - Compiled templates (*.json)
# - Validation results
# - What-if analysis
# - Compliance reports
# - Execution logs
```

## 📖 Usage Examples

### Basic Operations

```powershell
# Run plan stage only (safest for testing)
.\test-pipeline.ps1 -Stage Plan

# Run specific environment
.\test-pipeline.ps1 -Environment dev

# Run with verbose logging
.\test-pipeline.ps1 -Verbose
```

### Advanced Usage

```powershell
# Full pipeline with auto-approval (careful!)
.\test-pipeline.ps1 -Stage All -AutoApprove

# Skip compliance checking for faster testing
.\test-pipeline.ps1 -SkipPSRule

# Deploy stage only (after successful plan)
.\test-pipeline.ps1 -Stage Deploy -Environment dev
```

### Development Workflow

```powershell
# Quick validation during development
.\test-pipeline.ps1 -Stage Plan -SkipPSRule

# Full validation before commit
.\test-pipeline.ps1 -Stage Plan -Verbose

# Test deployment to dev environment
.\test-pipeline.ps1 -Stage All -Environment dev
```

## ⚙️ Configuration

### Environment Auto-Detection

The script automatically detects your environment based on:

1. **Git Branch Name**
   - `dev` branch → dev environment
   - `tst` branch → test environment  
   - `uat` branch → uat environment

2. **Folder Context**
   - Folders containing `dev`, `test`, `uat` in name

3. **Manual Override**
   - Use `-Environment` parameter to specify

### Environment Configurations

Each environment maps to specific Azure resources:

| Environment | Subscription | Template | Parameters |
|-------------|--------------|----------|------------|
| dev | Development subscription | main.bicep | dev.bicepparam |
| tst | Test subscription | main.bicep | test.bicepparam |
| uat | UAT subscription | main.bicep | uat.bicepparam |

### File Structure Requirements

```
your-infrastructure-repo/
├── main.bicep                 # Main template
├── dev.bicepparam            # Dev parameters
├── test.bicepparam           # Test parameters
├── uat.bicepparam            # UAT parameters
├── ps-rule.yaml              # Compliance rules
├── test-pipeline.ps1         # This script
└── pipeline-outputs/         # Generated outputs
    ├── main.json             # Compiled template
    ├── dev.parameters.json   # Compiled parameters
    ├── whatif-results.txt    # Change preview
    ├── psrule-results.json   # Compliance report
    └── pipeline-log-*.txt    # Execution logs
```

## 🎭 Pipeline Stages

### Plan Stage (18 Steps)

Mirrors your Azure DevOps plan stage exactly:

1. **Initialize job** - Environment setup
2. **Microsoft Defender** - Security scanning (simulated)
3. **Checkout repos** - Repository preparation
4. **Bicep build** - Template compilation
5. **Bicep build params** - Parameter compilation
6. **Validate** - Azure deployment validation
7. **Register Azure providers** - Resource provider setup
8. **What-if** - Change analysis
9. **Configure PSRule** - Compliance setup
10. **PSRule analysis** - Security and governance checks
11. **Generate PSRule report** - Compliance reporting
12. **Show debug information** - Diagnostic output
13. **Upload pipeline logs** - Log management
14. **Microsoft Defender** - Post-scan (simulated)
15. **Post-job cleanup** - Resource cleanup
16. **Finalize Job** - Stage completion

### Deploy Stage (12 Steps)

Replicates your deployment workflow:

1. **Initialize job** - Deployment setup
2. **Microsoft Defender** - Security validation
3. **Checkout repos** - Code preparation
4. **Manual approval** - Deployment gate (unless auto-approved)
5. **Deploy infrastructure** - Actual Azure deployment
6. **Show debug information** - Deployment diagnostics
7. **Publish pipeline artifacts** - Output management
8. **Pipeline summary** - Execution summary
9. **Microsoft Defender** - Post-deployment scan
10. **Post-job cleanup** - Resource cleanup
11. **Finalize Job** - Stage completion

## 📁 Output Files

The script generates comprehensive outputs in the `pipeline-outputs/` directory:

### Template Artifacts
- `main.json` - Compiled ARM template
- `*.parameters.json` - Compiled parameter files

### Analysis Results
- `whatif-results.txt` - Deployment change preview
- `validation-error.txt` - Validation failure details (if any)
- `psrule-results.json` - Compliance analysis results

### Deployment Outputs
- `deployment-result.json` - Deployment response (deploy stage)
- `deployment-error.txt` - Deployment failure details (if any)

### Execution Logs
- `pipeline-log-YYYYMMDD-HHMMSS.txt` - Complete execution log
- Timestamped entries with severity levels
- Performance metrics and error tracking

## 🔧 Parameters Reference

### Stage Parameters
```powershell
-Stage <Plan|Deploy|All>     # Pipeline stage to execute
```

### Environment Parameters
```powershell
-Environment <dev|tst|uat>   # Target environment
```

### Control Parameters
```powershell
-SkipPSRule                  # Skip compliance analysis
-SkipDeploy                  # Skip actual deployment
-AutoApprove                 # Auto-approve deployment
-Verbose                     # Enable verbose logging
```

## 🐛 Troubleshooting

### Common Issues

#### Prerequisites Not Met
```
✗ Azure CLI not authenticated. Run 'az login'
```
**Solution:** Run `az login` and ensure you're authenticated

#### Template Not Found
```
✗ Template file not found: main.bicep
```
**Solution:** Ensure you're in the correct directory with Bicep files

#### Validation Failures
```
✗ Validation failed
```
**Solution:** Check `validation-error.txt` for detailed error information

#### PSRule Errors
```
Failed to deserialize PSRule results
```
**Solution:** Check `ps-rule.yaml` configuration file exists and is valid

### Debug Mode

Enable verbose logging for detailed troubleshooting:

```powershell
.\test-pipeline.ps1 -Verbose
```

This provides:
- Detailed step execution information
- Azure CLI command outputs
- File system diagnostics
- Performance metrics

### Log Analysis

Check the generated log files for detailed execution information:

```powershell
# View latest log
Get-Content "pipeline-outputs/pipeline-log-*.txt" | Select-Object -Last 50

# Search for errors
Select-String -Pattern "Error" -Path "pipeline-outputs/pipeline-log-*.txt"
```

## 🚀 Advanced Usage

### Custom Compliance Rules

Extend PSRule configuration in `ps-rule.yaml`:

```yaml
# Custom organization rules
include:
  - PSRule.Rules.Azure

configuration:
  # Custom baseline
  baseline: 'MyOrg.Baseline'
  
  # Rule exclusions
  rule:
    exclude:
    - 'Azure.VM.UseHybridUseBenefit'
```

### CI/CD Integration

Integrate with your CI/CD pipeline:

```yaml
# Azure DevOps Pipeline
- task: PowerShell@2
  displayName: 'Local Pipeline Test'
  inputs:
    targetType: 'filePath'
    filePath: 'test-pipeline.ps1'
    arguments: '-Stage Plan -Environment $(Environment)'
    failOnStderr: true
```

### Git Hooks

Add as a pre-commit hook:

```bash
#!/bin/sh
# .git/hooks/pre-commit
pwsh ./test-pipeline.ps1 -Stage Plan -SkipPSRule
```

## 🤝 Contributing

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Testing Guidelines

- Test with multiple environments
- Verify error handling
- Check output file generation
- Validate Azure integration

### Code Standards

- Follow PowerShell best practices
- Add comprehensive error handling
- Include detailed logging
- Document new features

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

### Getting Help

1. **Check the logs** - Review `pipeline-outputs/` for detailed error information
2. **Enable verbose mode** - Use `-Verbose` for detailed diagnostics
3. **Verify prerequisites** - Ensure all required software is installed
4. **Check Azure permissions** - Verify subscription access

### Reporting Issues

When reporting issues, please include:

- PowerShell version (`$PSVersionTable`)
- Azure CLI version (`az version`)
- Complete error messages
- Environment configuration
- Steps to reproduce

## 📚 Additional Resources

### Documentation
- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [PSRule Documentation](https://microsoft.github.io/PSRule/)

### Best Practices
- [Azure DevOps Best Practices](https://docs.microsoft.com/en-us/azure/devops/pipelines/ecosystems/azure/)
- [Infrastructure as Code Patterns](https://docs.microsoft.com/en-us/azure/architecture/framework/devops/iac)
- [Azure Governance Guidelines](https://docs.microsoft.com/en-us/azure/governance/)

---

**Made with ❤️ for Azure DevOps and Infrastructure as Code enthusiasts**

*Bringing Azure DevOps pipeline testing to your local development environment*