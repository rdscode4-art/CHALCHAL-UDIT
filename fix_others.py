import os

filepath = 'lib/features/driver/screens/driver_home_screen.dart'
try:
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('â€¢', '•')
    content = content.replace('â€¦', '…')
    content = content.replace('â€“', '–')
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Fixed remaining artifacts.")
except Exception as e:
    print(f"Error: {e}")
