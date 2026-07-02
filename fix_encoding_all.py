import os
import sys

def fix_encoding_dir(directory):
    total_fixed = 0
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    count = content.count('â€”')
                    if count > 0:
                        print(f"Found {count} occurrences in {filepath}")
                        content = content.replace('â€”', '—')
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(content)
                        total_fixed += count
                except Exception as e:
                    print(f"Error processing {filepath}: {e}")
    print(f"Total fixes: {total_fixed}")

if __name__ == "__main__":
    fix_encoding_dir(sys.argv[1])
