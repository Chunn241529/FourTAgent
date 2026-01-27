import sys

def check(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    depth = 0
    
    for i, line in enumerate(lines):
        # Remove single line comments
        stripped = line.split('//')[0]
        
        for char in stripped:
            if char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
                if depth == 0:
                    print(f"Depth reached 0 at line {i+1}")
                if depth < 0:
                    print(f"Depth < 0 at line {i+1}")
                    return

    print(f"Final depth: {depth}")

if __name__ == "__main__":
    check(sys.argv[1])
