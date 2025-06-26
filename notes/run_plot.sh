#!/bin/bash

# Sapien Multiplier Data Plotting Script
# This script runs the Python plotting script with the multipliers.csv data

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Sapien Multiplier Data Plotter      ${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Check if we're in the right directory
if [[ ! -f "$SCRIPT_DIR/multipliers.csv" ]]; then
    echo -e "${RED}Error: multipliers.csv not found in $SCRIPT_DIR${NC}"
    echo "Please ensure you're running this script from the notes directory."
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/plot_from_csv.py" ]]; then
    echo -e "${RED}Error: plot_from_csv.py not found in $SCRIPT_DIR${NC}"
    echo "Please ensure the Python plotting script is in the notes directory."
    exit 1
fi

echo -e "${YELLOW}Checking Python dependencies...${NC}"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed or not in PATH${NC}"
    echo "Please install Python 3 to run the plotting script."
    exit 1
fi

# Check if required Python packages are available
echo "Checking required packages: pandas, matplotlib, numpy..."
python3 -c "import pandas, matplotlib, numpy" 2>/dev/null || {
    echo -e "${RED}Error: Required Python packages not found${NC}"
    echo "Please install required packages:"
    echo "  pip3 install pandas matplotlib numpy"
    echo "or:"
    echo "  pip install pandas matplotlib numpy"
    exit 1
}

echo -e "${GREEN}✓ Python dependencies OK${NC}"
echo

# Display data info
echo -e "${YELLOW}Multiplier data information:${NC}"
echo "CSV file: $SCRIPT_DIR/multipliers.csv"
echo "Data preview:"
head -n 6 "$SCRIPT_DIR/multipliers.csv"
echo "..."
echo "Total data points: $(tail -n +2 "$SCRIPT_DIR/multipliers.csv" | wc -l)"
echo

# Run the plotting script
echo -e "${YELLOW}Running plotting script...${NC}"
cd "$SCRIPT_DIR"

python3 plot_from_csv.py

echo
echo -e "${GREEN}✓ Plotting complete!${NC}"
echo -e "${BLUE}Charts should have been displayed in separate windows.${NC}"
echo

# Optionally save plots to files
read -p "Would you like to save the plots to PNG files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Saving plots to files...${NC}"
    
    # Create a modified version that saves plots
    cat > plot_and_save.py << 'EOF'
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from plot_from_csv import read_multiplier_data, create_multiplier_charts

# Read data
df = read_multiplier_data(csv_file='multipliers.csv')

# Enable non-interactive backend for saving
plt.ioff()

# Create the charts but save instead of show
def create_multiplier_charts_save(df):
    # Chart 1: Main multiplier chart
    df['multiplier_decimal'] = df['multiplier'] / 10000
    
    plt.figure(figsize=(14, 10))
    
    lockup_periods = sorted(df['lockup_days'].unique())
    colors = ['gray', 'blue', 'green', 'orange', 'red'][:len(lockup_periods)]
    
    for i, lockup in enumerate(lockup_periods):
        data = df[df['lockup_days'] == lockup].sort_values('tokens')
        plt.plot(data['tokens'], data['multiplier_decimal'], 
                label=f'{lockup} days', color=colors[i], linewidth=2, marker='o')
    
    plt.xlabel('Token Amount', fontsize=12)
    plt.ylabel('Multiplier (x)', fontsize=12)
    plt.title('Sapien Staking Multiplier by Token Amount and Lockup Period\n' + 
              'Live Data from Solidity Contract', fontsize=14, fontweight='bold')
    plt.legend(title='Lockup Period', fontsize=10)
    plt.grid(True, alpha=0.3)
    plt.xlim(0, df['tokens'].max() * 1.05)
    plt.ylim(1.0, 1.6)
    plt.axhline(y=1.0, color='gray', linestyle='--', alpha=0.5)
    plt.axhline(y=1.5, color='red', linestyle='--', alpha=0.5)
    
    plt.tight_layout()
    plt.savefig('multiplier_chart.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # Chart 2: Heatmap
    plt.figure(figsize=(12, 8))
    pivot_df = df.pivot(index='tokens', columns='lockup_days', values='multiplier_decimal')
    
    im = plt.imshow(pivot_df.values, cmap='viridis', aspect='auto')
    plt.xticks(range(len(pivot_df.columns)), pivot_df.columns)
    plt.yticks(range(len(pivot_df.index)), pivot_df.index)
    plt.xlabel('Lockup Days')
    plt.ylabel('Token Amount')
    plt.title('Multiplier Heatmap')
    
    cbar = plt.colorbar(im)
    cbar.set_label('Multiplier (x)')
    
    for i in range(len(pivot_df.index)):
        for j in range(len(pivot_df.columns)):
            plt.text(j, i, f'{pivot_df.values[i, j]:.3f}',
                    ha="center", va="center", color="white", fontsize=8)
    
    plt.tight_layout()
    plt.savefig('multiplier_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()

# Create and save charts
create_multiplier_charts_save(df)
print("Charts saved as:")
print("  - multiplier_chart.png")
print("  - multiplier_heatmap.png")
EOF

    python3 plot_and_save.py
    rm plot_and_save.py
    
    echo -e "${GREEN}✓ Plots saved to PNG files${NC}"
fi

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Script completed successfully!      ${NC}"
echo -e "${BLUE}======================================${NC}" 