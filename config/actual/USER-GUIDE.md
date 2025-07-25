# Actual Budget User Guide

This guide helps you get started with Actual Budget in your homelab infrastructure.

## Overview

Actual Budget is a personal finance management application that helps you:
- Track income and expenses
- Create and manage budgets
- Categorize transactions
- Monitor financial goals
- Sync data across multiple devices

## Getting Started

### Initial Access

1. **Web Interface**: Navigate to https://budget.${DOMAIN}
2. **Local Access**: http://localhost:5006 (if accessing locally)
3. **Server Password**: Enter the password configured in your `.env` file

### First-Time Setup

#### 1. Create Your First Budget

After logging in, you'll be prompted to create a new budget file:

1. Click "Create new file"
2. Enter a name for your budget (e.g., "Personal Budget 2025")
3. Choose whether to start with sample data or a blank budget
4. Click "Create"

#### 2. Set Up Accounts

Add your financial accounts:

1. Go to "Accounts" in the sidebar
2. Click "Add Account"
3. Choose account type:
   - **Checking**: For checking accounts
   - **Savings**: For savings accounts
   - **Credit Card**: For credit cards
   - **Investment**: For investment accounts
   - **Mortgage**: For mortgage accounts
   - **Other**: For other account types

4. Enter account details:
   - Account name
   - Starting balance
   - Account number (optional)

#### 3. Create Budget Categories

Set up categories for organizing your spending:

1. Go to "Budget" in the sidebar
2. Click "Add Category Group"
3. Create groups like:
   - **Fixed Expenses**: Rent, utilities, insurance
   - **Variable Expenses**: Groceries, entertainment, gas
   - **Savings Goals**: Emergency fund, vacation, retirement
   - **Debt Payments**: Credit cards, loans

4. Add individual categories within each group
5. Set monthly budget amounts for each category

## Daily Usage

### Adding Transactions

#### Manual Entry

1. Go to the account where the transaction occurred
2. Click "Add Transaction"
3. Fill in details:
   - Date
   - Payee
   - Category
   - Amount (positive for income, negative for expenses)
   - Notes (optional)

#### Import from Bank

1. Download transactions from your bank (CSV, OFX, or QFX format)
2. Go to the account in Actual Budget
3. Click "Import" button
4. Select your file and map columns
5. Review and confirm transactions

### Budget Management

#### Monthly Budget Review

1. Go to "Budget" view
2. Review each category:
   - **Green**: Under budget
   - **Yellow**: Approaching budget limit
   - **Red**: Over budget

3. Adjust budget amounts as needed
4. Move money between categories if necessary

#### Budget Adjustments

- **To Be Budgeted**: Shows available money to allocate
- **Overspending**: Red categories need attention
- **Category Transfer**: Move money between categories

### Transaction Categorization

#### Auto-Categorization Rules

1. Go to "Rules" in the sidebar
2. Click "Add Rule"
3. Set conditions (payee, amount, etc.)
4. Set actions (category, notes, etc.)
5. Apply to existing transactions if desired

#### Bulk Categorization

1. Select multiple transactions (Ctrl+click or Shift+click)
2. Right-click and choose "Set Category"
3. Select the appropriate category
4. All selected transactions will be updated

## Advanced Features

### Reconciliation

Keep your accounts accurate:

1. Go to the account you want to reconcile
2. Click "Reconcile"
3. Enter the statement balance
4. Mark transactions as cleared
5. Resolve any discrepancies

### Reports and Analytics

View financial insights:

1. Go to "Reports" in the sidebar
2. Available reports:
   - **Net Worth**: Track assets and liabilities
   - **Cash Flow**: Income vs expenses over time
   - **Category Spending**: Spending by category
   - **Custom Reports**: Create your own views

### Goals and Savings

Set up savings goals:

1. Create a category for your goal
2. Set a target amount and date
3. Budget money toward the goal each month
4. Track progress in the budget view

## Mobile Access

### Mobile App Setup

1. Download "Actual Budget" from:
   - iOS App Store
   - Google Play Store

2. Configure server connection:
   - Server URL: https://budget.${DOMAIN}
   - Password: Your server password

3. Sync data and start using on mobile

### Mobile Features

- View account balances
- Add transactions on the go
- Check budget status
- Sync automatically with server

## Data Management

### Backup Your Data

Your data is automatically backed up via Duplicati, but you can also create manual backups:

```powershell
# Create manual backup
./config/actual/backup-restore.ps1 -Action backup

# List available backups
./config/actual/backup-restore.ps1 -Action list

# Verify backup integrity
./config/actual/backup-restore.ps1 -Action verify -RestoreFile <backup-file>
```

### Export Data

1. Go to "Settings" in Actual Budget
2. Click "Export data"
3. Choose format (Actual Budget file or CSV)
4. Download the exported file

### Import Data

#### From Other Apps

1. Export data from your current app (Mint, YNAB, etc.)
2. In Actual Budget, go to "Settings"
3. Click "Import data"
4. Select your export file
5. Map categories and accounts
6. Review and confirm import

## Troubleshooting

### Common Issues

#### Can't Access the Service

1. Check if container is running: `docker ps | grep actual`
2. Check logs: `docker logs actual`
3. Verify port is accessible: `curl http://localhost:5006`

#### Forgot Server Password

1. Check your `.env` file for `ACTUAL_PASSWORD`
2. If needed, update the password and restart: `docker-compose restart actual`

#### Data Not Syncing

1. Check internet connection
2. Verify server URL in mobile app
3. Try logging out and back in

#### Import Issues

1. Ensure file format is supported (CSV, OFX, QFX)
2. Check column mapping during import
3. Verify date formats match expected format

### Getting Help

1. **Documentation**: Built-in help in the application
2. **Community**: Actual Budget Discord and forums
3. **Logs**: Check container logs for error messages
4. **Validation**: Run validation script to check configuration

## Best Practices

### Security

1. Use a strong server password
2. Access only via HTTPS (tunnel)
3. Regular backups
4. Keep the application updated

### Budgeting Tips

1. **Start Simple**: Begin with basic categories
2. **Be Realistic**: Set achievable budget amounts
3. **Review Regularly**: Check budget weekly
4. **Adjust as Needed**: Modify categories and amounts based on actual spending
5. **Emergency Fund**: Prioritize building an emergency fund

### Data Organization

1. **Consistent Naming**: Use consistent payee names
2. **Regular Reconciliation**: Reconcile accounts monthly
3. **Category Structure**: Keep categories organized and logical
4. **Transaction Notes**: Add notes for unusual transactions

## Integration with Homelab

### Monitoring

- Service health is monitored via Grafana dashboards
- Container logs are collected and searchable
- Backup status is tracked in Duplicati

### Security

- Access via secure Cloudflare tunnel
- No direct internet exposure
- Data encrypted at rest
- Regular automated backups

### Maintenance

- Container updates via Docker Compose
- Configuration managed via Git
- Backup verification automated
- Health checks ensure service availability

## Conclusion

Actual Budget provides powerful personal finance management capabilities within your secure homelab environment. With proper setup and regular use, it can help you achieve your financial goals while keeping your data private and secure.

For additional help, refer to the official Actual Budget documentation or use the validation and management scripts provided in the configuration directory.