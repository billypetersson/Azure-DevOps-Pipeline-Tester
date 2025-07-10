# Azure DevOps Pipeline Tester (Plan Only)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Azure CLI](https://img.shields.io/badge/Azure%20CLI-Latest-blue.svg)](https://docs.microsoft.com/en-us/cli/azure/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A comprehensive local testing solution that replicates Azure DevOps pipeline plan and validation stages for infrastructure-as-code testing. Test your Bicep templates, run compliance checks, and preview deployments locally before committing to your CI/CD pipeline - **without performing actual deployments**.

## 🎯 Overview

The Azure DevOps Pipeline Tester (Plan Only) mirrors the exact execution flow of your real Azure DevOps plan stages, providing:

- **13-step Plan Stage** matching your actual pipeline
- **Real-time validation** against Azure subscriptions
- **Comprehensive compliance checking** with PSRule
- **What-if analysis** for deployment preview
- **Detailed logging and reporting** for troubleshooting
- **Safe testing** with no actual deployments

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Usage Examples](#-usage-examples)
- [Configuration](#-configuration)
- [Pipeline Steps](#-pipeline-steps)
- [Output Files](#-output-files)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

### 🔄 **Complete Plan Stage Simulation**
- Exact step-by-step execution matching Azure DevOps
- Plan stage only - **no actual deployments**
- Real Azure CLI integration
- Authentic error handling

### 🏗️ **Infrastructure Validation**
- Bicep template compilation and validation
- Azure subscription-level deployment validation
- Resource provider registration checks (status only)
- What-if analysis with change preview

### 📏 **Compliance & Security**
- PSRule security baseline enforcement
- Azure Policy compliance checking
- Governance rule validation
- Custom compliance rule support

### 🎛️ **Environment Management**
- Multi-environment support (dev/test/uat/prod)
- Automatic environment detection
- Git branch-based configuration
- Override capabilities

### 📊 **Comprehensive Reporting**
- Real-time progress display
- Detailed error logging
- Performance metrics
- Structured output files

### 🛡️ **Safety Features**
- **No actual deployments** - plan and validation only
- Read-only Azure operations
- Safe failure modes
- Comprehensive logging

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

# Run specific step
.\test-pipeline.ps1 -Step Build
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
# Run all plan steps (default)
.\test-pipeline.ps1

# Run specific step
.\test-pipeline.ps1 -Step Build
.\test-pipeline.ps1 -Step Validate
.\test-pipeline.ps1 -Step WhatIf
.\test-pipeline.ps1 -Step PSRule

# Run specific environment
.\test-pipeline.ps1 -Environment dev

# Run with verbose logging
.\test-pipeline.ps1 -Verbose
```

### Advanced Usage

```powershell
# Skip specific steps
.\test-pipeline.ps1 -SkipBuild
.\test-pipeline.ps1 -SkipValidation
.\test-pipeline.ps1 -SkipWhatIf
.\test-pipeline.ps1 -SkipPSRule

# Keep all generated files
.\test-pipeline.ps1 -KeepAllFiles

# Skip cleanup entirely
.\test-pipeline.ps1 -NoCleanup
```

## ⚙️ Configuration

### Environment Auto-Detection

The script automatically detects your environment based on:

1. **Git Branch Name**
   - `dev` branch → dev environment
   - `tst` branch → test environment  
   - `uat` branch → uat environment
   - `prod` branch → prod environment

2. **Folder Context**
   - Folders containing `dev`, `test`, `uat`, `prod` in name

3. **Manual Override**
   - Use `-Environment` parameter to specify

### Environment Configurations

Each environment maps to specific Azure resources:

| Environment | Subscription | Template | Parameters |
|-------------|--------------|----------|------------|
| dev | Development subscription | main.bicep | dev.bicepparam |
| tst | Test subscription | main.bicep | test.bicepparam |
| uat | Acceptance subscription | main.bicep | uat.bicepparam |
| prod | Production subscription | main.bicep | prod.bicepparam |

### File Structure Requirements

```
your-infrastructure-repo/
├── main.bicep                # Main template
├── dev.bicepparam            # Dev parameters
├── test.bicepparam           # Test parameters
├── uat.bicepparam            # UAT parameters
├── prod.bicepparam           # Prod parameters
├── ps-rule.yaml              # Compliance rules (optional)
├── test-pipeline.ps1         # This script
└── pipeline-outputs/         # Generated outputs
    ├── main.json             # Compiled template
    ├── dev.parameters.json   # Compiled parameters
    ├── whatif-results.txt    # Change preview
    ├── psrule-results.json   # Compliance report
    └── pipeline-log-*.txt    # Execution logs
```

## 🎭 Pipeline Steps

### Plan Stage (13 Steps)

Mirrors your Azure DevOps plan stage exactly:

1. **Initialize job** - Environment setup
2. **Microsoft Defender** - Security scanning (simulated)
3. **Checkout repositories** - Repository preparation
4. **Bicep build** - Template compilation
5. **Validate** - Azure deployment validation
6. **Check Azure providers** - Resource provider verification (status only)
7. **What-if analysis** - Change analysis and preview
8. **PSRule analysis** - Security and governance checks
9. **Show debug information** - Diagnostic output (verbose mode)
10. **Upload pipeline logs** - Log management
11. **Microsoft Defender** - Post-scan (simulated)
12. **Post-job cleanup** - Resource cleanup
13. **Finalize Job** - Stage completion

### Safety Features

- **No actual deployments** - all operations are validation only
- **Provider registration** - check status only, no actual registration
- **What-if analysis** - preview only, no execution
- **Safe failure modes** - graceful error handling

## 📁 Output Files

The script generates comprehensive outputs in the `pipeline-outputs/` directory:

### Template Artifacts
- `main.json` - Compiled ARM template
- `*.parameters.json` - Compiled parameter files

### Analysis Results
- `whatif-results.txt` - Deployment change preview
- `validation-error.txt` - Validation failure details (if any)
- `psrule-results.json` - Compliance analysis results

### Execution Logs
- `pipeline-log-YYYYMMDD-HHMMSS.txt` - Complete execution log
- Timestamped entries with severity levels
- Performance metrics and error tracking

## 🔧 Parameters Reference

### Step Parameters
```powershell
-Step <Build|Validate|WhatIf|PSRule|All>  # Pipeline step to execute
```

### Environment Parameters
```powershell
-Environment <dev|tst|uat|prod>           # Target environment
```

### Control Parameters
```powershell
-SkipBuild                    # Skip Bicep build step
-SkipValidation              # Skip Azure validation
-SkipWhatIf                  # Skip what-if analysis
-SkipPSRule                  # Skip compliance analysis
-Verbose                     # Enable verbose logging
-KeepAllFiles               # Keep all generated files
-NoCleanup                  # Skip file cleanup entirely
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
**Solution:** Check if `ps-rule.yaml` configuration file exists and is valid

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
    arguments: '-Step All -Environment $(Environment)'
    failOnStderr: true
```

### Git Hooks

Add as a pre-commit hook:

```bash
#!/bin/sh
# .git/hooks/pre-commit
pwsh ./test-pipeline.ps1 -Step All -SkipPSRule
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

## ⚠️ Important Notes

### Safety First
- **This script performs NO actual deployments**
- All operations are validation and preview only
- Safe to run in any environment
- No Azure resources will be created or modified

### What This Script Does NOT Do
- ❌ Deploy infrastructure
- ❌ Modify Azure resources
- ❌ Register resource providers
- ❌ Create resource groups
- ❌ Execute ARM deployments

### What This Script DOES Do
- ✅ Validate Bicep templates
- ✅ Check Azure permissions
- ✅ Preview deployment changes
- ✅ Run compliance checks
- ✅ Generate reports
- ✅ Test pipeline configuration

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

*Bringing Azure DevOps pipeline testing to your local development environment - safely and efficiently*