import os
import sys

def fix_encoding(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        count = content.count('â€”')
        if count > 0:
            print(f"Found {count} occurrences in {filepath}")
            content = content.replace('â€”', '—')
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            print("Fixed.")
        else:
            print(f"No occurrences found in {filepath}")
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

if __name__ == "__main__":
    fix_encoding(sys.argv[1])
