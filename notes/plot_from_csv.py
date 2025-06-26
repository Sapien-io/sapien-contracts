import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import io
import sys

def read_multiplier_data(csv_content=None, csv_file=None):
    """
    Read multiplier data from CSV content or file
    """
    if csv_file:
        df = pd.read_csv(csv_file)
    elif csv_content:
        df = pd.read_csv(io.StringIO(csv_content))
    else:
        raise ValueError("Must provide either csv_content or csv_file")
    
    return df

def create_multiplier_charts(df):
    """
    Create comprehensive charts from multiplier data
    """
    # Convert multiplier to decimal form
    df['multiplier_decimal'] = df['multiplier'] / 10000
    
    # Create main multiplier chart
    plt.figure(figsize=(14, 10))
    
    # Get unique lockup periods and create color map
    lockup_periods = sorted(df['lockup_days'].unique())
    colors = ['gray', 'blue', 'green', 'orange', 'black'][:len(lockup_periods)]
    
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
    
    # Set axis limits
    plt.xlim(0, df['tokens'].max() * 1.05)
    plt.ylim(1.0, 1.6)
    
    # Add reference lines
    plt.axhline(y=1.0, color='gray', linestyle='--', alpha=0.5, label='Base (1.0x)')
    plt.axhline(y=1.5, color='black', linestyle='--', alpha=0.5, label='Max (1.5x)')
    
    plt.tight_layout()
    plt.show()
    
    # Create bonus breakdown chart for 365 days
    plt.figure(figsize=(14, 8))
    
    # Filter for 365 days
    df_365 = df[df['lockup_days'] == 365].sort_values('tokens')
    
    # Calculate bonuses (this is approximate since we don't have individual components)
    base_multiplier = 10000
    total_bonus = df_365['multiplier'] - base_multiplier
    
    plt.subplot(2, 1, 1)
    plt.plot(df_365['tokens'], total_bonus / 100, 'b-', linewidth=2, marker='o')
    plt.xlabel('Token Amount')
    plt.ylabel('Total Bonus (%)')
    plt.title('Total Bonus vs Token Amount (365 days)')
    plt.grid(True, alpha=0.3)
    plt.xlim(0, df_365['tokens'].max() * 1.05)
    
    # Create comparison table
    plt.subplot(2, 1, 2)
    
    # Create a comparison of different amounts at 365 days
    comparison_data = []
    for _, row in df_365.iterrows():
        comparison_data.append([
            f"{int(row['tokens'])} tokens",
            f"{row['multiplier_decimal']:.3f}x",
            f"{(row['multiplier'] - base_multiplier)/100:.1f}%"
        ])
    
    table_data = pd.DataFrame(comparison_data, 
                             columns=['Amount', 'Multiplier', 'Total Bonus'])
    
    # Create table plot
    plt.axis('tight')
    plt.axis('off')
    table = plt.table(cellText=table_data.values,
                     colLabels=table_data.columns,
                     cellLoc='center',
                     loc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1.2, 1.5)
    
    plt.title('Multiplier Summary (365 days)', pad=20)
    plt.tight_layout()
    plt.show()
    
    # Create heatmap
    plt.figure(figsize=(12, 8))
    
    # Pivot data for heatmap
    pivot_df = df.pivot(index='tokens', columns='lockup_days', values='multiplier_decimal')
    
    # Create heatmap
    im = plt.imshow(pivot_df.values, cmap='viridis', aspect='auto')
    
    # Set ticks and labels
    plt.xticks(range(len(pivot_df.columns)), pivot_df.columns)
    plt.yticks(range(len(pivot_df.index)), pivot_df.index)
    plt.xlabel('Lockup Days')
    plt.ylabel('Token Amount')
    plt.title('Multiplier Heatmap')
    
    # Add colorbar
    cbar = plt.colorbar(im)
    cbar.set_label('Multiplier (x)')
    
    # Add text annotations
    for i in range(len(pivot_df.index)):
        for j in range(len(pivot_df.columns)):
            text = plt.text(j, i, f'{pivot_df.values[i, j]:.3f}',
                           ha="center", va="center", color="white", fontsize=8)
    
    plt.tight_layout()
    plt.show()

def parse_forge_output(forge_output_text):
    """
    Parse the output from forge script and extract CSV data
    """
    lines = forge_output_text.strip().split('\n')
    csv_lines = []
    
    for line in lines:
        # Look for lines that match the CSV format (numbers separated by commas)
        if ',' in line and line.replace(',', '').replace(' ', '').isdigit():
            csv_lines.append(line.strip())
        elif line.strip() == "tokens,lockup_days,multiplier":
            csv_lines.append(line.strip())
    
    return '\n'.join(csv_lines)

def main():
    """
    Main function - can be used with different input methods
    """
    
    # Method 1: Read from CSV file (if it exists)
    try:
        df = read_multiplier_data(csv_file='multipliers.csv')
        print("Reading from CSV file...")
    except FileNotFoundError:
        print("CSV file not found. Please provide data using one of these methods:")
        print("1. Save forge script output to 'multiplier_data.csv'")
        print("2. Pipe forge output to this script")
        print("3. Use the sample data below")
    
    # Create charts
    create_multiplier_charts(df)
    
    # Print summary statistics
    print("\nSummary Statistics:")
    print("=" * 50)
    print(f"Token amounts tested: {sorted(df['tokens'].unique())}")
    print(f"Lockup periods tested: {sorted(df['lockup_days'].unique())} days")
    print(f"Multiplier range: {df['multiplier'].min()} - {df['multiplier'].max()}")
    print(f"Max multiplier: {df['multiplier'].max() / 10000:.3f}x")

if __name__ == "__main__":
    main() 