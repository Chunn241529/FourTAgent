import re

def check_structure(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
        
    brace_count = 0
    class_found = False
    
    for i, line in enumerate(lines):
        line_num = i + 1
        stripped = line.strip()
        
        # Check for class start
        if 'class ChatProvider ' in line:
            print(f"Class starts at line {line_num}")
            class_found = True
            
        open_braces = line.count('{')
        close_braces = line.count('}')
        
        brace_count += (open_braces - close_braces)
        
        if class_found and brace_count == 0 and open_braces > 0:
             # This implies we opened and closed, or closed everything.
             # But usually brace_count == 0 means we are at top level.
             pass

        if class_found and brace_count == 0:
             print(f"Class potentially closed at line {line_num}. Content: {stripped}")
             if line_num < len(lines) - 5: # If not near end of file
                 pass 

    print(f"Final brace count: {brace_count}")

check_structure('mobile_app/lib/providers/chat_provider.dart')
